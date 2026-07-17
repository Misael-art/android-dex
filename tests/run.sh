#!/usr/bin/env bash
# Regressões de segurança/estabilidade. Usa somente mocks locais: nunca acessa
# um dispositivo Android nem executa fastboot/heimdall reais.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEX_BIN="$ROOT_DIR/android-dex-kit/bin/android-dex"
FLASH_BIN="$ROOT_DIR/android-dex-flash/bin/android-dex-flash"
TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
PASS=0
FAIL=0

cleanup_tests() {
  local p
  for p in "$TMP_ROOT"/case-*/supervisor.pid; do
    [ -f "$p" ] || continue
    p="$(sed -n '1p' "$p")"
    [[ "$p" =~ ^[0-9]+$ ]] && kill "$p" 2>/dev/null || true
  done
  rm -rf "$TMP_ROOT"
}
trap cleanup_tests EXIT INT TERM

mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/adb" <<'MOCK'
#!/usr/bin/env bash
case "${1:-}" in
  start-server|get-state) exit 0 ;;
  devices)
    printf 'List of devices attached\n'
    [ -f "${MOCK_ADB_DEVICES:-}" ] && /bin/cat "$MOCK_ADB_DEVICES"
    ;;
  connect|disconnect|pair) exit 0 ;;
  -s)
    serial="${2:-}"; shift 2
    if [ "${1:-}" = shell ]; then
      shift
      case "${1:-}" in
        getprop)
          case "${2:-}" in
            ro.product.manufacturer) printf '%s\n' "${MOCK_MANUFACTURER:-Google}" ;;
            ro.product.brand) printf '%s\n' "${MOCK_BRAND:-google}" ;;
            ro.product.model) printf '%s\n' "${MOCK_MODEL:-Pixel8}" ;;
            ro.product.device) printf '%s\n' "${MOCK_DEVICE:-shiba}" ;;
            ro.build.version.sdk) printf '%s\n' "${MOCK_SDK:-35}" ;;
          esac
          ;;
        cmd)
          [ "${2:-}" = package ] && [ "${3:-}" = has-feature ] && printf '%s\n' "${MOCK_SECONDARY_FEATURE:-false}"
          ;;
        settings)
          case "${4:-}" in
            force_desktop_mode_on_external_displays) printf '%s\n' "${MOCK_FORCE_DESKTOP:-null}" ;;
            enable_freeform_support) printf '%s\n' "${MOCK_FREEFORM:-null}" ;;
          esac
          ;;
        pm)
          if [ "${2:-}" = path ]; then
            case " ${MOCK_PACKAGES:-} " in *" ${3:-} "*) printf 'package:/mock/%s.apk\n' "${3:-}";; esac
          fi
          ;;
      esac
      exit 0
    fi
    case "${1:-}" in
      shell|tcpip) exit 0 ;;
    esac
    ;;
  shell) exit 0 ;;
esac
exit 0
MOCK

cat > "$MOCK_BIN/fastboot" <<'MOCK'
#!/usr/bin/env bash
if [ "${1:-}" = -s ]; then shift 2; fi
case "${1:-}" in
  devices)
    [ -f "${MOCK_FASTBOOT_DEVICES:-}" ] && /bin/cat "$MOCK_FASTBOOT_DEVICES"
    ;;
  getvar)
    if [ "${2:-}" = "unlocked" ]; then
      printf 'unlocked: no\n' >&2
    else
      printf '%s: %s\n' "${2:-product}" "${MOCK_FASTBOOT_PRODUCT:-unknown}" >&2
    fi
    ;;
  fetch) exit 1 ;;
  *) printf '%s\n' "$*" >> "${MOCK_FASTBOOT_LOG:-/dev/null}" ;;
esac
MOCK

cat > "$MOCK_BIN/scrcpy" <<'MOCK'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  printf 'scrcpy 3.3.1\n'
  exit 0
fi
printf '%s\n' "$*" >> "${MOCK_SCRCPY_LOG:?}"
case "${MOCK_SCRCPY_MODE:-quick}" in
  hold)
    trap 'exit 0' INT TERM
    while :; do /bin/sleep 1; done
    ;;
  quick) exit 1 ;;
esac
MOCK

chmod +x "$MOCK_BIN/adb" "$MOCK_BIN/fastboot" "$MOCK_BIN/scrcpy"

new_case() {
  local name="$1" dir
  dir="$TMP_ROOT/case-$name"
  mkdir -p "$dir/home" "$dir/config/android-dex" "$dir/config/android-dex-flash" "$dir/state" "$dir/data"
  printf '%s\n' "$dir"
}

write_dex_config() {
  local dir="$1"
  cat > "$dir/config/android-dex/config.env" <<'CFG'
MODE="dex"
CONNECTION="usb"
DEVICE_IP=""
DEVICE_SERIAL=""
ENABLE_FREEFORM_TWEAKS="0"
RESTORE_TWEAKS_ON_EXIT="0"
RECONNECT="0"
BACKOFF_BASE="1"
BACKOFF_CAP="4"
HEALTHY_SESSION_SECONDS="15"
CFG
}

run_dex() {
  local dir="$1"; shift
  env HOME="$dir/home" XDG_CONFIG_HOME="$dir/config" XDG_STATE_HOME="$dir/state" \
    XDG_DATA_HOME="$dir/data" PATH="$MOCK_BIN:$PATH" MOCK_ADB_DEVICES="$dir/adb.devices" \
    MOCK_SCRCPY_LOG="$dir/scrcpy.log" MOCK_SCRCPY_MODE="${MOCK_SCRCPY_MODE:-quick}" \
    MOCK_MANUFACTURER="${MOCK_MANUFACTURER:-Google}" MOCK_BRAND="${MOCK_BRAND:-google}" \
    MOCK_MODEL="${MOCK_MODEL:-Pixel8}" MOCK_DEVICE="${MOCK_DEVICE:-shiba}" MOCK_SDK="${MOCK_SDK:-35}" \
    MOCK_SECONDARY_FEATURE="${MOCK_SECONDARY_FEATURE:-false}" MOCK_PACKAGES="${MOCK_PACKAGES:-}" \
    bash "$DEX_BIN" "$@"
}

run_flash() {
  local dir="$1" product="$2"; shift 2
  env HOME="$dir/home" XDG_CONFIG_HOME="$dir/config" XDG_STATE_HOME="$dir/state" \
    XDG_DATA_HOME="$dir/data" PATH="$MOCK_BIN:$PATH" MOCK_FASTBOOT_DEVICES="$dir/fastboot.devices" \
    MOCK_ADB_DEVICES="$dir/adb.devices" \
    MOCK_FASTBOOT_PRODUCT="$product" MOCK_FASTBOOT_LOG="$dir/fastboot.log" \
    MOCK_MANUFACTURER="${MOCK_MANUFACTURER:-Google}" MOCK_BRAND="${MOCK_BRAND:-google}" \
    MOCK_MODEL="${MOCK_MODEL:-Pixel8}" MOCK_DEVICE="${MOCK_DEVICE:-shiba}" MOCK_SDK="${MOCK_SDK:-35}" \
    bash "$FLASH_BIN" "$@"
}

assert_no_scrcpy() {
  local dir="$1"
  [ ! -s "$dir/scrcpy.log" ]
}

test_firmware_bundles_are_never_executed() {
  local dir bundle marker out
  dir="$(new_case firmware)"
  bundle="$dir/bundle"; marker="$dir/executed"; out="$dir/out"
  mkdir -p "$bundle"
  printf 'device\tfastboot\n' > "$dir/fastboot.devices"
  cat > "$dir/config/android-dex-flash/flash.env" <<'CFG'
ALLOW_DESTRUCTIVE="1"
REQUIRE_TYPED_CONFIRM="0"
CFG
  printf '#!/usr/bin/env bash\nprintf x > %q\n' "$marker" > "$bundle/flash-all.sh"

  if run_flash "$dir" unknown --commit --yes flash-firmware "$bundle" >"$out" 2>&1; then
    printf 'commit genérico deveria falhar\n' >&2; return 1
  fi
  [ ! -e "$marker" ] || { printf 'flash-all.sh foi executado\n' >&2; return 1; }
  grep -q "não é suportada com segurança" "$out" || return 1

  run_flash "$dir" unknown --dry-run --yes flash-firmware "$bundle" >"$out" 2>&1 || return 1
  [ ! -e "$marker" ] || { printf 'bundle executado em dry-run\n' >&2; return 1; }
  grep -q "não executa scripts contidos" "$out"
}

test_xiaomi_bundle_is_never_executed() {
  local dir bundle marker out
  dir="$(new_case xiaomi)"
  bundle="$dir/rom"; marker="$dir/executed"; out="$dir/out"
  mkdir -p "$bundle"
  printf 'device\tfastboot\n' > "$dir/fastboot.devices"
  printf 'ALLOW_DESTRUCTIVE="1"\nREQUIRE_TYPED_CONFIRM="0"\n' > "$dir/config/android-dex-flash/flash.env"
  printf '#!/usr/bin/env bash\nprintf x > %q\n' "$marker" > "$bundle/flash_all.sh"
  if run_flash "$dir" xiaomi --commit --yes flash-firmware "$bundle" >"$out" 2>&1; then
    printf 'commit Xiaomi deveria falhar\n' >&2; return 1
  fi
  [ ! -e "$marker" ] && grep -q "não é suportada com segurança" "$out"
}

test_legacy_dynamic_sinks_are_absent() {
  # Procuramos literalmente a expansão legada.
  # shellcheck disable=SC2016
  ! grep -R -E 'run_or_echo[[:space:]]+bash[[:space:]]+\./flash|run_or_echo[[:space:]]+heimdall[[:space:]]+flash[[:space:]]+\$EXTRA' \
    "$ROOT_DIR/android-dex-flash/lib" "$ROOT_DIR/android-dex-flash/bin"
}

test_udev_template_is_scoped_and_renderable() {
  local dir rendered
  dir="$(new_case udev)"; rendered="$dir/51-android-dex.rules"
  (
    export HOME="$dir/home" XDG_CONFIG_HOME="$dir/config" XDG_STATE_HOME="$dir/state" XDG_DATA_HOME="$dir/data"
    # shellcheck disable=SC1091
    . "$ROOT_DIR/android-dex-kit/install.sh"
    render_udev_rules plugdev "$rendered"
  ) || return 1
  grep -q 'ACTION!="add", ACTION!="bind"' "$rendered" || return 1
  grep -q 'ENV{ID_USB_INTERFACES}=="\*:ff4201:\*"' "$rendered" || return 1
  grep -q 'ATTR{bDeviceClass}=="ff", ATTR{idVendor}=="18d1"' "$rendered" || return 1
  grep -q 'GROUP="plugdev"' "$rendered" || return 1
  ! grep -q '@GROUP@' "$rendered" || return 1
  if command -v udevadm >/dev/null 2>&1; then udevadm verify "$rendered" >/dev/null 2>&1; fi
}

test_auto_mode_and_oem_profile() {
  local dir out
  dir="$(new_case auto-mode)"; write_dex_config "$dir"; out="$dir/out"
  sed -i 's/MODE="dex"/MODE="auto"/; s/HEALTHY_SESSION_SECONDS="15"/HEALTHY_SESSION_SECONDS="0"/' "$dir/config/android-dex/config.env"
  printf 'PHONE-A\tdevice\n' > "$dir/adb.devices"

  MOCK_SDK=34 MOCK_SECONDARY_FEATURE=false run_dex "$dir" --once >"$out" 2>&1 || return 1
  grep -q 'capacidade DeX não confirmada' "$out" || return 1
  grep -q -- '--new-display' "$dir/scrcpy.log" && return 1

  : > "$dir/scrcpy.log"
  MOCK_SDK=35 MOCK_SECONDARY_FEATURE=true MOCK_PACKAGES="com.google.android.apps.nexuslauncher" \
    run_dex "$dir" --once >"$out" 2>&1 || return 1
  grep -q 'desktop virtual habilitado' "$out" || return 1
  grep -q -- '--new-display=' "$dir/scrcpy.log" || return 1
  grep -q -- '--start-app=com.google.android.apps.nexuslauncher' "$dir/scrcpy.log"
}

test_signed_firmware_descriptor() {
  local dir bundle keys sha out
  command -v openssl >/dev/null 2>&1 || { printf 'openssl ausente\n' >&2; return 1; }
  dir="$(new_case signed-manifest)"; bundle="$dir/bundle"; keys="$dir/keys"; out="$dir/out"
  mkdir -p "$bundle" "$keys"
  printf 'PHONE-A\tdevice\n' > "$dir/adb.devices"
  printf 'firmware de teste\n' > "$bundle/factory-image.zip"
  sha="$(sha256sum "$bundle/factory-image.zip" | awk '{print $1}')"
  cat > "$bundle/firmware.manifest" <<EOF
format=android-dex-firmware-v1
oem=pixel
model=Pixel8
device=shiba
region=global
bootloader=test-1
artifact=factory-image.zip
sha256=$sha
EOF
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$dir/private.pem" >/dev/null 2>&1 || return 1
  openssl pkey -in "$dir/private.pem" -pubout -out "$keys/test.pem" >/dev/null 2>&1 || return 1
  openssl dgst -sha256 -sign "$dir/private.pem" -out "$bundle/firmware.manifest.sig" "$bundle/firmware.manifest" || return 1
  printf 'TRUSTED_KEYS_DIR="%s"\n' "$keys" > "$dir/config/android-dex-flash/flash.env"

  run_flash "$dir" unused verify-firmware "$bundle" >"$out" 2>&1 || { cat "$out" >&2; return 1; }
  grep -q 'Descritor autenticado e compatível' "$out" || return 1
  printf 'adulterado\n' >> "$bundle/factory-image.zip"
  run_flash "$dir" unused verify-firmware "$bundle" >"$out" 2>&1 && return 1
  grep -q 'SHA-256 do artefato diverge' "$out"
}

test_flash_identity_requires_unique_device() {
  local dir out
  dir="$(new_case flash-identity)"; out="$dir/out"
  printf 'FB-A\tfastboot\nFB-B\tfastboot\n' > "$dir/fastboot.devices"
  run_flash "$dir" unknown info >"$out" 2>&1 && return 1
  grep -q 'Defina FLASH_DEVICE_SERIAL' "$out" || return 1
  printf 'FLASH_DEVICE_SERIAL="FB-B"\n' > "$dir/config/android-dex-flash/flash.env"
  run_flash "$dir" unknown info >"$out" 2>&1 || return 1
  grep -q 'transporte      : fastboot' "$out"
}

test_ambiguous_or_offline_identity_blocks_session() {
  local dir out
  dir="$(new_case identity)"; write_dex_config "$dir"; out="$dir/out"
  printf 'PHONE-A\tdevice\nPHONE-B\tdevice\n' > "$dir/adb.devices"
  run_dex "$dir" --once >"$out" 2>&1 && { printf 'dois devices foram aceitos\n' >&2; return 1; }
  assert_no_scrcpy "$dir" || return 1
  grep -q "Defina DEVICE_SERIAL" "$out" || return 1

  printf 'DEVICE_SERIAL="PHONE-X"\n' >> "$dir/config/android-dex/config.env"
  printf 'PHONE-A\tdevice\n' > "$dir/adb.devices"
  run_dex "$dir" --once >"$out" 2>&1 && { printf 'serial offline caiu para outro device\n' >&2; return 1; }
  assert_no_scrcpy "$dir" && grep -q "não selecionarei outro aparelho" "$out"
}

wait_for_file() {
  local file="$1" i
  for i in $(seq 1 80); do
    [ -s "$file" ] && return 0
    /bin/sleep 0.1
  done
  return 1
}

test_single_instance_and_stop_supervisor() {
  local dir server_pid out
  dir="$(new_case stop)"; write_dex_config "$dir"
  printf 'PHONE-A\tdevice\n' > "$dir/adb.devices"
  MOCK_SCRCPY_MODE=hold run_dex "$dir" >"$dir/server.out" 2>&1 &
  server_pid=$!; printf '%s\n' "$server_pid" > "$dir/supervisor.pid"
  wait_for_file "$dir/state/android-dex/supervisor.state" || return 1
  wait_for_file "$dir/scrcpy.log" || return 1

  out="$dir/second.out"
  run_dex "$dir" --once >"$out" 2>&1 && { printf 'segunda instância foi aceita\n' >&2; return 1; }
  grep -q "já está em execução" "$out" || return 1

  MOCK_SCRCPY_MODE=hold run_dex "$dir" --stop >"$dir/stop.out" 2>&1 || return 1
  wait "$server_pid" || true
  [ ! -f "$dir/state/android-dex/supervisor.state" ] || return 1
  [ "$(wc -l < "$dir/scrcpy.log")" -eq 1 ] || { printf 'scrcpy reiniciou após --stop\n' >&2; return 1; }
}

test_backoff_grows_after_fast_failures() {
  local dir server_pid launches=0 i d1 d2
  dir="$(new_case backoff)"; write_dex_config "$dir"
  sed -i 's/RECONNECT="0"/RECONNECT="1"/' "$dir/config/android-dex/config.env"
  printf 'PHONE-A\tdevice\n' > "$dir/adb.devices"
  MOCK_SCRCPY_MODE=quick run_dex "$dir" >"$dir/server.out" 2>&1 &
  server_pid=$!; printf '%s\n' "$server_pid" > "$dir/supervisor.pid"
  for i in $(seq 1 140); do
    : "$i"
    [ -f "$dir/scrcpy.log" ] && launches="$(wc -l < "$dir/scrcpy.log")"
    [ "$launches" -ge 3 ] && break
    /bin/sleep 0.1
  done
  [ "$launches" -ge 3 ] || return 1
  run_dex "$dir" --stop >"$dir/stop.out" 2>&1 || return 1
  wait "$server_pid" || true
  d1="$(grep -oE 'recuperar em [0-9]+s' "$dir/server.out" | sed -n '1s/[^0-9]//gp')"
  d2="$(grep -oE 'recuperar em [0-9]+s' "$dir/server.out" | sed -n '2s/[^0-9]//gp')"
  [ -n "$d1" ] && [ -n "$d2" ] && [ "$d2" -ge "$d1" ]
}

run_test() {
  local name="$1"; shift
  if "$@"; then
    PASS=$((PASS + 1)); printf 'ok - %s\n' "$name"
  else
    FAIL=$((FAIL + 1)); printf 'not ok - %s\n' "$name"
  fi
}

run_test "bundles genéricos nunca executam scripts" test_firmware_bundles_are_never_executed
run_test "bundles Xiaomi nunca executam scripts" test_xiaomi_bundle_is_never_executed
run_test "sinks dinâmicos legados foram removidos" test_legacy_dynamic_sinks_are_absent
run_test "template udev é restrito e renderizável" test_udev_template_is_scoped_and_renderable
run_test "modo automático e perfil OEM" test_auto_mode_and_oem_profile
run_test "descritor de firmware assinado" test_signed_firmware_descriptor
run_test "flash exige identidade única" test_flash_identity_requires_unique_device
run_test "identidade ambígua/offline bloqueia sessão" test_ambiguous_or_offline_identity_blocks_session
run_test "instância única e --stop encerram supervisor" test_single_instance_and_stop_supervisor
run_test "backoff cresce após quedas rápidas" test_backoff_grows_after_fast_failures

printf '\n%s passed; %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

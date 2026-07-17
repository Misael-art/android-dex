#!/usr/bin/env bash
# flash-common.sh — camada de segurança e detecção do android-dex-flash.
# Sourced por: bin/android-dex-flash e pelos drivers em lib/drivers/*.sh.
# Depende de lib/common.sh (fundação compartilhada com android-dex).
# NÃO deve ser executado diretamente.
#
# Filosofia: esta ferramenta é um ORQUESTRADOR de ferramentas oficiais
# (fastboot, heimdall, Magisk, imagens de fábrica). Ela nunca implementa um
# "motor de flash" próprio. Toda ação que grava no aparelho passa por:
#   1) fingerprint do device               (fp_*)
#   2) trilhos de segurança                 (guard_*)
#   3) dry-run por padrão + consentimento   (run_or_echo / confirm_typed)

# Evita duplo-source
[ -n "${_ADXF_COMMON_LOADED:-}" ] && return 0
_ADXF_COMMON_LOADED=1

# ---------------------------------------------------------------------------
# Estado / config de flash
# ---------------------------------------------------------------------------
ADXF_APP_NAME="android-dex-flash"
ADXF_CONFIG_DIR="$XDG_CONFIG_HOME/$ADXF_APP_NAME"
ADXF_CONFIG_FILE="$ADXF_CONFIG_DIR/flash.env"
ADXF_STATE_DIR="$XDG_STATE_HOME/$ADXF_APP_NAME"
ADXF_LOG_FILE="$ADXF_STATE_DIR/$ADXF_APP_NAME.log"

mkdir -p "$ADXF_STATE_DIR" 2>/dev/null || true

adxf_load_config() {
  if [ -f "$ADXF_CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    set -a; . "$ADXF_CONFIG_FILE"; set +a
  fi
  # Padrões conservadores: dry-run ligado, ações destrutivas exigem opt-in.
  : "${DRY_RUN:=1}"                 # 1 = nunca grava; só mostra os comandos
  : "${ALLOW_DESTRUCTIVE:=0}"       # 1 = permite --commit em ações destrutivas
  : "${MIN_BATTERY:=40}"            # % mínimo de bateria p/ gravar
  : "${REQUIRE_TYPED_CONFIRM:=1}"   # 1 = exige "SIM" digitado
  : "${BACKUP_DIR:=$XDG_STATE_HOME/$ADXF_APP_NAME/backups}"
  : "${WORK_DIR:=$XDG_STATE_HOME/$ADXF_APP_NAME/work}"
  : "${MAGISK_APK:=}"               # caminho p/ Magisk-vXX.apk (opcional)
  : "${TRUSTED_KEYS_DIR:=$ADXF_CONFIG_DIR/trusted-keys}"
  : "${FLASH_DEVICE_SERIAL:=}"       # obrigatório quando houver mais de um device
  mkdir -p "$BACKUP_DIR" "$WORK_DIR" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Descritor autenticado de firmware (somente leitura / fail-closed)
# ---------------------------------------------------------------------------
firmware_manifest_get() {
  local manifest="$1" key="$2"
  awk -F= -v key="$key" '$1==key {sub(/^[^=]*=/, ""); print}' "$manifest"
}

verify_firmware_descriptor() {
  local input="$1" bundle manifest signature artifact artifact_path expected_sha actual_sha
  local format oem model device region bootloader key verified=0 count
  [ -n "$input" ] || die "Uso: verify-firmware <diretório-do-bundle | firmware.manifest>"
  if [ -d "$input" ]; then
    bundle="$(readlink -f "$input")"
    manifest="$bundle/firmware.manifest"
  elif [ -f "$input" ] && [ "$(basename "$input")" = firmware.manifest ]; then
    manifest="$(readlink -f "$input")"
    bundle="$(dirname "$manifest")"
  else
    die "Descritor não encontrado: informe um diretório com firmware.manifest."
  fi
  signature="$manifest.sig"
  [ -f "$manifest" ] || die "Manifesto ausente: $manifest"
  [ -f "$signature" ] || die "Assinatura destacada ausente: $signature"

  # Formato deliberadamente pequeno: um campo por linha, ASCII seguro, sem
  # source/eval e sem chaves duplicadas ou desconhecidas.
  if grep -Ev '^(format|oem|model|device|region|bootloader|artifact|sha256)=[-A-Za-z0-9._+* ]+$' "$manifest" | grep -q .; then
    die "Manifesto contém campo ou caractere não permitido."
  fi
  for key in format oem model device region bootloader artifact sha256; do
    count="$(awk -F= -v key="$key" '$1==key {n++} END{print n+0}' "$manifest")"
    [ "$count" -le 1 ] || die "Campo duplicado no manifesto: $key"
  done

  format="$(firmware_manifest_get "$manifest" format)"
  oem="$(firmware_manifest_get "$manifest" oem)"
  model="$(firmware_manifest_get "$manifest" model)"
  device="$(firmware_manifest_get "$manifest" device)"
  region="$(firmware_manifest_get "$manifest" region)"
  bootloader="$(firmware_manifest_get "$manifest" bootloader)"
  artifact="$(firmware_manifest_get "$manifest" artifact)"
  expected_sha="$(firmware_manifest_get "$manifest" sha256)"
  [ "$format" = "android-dex-firmware-v1" ] || die "Formato de manifesto incompatível: '${format:-vazio}'"
  if [ -z "$oem" ] || [ -z "$artifact" ] || [ -z "$expected_sha" ]; then die "Manifesto incompleto (oem/artifact/sha256 são obrigatórios)."; fi
  [ -n "$model" ] || [ -n "$device" ] || die "Manifesto precisa vincular model ou device."
  [[ "$expected_sha" =~ ^[0-9a-fA-F]{64}$ ]] || die "SHA-256 inválido no manifesto."
  case "$artifact" in */*|..|.|'') die "artifact precisa ser um nome de arquivo local, sem diretórios.";; esac
  artifact_path="$bundle/$artifact"
  [ -f "$artifact_path" ] || die "Artefato declarado não existe: $artifact_path"

  require_tool openssl "Instale openssl para verificar a assinatura do descritor." || return 1
  require_tool sha256sum "Instale coreutils para verificar a integridade do artefato." || return 1
  [ -d "$TRUSTED_KEYS_DIR" ] || die "Nenhuma chave confiável configurada em $TRUSTED_KEYS_DIR"
  for key in "$TRUSTED_KEYS_DIR"/*.pem; do
    [ -f "$key" ] || continue
    if openssl dgst -sha256 -verify "$key" -signature "$signature" "$manifest" >/dev/null 2>&1; then
      verified=1
      log_ok "Assinatura do manifesto válida com: $(basename "$key")"
      break
    fi
  done
  [ "$verified" = 1 ] || die "Assinatura do manifesto não corresponde a nenhuma chave confiável."

  actual_sha="$(sha256sum "$artifact_path" | awk '{print $1}')"
  [ "${actual_sha,,}" = "${expected_sha,,}" ] || die "SHA-256 do artefato diverge do manifesto."
  log_ok "Integridade do artefato confirmada: $artifact"

  [ "$FP_TRANSPORT" != none ] || die "Conecte o aparelho para vincular o descritor à identidade detectada."
  [ "$FP_OEM" = "$oem" ] || die "OEM do manifesto ('$oem') diverge do aparelho ('$FP_OEM')."
  if [ -n "$model" ] && [ "$model" != "*" ]; then
    [ "$FP_MODEL" = "$model" ] || die "Modelo do manifesto ('$model') diverge do aparelho ('${FP_MODEL:-?}')."
  fi
  if [ -n "$device" ] && [ "$device" != "*" ]; then
    [ "$FP_DEVICE" = "$device" ] || die "Device/codename do manifesto ('$device') diverge do aparelho ('${FP_DEVICE:-?}')."
  fi
  log_ok "Compatibilidade básica confirmada: OEM=$oem model=${model:-*} device=${device:-*}."
  [ -n "$region" ] && log_info "Região declarada: $region (validação automática ainda indisponível)."
  [ -n "$bootloader" ] && log_info "Bootloader mínimo declarado: $bootloader (anti-rollback ainda não validado)."
  printf '%s\n' "$artifact_path"
}

verify_descriptor_if_present() {
  local input="$1"
  if [ -d "$input" ] && [ -f "$input/firmware.manifest" ]; then
    verify_firmware_descriptor "$input" >/dev/null
  else
    log_warn "Bundle sem firmware.manifest assinado: somente orientação; nunca será elegível a --commit."
  fi
}

# ---------------------------------------------------------------------------
# Detecção de estado de transporte do aparelho
#   adb      = booted, depuração ligada
#   fastboot = bootloader/fastbootd
#   download = modo download da Samsung (Odin/Heimdall)
#   none     = nada visível
# ---------------------------------------------------------------------------
fp_transport() {
  if have fastboot && fastboot devices 2>/dev/null | grep -q .; then
    echo fastboot; return 0
  fi
  if have adb && adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{found=1} END{exit found?0:1}'; then
    echo adb; return 0
  fi
  # Modo download Samsung: aparece via lsusb (04e8:685d costuma ser download)
  if have lsusb && lsusb 2>/dev/null | grep -qiE '04e8:(685d|6860)'; then
    echo download; return 0
  fi
  echo none
}

fp_select_serial() {
  local transport="$1" requested="${FLASH_DEVICE_SERIAL:-}" item selected="" count=0
  case "$transport" in
    adb)
      while IFS= read -r item; do
        [ -n "$item" ] || continue
        if [ -n "$requested" ]; then [ "$item" = "$requested" ] && { selected="$item"; count=1; break; }; else selected="$item"; count=$((count + 1)); fi
      done < <(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1}')
      ;;
    fastboot)
      while IFS= read -r item; do
        [ -n "$item" ] || continue
        if [ -n "$requested" ]; then [ "$item" = "$requested" ] && { selected="$item"; count=1; break; }; else selected="$item"; count=$((count + 1)); fi
      done < <(fastboot devices 2>/dev/null | awk 'NF{print $1}')
      ;;
  esac
  if [ -n "$requested" ] && [ "$selected" != "$requested" ]; then
    die "FLASH_DEVICE_SERIAL='$requested' não está online em $transport; não selecionarei outro aparelho."
  fi
  [ "$count" -gt 0 ] || die "Nenhum aparelho online em $transport."
  [ "$count" -eq 1 ] || die "Há $count aparelhos em $transport. Defina FLASH_DEVICE_SERIAL para evitar operar no dispositivo errado."
  printf '%s\n' "$selected"
}

# getprop resiliente (só faz sentido no transporte adb)
fp_getprop() {
  local key="$1"
  adb -s "$FP_ADB_SERIAL" shell getprop "$key" 2>/dev/null | tr -d '\r'
}

# getvar do fastboot (a saída vai p/ stderr no fastboot)
fp_getvar() {
  local key="$1"
  fastboot -s "$FP_FASTBOOT_SERIAL" getvar "$key" 2>&1 | awk -F': ' -v k="$key" '$1==k{print $2; exit}' | tr -d '\r'
}

# Fingerprint amplo, tolerante ao transporte disponível.
# Popula variáveis FP_* no ambiente do chamador.
fp_collect() {
  FP_TRANSPORT="$(fp_transport)"
  FP_MANUFACTURER=""; FP_BRAND=""; FP_MODEL=""; FP_DEVICE=""
  FP_ANDROID=""; FP_SDK=""; FP_PATCH=""; FP_FINGERPRINT=""
  FP_BOOTLOADER_UNLOCKED="desconhecido"; FP_VERIFIED_BOOT=""; FP_SECURE=""

  case "$FP_TRANSPORT" in
    adb)
      FP_ADB_SERIAL="$(fp_select_serial adb)" || die "Não foi possível selecionar um único aparelho ADB."
      ANDROID_SERIAL="$FP_ADB_SERIAL"; export ANDROID_SERIAL
      FP_MANUFACTURER="$(fp_getprop ro.product.manufacturer)"
      FP_BRAND="$(fp_getprop ro.product.brand)"
      FP_MODEL="$(fp_getprop ro.product.model)"
      FP_DEVICE="$(fp_getprop ro.product.device)"
      FP_ANDROID="$(fp_getprop ro.build.version.release)"
      FP_SDK="$(fp_getprop ro.build.version.sdk)"
      FP_PATCH="$(fp_getprop ro.build.version.security_patch)"
      FP_FINGERPRINT="$(fp_getprop ro.build.fingerprint)"
      FP_VERIFIED_BOOT="$(fp_getprop ro.boot.verifiedbootstate)"
      FP_SECURE="$(fp_getprop ro.secure)"
      # oem unlock permitido no menu de dev? (1 = usuário liberou)
      FP_OEM_UNLOCK_ALLOWED="$(fp_getprop sys.oem_unlock_allowed)"
      ;;
    fastboot)
      FP_FASTBOOT_SERIAL="$(fp_select_serial fastboot)" || die "Não foi possível selecionar um único aparelho fastboot."
      ANDROID_SERIAL="$FP_FASTBOOT_SERIAL"; export ANDROID_SERIAL
      FP_MANUFACTURER="$(fp_getvar product)"
      FP_MODEL="$(fp_getvar product)"
      FP_DEVICE="$(fp_getvar product)"
      local u; u="$(fp_getvar unlocked)"
      case "$u" in
        yes) FP_BOOTLOADER_UNLOCKED="sim" ;;
        no)  FP_BOOTLOADER_UNLOCKED="não" ;;
      esac
      ;;
    download)
      FP_MANUFACTURER="samsung"; FP_BRAND="samsung"
      ;;
  esac

  # Normaliza fabricante para casar driver
  FP_OEM="$(fp_normalize_oem "${FP_MANUFACTURER}${FP_BRAND}${FP_MODEL}")"
}

# Mapeia manufacturer/brand → chave de driver
fp_normalize_oem() {
  local s; s="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$s" in
    *google*|*pixel*)                 echo pixel ;;
    *samsung*)                        echo samsung ;;
    *xiaomi*|*redmi*|*poco*|*hyperos*) echo xiaomi ;;
    *motorola*|*moto*|*lenovo*)       echo motorola ;;
    *oneplus*|*oppo*|*realme*)        echo oneplus ;;
    *sony*)                            echo oneplus ;;   # fluxo fastboot próximo
    *) echo generic ;;
  esac
}

# ---------------------------------------------------------------------------
# Bateria (checagem de guard rail)
# ---------------------------------------------------------------------------
fp_battery_level() {
  case "$(fp_transport)" in
    adb) adb -s "${FP_ADB_SERIAL:-$(fp_select_serial adb)}" shell dumpsys battery 2>/dev/null | awk -F': ' '/ level:/{print $2; exit}' | tr -d '\r ' ;;
    *)   echo "" ;;  # fastboot não expõe de forma padrão
  esac
}

# ---------------------------------------------------------------------------
# Execução segura: em DRY_RUN só ecoa; senão executa de verdade.
# ---------------------------------------------------------------------------
run_or_echo() {
  # Loga sempre o comando (auditoria).
  _adx_log "CMD" "$C_DIM" "$*" 2>/dev/null || true
  if [ "${DRY_RUN:-1}" = "1" ]; then
    printf '%s[dry-run]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2
    return 0
  fi
  printf '%s[exec]%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2
  "$@"
}

# ---------------------------------------------------------------------------
# Consentimento digitado — não aceita "y"; exige a palavra exata.
# ---------------------------------------------------------------------------
confirm_typed() {
  local expect="${1:-SIM}" prompt="${2:-Para confirmar, digite}"
  [ "${REQUIRE_TYPED_CONFIRM:-1}" = "1" ] || return 0
  local ans
  printf '%s%s "%s": %s' "$C_BOLD" "$prompt" "$expect" "$C_RESET" >&2
  read -r ans
  [ "$ans" = "$expect" ] || die "Confirmação não confere ('$ans' != '$expect'). Abortado."
}

# ---------------------------------------------------------------------------
# Trilhos de segurança
# ---------------------------------------------------------------------------
guard_require_destructive_optin() {
  if [ "${ALLOW_DESTRUCTIVE:-0}" != "1" ] && [ "${DRY_RUN:-1}" != "1" ]; then
    die "Ação destrutiva bloqueada. Rode com --dry-run (padrão) ou habilite ALLOW_DESTRUCTIVE=1 + --commit conscientemente."
  fi
}

guard_check_battery() {
  local lvl; lvl="$(fp_battery_level)"
  [ -n "$lvl" ] || { log_warn "Não consegui ler a bateria (transporte fastboot?). Garanta carga suficiente."; return 0; }
  if [ "$lvl" -lt "${MIN_BATTERY:-40}" ]; then
    die "Bateria em ${lvl}% (< ${MIN_BATTERY}%). Carregue antes de gravar — bateria baixa durante flash brica aparelho."
  fi
  log_ok "Bateria: ${lvl}% (ok)."
}

# Confere que o aparelho é o modelo que o usuário disse esperar (evita flashar
# firmware do modelo errado — causa clássica de hard-brick).
guard_verify_model() {
  local expected="$1"
  [ -n "$expected" ] || return 0
  local got="${FP_MODEL:-${FP_DEVICE:-}}"
  if [ -n "$got" ] && [ "$got" != "$expected" ]; then
    die "Modelo detectado ('$got') != esperado ('$expected'). Recusando gravar firmware de modelo divergente."
  fi
  log_ok "Modelo confere: ${got:-$expected}."
}

# Verifica hash de um arquivo contra um esperado (sha256).
guard_verify_sha256() {
  local file="$1" expected="$2"
  [ -f "$file" ] || die "Arquivo não encontrado: $file"
  [ -n "$expected" ] || { log_warn "Sem hash esperado p/ $(basename "$file") — pulei verificação de integridade."; return 0; }
  have sha256sum || { log_warn "sha256sum ausente; não verifiquei $file."; return 0; }
  local got; got="$(sha256sum "$file" | awk '{print $1}')"
  [ "$got" = "$expected" ] || die "Hash divergente em $(basename "$file"). Esperado $expected, obtido $got. NÃO gravar."
  log_ok "Integridade ok: $(basename "$file")."
}

# Banner de aviso irreversível padronizado.
warn_irreversible() {
  printf '\n%s%s  AVISO — AÇÃO IRREVERSÍVEL  %s\n' "$C_BOLD$C_RED" "▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁" "$C_RESET" >&2
  local line
  for line in "$@"; do printf '  %s•%s %s\n' "$C_RED" "$C_RESET" "$line" >&2; done
  printf '\n' >&2
}

# Checagem de ferramentas do host por necessidade.
require_tool() {
  local t="$1" hint="${2:-}"
  have "$t" && return 0
  log_error "Ferramenta ausente: '$t'. ${hint:-Instale-a e tente de novo.}"
  return 1
}

# ---------------------------------------------------------------------------
# Carregamento de driver de OEM
# ---------------------------------------------------------------------------
load_driver() {
  local oem="$1"
  local base; base="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
  local f="$base/drivers/${oem}.sh"
  [ -f "$f" ] || f="$base/drivers/generic.sh"
  # shellcheck disable=SC1090
  . "$f"
}

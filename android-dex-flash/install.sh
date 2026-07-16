#!/usr/bin/env bash
# install.sh — instala o android-dex-flash integrado ao host (Linux).
#
# Idempotente:
#   1. Instala dependências (fastboot/adb via android-tools; heimdall p/ Samsung).
#   2. Reaproveita o acesso USB (udev) do android-dex se já instalado; senão avisa.
#   3. Binário em ~/.local/bin, libs (common.sh + flash-common.sh + drivers) em
#      ~/.local/share/android-dex-flash/lib.
#   4. Cria ~/.config/android-dex-flash/flash.env (se não existir).
#
# Uso:
#   ./install.sh                 # instalação completa
#   ./install.sh --no-deps       # pula pacotes do sistema
#   ./install.sh --with-heimdall # força tentar instalar heimdall (Samsung)
#   ./install.sh --uninstall     # atalho p/ uninstall.sh
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
. "$SRC_DIR/lib/common.sh"

NO_DEPS=0
WITH_HEIMDALL=0
for a in "$@"; do
  case "$a" in
    --no-deps) NO_DEPS=1 ;;
    --with-heimdall) WITH_HEIMDALL=1 ;;
    --uninstall) exec "$SRC_DIR/uninstall.sh" ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) log_warn "Opção ignorada: $a" ;;
  esac
done

SUDO=""
need_root_cmd() {
  if [ "$(id -u)" -ne 0 ]; then
    have sudo && SUDO="sudo" || { log_warn "sudo ausente; passos de root serão pulados."; return 1; }
  fi
  return 0
}

detect_pm() { for pm in apt-get dnf pacman zypper apk; do have "$pm" && { echo "$pm"; return; }; done; echo ""; }

install_pkgs() {
  local pm="$1"; shift
  case "$pm" in
    apt-get) $SUDO apt-get update -y && $SUDO apt-get install -y "$@" ;;
    dnf)     $SUDO dnf install -y "$@" ;;
    pacman)  $SUDO pacman -Sy --noconfirm "$@" ;;
    zypper)  $SUDO zypper install -y "$@" ;;
    apk)     $SUDO apk add "$@" ;;
    *) return 1 ;;
  esac
}

install_deps() {
  [ "$NO_DEPS" = "1" ] && { log_info "Pulando dependências (--no-deps)."; return; }
  log_step "Dependências (fastboot/adb; heimdall p/ Samsung)"
  local pm; pm="$(detect_pm)"
  [ -n "$pm" ] || { log_warn "PM não reconhecido. Instale android-tools (adb+fastboot) e, p/ Samsung, heimdall."; return; }
  log_info "Gerenciador: $pm"
  need_root_cmd || true

  local pkg_tools
  case "$pm" in
    apt-get) pkg_tools="android-tools-adb android-tools-fastboot" ;;
    *)       pkg_tools="android-tools" ;;
  esac
  have fastboot || install_pkgs "$pm" $pkg_tools || log_warn "Falha ao instalar android-tools via $pm."
  have adb && log_ok "adb: $(adb version 2>/dev/null | head -n1)"
  have fastboot && log_ok "fastboot: $(fastboot --version 2>/dev/null | head -n1)"

  if [ "$WITH_HEIMDALL" = "1" ] || ! have heimdall; then
    log_info "Tentando instalar heimdall (Samsung/Odin)..."
    case "$pm" in
      apt-get) install_pkgs "$pm" heimdall-flash 2>/dev/null || log_warn "heimdall-flash indisponível no apt; compile ou baixe do projeto Heimdall." ;;
      pacman)  install_pkgs "$pm" heimdall 2>/dev/null || log_warn "heimdall via AUR pode ser necessário." ;;
      *)       install_pkgs "$pm" heimdall 2>/dev/null || log_warn "Instale heimdall manualmente p/ suporte Samsung." ;;
    esac
  fi
  have heimdall && log_ok "heimdall: presente (suporte Samsung habilitado)."
}

check_udev() {
  log_step "Acesso USB (udev)"
  if [ -f /etc/udev/rules.d/51-android-dex.rules ] || [ -f /etc/udev/rules.d/51-android.rules ]; then
    log_ok "Regras udev do Android já presentes (compartilhadas com android-dex)."
  else
    log_warn "Sem regras udev do Android detectadas."
    log_warn "Instale o android-dex-kit (./install.sh dele configura udev) ou adicione uma regra"
    log_warn "por vendor-id. Sem isso, adb/fastboot podem exigir sudo."
  fi
  # Fastboot precisa de acesso ao dispositivo em modo bootloader (VID muda!).
  log_info "Obs.: em modo fastboot o VID/PID do aparelho muda; a regra por-VID cobre isso (roadmap A1)."
}

install_files() {
  log_step "Instalando binário, libs e config"
  local bindir="$HOME/.local/bin"
  local libdir="$XDG_DATA_HOME/android-dex-flash/lib"
  mkdir -p "$bindir" "$libdir/drivers" "$ADXF_CONFIG_DIR"

  install -m 0755 "$SRC_DIR/bin/android-dex-flash" "$bindir/android-dex-flash"
  install -m 0644 "$SRC_DIR/lib/common.sh"         "$libdir/common.sh"
  install -m 0644 "$SRC_DIR/lib/flash-common.sh"   "$libdir/flash-common.sh"
  install -m 0644 "$SRC_DIR"/lib/drivers/*.sh      "$libdir/drivers/"
  log_ok "Binário em $bindir/android-dex-flash"
  log_ok "Libs em $libdir (common.sh + flash-common.sh + drivers/)"

  if [ -f "$ADXF_CONFIG_FILE" ]; then
    log_info "Config já existe, preservado: $ADXF_CONFIG_FILE"
  else
    install -m 0644 "$SRC_DIR/config/flash.env.example" "$ADXF_CONFIG_FILE"
    log_ok "Config criado (DRY_RUN=1 por padrão): $ADXF_CONFIG_FILE"
  fi
  install -m 0644 "$SRC_DIR/config/flash.env.example" "$ADXF_CONFIG_DIR/flash.env.example"

  case ":$PATH:" in
    *":$bindir:"*) : ;;
    *) log_warn "~/.local/bin não está no PATH. Adicione: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
  esac
}

final_hint() {
  cat >&2 <<EOF

${C_GREEN}${C_BOLD}android-dex-flash instalado.${C_RESET}

${C_BOLD}Comece SEMPRE pelo diagnóstico (risco zero):${C_RESET}
  android-dex-flash info      # detecta seu aparelho e diz o que é possível
  android-dex-flash caps      # capacidades e riscos do seu modelo

Ações que gravam são ${C_YELLOW}dry-run por padrão${C_RESET} (não escrevem nada):
  android-dex-flash unlock            # mostra a sequência (simulação)
  android-dex-flash unlock --commit   # executa de verdade (pede "SIM")

${C_RED}${C_BOLD}Avisos:${C_RESET} só use no SEU aparelho. Unlock/root/flash podem BRICAR e
frequentemente são IRREVERSÍVEIS (Knox, Play Integrity, garantia). Leia o README.
EOF
}

main() {
  log_step "android-dex-flash — instalação"
  install_deps
  check_udev
  install_files
  final_hint
}
main

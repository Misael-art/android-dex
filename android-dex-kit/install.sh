#!/usr/bin/env bash
# install.sh — instala o Android-DEX Kit integrado ao host (Linux).
#
# Faz, de forma idempotente:
#   1. Instala dependências (scrcpy, adb) via gerenciador da distro, com
#      fallback para snap quando a versão do repo for antiga demais p/ DeX.
#   2. Configura regras udev + grupo para acesso USB sem root.
#   3. Instala binários em ~/.local/bin, libs em ~/.local/share/android-dex.
#   4. Cria ~/.config/android-dex/config.env (se não existir).
#   5. Registra lançador .desktop + ícone (menu de aplicativos).
#   6. Instala o serviço de usuário systemd (opcional, não habilitado por padrão).
#
# Uso:
#   ./install.sh                 # instalação completa (pergunta antes de sudo)
#   ./install.sh --no-deps       # pula a instalação de pacotes
#   ./install.sh --enable-service# habilita o serviço systemd de usuário
#   ./install.sh --uninstall     # atalho p/ uninstall.sh
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
. "$SRC_DIR/lib/common.sh"

NO_DEPS=0
ENABLE_SERVICE=0
MIN_SCRCPY="3.0"   # mínimo para --new-display (modo DeX)

for a in "$@"; do
  case "$a" in
    --no-deps) NO_DEPS=1 ;;
    --enable-service) ENABLE_SERVICE=1 ;;
    --uninstall) exec "$SRC_DIR/uninstall.sh" ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) log_warn "Opção ignorada: $a" ;;
  esac
done

# ---------------------------------------------------------------------------
# sudo helper (só usa se existir e se precisar)
# ---------------------------------------------------------------------------
SUDO=""
need_root_cmd() {
  if [ "$(id -u)" -ne 0 ]; then
    if have sudo; then SUDO="sudo";
    else log_warn "sudo não encontrado; passos que exigem root serão pulados."; return 1; fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 1. Dependências
# ---------------------------------------------------------------------------
detect_pm() {
  for pm in apt-get dnf pacman zypper apk; do have "$pm" && { echo "$pm"; return; }; done
  echo ""
}

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

scrcpy_version() {
  have scrcpy || { echo ""; return; }
  scrcpy --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1
}

install_deps() {
  [ "$NO_DEPS" = "1" ] && { log_info "Pulando dependências (--no-deps)."; return; }
  log_step "Verificando dependências (scrcpy, adb)"

  local pm; pm="$(detect_pm)"
  if [ -z "$pm" ]; then
    log_warn "Gerenciador de pacotes não reconhecido. Instale 'scrcpy' e 'adb' manualmente."
    return
  fi
  log_info "Gerenciador detectado: $pm"

  need_root_cmd || true

  # nomes de pacotes por distro
  local scrcpy_pkg="scrcpy" adb_pkg
  case "$pm" in
    apt-get) adb_pkg="android-tools-adb" ;;
    dnf)     adb_pkg="android-tools" ;;
    pacman)  adb_pkg="android-tools" ;;
    zypper)  adb_pkg="android-tools" ;;
    apk)     adb_pkg="android-tools" ;;
  esac

  have adb    || install_pkgs "$pm" "$adb_pkg" || log_warn "Falha ao instalar adb via $pm."
  have scrcpy || install_pkgs "$pm" "$scrcpy_pkg" || log_warn "Falha ao instalar scrcpy via $pm."

  # Checa versão; se antiga demais para DeX, tenta snap (costuma ser recente).
  local ver; ver="$(scrcpy_version)"
  if [ -n "$ver" ] && ! version_ge "$ver" "$MIN_SCRCPY"; then
    log_warn "scrcpy $ver é antigo para o modo DeX (precisa >= $MIN_SCRCPY)."
    if have snap; then
      log_info "Tentando versão recente via snap..."
      if $SUDO snap install scrcpy 2>/dev/null; then log_ok "scrcpy via snap instalado."
      else log_warn "snap falhou. O modo 'mirror' funciona; para DeX, atualize o scrcpy."; fi
    else
      log_warn "Sem snap. O modo 'mirror' funciona normalmente; para DeX, compile/baixe scrcpy >= $MIN_SCRCPY."
    fi
  fi

  have adb && log_ok "adb: $(adb version 2>/dev/null | head -n1)"
  have scrcpy && log_ok "scrcpy: $(scrcpy_version)"
}

# ---------------------------------------------------------------------------
# 2. Acesso USB (udev + grupo) — sem root em runtime
# ---------------------------------------------------------------------------
render_udev_rules() {
  local group="$1" output="$2"
  local template="$SRC_DIR/udev/51-android-dex.rules.in"
  [ -f "$template" ] || { log_error "Template udev ausente: $template"; return 1; }
  case "$group" in *[!A-Za-z0-9_-]*|'') log_error "Grupo udev inválido: '$group'"; return 1;; esac
  sed "s/@GROUP@/$group/g" "$template" > "$output"
}

setup_udev() {
  log_step "Configurando acesso USB (udev)"
  if [ "$(id -u)" -ne 0 ] && ! have sudo; then
    log_warn "Sem privilégios para udev. Rode como root depois se o USB não autorizar."
    return
  fi
  need_root_cmd || return

  # Se a distro já trouxer regras Android, elas coexistem. A regra do kit cobre
  # interfaces ADB/fastboot e VIDs de bootloader que costumam escapar da regra
  # genérica de classe no nível do device.
  local rules="/etc/udev/rules.d/51-android-dex.rules"
  local group="plugdev"
  getent group plugdev >/dev/null 2>&1 || group="adbusers"
  getent group "$group" >/dev/null 2>&1 || $SUDO groupadd "$group" 2>/dev/null || true

  local tmp; tmp="$(mktemp)"
  render_udev_rules "$group" "$tmp" || { rm -f "$tmp"; return 1; }
  $SUDO install -m 0644 "$tmp" "$rules" && log_ok "Regra udev instalada: $rules"
  rm -f "$tmp"

  # adiciona o usuário ao grupo
  if ! id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$group"; then
    if $SUDO usermod -aG "$group" "$USER" 2>/dev/null; then
      log_ok "Usuário '$USER' adicionado ao grupo '$group' (reloga p/ efetivar)."
    else log_warn "Não consegui adicionar ao grupo '$group'."; fi
  fi

  $SUDO udevadm control --reload-rules 2>/dev/null || true
  $SUDO udevadm trigger 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 3–6. Arquivos do usuário
# ---------------------------------------------------------------------------
install_files() {
  log_step "Instalando binários, config e integração de desktop"

  local bindir="$HOME/.local/bin"
  local libdir="$ADX_DATA_DIR/lib"
  local profilesdir="$ADX_DATA_DIR/profiles"
  local appsdir="$XDG_DATA_HOME/applications"
  local icondir="$XDG_DATA_HOME/icons/hicolor/scalable/apps"
  local unitdir="$XDG_CONFIG_HOME/systemd/user"

  mkdir -p "$bindir" "$libdir" "$profilesdir" "$appsdir" "$icondir" "$unitdir" "$ADX_CONFIG_DIR"

  install -m 0755 "$SRC_DIR/bin/android-dex"         "$bindir/android-dex"
  install -m 0755 "$SRC_DIR/bin/android-dex-connect" "$bindir/android-dex-connect"
  install -m 0644 "$SRC_DIR/lib/common.sh"           "$libdir/common.sh"
  install -m 0644 "$SRC_DIR"/profiles/*.env          "$profilesdir/"
  log_ok "Binários em $bindir (android-dex, android-dex-connect)"

  if [ -f "$ADX_CONFIG_FILE" ]; then
    log_info "Config já existe, preservado: $ADX_CONFIG_FILE"
    install -m 0644 "$SRC_DIR/config/config.env.example" "$ADX_CONFIG_DIR/config.env.example"
  else
    install -m 0644 "$SRC_DIR/config/config.env.example" "$ADX_CONFIG_FILE"
    install -m 0644 "$SRC_DIR/config/config.env.example" "$ADX_CONFIG_DIR/config.env.example"
    log_ok "Config criado: $ADX_CONFIG_FILE"
  fi

  install -m 0644 "$SRC_DIR/desktop/android-dex.desktop" "$appsdir/android-dex.desktop"
  install -m 0644 "$SRC_DIR/icons/android-dex.svg"       "$icondir/android-dex.svg"
  if have update-desktop-database; then update-desktop-database "$appsdir" >/dev/null 2>&1 || true; fi
  if have gtk-update-icon-cache; then gtk-update-icon-cache "$XDG_DATA_HOME/icons/hicolor" >/dev/null 2>&1 || true; fi
  log_ok "Lançador e ícone registrados no menu de aplicativos."

  install -m 0644 "$SRC_DIR/systemd/android-dex.service" "$unitdir/android-dex.service"
  if have systemctl; then
    systemctl --user daemon-reload 2>/dev/null || true
    if [ "$ENABLE_SERVICE" = "1" ]; then
      if systemctl --user enable --now android-dex.service 2>/dev/null; then
        log_ok "Serviço systemd de usuário habilitado (auto-start na sessão gráfica)."
      else log_warn "Não consegui habilitar o serviço agora (talvez fora de sessão gráfica)."; fi
    else
      log_info "Serviço systemd instalado (desabilitado). Habilite com:"
      log_info "  systemctl --user enable --now android-dex.service"
    fi
  fi

  # PATH check
  case ":$PATH:" in
    *":$bindir:"*) : ;;
    *) log_warn "$HOME/.local/bin não está no PATH. Adicione ao seu shell rc:"
       log_warn "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
  esac
}

# ---------------------------------------------------------------------------
final_hint() {
  cat >&2 <<EOF

${C_GREEN}${C_BOLD}Instalação concluída.${C_RESET}

Próximos passos:
  1) No aparelho: Opções do desenvolvedor → ${C_BOLD}Depuração USB${C_RESET} (e/ou Depuração sem fio).
  2) USB:   conecte o cabo, autorize no aparelho e rode:  ${C_BOLD}android-dex${C_RESET}
     Wi-Fi: ${C_BOLD}android-dex-connect${C_RESET}  (emparelha e salva o IP) e depois ${C_BOLD}android-dex --wifi${C_RESET}
  3) Ajustes finos em:  ${C_BOLD}$ADX_CONFIG_FILE${C_RESET}
  4) Estado a qualquer momento:  ${C_BOLD}android-dex --status${C_RESET}

Se acabou de entrar num grupo novo (plugdev/adbusers), ${C_YELLOW}reloge${C_RESET} para o USB autorizar sem root.
EOF
}

main() {
  log_step "Android-DEX Kit — instalação"
  install_deps
  setup_udev
  install_files
  final_hint
}
if [ "${BASH_SOURCE[0]}" = "$0" ]; then main; fi

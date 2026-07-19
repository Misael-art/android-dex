#!/usr/bin/env bash
# uninstall.sh — remove o Android-DEX Kit (mantém dependências scrcpy/adb).
#
# Uso:
#   ./uninstall.sh            # remove arquivos do kit (preserva config)
#   ./uninstall.sh --purge    # remove também config, logs e regra udev
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
. "$SRC_DIR/lib/common.sh" 2>/dev/null || {
  XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
  XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
  ADX_CONFIG_DIR="$XDG_CONFIG_HOME/android-dex"
  ADX_DATA_DIR="$XDG_DATA_HOME/android-dex"
  ADX_STATE_DIR="$XDG_STATE_HOME/android-dex"
  log_info(){ echo "[INFO] $*" >&2; }; log_ok(){ echo "[OK] $*" >&2; }
  log_step(){ echo "==> $*" >&2; }; log_warn(){ echo "[WARN] $*" >&2; }
  have(){ command -v "$1" >/dev/null 2>&1; }
}

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

log_step "Removendo Android-DEX Kit"

# parar serviço + sessão
if have systemctl; then
  systemctl --user disable --now android-dex.service 2>/dev/null || true
fi
if [ -x "$HOME/.local/bin/android-dex" ]; then "$HOME/.local/bin/android-dex" --stop 2>/dev/null || true; fi

rm -f "$HOME/.local/bin/android-dex" "$HOME/.local/bin/android-dex-connect" "$HOME/.local/bin/android-dex-doctor"
rm -f "$XDG_DATA_HOME/applications/android-dex.desktop"
rm -f "$XDG_DATA_HOME/icons/hicolor/scalable/apps/android-dex.svg"
rm -f "$XDG_CONFIG_HOME/systemd/user/android-dex.service"
rm -rf "$ADX_DATA_DIR"
if have systemctl; then systemctl --user daemon-reload 2>/dev/null || true; fi
if have update-desktop-database; then update-desktop-database "$XDG_DATA_HOME/applications" >/dev/null 2>&1 || true; fi
log_ok "Binários, lançador, ícone e serviço removidos."

if [ "$PURGE" = "1" ]; then
  rm -rf "$ADX_CONFIG_DIR" "$ADX_STATE_DIR"
  log_ok "Config e logs removidos."
  if [ -f /etc/udev/rules.d/51-android-dex.rules ]; then
    if have sudo; then
      if sudo rm -f /etc/udev/rules.d/51-android-dex.rules; then sudo udevadm control --reload-rules 2>/dev/null || true; fi
      log_ok "Regra udev removida."
    else
      log_warn "Remova a regra udev manualmente: /etc/udev/rules.d/51-android-dex.rules"
    fi
  fi
else
  log_info "Config preservado em $ADX_CONFIG_DIR (use --purge para remover)."
fi

log_ok "Desinstalação concluída. (scrcpy e adb foram mantidos.)"

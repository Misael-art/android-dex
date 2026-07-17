#!/usr/bin/env bash
# uninstall.sh — remove o android-dex-flash (mantém adb/fastboot/heimdall).
#
# Uso:
#   ./uninstall.sh            # remove binário e libs (preserva config/backups)
#   ./uninstall.sh --purge    # remove também config, logs e backups
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
. "$SRC_DIR/lib/common.sh" 2>/dev/null || {
  XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
  XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
  log_info(){ echo "[INFO] $*" >&2; }; log_ok(){ echo "[OK] $*" >&2; }
  log_step(){ echo "==> $*" >&2; }; log_warn(){ echo "[WARN] $*" >&2; }
}

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

CFG="$XDG_CONFIG_HOME/android-dex-flash"
DATA="$XDG_DATA_HOME/android-dex-flash"
STATE="$XDG_STATE_HOME/android-dex-flash"

log_step "Removendo android-dex-flash"
rm -f "$HOME/.local/bin/android-dex-flash"
rm -rf "$DATA"
log_ok "Binário e libs removidos."

if [ "$PURGE" = "1" ]; then
  rm -rf "$CFG" "$STATE"
  log_ok "Config, logs e backups removidos."
else
  log_info "Config/backups preservados em $CFG e $STATE (use --purge para remover)."
fi
log_ok "Desinstalação concluída. (adb/fastboot/heimdall foram mantidos.)"

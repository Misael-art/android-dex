#!/usr/bin/env bash
# common.sh — funções compartilhadas do Android-DEX Kit
# Sourced por: android-dex, android-dex-connect, install.sh, uninstall.sh
# Não deve ser executado diretamente.

# ---------------------------------------------------------------------------
# Diretórios XDG (com fallbacks) e caminhos padrão
# ---------------------------------------------------------------------------
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"

ADX_APP_NAME="android-dex"
ADX_CONFIG_DIR="$XDG_CONFIG_HOME/$ADX_APP_NAME"
ADX_CONFIG_FILE="$ADX_CONFIG_DIR/config.env"
ADX_DATA_DIR="$XDG_DATA_HOME/$ADX_APP_NAME"
ADX_STATE_DIR="$XDG_STATE_HOME/$ADX_APP_NAME"
ADX_LOG_FILE="$ADX_STATE_DIR/$ADX_APP_NAME.log"
ADX_LOG_MAX_BYTES="${ADX_LOG_MAX_BYTES:-2097152}"   # 2 MiB — rotação simples

mkdir -p "$ADX_STATE_DIR" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Cores (desligadas se não for TTY ou se NO_COLOR estiver setado)
# ---------------------------------------------------------------------------
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_BOLD=$'\033[1m'
else
  C_RESET=; C_DIM=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_BOLD=
fi

# ---------------------------------------------------------------------------
# Logging: escreve no stderr (com cor) e em arquivo (sem cor), com rotação.
# ---------------------------------------------------------------------------
_adx_rotate_log() {
  [ -f "$ADX_LOG_FILE" ] || return 0
  local size
  size=$(wc -c < "$ADX_LOG_FILE" 2>/dev/null || echo 0)
  if [ "${size:-0}" -gt "$ADX_LOG_MAX_BYTES" ]; then
    mv -f "$ADX_LOG_FILE" "$ADX_LOG_FILE.1" 2>/dev/null || true
  fi
}

_adx_log() {
  # $1 = nível, $2 = cor, resto = mensagem
  local level="$1" color="$2"; shift 2
  local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
  local msg="$*"
  _adx_rotate_log
  printf '%s [%s] %s\n' "$ts" "$level" "$msg" >> "$ADX_LOG_FILE" 2>/dev/null || true
  printf '%s%s [%s]%s %s\n' "$color" "$ts" "$level" "$C_RESET" "$msg" >&2
}

log_info()  { _adx_log "INFO"  "$C_BLUE"   "$@"; }
log_ok()    { _adx_log "OK"    "$C_GREEN"  "$@"; }
log_warn()  { _adx_log "WARN"  "$C_YELLOW" "$@"; }
log_error() { _adx_log "ERRO"  "$C_RED"    "$@"; }
log_step()  { printf '\n%s==>%s %s%s\n' "$C_BOLD$C_BLUE" "$C_RESET" "$C_BOLD" "$*$C_RESET" >&2; }

die() { log_error "$@"; exit 1; }

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# Compara versões semânticas: retorna 0 se $1 >= $2
version_ge() {
  # uso: version_ge "3.3.1" "3.0"
  [ "$1" = "$2" ] && return 0
  local lower
  lower="$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)"
  [ "$lower" = "$2" ]
}

# Backoff exponencial com teto e jitter. Ecoa o próximo atraso (segundos).
# uso: delay=$(adx_backoff "$attempt" "$base" "$cap")
adx_backoff() {
  local attempt="$1" base="${2:-2}" cap="${3:-30}"
  local d=$(( base * (1 << (attempt > 5 ? 5 : attempt)) ))
  # jitter de 0..1s para evitar reconexões sincronizadas
  d=$(( d + RANDOM % 2 ))
  [ "$d" -gt "$cap" ] && d="$cap"
  echo "$d"
}

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------
adx_load_config() {
  if [ -f "$ADX_CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    set -a; . "$ADX_CONFIG_FILE"; set +a
  fi
  # Registra o que veio explicitamente de config/ambiente para que perfis de
  # aparelho só preencham lacunas e nunca sobrescrevam escolhas do usuário.
  [ "${START_APP+x}" = x ] && ADX_USER_START_APP_SET=1 || ADX_USER_START_APP_SET=0
  [ "${VD_SYSTEM_DECORATIONS+x}" = x ] && ADX_USER_DECORATIONS_SET=1 || ADX_USER_DECORATIONS_SET=0
  [ "${ENABLE_FREEFORM_TWEAKS+x}" = x ] && ADX_USER_FREEFORM_SET=1 || ADX_USER_FREEFORM_SET=0
  # Defaults (só aplicados se o config não definiu)
  : "${MODE:=auto}"                # auto | dex | mirror
  : "${CONNECTION:=auto}"          # auto | usb | wifi
  : "${DEVICE_IP:=}"               # ex.: 192.168.1.100:5555
  : "${DEVICE_SERIAL:=}"           # força um serial específico
  : "${DISPLAY_RES:=1920x1080}"
  : "${DISPLAY_DPI:=160}"
  : "${MAX_FPS:=60}"
  : "${VIDEO_BITRATE:=8M}"
  : "${AUDIO:=1}"
  : "${STAY_AWAKE:=1}"
  : "${TURN_SCREEN_OFF:=0}"        # em modo dex a tela física fica livre
  : "${ENABLE_FREEFORM_TWEAKS:=1}" # habilita janelas livres (desktop mode)
  : "${RESTORE_TWEAKS_ON_EXIT:=0}"
  : "${VD_SYSTEM_DECORATIONS:=1}"   # 0 = --no-vd-system-decorations (UI quebrada)
  : "${START_APP:=}"               # pacote a abrir no display virtual (ex.: launcher)
  : "${RECONNECT:=1}"              # supervisor auto-reconecta
  : "${BACKOFF_BASE:=2}"
  : "${BACKOFF_CAP:=30}"
  : "${HEALTHY_SESSION_SECONDS:=15}" # só zera backoff após sessão estável
  : "${AUTO_DEX_MIN_SDK:=35}"       # Android 15; política auto conservadora
  : "${WINDOW_TITLE:=Android DEX}"
  : "${EXTRA_ARGS:=}"
}

# ---------------------------------------------------------------------------
# ADB helpers — nunca assumem que o servidor está de pé
# ---------------------------------------------------------------------------
adb_ensure_server() {
  have adb || die "adb não encontrado no PATH. Rode install.sh primeiro."
  adb start-server >/dev/null 2>&1 || true
}

# Lista os seriais online por transporte, um por linha.
adb_usb_serials() {
  adb devices 2>/dev/null | awk 'NR>1 && $2=="device" && $1 !~ /:[0-9]+$/ {print $1}'
}

adb_tcp_serials() {
  adb devices 2>/dev/null | awk 'NR>1 && $2=="device" && $1 ~ /:[0-9]+$/ {print $1}'
}

# Ecoa um serial somente quando há exatamente um candidato. Retorno 2 significa
# ambiguidade e deve bloquear fallbacks para outro transporte/dispositivo.
_adb_unique_serial_from() {
  local kind="$1" serial="" item count=0
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    serial="$item"
    count=$((count + 1))
  done
  case "$count" in
    0) return 1 ;;
    1) printf '%s\n' "$serial" ;;
    *) log_error "Há $count dispositivos $kind online. Defina DEVICE_SERIAL explicitamente para evitar selecionar o aparelho errado."; return 2 ;;
  esac
}

adb_unique_usb_serial() { adb_usb_serials | _adb_unique_serial_from USB; }
adb_unique_tcp_serial() { adb_tcp_serials | _adb_unique_serial_from TCP/IP; }

# Compatibilidade com scripts externos antigos. Novos fluxos devem preferir os
# helpers unique acima para não selecionar silenciosamente o primeiro aparelho.
adb_first_usb_serial() { adb_usb_serials | head -n1; }
adb_first_tcp_serial() { adb_tcp_serials | head -n1; }

# Verdadeiro se o serial dado está em estado "device".
adb_serial_online() {
  local s="$1"
  [ -n "$s" ] || return 1
  adb devices 2>/dev/null | awk -v s="$s" 'NR>1 && $1==s && $2=="device"{f=1} END{exit f?0:1}'
}

# Um serial é TCP se contém ":porta"
adx_is_tcp_serial() { case "$1" in *:*[0-9]) return 0;; *) return 1;; esac; }

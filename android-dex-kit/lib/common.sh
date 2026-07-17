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

adx_debug() {
  [ "${ADX_DEBUG:-0}" = "1" ] || return 0
  _adx_log "DEBUG" "$C_DIM" "$@"
}

# Executa um comando não fatal e, quando ADX_DEBUG=1, registra comando e rc.
# Não use para comandos que recebam segredos na linha de comando (ex.: adb pair).
adx_try() {
  local rc rendered
  "$@"; rc=$?
  if [ "$rc" -ne 0 ] && [ "${ADX_DEBUG:-0}" = "1" ]; then
    printf -v rendered '%q ' "$@"
    adx_debug "Comando não fatal falhou (rc=$rc): ${rendered% }"
  fi
  return "$rc"
}

adx_try_quiet() {
  local rc rendered
  "$@" >/dev/null 2>&1; rc=$?
  if [ "$rc" -ne 0 ] && [ "${ADX_DEBUG:-0}" = "1" ]; then
    printf -v rendered '%q ' "$@"
    adx_debug "Comando silencioso não fatal falhou (rc=$rc): ${rendered% }"
  fi
  return "$rc"
}

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
  : "${ADB_TCP_PORT:=5555}"        # porta escolhida no fluxo legado adb tcpip
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
  : "${ADX_DEBUG:=0}"
}

# ---------------------------------------------------------------------------
# ADB helpers — nunca assumem que o servidor está de pé
# ---------------------------------------------------------------------------
adb_ensure_server() {
  have adb || die "adb não encontrado no PATH. Rode install.sh primeiro."
  adx_try_quiet adb start-server || true
}

# Lista os seriais online por transporte, um por linha.
adb_usb_serials() {
  adb devices 2>/dev/null | awk 'NR>1 && $2=="device" && $1 !~ /:[0-9]+$/ {print $1}'
}

adb_tcp_serials() {
  adb devices 2>/dev/null | awk 'NR>1 && $2=="device" && $1 ~ /:[0-9]+$/ {print $1}'
}

adb_online_serials() {
  adb devices 2>/dev/null | awk 'NR>1 && $2=="device" {print $1}'
}

# Mostra todos os transportes conhecidos, inclusive unauthorized/offline, para
# que o usuário entenda por que um aparelho não pode ser selecionado.
adb_list_devices() {
  local line serial state details model transport index=0
  printf '%-4s %-24s %-14s %-10s %s\n' '#' 'SERIAL' 'ESTADO' 'CONEXÃO' 'MODELO'
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    serial="${line%%[[:space:]]*}"
    details="${line#"$serial"}"
    # shellcheck disable=SC2086
    set -- $details
    state="${1:-desconhecido}"
    model="$(printf '%s\n' "$details" | sed -n 's/.* model:\([^[:space:]]*\).*/\1/p')"
    if adx_is_tcp_serial "$serial"; then transport='Wi-Fi'; else transport='USB'; fi
    index=$((index + 1))
    printf '%-4s %-24s %-14s %-10s %s\n' "$index" "$serial" "$state" "$transport" "${model:-—}"
  done < <(adb devices -l 2>/dev/null | sed '1d;/^[[:space:]]*$/d')
  [ "$index" -gt 0 ] || printf '%s\n' 'Nenhum aparelho detectado.'
}

_adb_serial_description() {
  local wanted="$1" line details model transport
  line="$(adb devices -l 2>/dev/null | awk -v s="$wanted" 'NR>1 && $1==s {print; exit}')"
  details="${line#"$wanted"}"
  model="$(printf '%s\n' "$details" | sed -n 's/.* model:\([^[:space:]]*\).*/\1/p')"
  if adx_is_tcp_serial "$wanted"; then transport='Wi-Fi'; else transport='USB'; fi
  printf '%s (%s, %s)' "$wanted" "$transport" "${model:-modelo desconhecido}"
}

# Seleciona somente entre aparelhos online do transporte pedido. Com múltiplos
# aparelhos, pergunta apenas em TTY; pipelines/serviços continuam fail-closed.
adb_choose_serial() {
  local kind="$1" item choice count=0
  local -a candidates=()
  case "$kind" in
    USB) mapfile -t candidates < <(adb_usb_serials) ;;
    TCP/IP) mapfile -t candidates < <(adb_tcp_serials) ;;
    *) mapfile -t candidates < <(adb_online_serials) ;;
  esac
  count="${#candidates[@]}"
  case "$count" in
    0) return 1 ;;
    1) printf '%s\n' "${candidates[0]}"; return 0 ;;
  esac
  if [ ! -t 0 ]; then
    log_error "Há $count dispositivos $kind online. Use --list e --device SERIAL (ou defina DEVICE_SERIAL) para evitar selecionar o aparelho errado."
    return 2
  fi
  log_warn "Há $count dispositivos $kind online. Escolha o aparelho desta sessão:"
  for item in "${!candidates[@]}"; do
    printf '  %s) %s\n' "$((item + 1))" "$(_adb_serial_description "${candidates[$item]}")" >&2
  done
  while :; do
    printf 'Número do aparelho (1-%s, vazio cancela): ' "$count" >&2
    IFS= read -r choice || return 2
    [ -n "$choice" ] || return 2
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
      printf '%s\n' "${candidates[$((choice - 1))]}"
      return 0
    fi
    log_warn "Seleção inválida: '$choice'."
  done
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

adx_valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

adx_valid_endpoint() {
  local endpoint="$1" host port
  case "$endpoint" in *:*) ;; *) return 1 ;; esac
  host="${endpoint%:*}"; port="${endpoint##*:}"
  [ -n "$host" ] || return 1
  [[ "$host" =~ ^[A-Za-z0-9._:-]+$ ]] || [[ "$host" =~ ^\[[0-9A-Fa-f:]+\]$ ]] || return 1
  adx_valid_port "$port"
}

# Endpoints publicados pelo serviço de Depuração sem fio do Android 11+.
adb_mdns_connect_endpoints() {
  adb mdns services 2>/dev/null | awk '
    /_adb-tls-connect\._tcp/ {
      for (i=1; i<=NF; i++)
        if ($i ~ /^\[[0-9A-Fa-f:]+\]:[0-9]+$/ || $i ~ /^[A-Za-z0-9._-]+:[0-9]+$/) print $i
    }' | awk '!seen[$0]++'
}

# Retorna um endpoint mDNS único, opcionalmente limitado ao host informado.
adb_discover_connect_endpoint() {
  local wanted_host="${1:-}" endpoint host found="" count=0
  while IFS= read -r endpoint; do
    adx_valid_endpoint "$endpoint" || continue
    host="${endpoint%:*}"
    [ -z "$wanted_host" ] || [ "$host" = "$wanted_host" ] || continue
    found="$endpoint"; count=$((count + 1))
  done < <(adb_mdns_connect_endpoints)
  case "$count" in
    0) return 1 ;;
    1) printf '%s\n' "$found" ;;
    *) log_error "Há $count endpoints de conexão mDNS para ${wanted_host:-os aparelhos detectados}; informe IP:PORTA explicitamente."; return 2 ;;
  esac
}

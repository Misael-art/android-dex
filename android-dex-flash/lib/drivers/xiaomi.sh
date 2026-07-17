#!/usr/bin/env bash
# drivers/xiaomi.sh — Xiaomi / Redmi / POCO (HyperOS/MIUI). Base fastboot, mas o
# UNLOCK depende da ferramenta PROPRIETÁRIA Mi Unlock com espera oficial.
#
# A ferramenta ORIENTA o processo oficial; NÃO tenta burlar a espera nem o
# login Mi — fazer isso violaria os termos e não é confiável/seguro.

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/generic.sh"

driver_caps() {
  cat >&2 <<TXT
  Xiaomi / Redmi / POCO (HyperOS/MIUI):

    • unlock         → SÓ pela Mi Unlock Tool OFICIAL (proprietária, Windows).
                       Exige conta Mi vinculada ao aparelho e uma ESPERA imposta
                       pela Xiaomi (dias/semana). Este driver te guia; a etapa de
                       unlock em si é feita na ferramenta oficial da Xiaomi.
    • root           → após desbloqueado: Magisk sobre o boot.img do fastboot ROM
                       do seu modelo → fastboot flash boot. (fluxo AOSP padrão)
    • flash-firmware → fastboot ROM oficial do modelo (pacote com images/ +
                       scripts flash_all.sh). Use o script do próprio pacote.

  O que se perde:
    • Garantia; Play Integrity cai (banco/Wallet podem parar); wipe no unlock.
    • HyperOS recente aumentou restrições de conta/região p/ desbloquear.

  Requisitos: para unlock, a Mi Unlock Tool oficial (Windows). Para root/flash,
  fastboot atualizado no host.
TXT
}

driver_warnings() {
  local action="$1"
  case "$action" in
    unlock)
      warn_irreversible \
        "O unlock Xiaomi é feito pela Mi Unlock Tool OFICIAL (Windows), não aqui." \
        "Exige conta Mi vinculada + espera oficial imposta pela Xiaomi (dias)." \
        "APAGA o aparelho; Play Integrity cai."
      ;;
    root) warn_irreversible "Use o boot.img do fastboot ROM do SEU modelo/versão — outro = bootloop." ;;
    flash-firmware) warn_irreversible "Use o fastboot ROM oficial do modelo; anti-rollback impede downgrade." ;;
  esac
}

driver_unlock() {
  cat >&2 <<'TXT'

  Desbloqueio Xiaomi (processo OFICIAL, não automatizável com segurança):
    1) No aparelho: Configurações → Sobre → vincular conta Mi; ligar
       "Desbloqueio de OEM" e "Depuração USB".
    2) Configurações → Config. adicionais → Opções do desenvolvedor →
       "Status de desbloqueio de Mi" → adicionar conta/dispositivo.
    3) No PC (Windows): baixe a Mi Unlock Tool OFICIAL da Xiaomi, faça login com
       a MESMA conta Mi, entre no fastboot e clique em "Unlock". Se a Xiaomi
       impuser espera (ex.: 168h), aguarde e repita — não há como burlar com
       segurança.

  Depois de desbloqueado, volte aqui para 'root' e 'flash-firmware'.
TXT
  log_warn "Este driver não executa o unlock Xiaomi (é proprietário/Windows). Ele te guia pelo processo oficial."
}

# root / flash-firmware / restore-boot herdados do generic.sh (fastboot).
# Para flash-firmware, aponte para o diretório do fastboot ROM (tem flash_all.sh).
driver_flash_firmware() {
  local path="${1:-}"
  [ -n "$path" ] || die "Uso: flash-firmware <dir-do-fastboot-ROM (com flash_all.sh)>"
  if [ -d "$path" ] && [ -f "$path/flash_all.sh" ]; then
    fb_require || return 1
    warn_irreversible "flash_all.sh do fastboot ROM apaga e regrava tudo. Confira o modelo."
    log_warn "O android-dex-flash não executa scripts contidos no fastboot ROM."
    log_info "Confira codename, região, variante, anti-rollback e hashes; conclua com a ferramenta oficial Xiaomi."
  else
    # cai para o fluxo genérico (flash-all.sh / zip)
    fb_flash_factory "$path"
  fi
}

# Unlock é um guia manual; gravações automáticas permanecem bloqueadas.
driver_commit_supported() { return 1; }

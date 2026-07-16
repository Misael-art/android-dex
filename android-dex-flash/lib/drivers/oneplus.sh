#!/usr/bin/env bash
# drivers/oneplus.sh — OnePlus / OPPO / Realme (e Sony, fluxo próximo). Base
# fastboot. OnePlus costuma permitir 'fastboot flashing unlock' direto; OPPO/
# Realme muitas vezes exigem uma app oficial de "deep testing" para liberar.

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/generic.sh"

driver_caps() {
  cat >&2 <<TXT
  OnePlus / OPPO / Realme (e Sony):

    • unlock         → OnePlus: 'fastboot flashing unlock' direto (com
                       "Desbloqueio de OEM" ligado). OPPO/Realme (ColorOS/
                       RealmeUI): normalmente exigem a app oficial "In-Depth Test"
                       para liberar o unlock — passo manual/oficial.
                       Sony: unlock por código no site oficial da Sony.
    • root           → Magisk sobre o boot.img do firmware do modelo → flash.
    • flash-firmware → OnePlus: payload.bin de OTA (payload-dumper) + fastboot,
                       ou MSMDownloadTool (Windows) p/ recuperação profunda.

  O que se perde:
    • Garantia; Play Integrity cai; wipe no unlock. OPPO/Realme costumam ser
      mais restritivos; alguns modelos praticamente não desbloqueiam.
    • Sony: câmera/recursos podem degradar por perda de chaves DRM.

  Requisitos: fastboot no host. Para OTAs A/B, 'payload-dumper' ajuda a extrair.
TXT
}

driver_warnings() {
  local action="$1"
  case "$action" in
    unlock)
      warn_irreversible \
        "APAGA o aparelho. OPPO/Realme podem exigir a app oficial 'In-Depth Test'." \
        "Sony perde chaves DRM (câmera/recursos degradam). Play Integrity cai."
      ;;
    root) warn_irreversible "boot.img do MESMO firmware do modelo — outro = bootloop." ;;
    flash-firmware) warn_irreversible "Use firmware/OTA oficial do modelo; anti-rollback pode brickar downgrade." ;;
  esac
}

driver_unlock() {
  fb_require || return 1
  log_info "OnePlus: 'flashing unlock' direto. OPPO/Realme: pode falhar sem a app oficial de teste."
  warn_irreversible "'fastboot flashing unlock' APAGA todos os dados."
  run_or_echo fastboot flashing unlock || run_or_echo fastboot oem unlock
  run_or_echo fastboot reboot
  log_ok "Comando de unlock enviado. Se falhou em OPPO/Realme, use a app oficial 'In-Depth Test' e tente de novo."
}

# root / flash-firmware / restore-boot herdados do generic.sh (fastboot).

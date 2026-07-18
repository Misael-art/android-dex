#!/usr/bin/env bash
# drivers/oneplus.sh — OnePlus. Base fastboot; modelos e operadoras podem impor
# restrições adicionais, por isso a gravação permanece guiada.

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/generic.sh"

driver_caps() {
  cat >&2 <<TXT
  OnePlus:

    • unlock         → 'fastboot flashing unlock' (com "Desbloqueio de OEM"
                       ligado), quando o modelo/operadora permitir.
    • root           → Magisk sobre o boot.img do firmware do modelo → flash.
    • flash-firmware → OnePlus: payload.bin de OTA (payload-dumper) + fastboot,
                       ou MSMDownloadTool (Windows) p/ recuperação profunda.

  O que se perde:
    • Garantia; Play Integrity cai; wipe no unlock.

  Requisitos: fastboot no host. Para OTAs A/B, 'payload-dumper' ajuda a extrair.
TXT
}

driver_warnings() {
  local action="$1"
  case "$action" in
    unlock)
      warn_irreversible \
        "APAGA o aparelho; confirme antes se o modelo/operadora permite unlock." \
        "Play Integrity cai e apps de banco/pagamento podem parar."
      ;;
    root) warn_irreversible "boot.img do MESMO firmware do modelo — outro = bootloop." ;;
    flash-firmware) warn_irreversible "Use firmware/OTA oficial do modelo; anti-rollback pode brickar downgrade." ;;
  esac
}

driver_unlock() {
  fb_require || return 1
  log_info "OnePlus: usando o protocolo canônico 'fastboot flashing unlock'."
  warn_irreversible "'fastboot flashing unlock' APAGA todos os dados."
  fb_run flashing unlock
  fb_run reboot
  log_ok "Comando de unlock enviado. Se foi recusado, confirme elegibilidade do modelo/operadora."
}

# root / flash-firmware / restore-boot herdados do generic.sh (fastboot).
driver_commit_supported() {
  # Permanece guiado até validação em hardware por geração/modelo.
  return 1
}

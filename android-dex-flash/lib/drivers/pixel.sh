#!/usr/bin/env bash
# drivers/pixel.sh — Google Pixel / AOSP. O caminho mais limpo e documentado;
# serve de referência para os demais drivers.
#
# Fluxo canônico:
#   1) Opções do desenvolvedor → "Desbloqueio de OEM" ligado.
#   2) fastboot flashing unlock            (APAGA o aparelho)
#   3) Root: Magisk corrige o boot.img de fábrica → fastboot flash boot
#   4) Firmware: imagem de fábrica oficial (flash-all.sh) — flash.android.com
#      também funciona pelo navegador (Web USB).

# Reaproveita as primitivas fastboot do driver genérico.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/generic.sh"

driver_caps() {
  cat >&2 <<TXT
  Pixel/AOSP — o mais amigável para modificação (suporte de primeira classe):

    • unlock         → 'fastboot flashing unlock'. Exige o toggle
                       "Desbloqueio de OEM" ligado nas Opções do desenvolvedor.
                       APAGA todos os dados. Reversível com 'flashing lock'.
    • root           → Magisk sobre o boot.img de FÁBRICA do build atual.
                       Reversível (restaurar boot de estoque remove o root).
    • flash-firmware → imagem de fábrica oficial (developers.google.com/android
                       /images) via flash-all.sh, ou o Android Flash Tool no
                       navegador (flash.android.com).

  O que se perde:
    • Play Integrity cai para nível básico → Google Wallet e vários apps de
      banco podem parar (contornável com Play Integrity Fix, sem garantia).
    • Wipe total no unlock. Garantia em geral preservada legalmente nos EUA/UE,
      mas alguns apps/serviços se recusam a rodar.

  Pré-requisitos no host: fastboot atualizado. Bootloaders de operadora (ex.:
  Verizon) podem ser IMPOSSÍVEIS de desbloquear.
TXT
}

driver_warnings() {
  local action="$1"
  case "$action" in
    unlock)
      warn_irreversible \
        "'fastboot flashing unlock' APAGA todos os dados do Pixel." \
        "Requer 'Desbloqueio de OEM' ligado; bootloader de operadora pode recusar." \
        "Play Integrity cairá — Wallet e apps de banco podem parar."
      ;;
    root)
      warn_irreversible \
        "Use o boot.img de FÁBRICA do MESMO build instalado — outro build = bootloop." \
        "Reversível: restaurar o boot de estoque remove o root."
      ;;
    flash-firmware)
      warn_irreversible \
        "flash-all.sh regrava TODAS as partições e apaga dados." \
        "Anti-rollback: NÃO grave build mais antigo que o atual."
      ;;
  esac
}

# Herdadas do generic.sh (fastboot puro é o caminho certo p/ Pixel):
#   driver_unlock / driver_root / driver_flash_firmware / driver_restore_boot

# Neste estágio, somente o unlock canônico do Pixel pode executar no host.
# Root/firmware/restore permanecem guiados até validação forte do artefato.
driver_commit_supported() {
  case "$1" in unlock|boot-recovery) return 0 ;; *) return 1 ;; esac
}

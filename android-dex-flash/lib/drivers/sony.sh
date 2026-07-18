#!/usr/bin/env bash
# drivers/sony.sh — Sony Xperia. O site oficial fornece um código por IMEI para
# modelos elegíveis; o unlock pode apagar chaves DRM e degradar câmera/recursos.

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/generic.sh"

driver_caps() {
  cat >&2 <<'TXT'
  Sony Xperia:

    • unlock         → verifique "Bootloader unlock allowed" no service menu,
                       obtenha o código no portal oficial Sony e use o comando
                       indicado pelo fabricante. APAGA os dados.
    • root           → Magisk sobre boot/init_boot do build exato.
    • flash-firmware → Xperia Companion/Emma ou pacote oficial compatível.

  O que pode ser permanente: perda de chaves DRM, degradação de câmera e de
  recursos proprietários, além de Play Integrity. Gravações ficam guiadas.
TXT
}

driver_warnings() {
  local action="$1"
  case "$action" in
    unlock) warn_irreversible "Unlock Sony pode apagar chaves DRM permanentemente." "Câmera e recursos proprietários podem degradar; ocorre wipe total." ;;
    root|flash-firmware|restore-boot) warn_irreversible "Imagem precisa corresponder ao Xperia/build exato." ;;
  esac
}

driver_unlock() {
  fb_require || return 1
  [ -n "${UNLOCK_CODE:-}" ] || die "Obtenha UNLOCK_CODE no portal oficial Sony após confirmar elegibilidade do IMEI."
  log_info "Roteiro oficial: fastboot oem unlock 0x<CÓDIGO> (não executado automaticamente)."
  fb_run oem unlock "0x$UNLOCK_CODE"
}

driver_commit_supported() { return 1; }

#!/usr/bin/env bash
# drivers/motorola.sh — Motorola / Lenovo. Base fastboot. O unlock exige um
# CÓDIGO gerado no site OFICIAL da Motorola a partir do identificador do device.

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/generic.sh"

driver_caps() {
  cat >&2 <<TXT
  Motorola / Lenovo:

    • unlock         → 2 passos de fastboot: obter o dado do device
                       ('fastboot oem get_unlock_data'), colar no site OFICIAL da
                       Motorola p/ receber um CÓDIGO por e-mail, e então
                       'fastboot oem unlock <CÓDIGO>'. APAGA o aparelho.
    • root           → Magisk sobre o boot.img do firmware do modelo → flash.
    • flash-firmware → firmware oficial (pacote com flashfile) via fastboot.

  O que se perde:
    • Garantia; Play Integrity cai; wipe no unlock. Alguns modelos de operadora
      (ex.: alguns nos EUA) NÃO são elegíveis a desbloqueio.

  Requisitos: fastboot no host + conta/registro no site oficial da Motorola.
TXT
}

driver_warnings() {
  local action="$1"
  case "$action" in
    unlock)
      warn_irreversible \
        "Unlock Motorola exige CÓDIGO do site oficial (elegibilidade varia)." \
        "APAGA o aparelho; modelos de operadora podem ser inelegíveis." \
        "Play Integrity cai; garantia afetada."
      ;;
    root) warn_irreversible "boot.img do MESMO firmware do modelo — outro = bootloop." ;;
    flash-firmware) warn_irreversible "Use o firmware oficial do modelo; anti-rollback pode brickar downgrade." ;;
  esac
}

driver_unlock() {
  fb_require || return 1
  log_step "Obtendo dados de desbloqueio da Motorola"
  run_or_echo fastboot oem get_unlock_data
  cat >&2 <<'TXT'

  Próximos passos (oficiais):
    1) Junte as linhas do 'unlock data' acima em uma string única.
    2) Vá ao site OFICIAL de desbloqueio da Motorola, faça login, cole a string
       e verifique a elegibilidade. Se elegível, você recebe um CÓDIGO por e-mail.
    3) Rode:  UNLOCK_CODE=<código> android-dex-flash unlock --commit
TXT
  if [ -n "${UNLOCK_CODE:-}" ]; then
    warn_irreversible "'fastboot oem unlock' APAGA o aparelho."
    run_or_echo fastboot oem unlock "$UNLOCK_CODE"
    run_or_echo fastboot reboot
    log_ok "Comando de unlock enviado."
  else
    log_warn "Sem UNLOCK_CODE ainda — pare aqui, obtenha o código no site oficial e volte."
  fi
}

# root / flash-firmware / restore-boot herdados do generic.sh (fastboot).

#!/usr/bin/env bash
# drivers/oppo.sh — OPPO / Realme. O desbloqueio depende de elegibilidade e do
# mecanismo oficial da região/modelo; não se presume compatibilidade OnePlus.

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/generic.sh"

driver_caps() {
  cat >&2 <<'TXT'
  OPPO / Realme (ColorOS / Realme UI):

    • unlock         → somente quando o fabricante oferece o fluxo oficial de
                       Deep Testing/In-Depth Test para o modelo e a região.
                       Sem essa autorização, fastboot não é uma alternativa.
    • root           → após unlock oficial, Magisk sobre boot/init_boot exato.
    • flash-firmware → ferramenta/pacote oficial específico do modelo/região.

  Este driver nunca tenta explorar, burlar conta/região ou tratar o aparelho
  como OnePlus. Todas as gravações permanecem somente guiadas.
TXT
}

driver_warnings() {
  local action="$1"
  case "$action" in
    unlock) warn_irreversible "Elegibilidade depende do modelo/região e do fluxo oficial Deep Testing." "Unlock apaga dados e reduz Play Integrity." ;;
    root|flash-firmware|restore-boot) warn_irreversible "Use somente imagem oficial do modelo, região e build exatos." ;;
  esac
}

driver_unlock() {
  cat >&2 <<'TXT'
  Consulte no suporte oficial OPPO/Realme se existe Deep Testing para seu modelo
  e região. Conclua a autorização no aparelho; não há comando genérico seguro.
TXT
  die "Unlock OPPO/Realme não é automatizado sem autorização oficial específica."
}

driver_commit_supported() { return 1; }

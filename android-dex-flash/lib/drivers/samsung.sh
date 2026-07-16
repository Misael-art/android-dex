#!/usr/bin/env bash
# drivers/samsung.sh — Samsung Galaxy. NÃO usa fastboot: usa modo Download
# (Odin protocol) via Heimdall (open-source, cross-platform).
#
# AVISO CENTRAL: desbloquear o bootloader QUEIMA o Knox e-fuse — permanente e
# irreversível. Samsung Pay/Pass, Secure Folder, Health e recursos Knox param
# PARA SEMPRE. Muitos modelos Snapdragon (EUA) têm bootloader que NÃO desbloqueia.

driver_caps() {
  cat >&2 <<TXT
  Samsung Galaxy — modificação possível, porém com o CUSTO MAIS ALTO da lista:

    • unlock         → via toggle "Desbloqueio de OEM" + segurar Vol nos botões
                       no modo Download. QUEIMA O KNOX (e-fuse 0x1),
                       PERMANENTE E IRREVERSÍVEL.
    • root           → Magisk sobre o AP (boot/recovery) do firmware oficial;
                       gravado com heimdall no modo Download.
    • flash-firmware → firmware oficial (.tar.md5: AP/BL/CP/CSC) via heimdall.
                       Baixe da Samsung com samloader/Frija (fontes oficiais).

  O que se perde ao desbloquear (Knox tripado, PARA SEMPRE):
    • Samsung Pay/Wallet, Samsung Pass, Secure Folder, Samsung Health (dados),
      Knox/segurança corporativa. Play Integrity cai (apps de banco quebram).
    • Muitos Galaxy Snapdragon (mercado EUA) NÃO são desbloqueáveis — sem opção.

  Requisitos no host: 'heimdall' (heimdall-flash). Este driver NÃO usa fastboot.
TXT
}

driver_warnings() {
  local action="$1"
  case "$action" in
    unlock)
      warn_irreversible \
        "DESBLOQUEAR QUEIMA O KNOX E-FUSE — PERMANENTE E IRREVERSÍVEL." \
        "Samsung Pay/Pass/Secure Folder/Health morrem para sempre." \
        "Vários Galaxy Snapdragon (EUA) NÃO desbloqueiam — verifique antes." \
        "Requer 'Desbloqueio de OEM' ligado nas Opções do desenvolvedor."
      ;;
    root)
      warn_irreversible \
        "Root Samsung usa o AP do firmware OFICIAL do MESMO modelo/versão." \
        "Knox já terá sido tripado no unlock (permanente)."
      ;;
    flash-firmware)
      warn_irreversible \
        "Firmware precisa casar modelo + CSC (região). Errado = brick." \
        "Anti-rollback (fuse de bootloader) impede downgrade — pode brickar."
      ;;
  esac
}

sm_require() {
  require_tool heimdall "Instale 'heimdall'/'heimdall-flash' (protocolo Odin, open-source)." || return 1
  local t; t="$(fp_transport)"
  if [ "$t" != "download" ]; then
    log_warn "Aparelho não parece estar no modo Download."
    log_info "Desligue, segure Vol-Baixo + Vol-Cima e conecte o USB (ou combinação do seu modelo), aceite o aviso e conecte."
    log_info "Confira com: heimdall detect"
  fi
  return 0
}

# Descobre o toggle de OEM unlock (só dá p/ ler com adb, antes de ir p/ Download).
sm_check_oem_unlock() {
  if [ "$(fp_transport)" = "adb" ]; then
    local v; v="$(fp_getprop sys.oem_unlock_allowed)"
    [ "$v" = "1" ] || die "Ligue 'Desbloqueio de OEM' nas Opções do desenvolvedor antes de continuar (atual: '${v:-desconhecido}')."
  fi
}

driver_unlock() {
  sm_check_oem_unlock
  cat >&2 <<'TXT'

  Desbloqueio Samsung (não é um comando único de host):
    1) Opções do desenvolvedor → "Desbloqueio de OEM" LIGADO (feito acima).
    2) Desligue. Entre no modo Download (combinação do seu modelo).
    3) Na tela de aviso, SEGURE Volume-Cima por alguns segundos para
       CONFIRMAR o desbloqueio → NESTE ponto o Knox é queimado e o aparelho
       faz wipe. Não há comando de host que faça isso por você.
TXT
  warn_irreversible "A confirmação física no aparelho queima o Knox. Sem volta."
  log_warn "Este driver NÃO automatiza a queima do Knox de propósito — a confirmação é sua, no aparelho."
}

driver_root() {
  sm_require || return 1
  cat >&2 <<'TXT'

  Root Samsung via Magisk + Heimdall:
    1) Baixe o firmware OFICIAL do SEU modelo/CSC (samloader ou Frija).
    2) Extraia o AP_*.tar.md5; dele, o Magisk corrige o boot/recovery
       (app Magisk → "Instalar → Selecionar e corrigir" o AP) → AP_patched.tar.
    3) No modo Download, grave o AP corrigido com heimdall.
       Informe o .tar/.img corrigido via PATCHED_IMG=/caminho.
TXT
  local patched="${PATCHED_IMG:-}"
  [ -n "$patched" ] || die "Informe PATCHED_IMG=/caminho (AP corrigido pelo Magisk)."
  [ -f "$patched" ] || die "PATCHED_IMG não existe: $patched"
  guard_verify_sha256 "$patched" "${PATCHED_SHA256:-}"
  sm_require || return 1
  log_step "Gravando AP corrigido (Magisk) via heimdall"
  # Partição típica de boot no protocolo Odin: BOOT (varia por modelo).
  run_or_echo heimdall flash --BOOT "$patched" --no-reboot
  log_ok "Gravado. Reinicie manualmente segurando Vol-Baixo+Power e entre logo no Magisk (evita restaurar o boot no 1º boot)."
}

driver_flash_firmware() {
  local ap="${AP:-${1:-}}"
  sm_require || return 1
  cat >&2 <<'TXT'

  Firmware Samsung (oficial) via heimdall:
    Forneça os componentes do firmware do seu modelo/CSC:
      AP=/caminho/AP_*.tar.md5  BL=/caminho/BL_*.tar.md5
      CP=/caminho/CP_*.tar.md5  CSC=/caminho/CSC_*.tar.md5
    (Baixe com samloader/Frija — fontes oficiais da Samsung.)
TXT
  [ -n "$ap" ] || die "Informe ao menos AP=/caminho/AP_*.tar.md5 (e de preferência BL/CP/CSC)."
  guard_verify_model "$EXPECT_MODEL"
  log_step "Gravando firmware oficial via heimdall (modo Download)"
  # Heimdall grava por partição; para .tar oficiais o caminho robusto é
  # extrair e mapear cada imagem. Aqui delegamos ao modo interativo do heimdall
  # via flash com os arquivos que o usuário mapear em EXTRA_HEIMDALL.
  if [ -n "${EXTRA_HEIMDALL:-}" ]; then
    # shellcheck disable=SC2086
    run_or_echo heimdall flash $EXTRA_HEIMDALL
  else
    log_warn "Gravação de .tar.md5 completos exige mapear partições. Extraia os .img e informe via:"
    log_warn '  EXTRA_HEIMDALL="--BOOT boot.img --SYSTEM system.img ..." android-dex-flash flash-firmware --commit'
    die "Sem mapeamento de partições (EXTRA_HEIMDALL). Abortando por segurança."
  fi
}

driver_restore_boot() {
  die "Restauração Samsung: regrave o AP OFICIAL do seu firmware via 'flash-firmware' (heimdall)."
}

#!/usr/bin/env bash
# drivers/generic.sh — base AOSP/fastboot. Serve de fallback e de biblioteca de
# primitivas fastboot reutilizada pelos drivers pixel/motorola/oneplus.
#
# Contrato de driver (todo driver define estas funções):
#   driver_caps            — imprime o que é possível e o que se perde
#   driver_warnings ACTION — avisos específicos antes da ação
#   driver_unlock          — desbloqueia o bootloader
#   driver_root            — root via Magisk (patch boot.img + flash)
#   driver_flash_firmware ARGS — grava firmware oficial
#   driver_restore_boot    — restaura boot.img de fábrica (recuperação)

# ---------------------------------------------------------------------------
# Primitivas fastboot (usadas pelos drivers baseados em fastboot)
# ---------------------------------------------------------------------------
fb_require() {
  require_tool fastboot "Instale o pacote 'android-tools'/'fastboot' (mesmo do adb)." || return 1
  if ! fastboot devices 2>/dev/null | awk -v s="$FP_FASTBOOT_SERIAL" '$1==s{found=1} END{exit found?0:1}'; then
    log_warn "Nenhum aparelho em fastboot. Rode: android-dex-flash reboot-bootloader"
    return 1
  fi
  return 0
}

fb_run() { run_or_echo fastboot -s "$FP_FASTBOOT_SERIAL" "$@"; }

fb_unlock() {
  # Pixel/AOSP moderno: use somente o protocolo canônico. Não tente um segundo
  # comando de unlock automaticamente após falha/recusa do primeiro.
  fb_require || return 1
  log_step "Desbloqueando bootloader via fastboot"
  log_info "No aparelho, use Volume p/ selecionar e Power p/ confirmar o desbloqueio."
  fb_run flashing unlock
  fb_run reboot
  log_ok "Comando de unlock enviado. O aparelho fará wipe e reiniciará."
}

# Fluxo de root Magisk, documentado e orquestrado.
# Requer que o usuário forneça o boot.img de estoque correspondente ao firmware
# instalado (extraído da imagem de fábrica/OTA do próprio modelo).
fb_root_magisk() {
  local boot_stock="${BOOT_IMG:-}" partition="${ROOT_PARTITION:-boot}"
  case "$partition" in boot|init_boot) ;; *) die "ROOT_PARTITION deve ser boot ou init_boot." ;; esac
  cat >&2 <<'TXT'

  Root via Magisk (método moderno, reversível):
    1) Obtenha o boot.img de ESTOQUE do MESMO firmware que está no aparelho
       (da imagem de fábrica/OTA do seu modelo). Aponte via BOOT_IMG=/caminho.
    2) Instale o app Magisk no aparelho, abra-o e use "Instalar → Selecionar e
       corrigir um arquivo", escolhendo esse boot.img → gera magisk_patched.img.
    3) Traga o magisk_patched.img de volta e informe via PATCHED_IMG=/caminho.
    4) Este comando grava a partição definida por ROOT_PARTITION (boot ou
       init_boot): fastboot flash <partição> <magisk_patched.img>.

TXT
  local patched="${PATCHED_IMG:-}"
  if [ -z "$patched" ]; then
    if [ -n "$boot_stock" ] && [ -f "$boot_stock" ]; then
      log_info "Imagem de estoque validada localmente: $boot_stock. Copie-a para o aparelho selecionado e corrija-a no Magisk."
    fi
    die "Informe PATCHED_IMG=/caminho/magisk_patched.img (gerado pelo Magisk) e rode de novo."
  fi
  [ -f "$patched" ] || die "PATCHED_IMG não existe: $patched"
  guard_verify_sha256 "$patched" "${PATCHED_SHA256:-}"
  fb_require || return 1
  # Backup do que houver antes (best-effort).
  fb_backup_boot "$partition"
  log_step "Gravando boot corrigido (Magisk)"
  fb_run flash "$partition" "$patched"
  fb_run reboot
  log_ok "Boot corrigido gravado. Abra o Magisk e confirme o estado de root."
}

# Tenta salvar o boot atual (só funciona com fastbootd + partições legíveis;
# muitos aparelhos não permitem 'fetch'). Best-effort, nunca fatal.
fb_backup_boot() {
  local partition="${1:-boot}" out
  out="$BACKUP_DIR/${partition}-backup-$(date +%Y%m%d-%H%M%S).img"
  if [ "${DRY_RUN:-1}" = "1" ]; then
    log_info "[dry-run] Tentaria salvar a partição $partition em: $out"
    return 0
  fi
  if fastboot -s "$FP_FASTBOOT_SERIAL" fetch "$partition" "$out" >/dev/null 2>&1; then
    log_ok "Backup do boot atual salvo: $out"
  else
    log_warn "Não consegui fazer backup do boot via fastboot (normal em muitos aparelhos). Guarde o boot.img de fábrica manualmente."
  fi
}

fb_flash_factory() {
  # Espera um diretório de imagem de fábrica com 'flash-all.sh' (padrão Pixel)
  # OU um zip de imagens. Por segurança, apenas valida e orienta: bundles de
  # firmware são dados não confiáveis e seus scripts nunca são executados.
  local path="${1:-}"
  [ -n "$path" ] || die "Uso: flash-firmware <dir-da-imagem-de-fábrica | flash-all.sh | zip>"
  fb_require || return 1
  if [ -d "$path" ] && [ -f "$path/flash-all.sh" ]; then
    log_step "Bundle de imagem de fábrica identificado"
    warn_irreversible "flash-all.sh apaga o aparelho e regrava TODAS as partições." \
                      "Firmware do modelo ERRADO = hard-brick. Confira que é do seu device."
    log_warn "O android-dex-flash não executa scripts contidos em bundles de firmware."
    log_info "Valide modelo, variante, região, anti-rollback e hashes; depois use a ferramenta oficial do fabricante."
  elif [ -f "$path" ] && case "$path" in *.zip) true;; *) false;; esac; then
    log_step "ZIP de imagem de fábrica identificado"
    log_warn "A gravação automática por 'fastboot update' está desativada até haver um descritor assinado de compatibilidade e partições."
    log_info "Use a ferramenta oficial do fabricante após verificar modelo, variante, região, anti-rollback e SHA-256."
  else
    die "Caminho não reconhecido. Aponte para o diretório da imagem de fábrica (com flash-all.sh) ou um zip oficial."
  fi
}

fb_restore_boot() {
  local img="${BOOT_IMG:-}" partition="${BOOT_PARTITION:-boot}"
  case "$partition" in boot|init_boot) ;; *) die "BOOT_PARTITION deve ser boot ou init_boot." ;; esac
  [ -n "$img" ] || die "Informe BOOT_IMG=/caminho/boot.img (de estoque) para restaurar."
  [ -f "$img" ] || die "BOOT_IMG não existe: $img"
  guard_verify_sha256 "$img" "${BOOT_SHA256:-}"
  fb_require || return 1
  log_step "Restaurando boot de estoque"
  fb_run flash "$partition" "$img"
  fb_run reboot
  log_ok "Boot de estoque restaurado."
}

fb_boot_recovery() {
  local img="${RECOVERY_IMG:-}" sha="${RECOVERY_SHA256:-}"
  [ -n "$img" ] || die "Informe RECOVERY_IMG=/caminho/recovery.img."
  [ -f "$img" ] || die "RECOVERY_IMG não existe: $img"
  if [ "${DRY_RUN:-1}" = 1 ]; then guard_verify_sha256 "$img" "$sha"; else guard_require_sha256 "$img" "$sha"; fi
  fb_require || return 1
  [ "${DRY_RUN:-1}" = 1 ] || { guard_require_expected_model; guard_require_unlocked; }
  log_step "Inicialização temporária de recovery (não grava partição)"
  fb_run boot "$img"
  log_ok "Recovery enviado para boot temporário; a imagem não foi persistida."
}

# ---------------------------------------------------------------------------
# Implementação genérica (fallback)
# ---------------------------------------------------------------------------
driver_caps() {
  cat >&2 <<TXT
  Fabricante não mapeado por um driver dedicado — usando o fluxo AOSP/fastboot
  genérico. Pode funcionar em aparelhos que seguem o padrão fastboot.

  Possível (se o bootloader for desbloqueável via fastboot):
    • unlock         → fastboot flashing unlock  (APAGA o aparelho)
    • root           → Magisk (patch boot.img + fastboot flash boot)
    • flash-firmware → imagem de fábrica com flash-all.sh, ou 'fastboot update'

  O que se perde ao desbloquear/rootar (regra geral):
    • garantia; Play Integrity (apps de banco/Wallet podem parar);
      wipe total dos dados no unlock; risco de brick.

  ATENÇÃO: sem driver dedicado, não há avisos específicos do seu OEM.
  Confirme o procedimento correto do seu modelo antes de usar --commit.
TXT
}

driver_warnings() {
  local action="$1"
  case "$action" in
    unlock) warn_irreversible "Desbloquear o bootloader APAGA todos os dados do aparelho." \
                              "Reduz a segurança do device e pode quebrar apps que checam integridade." ;;
    root)   warn_irreversible "Root modifica o boot; apps de banco/pagamento podem parar (Play Integrity)." ;;
    flash-firmware) warn_irreversible "Firmware do modelo errado causa hard-brick. Verifique o modelo." ;;
  esac
}

driver_unlock()          { fb_unlock; }
driver_root()            { fb_root_magisk; }
driver_flash_firmware()  { fb_flash_factory "$@"; }
driver_restore_boot()    { fb_restore_boot; }
driver_boot_recovery()   { fb_boot_recovery; }

# Fallback desconhecido é sempre deny-by-default. Drivers dedicados podem
# liberar somente ações cujo protocolo esteja suficientemente definido.
driver_commit_supported() { return 1; }

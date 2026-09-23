# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/);
versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [0.1.4] — 2026-09-22

### android-dex-ui
- **Eventos em tempo real** (`events.subscribe`): conexão persistente com
  notificações JSON-RPC ordenadas por `seq` e heartbeat de 15 s. A UI assina
  automaticamente e volta ao `events.poll` se a conexão cair.
- **Histórico de manutenção** na tela Sessões (novo método `job.list`): status,
  horários, erro e caminho do log de cada job. Sessões mostram `stop-failed`
  e permitem tentar encerrar de novo.
- **Tabela única de OEM** (`oem.py`) para driver do flash e perfil desktop;
  um teste compara com `normalize_profile_key` do kit e falha se divergirem.
- **systemd de usuário com socket activation** (`systemd/android-dexd.{socket,service}`);
  o serviço aceita o socket herdado (`LISTEN_FDS`).

### Empacotamento
- **PKGBUILD** para Arch/Manjaro em `packaging/aur/` (kit + flash + UI + unidades).
- Flatpak avaliado e **não adotado**: o fluxo depende de `adb`/`scrcpy`/udev do
  host e acesso USB amplo, o que anula o sandbox. AppImage + PKGBUILD cobrem o uso.

## [0.1.3] — 2026-09-22

### android-dex-ui — robustez do serviço `android-dexd`
- **Plano de manutenção de uso único**: `maintenance.apply` consome o plano
  atomicamente; reenviar o mesmo `planId` retorna `E-PLAN-MISSING`.
- **Cursor de eventos monotônico**: `events.poll` não trava mais após 200
  eventos; cada evento tem `seq` e a resposta indica `truncated`.
- **Concorrência**: sessões e jobs protegidos por lock; dois `desktop.start`
  simultâneos criam uma única sessão.
- **Jobs órfãos** de um daemon anterior viram `interrupted` ao reiniciar.
- **`maintenance.cancel`** cancela de fato jobs canceláveis ainda na fila;
  gravações críticas continuam bloqueadas (`E-JOB-CRITICAL`).
- **Instância única**: um segundo daemon não remove o socket de um serviço vivo;
  o socket nasce com `umask 077`.
- **Sessões confiáveis**: PID reutilizado é detectado pelo tempo de início do
  processo; `--stop` com falha marca `stop-failed` e retorna `E-STOP-FAILED`.
- **Log completo por job** em `job-<id>.log` (0600); `jobs.json` guarda só o final.

### Qualidade e CI
- `make ui-test`/`ui-smoke` funcionam sem instalar o pacote (`PYTHONPATH`).
- ShellCheck sem exclusões globais de SC2034/SC2153; variável morta
  `NON_INTERACTIVE` removida.
- `appimagetool` fixado em 1.9.1 com verificação SHA-256; actions pinadas por SHA.
- Template de issue "Relatório de aparelho" para destravar A1/A3/A4/A6.

## [0.1.2] — 2026-09-02

### android-dex-kit — experiência do modo desktop (DeX)
- **Fim da "tela preta" silenciosa.** No MIUI/HyperOS o modo desktop depende de
  freeform (`settings put`) e controle (`INJECT_EVENTS`), ambos bloqueados até
  ligar **"Depuração USB (Configurações de segurança)"** + reiniciar. Antes o DeX
  abria um display virtual preto e sem controle, sem explicação.
  - Detecção **funcional e auto-reversível** do portão de segurança
    (`adx_secure_settings_state` grava/remove uma chave descartável — o `dumpsys`
    reporta a permissão como concedida mesmo quando o sistema ainda a nega).
  - **Aviso específico por marca** ao iniciar, dizendo o porquê e como resolver.
  - **Fallback automático para mirror** quando o desktop não é viável (mostra a
    tela real em vez de um display preto). `START_APP` cai para o home padrão.
- **`android-dex-doctor`**: nova seção "Controle e modo desktop" (somente leitura)
  com o requisito por marca.
- **`android-dex-connect` (Wi-Fi)**: distingue claramente o endereço de
  **EMPARELHAMENTO** (temporário) do de **CONEXÃO** (persistente) e termina com um
  resumo de próximos passos (`android-dex --wifi`).

### Geral
- `android-dex-ui` alinhado para 0.1.2 (conteúdo inalterado; mantém os artefatos
  da release na mesma versão).

## [0.1.1] — 2026-09-02

### Corrigido
- `android-dex-flash/install.sh` abortava com `ADXF_CONFIG_DIR: variável não
  associada` (sob `set -u`): o instalador referenciava variáveis definidas apenas
  em `flash-common.sh`, que ele não carrega. Agora define os caminhos de config
  localmente, como já faz o instalador do kit. A instalação do android-dex-flash
  volta a concluir (binário, libs, drivers, firmware e `flash.env`).

### Alterado
- `android-dex-ui` alinhado para **0.1.1** (`pyproject.toml` e `__version__`), para
  o wheel/sdist da release baterem com a tag. Conteúdo da UI inalterado.

## [0.1.0] — 2026-07-19

Primeira release pública do workspace **Android-DEX** (três componentes que
compartilham `lib/common.sh`).

### android-dex-ui (novo)
- Interface nativa **PySide6 Essentials + Qt Quick/QML** (pt-BR, responsiva).
- Daemon por usuário **`android-dexd`** com IPC JSON-RPC 2.0 sobre socket
  `0600` em `$XDG_RUNTIME_DIR`, UID verificado, métodos/argumentos allowlisted
  (sem `shell=True`, sem argv livre, sem scripts vindos de firmware).
- Fluxo "DeX primeiro"; firmware/bootloader isolados em **Manutenção avançada**
  com prévia, hashes SHA-256, plano vinculado ao aparelho e validade de 10 min.
- Entrypoints: `android-dex-ui`, `android-dexd`, `android-dex-setup`.
- Empacotamento **AppImage** (UI + Qt + Python embutidos) com smoke multi-distro.

### android-dex-kit
- **Modo automático** dex↔mirror por capacidade (SDK, freeform, launcher).
- **Perfis por OEM** (`profiles/*.env`) para launcher/decorações/DPI.
- `android-dex --list`/`--device` para múltiplos aparelhos; Wi-Fi com porta
  dinâmica e descoberta mDNS.
- Novo diagnóstico **`android-dex-doctor`** (somente leitura).
- Template **udev por vendor-id** (`udev/51-android-dex.rules.in`).
- Paridade Windows (PowerShell) e restauração exata de tweaks temporários.

### android-dex-flash
- Descritores de **firmware assinados** (manifest v2) com verificação OpenSSL,
  SHA-256, plano de partições e índice **anti-rollback**.
- Novos comandos somente-leitura/guiados: `verify-firmware`, `check-rollback`,
  `backup-boot`, `extract-payload`; `boot-recovery` temporário (Pixel).
- **Fail-closed**: root/firmware/restauração não aceitam `--commit` sem
  descritores certificados; bundles nunca são executados como código.
- Drivers dedicados: Pixel, Samsung (aviso Knox permanente), Xiaomi, Motorola,
  OnePlus, OPPO, Sony, genérico.

### Infra
- CI (`.github/workflows/test.yml`): shell (syntax + regressões + ShellCheck),
  parser PowerShell, testes de UI (pytest + qmltestrunner + render offscreen) e
  build/smoke do AppImage.
- Workflow de release por tag e artefatos versionados (AppImage, tarballs,
  wheel/sdist, `SHA256SUMS`).

[0.1.2]: https://github.com/Misael-art/android-dex/releases/tag/v0.1.2
[0.1.1]: https://github.com/Misael-art/android-dex/releases/tag/v0.1.1
[0.1.0]: https://github.com/Misael-art/android-dex/releases/tag/v0.1.0

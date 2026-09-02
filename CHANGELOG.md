# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/);
versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [0.1.1] — 2026-09-02

### Corrigido
- `android-dex-flash/install.sh` abortava com `ADXF_CONFIG_DIR: variável não
  associada` (sob `set -u`): o instalador referenciava variáveis definidas apenas
  em `flash-common.sh`, que ele não carrega. Agora define os caminhos de config
  localmente, como já faz o instalador do kit. A instalação do android-dex-flash
  volta a concluir (binário, libs, drivers, firmware e `flash.env`).

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

[0.1.1]: https://github.com/Misael-art/android-dex/releases/tag/v0.1.1
[0.1.0]: https://github.com/Misael-art/android-dex/releases/tag/v0.1.0

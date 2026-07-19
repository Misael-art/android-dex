# Android-DEX UI

Aplicação Linux nativa em **PySide6 Essentials + Qt Quick/QML**. A experiência
é DeX primeiro: iniciar o desktop é a ação principal; firmware e bootloader
ficam isolados no assistente **Manutenção avançada**.

## O que está implementado

- Início com detecção do aparelho, bateria e CTA DeX→mirror.
- Seleção explícita quando há mais de um dispositivo.
- Descoberta, pareamento e conexão ADB por Wi‑Fi.
- Sessões supervisionadas pelo serviço mesmo com a janela fechada.
- Diagnóstico e restauração exata dos tweaks temporários.
- Assistente de manutenção com prévia, hashes, validade de 10 minutos,
  confirmação explícita e execução apenas nos drivers já certificados.
- Interface pt-BR responsiva em 1440×1024, 1280×800 e 960×640, com atalhos
  `Ctrl+1`…`Ctrl+6`, foco visível e controles de pelo menos 48 px.

## Dependências

A UI/AppImage inclui Python e Qt. As ferramentas que interagem com o aparelho
permanecem no sistema, para receber atualizações de segurança da distribuição:

- `adb` e `fastboot` (Android platform-tools)
- `scrcpy` 3.0 ou superior para display virtual
- `heimdall` para os roteiros Samsung
- OpenSSL para descritores de firmware assinados
- regras udev do `android-dex-kit`

Verifique sem modificar o sistema:

```bash
android-dex-setup --json
```

Para delegar a instalação ao setup do kit, com prévia e autenticação do
sistema:

```bash
android-dex-setup --apply --confirm INSTALAR
```

## Instalação para desenvolvimento

```bash
cd android-dex-ui
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -e '.[test]'

android-dex-ui --demo   # seguro: não chama ferramentas externas
android-dex-ui          # aparelho real
```

Sem instalação, a partir da raiz do repositório:

```bash
PYTHONPATH=android-dex-ui/src python3 -m android_dex_ui.main --demo
```

## Arquitetura

```text
android-dex-ui (Qt/QML)
        │ JSON-RPC 2.0
        ▼
$XDG_RUNTIME_DIR/android-dex/core.sock
        │ diretório 0700 · socket 0600 · SO_PEERCRED/UID
        ▼
android-dexd (serviço por usuário)
        ├── android-dex-kit   → sessão DeX/mirror, Wi‑Fi, diagnóstico
        └── android-dex-flash → validações, dry-run e commits certificados
```

O envelope público é `{"jsonrpc":"2.0","id":"…","method":"…","params":{}}`.
Respostas contêm `result` ou um erro com `code`, `title`, `detail`,
`recoverable` e `actions`. Os schemas versionados estão em [`schemas/`](schemas/).

O serviço só conhece métodos e argumentos allowlisted. Não há `shell=True`,
`eval`, argv livre, scripts vindos de firmware nem downloads de firmware.

### Estado XDG

| Conteúdo | Local |
| :-- | :-- |
| Socket | `$XDG_RUNTIME_DIR/android-dex/core.sock` |
| Sessões/jobs/planos | `$XDG_STATE_HOME/android-dex-ui/` |
| Logs de sessão | `$XDG_STATE_HOME/android-dex-ui/logs/` |

Fechar a janela não encerra `android-dexd` nem uma sessão ativa. Use a tela
Sessões ou `android-dex --stop` para encerrar de forma explícita.

## Segurança da manutenção

1. A UI seleciona aparelho, ação e artefato local.
2. O serviço normaliza o caminho, recusa links simbólicos e calcula SHA-256.
3. O driver gera uma prévia/dry-run; operações não certificadas permanecem
   somente roteiro.
4. O plano vincula serial, modelo, codename, fingerprint, OEM, ação, hashes e
   expira em 10 minutos.
5. No `apply`, identidade, política do driver, bateria e hashes são repetidos.
6. O script mantém seus próprios guard rails e pede `SIM`; Samsung usa o aviso
   `KNOX PERMANENTE` e continua sem commit automático.

A confirmação digitada só existe em memória durante a chamada e não é
persistida nem registrada em logs. A UI sempre mostra wipe, Knox, Play
Integrity, downgrade e risco de brick.

## Testes

```bash
# contrato, socket, segurança, serviço e render de todas as telas
python3 -m pytest -q tests

# foco, teclado, leitores de tela (nomes acessíveis), seletor e diálogo crítico
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input qml-tests -import src/android_dex_ui/qml -o -,txt

# regressões dos dois toolkits
make -C .. test
```

A CI executa também ShellCheck, parser PowerShell, smoke Qt offscreen, build do
AppImage e smoke do próprio artefato.

## AppImage

```bash
# valida a árvore autossuficiente sem precisar de appimagetool
make -C .. appdir

# com appimagetool instalado ou APPIMAGETOOL_BIN definido
make -C .. appimage

bash appimage/smoke-appimage.sh build/Android-DEX-x86_64.AppImage
```

O AppImage contém UI, Qt, Python e o daemon. `adb`, `fastboot`, `scrcpy`,
`heimdall`, OpenSSL e udev continuam externos por design.

## Limites honestos

- A primeira versão usa somente firmware local escolhido pelo usuário.
- Operações não certificadas pelo backend continuam dry-run/roteiro guiado.
- Windows reutilizará contrato e design; este pacote é o release Linux.
- A matriz física Samsung, Pixel, Xiaomi, Motorola e OnePlus complementa os
  testes automatizados e não é substituída pelo modo demo.

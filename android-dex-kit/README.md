# Android-DEX Kit

Uma solução **robusta e resiliente** para transformar um Android conectado numa
experiência de desktop, plenamente integrada ao ambiente Linux do host. É a mesma
ideia do projeto [Android-Dex](https://github.com/Shrey113/Android-Dex) do Shrey113
(que por baixo usa **scrcpy + ADB**), mas reconstruída como um toolkit aberto,
enxuto e inteiramente seu para modificar — sem depender de binários fechados.

Sem root. Funciona por USB ou Wi-Fi. Modo "DeX" (display virtual separado, estilo
desktop) em scrcpy ≥ 3.0 e Android com Desktop Mode, ou espelhamento tradicional
em qualquer versão.

## O que "robusto e resiliente" significa aqui

O núcleo é um **supervisor** (`android-dex`) que não apenas lança o scrcpy, mas
cuida da sessão de ponta a ponta: seleciona um único aparelho (com escolha
interativa quando há ambiguidade), fixa sua identidade pela sessão, aplica os ajustes de modo
desktop, sobe a sessão e, se a conexão
cair, reconecta sozinho com *backoff* exponencial e *jitter*. Se o transporte
Wi-Fi morrer, ele derruba e refaz o `adb connect`. Um lock impede supervisores
duplicados, e `--stop` encerra o supervisor validado junto com o scrcpy. O
encerramento é limpo (e reverte ajustes opcionalmente) via `trap`. Além disso, um serviço
**systemd de usuário** cobre a falha do processo inteiro (ex.: `adb` morto),
reiniciando o supervisor. Tudo é logado em `~/.local/state/android-dex/`.

"Plenamente integrado ao host" quer dizer instalação idempotente que registra:
binários em `~/.local/bin`, lançador no menu de aplicativos com ícone XDG (e ações
de clique-direito para Espelhar / Wi-Fi / Status / Parar), regras **udev** para
acesso USB sem root, e o serviço systemd para auto-start na sessão gráfica.

## Instalação

```bash
cd android-dex-kit
./install.sh
```

O instalador detecta a distro (apt/dnf/pacman/zypper/apk), instala `scrcpy` e
`adb` (com *fallback* para `snap` quando a versão do repositório for antiga demais
para o modo DeX), configura udev + grupo de acesso USB, e registra todos os
arquivos do usuário. Opções úteis:

```bash
./install.sh --no-deps          # não mexe em pacotes do sistema
./install.sh --enable-service   # já habilita o serviço systemd de usuário
./install.sh --uninstall        # remove o kit
```

Depois da primeira instalação, se você foi adicionado a um grupo novo
(`plugdev`/`adbusers`), **relogue** para o USB autorizar sem root.

## Uso

No aparelho, ative *Opções do desenvolvedor* → **Depuração USB** (e/ou **Depuração
sem fio**).

Por cabo, basta conectar, autorizar o computador na primeira vez e rodar:

```bash
android-dex
```

Por Wi-Fi, primeiro emparelhe (só uma vez) e depois conecte:

```bash
android-dex-connect      # migra do USB p/ Wi-Fi, ou emparelha por código
android-dex --wifi       # usa o IP que ficou salvo
android-dex-connect --discover # mostra portas de conexão anunciadas por mDNS
```

Outros comandos:

```bash
android-dex --mirror     # espelha a tela real em vez do modo desktop
android-dex --list       # lista serial, estado, transporte e modelo
android-dex --device PHONE-A # escolhe o serial sem ambiguidade
android-dex --once       # roda uma sessão sem ficar reconectando
android-dex --status     # mostra estado, dispositivos e sessão ativa
android-dex --stop       # encerra a sessão atual
android-dex-doctor       # relatório somente leitura de host/capacidades
android-dex --restore-tweaks --device PHONE-A # restaura ajustes globais salvos
android-dex 192.168.1.50 # usa ADB_TCP_PORT (5555 por padrão)
android-dex-connect --from-usb --port 43210 # escolhe outra porta adb tcpip
```

O lançador "Android DEX" também aparece no menu de aplicativos; o clique-direito
dá acesso rápido a Espelhar, Wi-Fi, Status e Encerrar.

## Configuração

Tudo mora em `~/.config/android-dex/config.env` (criado a partir do
`config.env.example`). Os campos principais:

| Variável | Padrão | Função |
| --- | --- | --- |
| `MODE` | `auto` | detecta conservadoramente; também aceita `dex` ou `mirror` |
| `CONNECTION` | `auto` | `auto`, `usb` ou `wifi` |
| `DEVICE_IP` | vazio | IP:porta do aparelho (preenchido pelo `-connect`) |
| `DEVICE_SERIAL` | vazio | fixa um serial quando há vários aparelhos |
| `ADB_TCP_PORT` | `5555` | porta do fluxo legado `adb tcpip` |
| `DISPLAY_RES` | `1920x1080` | resolução do desktop virtual |
| `DISPLAY_DPI` | `160` | densidade (menor = mais área útil) |
| `MAX_FPS` / `VIDEO_BITRATE` | `60` / `8M` | qualidade do vídeo |
| `AUDIO` | `1` | encaminha o áudio do aparelho (scrcpy 2.0+) |
| `STAY_AWAKE` | `1` | impede o aparelho de dormir |
| `ENABLE_FREEFORM_TWEAKS` | `1` | liga janelas livres (desktop) via adb |
| `RESTORE_TWEAKS_ON_EXIT` | `0` | restaura o snapshot exato ao encerrar |
| `VD_SYSTEM_DECORATIONS` | `1` | `0` = `--no-vd-system-decorations` (UI quebrada) |
| `START_APP` | vazio | abre um app/launcher no display virtual vazio |
| `RECONNECT` | `1` | supervisor reconecta em quedas |
| `BACKOFF_CAP` | `30` | teto do atraso entre tentativas (s) |
| `HEALTHY_SESSION_SECONDS` | `15` | estabilidade mínima antes de zerar o backoff |
| `AUTO_DEX_MIN_SDK` | `35` | SDK mínimo para tentar DeX automaticamente |
| `EXTRA_ARGS` | vazio | argumentos crus repassados ao scrcpy |
| `ADX_DEBUG` | `0` | registra falhas não fatais normalmente silenciosas |

Antes de alterar os três ajustes globais do modo desktop, o runtime salva os
valores anteriores (inclusive a ausência de um valor) em
`~/.local/state/android-dex/tweaks/`. Se a restauração automática estiver
desligada, o log mostra o comando `--restore-tweaks`; o snapshot só é removido
depois que todos os valores forem restaurados com sucesso. Em modo `mirror`,
esses ajustes não são aplicados.

## Compatibilidade do modo DeX

O padrão `MODE="auto"` lê fabricante, SDK e capacidades de display secundário.
Quando a capacidade não é confirmada, usa `mirror`; se um display virtual cair
rapidamente, restaura os tweaks aplicados e tenta `mirror` uma vez. Perfis instalados para Samsung, Google,
Xiaomi, Motorola e OnePlus/OPPO/Realme ajustam freeform, decorações e escolhem um
launcher somente quando o pacote realmente existe. As escolhas explícitas do
usuário continuam tendo prioridade. Use `--dex` para forçar um teste ou
`--mirror` para máxima compatibilidade.

O instalador também inclui regras udev para interfaces ADB/fastboot, VIDs
Android conhecidos e Samsung Download/Odin; regras existentes da distro
continuam coexistindo.

## Serviço systemd (opcional)

Para o desktop subir sozinho quando o aparelho estiver disponível:

```bash
systemctl --user enable --now android-dex.service
systemctl --user status android-dex.service
journalctl --user -u android-dex.service -f
```

Ele já é resiliente por dentro (reconexão), e o `Restart=on-failure` cobre a queda
do processo inteiro.

## Diagnóstico

Veja o estado com `android-dex --status` e os logs em
`~/.local/state/android-dex/android-dex.log`.

`android-dex-doctor [--device SERIAL]` verifica adb/scrcpy, autorização USB,
perfil OEM, SDK, display secundário e endpoints mDNS sem modificar o aparelho.
Ele é o roteiro reproduzível para validar novos modelos na matriz de hardware.

Para investigar uma falha normalmente não fatal, rode uma sessão com
`ADX_DEBUG=1 android-dex --once`. O log mostrará o comando e o código de saída,
sem transformar a falha em queda do supervisor.

Problemas comuns: se `adb devices` mostra `unauthorized`, confirme o diálogo de
autorização no aparelho; se mostra vazio no USB, o problema costuma ser
permissão — relogue após a instalação (grupo udev) ou verifique o cabo. No Wi-Fi,
lembre que o código e a porta de **emparelhamento** mudam a cada vez que a tela de
Depuração sem fio é aberta, e a porta de **conexão** é diferente da de
emparelhamento. O `android-dex-connect` tenta descobri-la por mDNS e só pergunta
quando a descoberta não é única ou não está disponível.

## Desinstalação

```bash
./uninstall.sh            # remove o kit, preserva config e o scrcpy/adb
./uninstall.sh --purge    # remove também config, logs e a regra udev
```

## Windows 10/11 (PowerShell)

A porta em [`windows/`](windows/) implementa seleção segura, modo automático,
snapshot/restauração de tweaks, lock por mutex, estado validado, fallback para
mirror e reconexão com backoff. Com `adb.exe` e `scrcpy.exe` no `PATH`:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows\install.ps1                 # instala e cria atalho no Desktop
.\windows\install.ps1 -EnableStartup  # também cria Tarefa Agendada no logon

& "$env:LOCALAPPDATA\AndroidDex\android-dex.ps1" -Command list
& "$env:LOCALAPPDATA\AndroidDex\android-dex.ps1" -Device PHONE-A -Once
& "$env:LOCALAPPDATA\AndroidDex\android-dex.ps1" -Command stop
```

Configuração: `$env:APPDATA\AndroidDex\config.ps1`. A CI valida todos os
scripts com o parser do Windows PowerShell 5.1 e executa um smoke test de
listagem no `windows-latest`.

---

Construído sobre [scrcpy](https://github.com/Genymobile/scrcpy) (Genymobile).
Inspirado no [Android-Dex](https://github.com/Shrey113/Android-Dex) (Shrey113).

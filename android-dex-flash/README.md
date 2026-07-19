# android-dex-flash

Ferramenta de **manutenção de dispositivo Android** — diagnóstico, desbloqueio de
bootloader, root (Magisk) e flash de firmware — construída como **orquestrador
das ferramentas oficiais de cada fabricante** (`fastboot`, `heimdall`, `Magisk`,
imagens de fábrica). Projeto **irmão** do [`android-dex-kit`](../android-dex-kit),
com quem compartilha a fundação `lib/common.sh` (logging com rotação, XDG,
backoff, helpers de ADB).

> **Leia isto antes de tudo.** Esta ferramenta mexe em bootloader e partições.
> Ela existe para reduzir **erro humano**, não para eliminar o **risco físico**.
> Só use no **seu próprio aparelho**.

## Por que é um projeto separado

Espelhar a tela (o `android-dex`) é inofensivo; qualquer um roda sem medo.
Desbloquear bootloader e gravar partições **pode brickar o aparelho** e costuma
ser **irreversível**. Manter as duas coisas separadas evita que alguém aperte o
botão errado — e dá a esta ferramenta um ciclo de consentimento próprio.

## Modelo de segurança (o que torna "amigável e seguro" real)

- **`--dry-run` é o padrão.** Root, firmware e restauração são atualmente
  **guiados e fail-closed**: não aceitam `--commit` até existirem descritores
  verificáveis por modelo/partição.
- **Bundles são dados, nunca código.** `flash-all.sh`/`flash_all.sh` contidos em
  pacotes de firmware jamais são executados pela ferramenta.
- **Consentimento digitado.** Antes de gravar, você digita `SIM` (não aceita `y`).
- **Guard rails** antes de qualquer gravação:
  - confere que o **modelo** bate com o esperado (`--model`), evitando firmware
    de outro aparelho (causa clássica de hard-brick);
  - verifica **bateria mínima** (padrão 40%);
  - verifica **hash sha256** dos insumos quando informado;
  - cria **backup de boot/init_boot** com metadados e SHA-256 quando o transporte
    permite leitura;
  - compara `security_patch` e índice anti-rollback de manifestos v2.
- **Avisos específicos por OEM** (ex.: Knox e-fuse na Samsung é permanente).
- **Auditoria:** todo comando é logado em
  `~/.local/state/android-dex-flash/android-dex-flash.log`.

Nada disso te protege de um aparelho fisicamente incapaz de desbloquear, de um
anti-rollback, ou da perda de Play Integrity. A ferramenta te avisa; a decisão
é sua.

## Instalação

```bash
cd android-dex-flash
./install.sh                 # instala adb/fastboot; heimdall p/ Samsung
./install.sh --with-heimdall # força tentar instalar heimdall
./install.sh --no-deps       # não mexe em pacotes do sistema
```

O acesso USB (udev) é **compartilhado** com o `android-dex-kit`: se você já
instalou aquele, o acesso sem root já vale aqui. Em modo *fastboot* o VID/PID do
aparelho muda — a regra udev por *vendor id* (roadmap **A1** do kit) é o que
cobre esse caso de forma confiável.

## Uso

Comece **sempre** pelo diagnóstico — ele nunca grava nada:

```bash
android-dex-flash info     # marca/modelo/SO/bootloader + o que é possível/se perde
android-dex-flash caps     # capacidades e riscos detalhados do seu modelo
android-dex-flash verify-firmware DIR # assinatura, hash e identidade; não grava
android-dex-flash check-rollback DIR  # compara patch/índice sem gravar
android-dex-flash backup-boot         # lê boot/init_boot e cria manifesto local
android-dex-flash extract-payload payload.bin DIR # extrai OTA A/B + hashes
```

Ações e roteiros (todos em dry-run por padrão):

```bash
android-dex-flash unlock                 # simula o desbloqueio (mostra a sequência)
android-dex-flash unlock --commit        # só em drivers dedicados certificados
android-dex-flash root                   # valida insumos e mostra o roteiro Magisk
android-dex-flash flash-firmware DIR     # valida o tipo do pacote e orienta
android-dex-flash reboot-bootloader      # reinicia p/ fastboot/download
android-dex-flash --model sunfish unlock --commit   # trava o modelo esperado
RECOVERY_IMG=recovery.img RECOVERY_SHA256=... \
  android-dex-flash --model shiba boot-recovery --commit # boot temporário Pixel
```

Insumos (boot.img de estoque, imagem corrigida pelo Magisk, código de unlock da
Motorola, etc.) são informados por variáveis no
`~/.config/android-dex-flash/flash.env` ou no ambiente — veja
[`config/flash.env.example`](config/flash.env.example).

## Suporte por fabricante (drivers)

| OEM | Unlock | Observação central |
| --- | --- | --- |
| **Pixel / AOSP** | `fastboot flashing unlock` | Caminho mais limpo; referência. Play Integrity cai. |
| **Samsung** | modo Download + confirmação física | **Queima o Knox e-fuse — permanente.** Usa `heimdall`, não fastboot. Muitos Snapdragon (EUA) não desbloqueiam. |
| **Xiaomi/Redmi/POCO** | Mi Unlock Tool oficial (Windows) + espera | A ferramenta **guia** o processo oficial; não burla a espera/login. |
| **Motorola/Lenovo** | código do site oficial | 2 passos: `get_unlock_data` → código por e-mail → `oem unlock <código>`. |
| **OnePlus** | `fastboot flashing unlock` | Elegibilidade varia por modelo/operadora; permanece guiado. |
| **OPPO/Realme** | fluxo oficial Deep Testing, quando oferecido | Nunca são tratados como OnePlus nem burlam região/conta. |
| **Sony Xperia** | código do portal oficial Sony | Pode perder chaves DRM e degradar câmera/recursos. |

Fabricante não mapeado cai no driver **genérico** em modo somente guiado:
nenhuma ação destrutiva aceita `--commit`.

## Root (Magisk) — como funciona aqui

O método moderno e **reversível**: pegue `boot.img` ou `init_boot.img` de
**estoque** do firmware que está no aparelho, corrija-o com o app **Magisk**
(`magisk_patched.img`) e grave com o procedimento oficial do modelo. Selecione
`ROOT_PARTITION=boot` ou `init_boot`. A ferramenta aceita o `PATCHED_IMG`,
verifica hash (se informado) e mostra a sequência, mas neste estágio não grava
automaticamente. Restaurar o boot de estoque remove o root.

## Firmware

- **Pixel:** imagem de fábrica oficial com `flash-all.sh`, ou `fastboot update`.
- **Xiaomi:** *fastboot ROM* oficial (tem `flash_all.sh`).
- **Samsung:** firmware oficial (`AP/BL/CP/CSC`) baixado com samloader/Frija,
  gravado com `heimdall` (mapeando partições).
- **OnePlus/OPPO:** `payload.bin` de OTA (payload-dumper) + fastboot.

A ferramenta **não hospeda nem baixa firmware**: você aponta para o pacote
oficial do seu modelo. Ela identifica o formato e orienta as verificações, mas
não executa scripts do bundle nem grava partições automaticamente. A conclusão
é feita na ferramenta oficial do fabricante.

Bundles podem trazer `firmware.manifest` + `firmware.manifest.sig`. O comando
`verify-firmware` verifica assinatura OpenSSL contra uma chave pública colocada
explicitamente em `~/.config/android-dex-flash/trusted-keys/`, confere SHA-256 e
vincula OEM/modelo/codename ao único aparelho selecionado. O formato v2 também
valida plano de partições, hashes individuais, patch de segurança e índice
anti-rollback quando o aparelho o expõe. O formato e o comando de assinatura
estão em [`firmware/README.md`](firmware/README.md). Região e revisões de
bootloader proprietárias ainda podem exigir a ferramenta oficial; um resultado
inconclusivo permanece sem permissão de gravação automática.

## Backup, payload e recuperação

- `backup-boot` tenta `fastboot fetch` ou leitura root via ADB; sem suporte do
  aparelho, aceita `BOOT_IMG` oficial como cópia conhecida. Só publica arquivo
  não vazio e cria manifesto + SHA-256.
- `extract-payload` chama um `payload-dumper-go` já instalado, escreve em
  diretório vazio e gera `SHA256SUMS`; nunca baixa executáveis.
- `boot-recovery` usa `fastboot boot`, sem gravar partição. Execução real está
  liberada apenas no driver Pixel e exige bootloader confirmado como
  desbloqueado, `--model` e `RECOVERY_SHA256`.
- `restore-boot` continua fail-closed para gravação automática, mas gera o
  roteiro exato para `boot` ou `init_boot` e verifica `BOOT_SHA256`.

## Limites honestos (o que ela NÃO faz)

- Não burla espera de unlock (Xiaomi), login de conta, nem proteção de operadora.
- Não executa root/firmware/restore em `--commit` sem descritores validados por
  modelo, região, revisão de bootloader e layout de partições.
- Não desbloqueia aparelhos que o fabricante travou (muitos Galaxy Snapdragon,
  Huawei pós-2018, bootloaders de operadora).
- Não promete detectar todo fuse proprietário. Se anti-rollback ficar
  inconclusivo, orienta usar a ferramenta oficial e não libera commit.
- Não restaura Knox nem Play Integrity depois de perdidos.

## Desinstalação

```bash
./uninstall.sh            # remove binário e libs (preserva config/backups)
./uninstall.sh --purge    # remove também config, logs e backups
```

## Integração legível por máquina

`--json` reserva `stdout` para um único documento no formato
`android-dex.machine.v1`; avisos, roteiro e logs humanos seguem em `stderr`.

```bash
android-dex-flash --json --non-interactive info
android-dex-flash --json --non-interactive caps
android-dex-flash --json --non-interactive check-rollback DIRETORIO
```

O modo não interativo **não autoriza gravação**. A combinação
`--non-interactive --commit` é recusada; o serviço usa um plano temporário e
fornece a confirmação explícita ao script somente no momento do `apply`.

---

Orquestra: [fastboot/adb](https://developer.android.com/tools/releases/platform-tools)
(Google), [Heimdall](https://gitlab.com/BenjaminDobell/Heimdall),
[Magisk](https://github.com/topjohnwu/Magisk). Firmware sempre de fontes oficiais
do fabricante. Veja o [ROADMAP](../ROADMAP.md) para o plano de evolução.

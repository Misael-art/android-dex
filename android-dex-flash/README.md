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

- **`--dry-run` é o padrão.** Nenhuma ação grava nada até você passar `--commit`.
- **Consentimento digitado.** Antes de gravar, você digita `SIM` (não aceita `y`).
- **Guard rails** antes de qualquer gravação:
  - confere que o **modelo** bate com o esperado (`--model`), evitando firmware
    de outro aparelho (causa clássica de hard-brick);
  - verifica **bateria mínima** (padrão 40%);
  - verifica **hash sha256** dos insumos quando informado;
  - **backup** best-effort do boot antes de rootar.
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
```

Ações que gravam (todas em dry-run por padrão):

```bash
android-dex-flash unlock                 # simula o desbloqueio (mostra a sequência)
android-dex-flash unlock --commit        # executa (pede bateria/modelo/"SIM")
android-dex-flash root --commit          # patch boot.img (Magisk) + flash
android-dex-flash flash-firmware DIR --commit   # grava firmware oficial
android-dex-flash reboot-bootloader      # reinicia p/ fastboot/download
android-dex-flash --model sunfish unlock --commit   # trava o modelo esperado
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
| **OnePlus/OPPO/Realme/Sony** | `fastboot flashing unlock` | OPPO/Realme podem exigir app oficial "In-Depth Test"; Sony perde DRM. |

Fabricante não mapeado cai no driver **genérico** (fluxo AOSP/fastboot), com
avisos mais conservadores.

## Root (Magisk) — como funciona aqui

O método moderno e **reversível**: pegue o `boot.img` de **estoque** do firmware
que está no aparelho, corrija-o com o app **Magisk** (`magisk_patched.img`) e
grave com `fastboot flash boot`. A ferramenta empurra o `boot.img`, aceita o
`PATCHED_IMG` de volta, verifica hash (se informado), faz backup best-effort e
grava. Restaurar o boot de estoque remove o root.

## Firmware

- **Pixel:** imagem de fábrica oficial com `flash-all.sh`, ou `fastboot update`.
- **Xiaomi:** *fastboot ROM* oficial (tem `flash_all.sh`).
- **Samsung:** firmware oficial (`AP/BL/CP/CSC`) baixado com samloader/Frija,
  gravado com `heimdall` (mapeando partições).
- **OnePlus/OPPO:** `payload.bin` de OTA (payload-dumper) + fastboot.

A ferramenta **não hospeda nem baixa firmware**: você aponta para o pacote
oficial do seu modelo. Ela verifica modelo/hash e delega ao script/protocolo
oficial.

## Limites honestos (o que ela NÃO faz)

- Não burla espera de unlock (Xiaomi), login de conta, nem proteção de operadora.
- Não desbloqueia aparelhos que o fabricante travou (muitos Galaxy Snapdragon,
  Huawei pós-2018, bootloaders de operadora).
- Não impede brick por firmware errado além dos guard rails — por isso os avisos.
- Não restaura Knox nem Play Integrity depois de perdidos.

## Desinstalação

```bash
./uninstall.sh            # remove binário e libs (preserva config/backups)
./uninstall.sh --purge    # remove também config, logs e backups
```

---

Orquestra: [fastboot/adb](https://developer.android.com/tools/releases/platform-tools)
(Google), [Heimdall](https://gitlab.com/BenjaminDobell/Heimdall),
[Magisk](https://github.com/topjohnwu/Magisk). Firmware sempre de fontes oficiais
do fabricante. Veja o [ROADMAP](../ROADMAP.md) para o plano de evolução.

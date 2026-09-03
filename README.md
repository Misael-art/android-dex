<div align="center">

<img src="assets/banner.svg" alt="Android-DEX" width="100%">

<br>

**Transforme um Android conectado em um desktop no Linux — e cuide do aparelho de ponta a ponta.**
Uma aplicação Qt/QML e dois toolkits irmãos sobre as ferramentas oficiais
(`scrcpy`, `adb`, `fastboot`, `heimdall`, `Magisk`).

<br>

[![Release](https://img.shields.io/github/v/release/Misael-art/android-dex?color=3ddc84&label=release)](https://github.com/Misael-art/android-dex/releases/latest)
![License](https://img.shields.io/badge/license-MIT-3ddc84)
![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Linux-333?logo=linux&logoColor=white)
![android-dex](https://img.shields.io/badge/android--dex-sem%20root-brightgreen)
![android-dex-flash](https://img.shields.io/badge/android--dex--flash-dry--run%20por%20padr%C3%A3o-orange)
![PRs](https://img.shields.io/badge/PRs-welcome-4f8cff)

</div>

---

## ✨ O que é isto?

Um workspace com **três camadas deliberadamente separadas**. A interface nunca
executa comandos livres: ela conversa com um serviço local, que delega apenas
operações allowlisted aos toolkits existentes.

| Projeto | O que faz | Risco | Root? |
| :-- | :-- | :--: | :--: |
| ✨ **[android-dex-ui](android-dex-ui/)** | Aplicação nativa PySide6/Qt Quick, sessões DeX, Wi‑Fi, diagnóstico e manutenção guiada. | 🟢/🟠 isolado por fluxo | ❌ não |
| 🖥️ **[android-dex-kit](android-dex-kit/)** | Experiência **desktop/DeX** via `scrcpy + ADB`, com modo automático, perfis OEM, supervisor resiliente, systemd e udev. | 🟢 baixo | ❌ não |
| 🔧 **[android-dex-flash](android-dex-flash/)** | Diagnóstico e manutenção guiada, com bundles não executáveis e descritores assinados; gravações sem validação permanecem bloqueadas. | 🔴 alto | ⚠️ opcional |

> [!NOTE]
> São **separados de propósito**: espelhar a tela é inofensivo; mexer em bootloader e partições pode **brickar** o aparelho. A separação evita apertar o botão errado.

---

## 🧭 Índice

- [Arquitetura](#-arquitetura)
- [Instalação e releases](#-instalação-e-releases)
- [Interface Qt/QML](#-interface-qtqml)
- [android-dex — desktop sem root](#️-android-dex--desktop-sem-root)
- [android-dex-flash — manutenção do aparelho](#-android-dex-flash--manutenção-do-aparelho)
- [Compatibilidade por marca](#-compatibilidade-por-marca)
- [Segurança](#-segurança-android-dex-flash)
- [Roadmap](#️-roadmap)
- [Créditos](#-créditos)

---

## 🏗️ Arquitetura

```mermaid
flowchart TD
    UI["android-dex-ui<br/><i>PySide6 + Qt Quick/QML</i>"]
    D["android-dexd<br/><i>JSON-RPC · socket 0600 · UID</i>"]
    C["lib/common.sh<br/><i>fundação compartilhada</i><br/>log · XDG · backoff · ADB helpers"]

    subgraph KIT["🖥️ android-dex-kit  ·  sem root"]
      direction TB
      A1["android-dex<br/><i>supervisor + reconexão</i>"]
      A2["android-dex-connect<br/><i>assistente Wi-Fi</i>"]
      A3["scrcpy + ADB"]
      A1 --> A3
      A2 --> A3
    end

    subgraph FLASH["🔧 android-dex-flash  ·  alto risco"]
      direction TB
      B0["flash-common.sh<br/><i>guard rails · dry-run · consentimento</i>"]
      B1["drivers/<br/>pixel · samsung · xiaomi<br/>motorola · oneplus · generic"]
      B2["fastboot · heimdall · Magisk"]
      B0 --> B1 --> B2
    end

    UI -->|"core.sock"| D
    D -->|"argv allowlisted"| KIT
    D -->|"plano vinculado + confirmação"| FLASH
    C --> KIT
    C --> FLASH

    style C fill:#12233c,stroke:#3ddc84,color:#dbe6f5
    style UI fill:#0e1b2f,stroke:#13bdf2,color:#dbe6f5
    style D fill:#12233c,stroke:#59d35d,color:#dbe6f5
    style KIT fill:#0e1b2f,stroke:#3ddc84,color:#dbe6f5
    style FLASH fill:#0e1b2f,stroke:#4f8cff,color:#dbe6f5
```

---

## 📦 Instalação e releases

Duas formas: baixar os artefatos prontos da **[Release](https://github.com/Misael-art/android-dex/releases/latest)**
(recomendado para usar) ou instalar a partir do **código-fonte** (para desenvolver).
Todos os artefatos da release têm checksums em `SHA256SUMS`.

### A) A partir da release (recomendado)

Baixe da página de [Releases](https://github.com/Misael-art/android-dex/releases/latest)
ou com a `gh` CLI:

```bash
# Interface — AppImage autossuficiente (Qt + Python embutidos)
gh release download -R Misael-art/android-dex -p 'Android-DEX-*.AppImage'
chmod +x Android-DEX-x86_64.AppImage
./Android-DEX-x86_64.AppImage            # ou mova para ~/.local/bin

# Toolkits em shell (kit + flash)
gh release download -R Misael-art/android-dex -p '*.tar.gz'
tar xzf android-dex-kit-*.tar.gz   && ( cd android-dex-kit   && ./install.sh )
tar xzf android-dex-flash-*.tar.gz && ( cd android-dex-flash && ./install.sh )

# UI via pip/pipx (alternativa ao AppImage)
gh release download -R Misael-art/android-dex -p 'android_dex_ui-*.whl'
pipx install ./android_dex_ui-*.whl      # expõe android-dex-ui, android-dexd, android-dex-setup

# Conferir integridade
gh release download -R Misael-art/android-dex -p 'SHA256SUMS' && sha256sum -c SHA256SUMS
```

> [!TIP]
> Algumas distros trazem o **AppImageLauncher**, que abre um diálogo de integração
> ao executar o AppImage — aceite-o, ou rode com `APPIMAGELAUNCHER_DISABLE=1` para
> pular a interação. O AppImage usa FUSE; sem FUSE, rode com `--appimage-extract-and-run`.

### B) A partir do código-fonte

```bash
git clone https://github.com/Misael-art/android-dex.git
cd android-dex

( cd android-dex-kit   && ./install.sh )   # desktop: scrcpy/adb, udev, launcher, systemd
( cd android-dex-flash && ./install.sh )   # manutenção: adb/fastboot; heimdall p/ Samsung

# UI (opcional, para desenvolver)
cd android-dex-ui && python3 -m venv .venv && . .venv/bin/activate && pip install -e '.[test]'
```

### Requisitos

| Para | Precisa de |
| :-- | :-- |
| Desktop (kit) | `adb`, `scrcpy` ≥ 3.0 — o `install.sh` instala pela sua distro |
| Manutenção (flash) | `adb`, `fastboot`; `heimdall` para os roteiros Samsung |
| UI a partir do source | Python ≥ 3.11 + `PySide6-Essentials` ≥ 6.8 (o AppImage já traz tudo) |

Os `install.sh` pedem elevação (sudo/pacman/apt) **apenas** para pacotes do sistema
e para a regra **udev** (acesso USB sem root); a parte de usuário vai para
`~/.local/bin`. Depois, rode **`android-dex-doctor`** para um diagnóstico do host
(adb, scrcpy, udev e aparelhos visíveis). Suporte a **Linux** (a UI reutilizará o
mesmo contrato no Windows futuramente).

---

## ✨ Interface Qt/QML

A experiência começa pelo modo desktop. Firmware e bootloader ficam em
**Manutenção avançada**, depois de um divisor e com linguagem visual âmbar.

```bash
cd android-dex-ui
python3 -m venv .venv
. .venv/bin/activate
pip install -e .

android-dex-ui          # uso real; inicia android-dexd quando necessário
android-dex-ui --demo   # aparelho fictício, não chama adb/scrcpy/fastboot
android-dex-setup       # verifica dependências externas
```

O daemon por usuário continua supervisionando a sessão quando a janela fecha.
O transporte Linux usa `$XDG_RUNTIME_DIR/android-dex/core.sock`; diretório e
socket são privados (`0700`/`0600`) e o UID do cliente é verificado.

👉 Instalação, contrato e testes em **[android-dex-ui/README.md](android-dex-ui/README.md)**.

---

## 🖥️ android-dex — desktop sem root

Modo automático tenta **DeX** somente quando SDK/capacidades o sustentam e cai
para **mirror** quando houver dúvida ou falha rápida. Perfis OEM ajustam launcher
e decorações; USB/Wi-Fi reconectam com backoff exponencial.

<details open>
<summary><b>Instalar e usar (30 segundos)</b></summary>

```bash
cd android-dex-kit
./install.sh                 # instala scrcpy/adb, udev, launcher, systemd

# no aparelho: Opções do desenvolvedor → Depuração USB
android-dex                  # auto-detecta e sobe a sessão

android-dex-connect          # migra p/ Wi-Fi (emparelha e salva o IP)
android-dex --wifi           # conecta pelo IP salvo
android-dex --list           # lista aparelhos; --device escolhe um deles
android-dex --status         # estado, dispositivos e sessão ativa
android-dex-doctor           # diagnóstico somente leitura + capacidades
```
</details>

👉 Detalhes completos em **[android-dex-kit/README.md](android-dex-kit/README.md)**.

---

## 🔧 android-dex-flash — manutenção do aparelho

Um **orquestrador** das ferramentas oficiais de cada fabricante — **nunca** um "motor de flash" próprio. Existe para reduzir **erro humano**, não para eliminar o **risco físico**.

> [!WARNING]
> Só use no **seu próprio aparelho**. Desbloqueio de bootloader, root e flash podem **brickar** o aparelho e frequentemente são **irreversíveis** (Knox e-fuse, Play Integrity, garantia).

**O que torna "seguro e amigável" real:**

- 🧪 **`--dry-run` é o padrão** — nada é gravado até você pedir `--commit`.
- ⌨️ **Consentimento digitado** — antes de gravar, você digita `SIM` (não aceita `y`).
- 🛡️ **Guard rails** — confere modelo, bateria mínima, hash sha256 dos insumos e faz backup do boot.
- ⚠️ **Avisos por marca** — ex.: o Knox e-fuse da Samsung é permanente.

<details>
<summary><b>Comece sempre pelo diagnóstico (risco ZERO)</b></summary>

```bash
cd android-dex-flash
./install.sh

android-dex-flash info       # marca/modelo/SO/bootloader + o que é possível e o que se perde
android-dex-flash caps       # capacidades e riscos do seu modelo
android-dex-flash check-rollback DIR # assinatura + anti-downgrade
android-dex-flash backup-boot        # backup com manifesto e SHA-256
android-dex-flash extract-payload payload.bin DIR

# ações que gravam — dry-run por padrão:
android-dex-flash unlock             # simula (mostra a sequência exata)
android-dex-flash unlock --commit    # só em drivers dedicados certificados
android-dex-flash flash-firmware DIR # roteiro guiado; não executa scripts
```
</details>

👉 Detalhes completos e limites honestos em **[android-dex-flash/README.md](android-dex-flash/README.md)**.

---

## 📱 Compatibilidade por marca

**Modo desktop (`android-dex`):**

| Marca / SO | Experiência | Ajuste |
| :-- | :-- | :-- |
| Samsung One UI 8 / Android 15+ | 🟢 DeX nativo no display virtual | funciona direto |
| Pixel / AOSP 15+ | 🟡 desktop mode (às vezes exige tela física) | `START_APP` |
| Xiaomi / Oppo / Motorola | 🟡 abre vazio, precisa de launcher | `START_APP` + `VD_SYSTEM_DECORATIONS=0` |
| Xiaomi/POCO (HyperOS) | ⚠️ DeX exige **"Depuração USB (Configurações de segurança)"** + reboot | senão o app avisa e cai para mirror |
| Qualquer aparelho | 🟢 `MODE="mirror"` | sempre funciona |

> [!NOTE]
> Quando o modo desktop **não é viável** (ex.: HyperOS sem a permissão de segurança, freeform bloqueado), o `android-dex` **avisa o motivo e usa mirror** em vez de abrir uma tela preta. Rode `android-dex-doctor` para ver o estado de controle/desktop do seu aparelho.

**Manutenção (`android-dex-flash`):**

| Marca | Desbloqueio | Observação central |
| :-- | :-- | :-- |
| **Pixel / AOSP** | `fastboot flashing unlock` | caminho mais limpo (referência) |
| **Samsung** | modo Download + confirmação física | 🔥 **queima o Knox — permanente**; usa `heimdall` |
| **Xiaomi/Redmi/POCO** | Mi Unlock oficial + espera | a ferramenta **guia**, não burla |
| **Motorola/Lenovo** | código do site oficial | `get_unlock_data` → e-mail → `oem unlock` |
| **OnePlus/Oppo/Realme/Sony** | `fastboot flashing unlock` | Oppo/Realme podem exigir app oficial |

---

## 🔒 Segurança (android-dex-flash)

```text
ação destrutiva
   └─ fingerprint do device ......... quem é o aparelho?
   └─ avisos por OEM ................ o que você perde?
   └─ --dry-run (padrão) ............ mostra os comandos, não grava
        └─ driver permite --commit? . root/firmware/restore: não (fail-closed)
        └─ --commit (somente ação certificada)
             └─ bateria ≥ 40% ....... trava se estiver baixa
             └─ modelo confere ...... recusa firmware de outro modelo
             └─ hash sha256 ......... integridade dos insumos
             └─ digitar "SIM" ....... consentimento explícito
                  └─ executa + loga tudo (auditoria)
```

A ferramenta é **honesta sobre o que não faz**: não burla espera de unlock, não desbloqueia aparelhos travados pelo fabricante e não restaura Knox/Play Integrity perdidos.

Na interface, um plano destrutivo expira em 10 minutos e vincula serial,
modelo, fingerprint, OEM, ação, caminhos canônicos, tamanhos e SHA-256. No
`apply`, serviço e script repetem identidade, política do driver, bateria e
hashes. `KNOX PERMANENTE` é exigido para Samsung; as demais confirmações usam
`SIM`. A frase digitada nunca é persistida nem incluída nos logs.

---

## 🗺️ Roadmap

Plano histórico em **[ROADMAP.md](ROADMAP.md)**. A UI Qt/QML, o contrato
`android-dex.machine.v1`, o daemon privado e a automação de AppImage já estão
implementados nesta branch; a matriz física multi-OEM permanece uma atividade
de validação de hardware, sem ampliar os drivers que aceitam `--commit`.

- **A1** — regra udev por *vendor id* (compatibilidade plug-and-play entre marcas)
- **A3 / A4** — perfis por dispositivo + detecção automática de `dex` vs `mirror`
- **Flash Fase 0** ✅ `device-info` (pronto) → Fases 1–3 (Pixel/Samsung/Xiaomi/Motorola/OnePlus)

---

## 🙏 Créditos

Construído sobre [scrcpy](https://github.com/Genymobile/scrcpy) (Genymobile) e as ferramentas oficiais [platform-tools](https://developer.android.com/tools/releases/platform-tools) (Google), [Heimdall](https://gitlab.com/BenjaminDobell/Heimdall) e [Magisk](https://github.com/topjohnwu/Magisk). Inspirado no [Android-Dex](https://github.com/Shrey113/Android-Dex) (Shrey113). Firmware sempre de fontes **oficiais** do fabricante.

<div align="center">

**[⬆ voltar ao topo](#)** · Feito com shell, cuidado e muitos avisos de segurança.

</div>

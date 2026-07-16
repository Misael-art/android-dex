# Roadmap — Android-DEX (workspace)

Este workspace tem dois projetos irmãos que compartilham a mesma fundação
(`lib/common.sh`: logging com rotação, XDG, backoff, helpers de ADB):

- **`android-dex-kit/`** — experiência desktop (DeX/espelhamento) de um Android
  conectado, via scrcpy + ADB. **Sem root.** Já funcional.
- **`android-dex-flash/`** — ferramenta *separada* de manutenção de dispositivo:
  diagnóstico, desbloqueio de bootloader, root (Magisk) e flash de firmware,
  roteando para as ferramentas oficiais de cada fabricante. **Alto risco, por
  isso é um projeto à parte, com trilhos de segurança próprios.**

Legenda de status: `TODO` · `WIP` (em progresso) · `DONE` · `BLOCKED`.

---

## Parte A — Melhorias do `android-dex-kit` (ordenadas por impacto)

> Correções e recursos que aumentam robustez, resiliência e **compatibilidade
> entre marcas** sem sair do escopo "sem root".

### A1. Regra udev confiável por *vendor ID* — `TODO` · impacto: ALTO
**Problema.** `install.sh:139` casa `ATTR{bDeviceClass}=="ff"` no nível do
*device*. Muitos aparelhos (Samsung, Xiaomi, etc.) expõem `bDeviceClass=0x00` no
device e a interface ADB (`ff/42/01`) só como *interface*, ou aparecem como
composto MTP+ADB — nesses casos a regra não pega e o USB volta a exigir root.
Hoje o kit depende, na prática, do pacote `android-sdk-platform-tools-common`
existir na distro.
**Solução.** Embarcar uma lista de `idVendor` por fabricante (padrão do
`android-udev` do Debian / repositório M0Rf30), gerando
`/etc/udev/rules.d/51-android-dex.rules` com uma linha por VID conhecido +
`TAG+="uaccess"`. Manter a regra genérica atual como *fallback* adicional.
**Aceite.** `adb devices` autoriza sem root em Samsung, Xiaomi, Motorola, Pixel
e OnePlus após relogin; `udevadm test` mostra `uaccess` aplicado ao nó do device.

### A2. Corrigir o *fallback* do `--stop` — `TODO` · impacto: MÉDIO
**Problema.** `android-dex:259` faz `pkill -f 'scrcpy .*android-dex'`, mas a
linha de comando do scrcpy contém `--window-title "Android DEX"` (espaço e
maiúsculas), não `android-dex`. O caminho por PID-file funciona; o *fallback*
nunca casa — bug silencioso.
**Solução.** Casar pelo título real (`--window-title "$WINDOW_TITLE"`) ou marcar
os processos com um argumento-âncora estável (ex.: variável de ambiente
`ADX_SESSION=1` no `scrcpy`), e casar por ela. Testar com PID-file ausente.
**Aceite.** Matar o PID-file na mão e rodar `--stop` ainda encerra a sessão.

### A3. Perfis por dispositivo (`profiles/`) — `TODO` · impacto: ALTO
**Problema.** Ajustes de compatibilidade (`START_APP`, `VD_SYSTEM_DECORATIONS`,
DPI/resolução) hoje são descobertos por tentativa e erro por marca.
**Solução.** Diretório `profiles/` com presets casados por
`ro.product.manufacturer` / `ro.product.model` (lidos via `adb shell getprop`),
aplicados automaticamente antes de montar os argumentos do scrcpy. Usuário pode
sobrescrever no `config.env`.
**Aceite.** Em um não-Samsung, `android-dex` sobe já com launcher e decorações
corretas sem edição manual de config.

### A4. Detecção automática de capacidade (dex vs mirror) — `TODO` · impacto: ALTO
**Problema.** O kit tenta `dex` e o usuário vê tela preta quando o aparelho não
tem Desktop Mode utilizável.
**Solução.** Antes de escolher o modo: checar versão do Android, presença de
`enable_freeform_support`, e se o display virtual sobe com launcher. Se não,
cair para `mirror` com mensagem clara explicando o porquê.
**Aceite.** Aparelho sem Desktop Mode nunca mostra tela preta; loga o motivo do
downgrade para mirror.

### A5. Seletor de múltiplos aparelhos (`--list`) — `TODO` · impacto: MÉDIO
**Problema.** `resolve_device` pega "o primeiro" USB/TCP; com dois aparelhos sem
`DEVICE_SERIAL` o comportamento é imprevisível.
**Solução.** `android-dex --list` lista `adb devices -l` numerado com
modelo/serial; seleção interativa quando há mais de um e nenhum `DEVICE_SERIAL`.
**Aceite.** Com dois aparelhos plugados, o usuário escolhe qual usar.

### A6. `--from-usb` com porta de depuração sem fio dinâmica — `TODO` · impacto: MÉDIO
**Problema.** A migração USB→TCP assume porta `5555` (`android-dex-connect:48`).
Em Android 11+ com depuração sem fio "pura" a porta é aleatória.
**Solução.** Após `adb tcpip`, descobrir a porta via `adb shell` (ou usar
`adb pair`/mDNS quando disponível) em vez de fixar 5555; manter 5555 como padrão.
**Aceite.** `--from-usb` conecta em aparelho cuja porta de depuração não é 5555.

### A7. Tornar visível a persistência dos tweaks globais — `TODO` · impacto: BAIXO
**Problema.** `RESTORE_TWEAKS_ON_EXIT=0` por padrão deixa `enable_freeform_support`
e afins alterados em `settings global` do aparelho — modificação persistente
pouco visível.
**Solução.** Log explícito na 1ª aplicação ("estes ajustes ficam no aparelho até
`--restore-tweaks`") e um subcomando `android-dex --restore-tweaks`.
**Aceite.** Usuário consegue reverter tudo com um comando; a persistência é
anunciada.

### A8. Rigor de shell / erros silenciosos — `TODO` · impacto: BAIXO
**Observação.** `set -uo pipefail` sem `-e` e muitos `|| true` são escolha
consciente (o supervisor não pode morrer por um comando bobo), mas erros passam
sem registro.
**Solução.** Wrapper `try()` que loga o comando e o `rc` em nível DEBUG quando
`ADX_DEBUG=1`, preservando o comportamento não-fatal.
**Aceite.** Com `ADX_DEBUG=1`, falhas de comandos "silenciosos" aparecem no log.

### A9. Suíte de smoke tests — `TODO` · impacto: MÉDIO
**Solução.** `tests/` com `shellcheck` em todos os scripts + testes de
`version_ge`, `adx_backoff`, parsing de `adb devices` (com fixtures), e um
`--dry-run` que imprime os argumentos do scrcpy sem executar.
**Aceite.** `make test` roda em CI sem aparelho físico.

### A10. Paridade Windows (PowerShell) — `TODO` · impacto: BAIXO
**Solução.** Porta do supervisor para PowerShell (mesmo laço + backoff), atalho
`.lnk`, Tarefa Agendada no logon, `config.ps1`. Já esboçado no README do kit.
**Aceite.** `android-dex.ps1` sobe sessão resiliente no Windows 10/11.

---

## Parte B — Projeto irmão `android-dex-flash`

> Manutenção de dispositivo (unlock/root/firmware). **Nunca** um "motor de flash"
> próprio: é um **orquestrador** que roteia para as ferramentas oficiais/
> consagradas de cada OEM (`fastboot`, `heimdall`, `Magisk`, imagens de fábrica),
> com trilhos de segurança reais.

### Princípios inegociáveis
- **Somente o aparelho do próprio usuário.** A ferramenta assume propriedade.
- **Não existe root/flash universal e sem risco.** O objetivo é reduzir erro
  humano, não eliminar o risco físico de brick.
- **`--dry-run` é o padrão** para toda ação destrutiva; execução real exige
  confirmação digitada explícita (`--commit` + `digite: SIM`).
- **Consentimento por-passo** com o aviso específico do OEM (ex.: Knox e-fuse é
  permanente; Play Integrity/banco quebram).
- **Verificar antes de gravar:** modelo, hash do firmware, bateria mínima,
  backup reconhecido.

### Arquitetura (drivers por OEM)
```
bin/android-dex-flash  ── dispatcher (info | caps | unlock | root | flash-firmware)
        │  detecta estado (adb / fastboot / download) e OEM
        ▼
lib/drivers/<oem>.sh   ── driver_caps / driver_unlock / driver_root /
                          driver_flash_firmware / driver_warnings
lib/flash-common.sh    ── guard rails, consentimento, dry-run, fingerprint
lib/common.sh          ── (compartilhado com android-dex) log, XDG, backoff
```

### Fase 0 — `device-info` (leitura, risco ZERO) — `DONE`
Detecta marca/modelo/SO/patch de segurança, estado do bootloader
(`fastboot getvar unlocked`), verified boot, dicas de Play Integrity, ferramentas
presentes no host, e imprime **o que é possível** naquele aparelho e **o que se
perde**. Fundação segura para todo o resto.
**Aceite.** `android-dex-flash info` roda sem nunca escrever no aparelho.

### Fase 1 — Driver Pixel/AOSP (referência) — `WIP`
O caminho mais limpo e documentado: `fastboot flashing unlock` → patch do
`boot.img` com Magisk → `fastboot flash boot` → imagens de fábrica
(`flash-all`/`fastboot update`). Serve de modelo para os demais.
**Aceite.** Fluxo completo em `--dry-run` mostra a sequência exata; `--commit`
exige confirmação digitada e checa bateria/modelo.

### Fase 2 — Driver Samsung (Heimdall) — `WIP`
`heimdall` (open-source, cross-platform) + toggle "OEM unlock". **Aviso central:
o desbloqueio queima o Knox e-fuse permanentemente** (Samsung Pay/Pass/Health/
Pasta Segura morrem). Firmware via fontes oficiais (samloader/Frija).
**Aceite.** Recusa de continuar sem o usuário digitar o reconhecimento do Knox.

### Fase 3 — Xiaomi / Motorola / OnePlus — `WIP`
Cada um com sua peculiaridade de unlock: Xiaomi Mi Unlock (proprietário, espera
oficial de dias, só Windows p/ a etapa de unlock — a ferramenta orienta, não
burla); Motorola (código de unlock do site oficial); OnePlus/Sony (fastboot).
**Aceite.** `caps` explica corretamente, por marca, o que a ferramenta faz e o
que exige passo manual/oficial.

### Fase 4 — Backlog do flash — `TODO`
- Recovery customizada (TWRP/OrangeFox) onde aplicável.
- `payload-dumper` para extrair partições de OTAs A/B.
- Verificação de anti-rollback (recusar downgrade que possa brickar).
- Backup guiado (`fastboot`/adb) antes de qualquer gravação.
- Restauração pós-erro (voltar `boot.img` de fábrica).

---

## Ordem sugerida de execução
1. **A1 + A2** (correções de compatibilidade/robustez de maior retorno no kit).
2. **A3 + A4** (perfis + detecção de capacidade — a maior melhoria de UX/marca).
3. Endurecer as Fases 1–3 do `android-dex-flash` a partir do esqueleto atual.
4. A5–A10 conforme prioridade.

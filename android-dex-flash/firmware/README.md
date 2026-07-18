# Descritor autenticado de firmware

O `firmware.manifest` vincula exatamente um artefato a OEM, modelo e codename.
Ele é texto ASCII estrito e nunca é carregado com `source` ou `eval`.

Arquivos esperados no mesmo diretório:

```text
firmware.manifest
firmware.manifest.sig
factory-image.zip
```

Assine o manifesto com uma chave privada mantida fora do projeto:

```bash
openssl dgst -sha256 -sign firmware-signing-private.pem \
  -out firmware.manifest.sig firmware.manifest
```

Coloque apenas a chave pública explicitamente confiada em
`~/.config/android-dex-flash/trusted-keys/nome.pem` e valide com:

```bash
android-dex-flash verify-firmware /caminho/do/bundle
```

A validação exige assinatura, SHA-256, OEM e modelo/device compatíveis com o
aparelho conectado.

## Formato v2

O formato `android-dex-firmware-v2` acrescenta:

- `security_patch=AAAA-MM-DD`, comparado ao patch instalado quando o aparelho
  está em ADB;
- `rollback_index=N`, comparado quando o OEM expõe um índice por getprop ou
  fastboot;
- `plan=flash.plan` e `plan_sha256=...`, inventário assinado das operações e de
  cada imagem. O plano é dado estrito, nunca shell.

Cada linha de `flash.plan` possui quatro colunas separadas por TAB:

```text
update<TAB>all<TAB>factory-image.zip<TAB>SHA256
flash<TAB>boot<TAB>boot.img<TAB>SHA256
```

Use os arquivos `firmware.manifest.example` e `flash.plan.example` como base.
Mesmo o v2 não executa scripts do bundle. Se patch/índice atual não puder ser
lido, o resultado anti-rollback fica inconclusivo e a gravação automática
permanece bloqueada; use a ferramenta oficial do fabricante.

Validação dedicada:

```bash
android-dex-flash check-rollback /caminho/do/bundle
```

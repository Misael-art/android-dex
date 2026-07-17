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
aparelho conectado. Região, revisão de bootloader, anti-rollback, slots e plano
de partições ainda não são automaticamente verificáveis; por isso um manifesto
válido não habilita gravação automática nesta versão.

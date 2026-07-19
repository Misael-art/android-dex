# Contrato machine-v1

Cada requisição ocupa uma linha UTF-8 terminada por `\n` no socket privado. Respostas usam
`result` ou o erro estruturado, nunca ambos. Eventos são registros NDJSON com `jobId` e
`correlationId`; a primeira versão os consulta com `events.poll` para permitir reconexão da UI.

O transporte Linux usa `$XDG_RUNTIME_DIR/android-dex/core.sock`, diretório `0700`, socket
`0600` e validação de UID por `SO_PEERCRED`. Nenhum método recebe argv ou texto de shell.

# Agent Roadmap — hardening do `android-dexd` e do workspace

Plano executável por um agente de IA. Origem: análise de 2026-09-22 (v0.1.2).
Cada tarefa é **independente, pequena e verificável**. Execute na ordem das fases.

## Regras para o agente

1. Uma tarefa = uma branch/commit (`fix/<id>-slug`), mensagem no estilo `ui: ...`/`kit: ...`.
2. **Teste de regressão primeiro** (deve falhar), depois a correção (deve passar).
3. Antes de concluir: `make test lint` e `PYTHONPATH=android-dex-ui/src make ui-test qml-test` verdes.
4. Nunca execute `fastboot`/`heimdall`/`adb` reais; use apenas o modo `demo` e mocks (`tests/run.sh`).
5. Não altere a allowlist de métodos RPC além do descrito aqui.
6. Atualize `CHANGELOG.md` (seção *Unreleased*) e o status desta tabela (`TODO` → `DONE`).
7. Em dúvida sobre comportamento de segurança, **falhe fechado** e registre a dúvida no PR.

Arquivo principal: `android-dex-ui/src/android_dex_ui/service.py` (linhas citadas são de v0.1.2).

---

## Fase 0 — Pré-requisito de testes

### T0. `ui-test` roda sem instalar o pacote — `DONE` · P1
- **Problema:** `make ui-test` falha em 9 testes localmente (`ModuleNotFoundError: android_dex_ui`) porque subprocessos não herdam o pacote.
- **Fazer:** no `Makefile`, prefixar `ui-test`, `ui-smoke` com `PYTHONPATH=$(CURDIR)/android-dex-ui/src`.
- **Aceite:** `make ui-test` passa (25/25) num clone limpo sem `pip install -e`.

---

## Fase 1 — Segurança do fluxo destrutivo (P0)

### T1. Plano de manutenção de uso único — `DONE` · P0
- **Problema:** `maintenance_apply` (~L591) lê `plans/<id>.json` e nunca o consome → o mesmo plano pode disparar a gravação várias vezes até expirar.
- **Fazer:** sob `self._lock`, renomear atomicamente `plan_path` → `plan_path.with_suffix(".used")` (ou `unlink`) **antes** de iniciar o worker; se o rename falhar (`FileNotFoundError`), levantar `E-PLAN-MISSING`. Validações que falham antes do consumo não devem consumir.
- **Teste:** demo: `plan` → `apply` OK → segundo `apply` com mesmo `planId` retorna `E-PLAN-MISSING`.

### T2. Cursor de eventos monotônico — `DONE` · P0
- **Problema:** `_emit` corta a lista em `[-200:]` e `events_poll` devolve `cursor=len(events)` (máx. 200). Após 200 eventos o cliente fica preso em `after=200` e perde todos os eventos seguintes (progresso/conclusão de jobs).
- **Fazer:** contador `self._event_seq` (int crescente); cada evento recebe `"seq"`; `events_poll` devolve eventos com `seq > after` e `cursor = self._event_seq`. Se `after < seq_mais_antigo - 1`, incluir `"truncated": true`. Atualizar `schemas/event.schema.json` e `controller.py` (L221-224) se necessário.
- **Teste:** emitir 250 eventos; poll com cursor anterior retorna os novos; cursor cresce além de 200.

### T3. Lock em sessões e jobs — `DONE` · P0
- **Problema:** `ThreadingUnixStreamServer` → handlers concorrentes. `desktop_start` (checagem `E-SESSION-ACTIVE` + criação), `desktop_stop`, `session_list` e `job_status` mutam/leem `_sessions`/`_jobs` sem lock (TOCTOU: duas sessões simultâneas).
- **Fazer:** envolver check+create de `desktop_start` e todas as mutações/escritas de `_sessions`/`_jobs` com `self._lock` (é `RLock`); `job_status` retorna cópia (`dict(...)`) sob lock.
- **Teste:** demo, 2 threads chamando `desktop.start` ao mesmo tempo → exatamente uma sucede, outra `E-SESSION-ACTIVE`.

### T4. Reconciliação de jobs no boot — `DONE` · P0
- **Problema:** `_jobs` é carregado do disco; jobs `queued/running` de um daemon anterior ficam "running" para sempre.
- **Fazer:** no `__init__`, marcar esses jobs como `status="interrupted"`, `error={code:"E-JOB-INTERRUPTED",...}`, `completedAt`; persistir.
- **Teste:** escrever `jobs.json` com job `running`, instanciar `AndroidDexCore(demo=True)`, verificar `interrupted`.

---

## Fase 2 — Robustez do serviço (P1)

### T5. `maintenance.cancel` honesto — `DONE` · P1
- **Problema:** sempre retorna `{"cancelled": False}`, mesmo com `cancelable=True`.
- **Fazer (opção preferida):** se `cancelable` for falso → `E-JOB-CRITICAL` (como hoje); se verdadeiro → sinalizar `threading.Event` do job; no worker não-demo usar `Popen(start_new_session=True)` e `os.killpg(SIGTERM)`; status `cancelled`. Se isso exigir mudança grande em `runner.py`, **alternativa:** retornar `E-JOB-NOT-CANCELABLE` explícito e documentar. Nenhum job destrutivo deve virar cancelável.
- **Teste:** job cancelável em demo → `cancelled`; job crítico → `E-JOB-CRITICAL`.

### T6. Instância única do daemon — `DONE` · P1
- **Problema:** `serve()` (~L921) apaga o socket existente sem checar se há daemon vivo; o primeiro fica órfão.
- **Fazer:** antes do `unlink`, tentar `connect()`; se conectar → sair com erro "já em execução" (exit 1). Só remover socket se `ConnectionRefusedError`.
- **Teste:** subir `serve(demo=True)` em thread; segunda chamada falha sem remover o socket.

### T7. Socket criado já com 0600 — `DONE` · P2
- **Fazer:** `old = os.umask(0o077)` antes do bind, restaurar depois; manter `chmod` como defesa.
- **Teste:** `test_socket_mode_and_roundtrip` continua passando.

### T8. Estado de sessão confiável — `DONE` · P1
- **Problemas:** (a) `desktop_stop` marca sessões `stopped` mesmo se `--stop` falhou; (b) `session_list` usa só `os.kill(pid,0)` → PID reutilizado vira sessão fantasma; (c) ramo `PermissionError` não marca `changed`.
- **Fazer:** (a) usar returncode: falha → status `stop-failed` + `RpcFault` recuperável; (b) gravar `procStart` (campo 22 de `/proc/<pid>/stat`) no start e comparar; divergência = `finished`; (c) `changed = True`.
- **Teste:** sessão com `pid` vivo mas `procStart` diferente → `finished`.

### T9. Log completo por job — `DONE` · P2
- **Problema:** saída truncada em 12 KB dentro de `jobs.json`.
- **Fazer:** gravar stdout/stderr completos em `log_dir()/job-<id>.log` (0600); `jobs.json` guarda caminho + tail de 4 KB.

---

## Fase 3 — Qualidade e CI (P1/P2)

### T10. Testes de regressão cobrindo T1–T8 — `DONE` · P1
- Consolidar em `android-dex-ui/tests/test_service_robustness.py`. (Se já criados por tarefa, apenas garantir cobertura.)

### T11. ShellCheck pontual — `DONE` · P2
- Remover `SC2034,SC2153` do `-e` global no `Makefile`; adicionar `# shellcheck disable=SCxxxx` com justificativa só onde necessário. Aceite: `make lint` verde.

### T12. Supply chain do AppImage — `DONE` · P1
- `test.yml`/`release.yml` baixam `appimagetool` do canal `continuous` sem pin. Fixar URL de release versionada + verificar `sha256sum -c`. Pinar actions por SHA de commit.

### T13. Template de relatório de dispositivo — `DONE` · P2
- Criar `.github/ISSUE_TEMPLATE/device-report.yml` pedindo marca/modelo/Android/versão scrcpy e a saída de `android-dex-doctor`. Objetivo: destravar A1/A3/A4/A6 do `ROADMAP.md`.

---

## Fase 4 — Expansão (P3, só após Fases 1–3)

| ID | Item | Nota |
|:--|:--|:--|
| E1 | Streaming de eventos (subscribe) no socket, substituindo polling | usar `protocol.event()` já existente; manter `events.poll` como fallback |
| E2 | Tabela única de OEM compartilhada entre `_oem()` e `android-dex-kit/profiles/` | elimina cadeia de `if` |
| E3 | Unidade systemd `--user` para `android-dexd` (socket activation) | |
| E4 | Tela de histórico de sessões/jobs com logs na UI | depende de T9 |
| E5 | Empacotamento Flatpak / AUR | |

---

## Status

| Fase | Tarefas | Status |
|:--|:--|:--|
| 0 | T0 | DONE |
| 1 | T1 T2 T3 T4 | DONE |
| 2 | T5 T6 T7 T8 T9 | DONE |
| 3 | T10 T11 T12 T13 | DONE |
| 4 | E1–E5 | TODO |

**Definição de pronto global:** todas as fases 0–3 `DONE`, CI verde, `CHANGELOG.md` atualizado, release `v0.1.3`.

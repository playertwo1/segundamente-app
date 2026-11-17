# Plano — F12-05: Cancelamento e reagendamento de avisos ativos no Android via sync

**Spec de referência:** [2026-11-15-f1205-cancelamento-avisos.md](../specs/2026-11-15-f1205-cancelamento-avisos.md)  
**Passo da ponte:** Passo 9 (`docs/lumen/PONTE.md`)  
**Branch:** `feat/f1205-cancelamento-avisos`

---

## 1. Pré-condições e diretrizes

- Manter zero telemetria, dados estritamente sintéticos nos testes e nenhuma regressão nos callers de `TodoAlarmService.instance`.
- Não expor caminhos locais absolutos do ambiente ou informações pessoais em nenhum arquivo de documentação ou teste.
- Preservar o teste físico com o Galaxy S25 Ultra como `NOT_RUN` até a sessão de validação conjunta.

---

## 2. Mapa de arquivos

### Novos arquivos
- `test/data/services/todo_alarm_service_test.dart` — suíte unitária para `TodoAlarmService` usando `TodoAlarmBackend` em memória e relógio determinístico.

### Arquivos modificados
- `lib/data/services/todo_alarm_service.dart` — costura `TodoAlarmBackend`, construtor de teste, leitura de `getActiveNotifications()` no canal `'todo_reminders'` e cancelamento idempotente para itens concluídos, excluídos, reagendados ou órfãos.
- `test/data/services/todo_sync_service_test.dart` — casos de teste de integração cobrindo `AC-08` e `T05` conectando `TodoAlarmService.forTesting` ao `TodoService.alarmSynchronizer`.
- `STATE.md`, `docs/lumen/PONTE.md` e `docs/roadmap/F12-sync-com-o-lumen.md` — atualização de status e alinhamento de referências.

---

## 3. Etapas de implementação

### Etapa 1 — Endurecimento de `TodoAlarmService`

**Arquivo:** `lib/data/services/todo_alarm_service.dart`

1. Confirmar a abstração `TodoAlarmBackend` e a implementação `_PluginTodoAlarmBackend`.
2. Expor o construtor `@visibleForTesting TodoAlarmService.forTesting({required TodoAlarmBackend backend, DateTime Function()? now})`.
3. Em `synchronize(List<TodoItem> items)`:
   - Coletar pedidos pendentes e notificações ativas em `'todo_reminders'`;
   - Calcular `allIds = _notificationIds(items)` sobre todos os itens;
   - Cancelar:
     - Pedidos pendentes órfãos ou sem agendamento futuro;
     - Itens concluídos (`done`), tombstones (`isTombstoned`) ou sem alarme futuro, usando o ID determinístico em `allIds`;
     - Itens ativos adiados (`snoozedUntil != null`) antes de agendar no novo horário (`T05`);
     - Notificações ativas na bandeja em `'todo_reminders'` que não correspondam a tarefas ativas com alarme futuro;
   - Agendar itens ativos com horário válido via `_backend.zonedSchedule`.

### Etapa 2 — Suíte unitária do alarme

**Arquivo:** `test/data/services/todo_alarm_service_test.dart`

1. Implementar `FakeTodoAlarmBackend` registrando histórico de invocações (`cancel`, `zonedSchedule`), lista de pendentes e lista de notificações ativas simuladas.
2. Cobrir os seguintes cenários:
   - Agendamento correto no instante `due - alertMinutes`;
   - Execuções consecutivas idempotentes sem cancelamentos indevidos;
   - Notificação já disparada (ausente de `pendingNotificationRequests()`, presente em `getActiveNotifications()`): cancelada após conclusão ou exclusão;
   - Notificações de outros canais na bandeja preservadas intactas;
   - Reagendamento (`T05`): cancela o ID antes de emitir nova chamada de agendamento.

### Etapa 3 — Integração com o motor de sync

**Arquivo:** `test/data/services/todo_sync_service_test.dart`

1. Configurar `TodoAlarmService.forTesting` injetado em `TodoService.alarmSynchronizer`.
2. Validar recepção de lote via `_applyPulledMessages`:
   - Tarefa nova vinda do Lumen agenda alarme localmente; replay da mesma mutação não duplica;
   - Conclusão remota (`done: true`) cancela o alarme local e não cria `nextOccurrence` no Android;
   - Exclusão remota (`deleted_at != null`) cancela o alarme local;
   - Adiamento remoto (`snoozed_until` no futuro) cancela o aviso anterior e agenda no novo instante (`T05`).

### Etapa 4 — Atualização de documentação

1. Atualizar `docs/roadmap/F12-sync-com-o-lumen.md`:
   - Remover menções defasadas a branches provisórias (como `feat/f1204-sync-tarefas (sem merge)`);
   - Confirmar `F12-04` e `F12-05` com código e testes sintéticos completos.
2. Atualizar `docs/lumen/PONTE.md`:
   - Alinhar o status do Passo 9 com o término da validação sintética.
3. Atualizar `STATE.md`:
   - Registrar as métricas de testes e manter o teste real de hardware como `NOT_RUN`.

---

## 4. Comandos de validação

```bash
# Executar testes unitários e de integração de alarme e sync
flutter test --no-pub \
  test/data/services/todo_alarm_service_test.dart \
  test/data/services/todo_sync_service_test.dart \
  test/data/services/todo_service_test.dart \
  test/integration/todo_undo_flow_test.dart

# Análise estática do código modificado
flutter analyze --no-pub \
  lib/data/services/todo_alarm_service.dart \
  test/data/services/todo_alarm_service_test.dart \
  test/data/services/todo_sync_service_test.dart
```

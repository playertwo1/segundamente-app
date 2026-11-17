# F12-05 — Cancelamento e reagendamento de avisos ativos no Android via sync (Passo 9 / Ponte)

**Data:** 2026-11-15
**Passo do plano da ponte:** Passo 9 (`F12-05` — [`docs/lumen/PONTE.md`](../../lumen/PONTE.md))
**Critérios de aceite:** `AC-08` (alarme local independente no Android) e `T05` (lembrete reagendado cancela aviso anterior antes de programar novo)
**Branch:** `feat/f1205-cancelamento-avisos`

---

## 1. Diagnóstico e objetivo

Na entrega `F12-04`, o motor de sincronização (`TodoSyncService` + `TodoService.applyRemoteMutationBatch`) já acionava `TodoService.alarmSynchronizer` após receber alterações do Lumen (conclusão, exclusão/tombstone, adiamento ou criação de tarefa). Porém, `TodoAlarmService.synchronize(List<TodoItem> items)` apresentava uma lacuna crítica no Android:

- Ele calculava IDs determinísticos apenas para tarefas ativas e só chamava `cancel(id)` para entradas ainda presentes em `pendingNotificationRequests()`.
- Quando o alarme **já havia tocado** no Android (saindo de `pendingNotificationRequests()` e permanecendo visível na bandeja de notificações), uma conclusão (`done: true`), exclusão (`deletedAt != null`) ou adiamento (`snoozedUntil` futuro) vindo do PC e sincronizado no celular não cancelava a notificação já exibida.
- Além disso, `TodoAlarmService` acoplava-se diretamente a `FlutterLocalNotificationsPlugin`, `Platform.isAndroid` e `DateTime.now()`, impedindo testes unitários e integrados determinísticos de agendamento/cancelamento.

Esta etapa endurece `TodoAlarmService` para garantir remoção de avisos pendentes e ativos na bandeja e adiciona cobertura automatizada unitária e integrada com `TodoSyncService`.

### Fora de escopo
- Alterações no lado desktop Windows (Lumen) ou no Worker Cloudflare.
- Ligação direta LAN TLS / WebSocket ao vivo ou novas entidades `v1.1`.
- Edição de `PONTE.md`, `STATE.md` ou `F12-sync-com-o-lumen.md` e execução em hardware físico (S25 + notebook), conduzidas separadamente pelo coordenador após esta entrega.

---

## 2. Desenho técnico (`lib/data/services/todo_alarm_service.dart`)

### 2.1 Costura testável (`TodoAlarmBackend`)
- Introduzir a interface `TodoAlarmBackend` encapsulando suporte de plataforma (`isSupported`), inicialização (`initialize`, `getNotificationAppLaunchDetails`), leitura/solicitação de permissões (`readStatus`, `areNotificationsEnabled`, `openAppNotificationSettings`, `requestNotificationsPermission`, `requestExactAlarmsPermission`) e operações de agendamento/bandeja (`pendingNotificationRequests`, `getActiveNotifications`, `cancel`, `zonedSchedule`).
- Manter `_PluginTodoAlarmBackend` como implementação padrão delegando para `FlutterLocalNotificationsPlugin` e `AndroidFlutterLocalNotificationsPlugin`.
- Adicionar construtor `@visibleForTesting TodoAlarmService.forTesting({required TodoAlarmBackend backend, DateTime Function()? now})` com relógio injetável para testes determinísticos, sem quebrar `TodoAlarmService.instance` nem qualquer caller existente (`main.dart`, `todo_repository.dart`, `todo_service.dart`).

### 2.2 Algoritmo de `synchronize(List<TodoItem> items)`
1. Se `!_backend.isSupported`, retornar `TodoAlarmStatus.unsupported`.
2. Inicializar backend, ler `status = await _backend.readStatus(channelId: _channelId)` e obter `pendingNotificationRequests()`.
3. Consultar `getActiveNotifications()` dentro de `try/catch` seguro (degradando para lista vazia se a plataforma/versão não suportar), filtrando estritamente `notification.channelId == _channelId` (`'todo_reminders'`) para nunca interferir em outros canais do app.
4. Calcular `scheduledDates` para os itens ativos com horário válido via `TodoScheduleCalculator.alarmDateTimeFor(..., now: _now())`.
5. Calcular `allIds = _notificationIds(items)` sobre **todos** os itens recebidos (ativos, concluídos, tombstones e sem agendamento), garantindo mapeamento determinístico consistente mesmo após conclusão ou exclusão.
6. Executar `cancel(id: ...)` (deduplicado por `id` na mesma passada) para:
   - pedidos pendentes com prefixo `'todoAlarm:'` quando `status != TodoAlarmStatus.ready`, `!scheduledDates.containsKey(taskId)` ou `request.id != allIds[taskId]`;
   - todo item em `items` que esteja concluído (`item.done`), em tombstone (`item.isTombstoned`) ou sem alarme futuro (`!scheduledDates.containsKey(item.id)`), chamando `cancel(id: allIds[item.id]!)` mesmo que ausente de `pendingNotificationRequests()`;
   - todo item ativo adiado para o futuro (`item.snoozedUntil != null && scheduledDates.containsKey(item.id)`), garantindo `cancel(id: allIds[item.id]!)` **antes** do novo `zonedSchedule(...)` (`T05`);
   - toda notificação ativa no canal `'todo_reminders'` com `id` órfão (ausente de `allIds`) ou pertencente a item concluído, excluído, sem agendamento futuro, adiado ou quando `status != TodoAlarmStatus.ready`.
7. Se `status != TodoAlarmStatus.ready`, retornar `status`. Caso contrário, agendar via `zonedSchedule` apenas os itens ativos com `scheduledDates[item.id] != null`.

---

## 3. Critérios de verificação automatizada

1. `test/data/services/todo_alarm_service_test.dart`:
   - Tarefa futura com `alertMinutes` agenda `zonedSchedule` em `due - alertMinutes`;
   - Re-sincronização idempotente mantém agendamento sem perda ou cancelamento indevido;
   - Tarefa concluída (`done: true`) ou excluída (`deletedAt != null`) cujo alarme já havia tocado (ausente de `pendingNotificationRequests`) tem `cancel(id)` chamado, além de remoção de órfãs em `getActiveNotifications()` apenas no canal `'todo_reminders'`;
   - Tarefa adiada (`snoozedUntil` futuro) chama `cancel(id)` antes de reagendar `zonedSchedule` no novo instante.
2. `test/data/services/todo_sync_service_test.dart`:
   - Integração ponta a ponta com `TodoAlarmService.forTesting` ligado ao `TodoService.alarmSynchronizer`:
     - tarefa vinda do PC na primeira consulta agenda `due - alertMinutes`; replay do mesmo envelope é idempotente;
     - conclusão ou exclusão no PC seguida de sync no celular dispara `cancel(id)` mesmo sem pedido pendente;
     - adiamento no PC (`snoozed_until` futuro) dispara `cancel(id)` e reagenda para o novo instante no celular;
     - conclusão ou adiamento no celular aciona `alarmSynchronizer` localmente e enfileira envelope na outbox para o PC.
3. Validação estática e regressão (`todo_alarm_service_test.dart`, `todo_sync_service_test.dart`, `todo_service_test.dart`, `todo_undo_flow_test.dart` e `flutter analyze --no-pub`). Validação em hardware real (S25 + notebook) permanece `NOT_RUN` até o teste físico do Passo 9.

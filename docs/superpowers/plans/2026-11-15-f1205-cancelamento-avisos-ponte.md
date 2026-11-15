# F12-05 — Plano de implementação: Cancelamento e reagendamento de avisos ativos no Android

> **Para agentes implementadores:** manter zero telemetria, dados estritamente sintéticos, nenhuma regressão nos callers existentes de `TodoAlarmService.instance` e execução offline sem rede real nos testes.
> **SDK Flutter:** `C:\Users\notefael\tools\flutter\bin\flutter.bat`.

**Spec:** [`2026-11-15-f1205-cancelamento-avisos-ponte.md`](../specs/2026-11-15-f1205-cancelamento-avisos-ponte.md)
**Branch:** `feat/f1205-cancelamento-avisos`

---

## Mapa de arquivos

### Novos arquivos
- `test/data/services/todo_alarm_service_test.dart` — testes unitários do `TodoAlarmService` com `TodoAlarmBackend` em memória e relógio determinístico.

### Arquivos modificados
- `lib/data/services/todo_alarm_service.dart` — costura `TodoAlarmBackend`, construtor `@visibleForTesting TodoAlarmService.forTesting(...)`, leitura segura de `getActiveNotifications()` no canal `'todo_reminders'` e cancelamento explícito para itens concluídos, excluídos, sem alarme futuro, adiados ou órfãos.
- `test/data/services/todo_sync_service_test.dart` — inicialização de l10n para uso do `TodoAlarmService` real e novos cenários integrados com `TodoService.alarmSynchronizer` cobrindo `AC-08` e `T05`.

---

## Tarefa 1 — Endurecer `TodoAlarmService`

**Arquivo:** `lib/data/services/todo_alarm_service.dart`

1. Definir `abstract interface class TodoAlarmBackend` e a implementação padrão `_PluginTodoAlarmBackend` usando `FlutterLocalNotificationsPlugin` / `AndroidFlutterLocalNotificationsPlugin`.
2. Expor `TodoAlarmService.forTesting({required TodoAlarmBackend backend, DateTime Function()? now})` preservando `TodoAlarmService.instance` sem mudanças de assinatura para os callers atuais.
3. Atualizar `synchronize(List<TodoItem> items)`:
   - usar `_backend.isSupported`, `_backend.readStatus(channelId: _channelId)`, `_backend.pendingNotificationRequests()` e `_backend.getActiveNotifications()` (em `try/catch`, filtrando `channelId == 'todo_reminders'`);
   - calcular `allIds = _notificationIds(items)` para todos os itens recebidos;
   - cancelar (sem duplicar chamadas ao mesmo `id` no ciclo):
     - pendentes inválidos/sem agendamento/sem permissão;
     - itens concluídos (`done`), tombstones (`isTombstoned`) ou sem alarme futuro (`!scheduledDates.containsKey(item.id)`), mesmo quando ausentes de `pendingNotificationRequests()`;
     - itens ativos com `snoozedUntil != null && scheduledDates.containsKey(item.id)` antes de chamar `zonedSchedule(...)`;
     - notificações ativas no canal `'todo_reminders'` com `id` órfão ou pertencentes a item sem agendamento futuro, concluído, excluído ou adiado;
   - agendar via `_backend.zonedSchedule` somente os itens ativos com `scheduledDates[item.id] != null`.

## Tarefa 2 — Testes unitários do `TodoAlarmService`

**Arquivo:** `test/data/services/todo_alarm_service_test.dart`

1. Criar fake `TodoAlarmBackend` registrando chamadas ordenadas (`cancel`, `zonedSchedule`), lista de pendentes e lista de notificações ativas (incluindo simulação de erro em `getActiveNotifications()`).
2. Cobrir:
   - agendamento exato em `due - alertMinutes` (`America/Sao_Paulo`);
   - re-sincronização idempotente sem perda ou cancelamento indevido;
   - cancelamento de tarefa concluída (`done: true`) ou excluída (`deletedAt != null`) ausente de `pendingNotificationRequests()`;
   - remoção de notificação ativa órfã ou inválida em `'todo_reminders'` preservando outros canais, e degradação segura se `getActiveNotifications()` lançar erro;
   - tarefa adiada (`snoozedUntil` futuro) chamando `cancel(id)` antes de `zonedSchedule` no novo horário (`T05`).

## Tarefa 3 — Testes integrados `TodoSyncService` + `TodoAlarmService`

**Arquivo:** `test/data/services/todo_sync_service_test.dart`

1. Inicializar `TestWidgetsFlutterBinding.ensureInitialized()`, `SharedPreferences.setMockInitialValues({'language': 'pt'})` e `UserStorage.initL10n()` para permitir uso do `TodoAlarmService` real nos novos testes integrados.
2. Conectar `TodoAlarmService.forTesting` ao `TodoService.alarmSynchronizer` com `_FakeRelayMailbox` cobrindo:
   - criação no PC chegando ao celular e agendando `due - alertMinutes`, com replay idempotente sem duplicar nem alterar agendamento;
   - conclusão e exclusão no PC disparando `cancel(id)` no celular mesmo sem pedido pendente;
   - adiamento no PC (`snoozed_until` futuro) disparando `cancel(id)` antes de reagendar no celular;
   - conclusão e adiamento locais no celular acionando `alarmSynchronizer` e enfileirando o envelope na outbox para o PC.

## Tarefa 4 — Validação e limpeza

1. Executar testes:
   ```powershell
   C:\Users\notefael\tools\flutter\bin\flutter.bat test --no-pub `
     test/data/services/todo_alarm_service_test.dart `
     test/data/services/todo_sync_service_test.dart `
     test/data/services/todo_service_test.dart `
     test/integration/todo_undo_flow_test.dart
   ```
2. Executar análise estática:
   ```powershell
   C:\Users\notefael\tools\flutter\bin\flutter.bat analyze --no-pub `
     lib/data/services/todo_alarm_service.dart `
     test/data/services/todo_alarm_service_test.dart `
     test/data/services/todo_sync_service_test.dart
   ```
3. Restaurar eventuais mutações automáticas do Flutter 3.47:
   ```powershell
   git -C C:\Users\notefael\projetos\segundamente checkout -- analysis_options.yaml android/gradle.properties
   ```

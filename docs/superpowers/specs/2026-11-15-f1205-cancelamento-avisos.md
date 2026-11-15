# Spec — F12-05: Cancelamento e reagendamento de avisos ativos no Android via sync

**Data:** 2026-11-15  
**Passo da ponte:** Passo 9 (`F12-05` — `docs/lumen/PONTE.md`)  
**Critérios de aceite:** `AC-08` (alarme local independente no Android) e `T05` (lembrete reagendado cancela aviso anterior antes de programar novo)  
**Contrato de referência:** `docs/lumen/CONTRATO-SYNC.md` §7.3  
**Branch prevista:** `feat/f1205-cancelamento-avisos`

---

## 1. Objetivo e escopo

Garantir que a sincronização ponta a ponta de tarefas via caixa de correio HTTP reflita com exatidão o ciclo de vida dos avisos e lembretes no aplicativo Android (Segunda Mente):

1. **Cancelamento cruzado e local:** ao receber alteração remota do Lumen ou ao executar mutação local de conclusão (`done: true`), exclusão (`deletedAt != null` / tombstone) ou adiamento (`snoozedUntil` futuro), qualquer aviso programado para a tarefa deve ser imediatamente cancelado.
2. **Avisos já disparados na bandeja:** tarefas concluídas ou excluídas cujo alarme já tocou e que saíram de `pendingNotificationRequests()` mas ainda repousam ativas na bandeja de notificações do sistema operacional Android (`getActiveNotifications()`) devem ser canceladas sem deixar avisos órfãos ou inconsistentes.
3. **Reagendamento determinístico (`T05`):** alterações nos campos de tempo (`dueDate`, `dueTime`, `timeZone`, `alertMinutes`) ou novo adiamento (`snoozedUntil`) devem cancelar com segurança o aviso anterior antes de efetuar o novo agendamento exato.
4. **Isolamento de canais e robustez:** o cancelamento na bandeja deve filtrar estritamente o canal `'todo_reminders'` e o payload prefixado `todoAlarm:<taskId>`, nunca afetando notificações de outros canais do aplicativo.
5. **Regra de recorrência remota (§7.3 do contrato):** ao receber um envelope remoto marcando uma tarefa recorrente como `done: true`, o Android **nunca** calcula ou gera `nextOccurrence` localmente (apenas o dispositivo que originou a conclusão cria a próxima ocorrência).

### Fora de escopo

- Alterações no lado Windows (Lumen) ou no Worker Cloudflare (endereçados em `L6.4`).
- Sincronização de notas, conversas, personas ou anexos (pertencentes à versão 1.1 do contrato).
- Execução do teste físico ponta a ponta com o aparelho Samsung Galaxy S25 Ultra conectado (permanece explicitamente registrado como `NOT_RUN` até a sessão de validação física com hardware).

---

## 2. Diagnóstico da implementação anterior

Na etapa `F12-04`, o motor de sincronização (`TodoSyncService`) passou a integrar a outbox local e a aplicação remota através de `TodoService.applyRemoteMutationBatch`, que por sua vez invoca `TodoService.alarmSynchronizer` (`TodoAlarmService.instance.synchronize`).

Entretanto, foram identificados pontos que demandam garantia estrita:
- `pendingNotificationRequests()` do plugin do Flutter retorna apenas notificações ainda não disparadas pelo alarme exato do Android. Quando o alarme toca no horário previsto, o sistema move a notificação para a bandeja ativa (`getActiveNotifications()`). Um `cancel(id)` que consultava apenas os pendentes deixava o card visível na bandeja mesmo após o item ser concluído ou deletado remotamente no Lumen.
- O mapeamento determinístico de inteiros de notificação a partir do ID textual da tarefa (`_notificationIds`) precisa ser executado sobre **todos** os itens da lista recebida (inclusive concluídos e excluídos), garantindo que o `id` inteiro calculado coincida exatamente com o que foi agendado originalmente.
- Para testes unitários e de integração determinísticos sem dependência do motor Android nativo, é necessária uma costura de teste (*test seam*) limpa e de baixo acoplamento (`TodoAlarmBackend`), permitindo relógio injetável (`DateTime Function()? now`) e simulação em memória das listas de pedidos pendentes e notificações ativas na bandeja.

---

## 3. Desenho técnico

### 3.1 Costura testável (`TodoAlarmBackend` em `lib/data/services/todo_alarm_service.dart`)

Introdução da abstração `TodoAlarmBackend` e construtor de teste:

```dart
abstract interface class TodoAlarmBackend {
  bool get isSupported;
  Future<bool?> initialize({required TodoAlarmActionHandler onAction});
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails();
  Future<TodoAlarmStatus> readStatus({required String channelId});
  Future<bool?> areNotificationsEnabled();
  Future<bool?> openAppNotificationSettings();
  Future<bool?> requestNotificationsPermission();
  Future<bool?> requestExactAlarmsPermission();
  Future<List<PendingNotificationRequest>> pendingNotificationRequests();
  Future<List<ActiveNotification>> getActiveNotifications();
  Future<void> cancel({required int id});
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    required String payload,
  });
}
```

- A classe de produção `_PluginTodoAlarmBackend` implementa `TodoAlarmBackend` delegando para `FlutterLocalNotificationsPlugin` e `AndroidFlutterLocalNotificationsPlugin`.
- `TodoAlarmService.forTesting({required TodoAlarmBackend backend, DateTime Function()? now})` expõe a injeção necessária para testes determinísticos sem alterar o singleton `TodoAlarmService.instance` nem os callers de produção (`main.dart`, `todo_service.dart`, `todo_repository.dart`).

### 3.2 Algoritmo de sincronização e cancelamento em `synchronize`

Em `TodoAlarmService.synchronize(List<TodoItem> items)`:

1. Se `!_backend.isSupported`, retorna `TodoAlarmStatus.unsupported`.
2. Inicializa o backend e consulta `status = await _backend.readStatus(channelId: 'todo_reminders')`.
3. Coleta os pedidos pendentes (`pendingNotificationRequests()`) e as notificações ativas na bandeja (`getActiveNotifications()`, degradando graciosamente em caso de erro e filtrando `notification.channelId == 'todo_reminders'`).
4. Identifica tarefas ativas com horário configurado (`!item.done && !item.isTombstoned && item.hasAlarmTime`) e calcula suas datas de alarme (`TodoScheduleCalculator.alarmDateTimeFor`).
5. Gera o mapa determinístico `allIds = _notificationIds(items)` para toda a lista de itens.
6. Executa cancelamento idempotente (`cancelOnce(id)`):
   - **Pendentes inconsistentes:** qualquer pedido em `pendingNotificationRequests()` com prefixo `todoAlarm:` cujo status de alarme não esteja pronto, ou cuja tarefa não tenha mais alarme futuro, ou cujo ID tenha divergido;
   - **Itens sem alarme ativo:** para todo item em `items` que esteja concluído (`item.done`), excluído (`item.isTombstoned`), sem data de alarme futura, ou com adiamento ativo (`snoozedUntil != null`), cancela `allIds[item.id]!` mesmo que já não conste em `pendingNotificationRequests()`;
   - **Bandeja de notificações ativas:** para qualquer notificação presente em `getActiveNotifications()` no canal `'todo_reminders'`, se o ID não corresponder a uma tarefa ativa com agendamento futuro e sem adiamento, aciona `cancelOnce(id)`.
7. Se `status != TodoAlarmStatus.ready`, encerra retornando o status.
8. Para cada tarefa ativa com data de alarme futura calculada, agenda o disparo pontual via `_backend.zonedSchedule` com payload `todoAlarm:<taskId>`.

### 3.3 Integração com `TodoService` e `TodoSyncService`

- `TodoService.alarmSynchronizer` (já existente como função estática injetável) dispara `synchronize` em toda mutação local (`setDone`, `snooze`, `deleteForSession`, `remove`, `edit`) e ao término de `applyRemoteMutationBatch`.
- Em `TodoSyncService._applySingleRemoteTask`, quando o envelope remoto traz `done: true`, nenhuma chamada para gerar recorrência (`nextOccurrence`) é permitida no lado cliente receptor, cumprindo a seção 7.3 do `CONTRATO-SYNC.md`.

---

## 4. Atualização de documentação da ponte

Após a validação sintética:
1. `STATE.md`: registrar a conclusão dos testes sintéticos de `F12-05` (`AC-08` e `T05`) mantendo a validação com aparelho Galaxy S25 Ultra como `NOT_RUN`.
2. `docs/lumen/PONTE.md`: atualizar o Passo 9 indicando código e testes sintéticos completos no Flutter e no Rust.
3. `docs/roadmap/F12-sync-com-o-lumen.md`: corrigir referências defasadas a branches provisórias (como `feat/f1204-sync-tarefas (sem merge)`), consolidando o status de `F12-04` e `F12-05`.

---

## 5. Critérios de verificação automatizada

1. **Testes unitários de alarme:** `test/data/services/todo_alarm_service_test.dart`
   - Agendamento exato em `due - alertMinutes` no fuso configurado;
   - Idempotência em múltiplas invocações consecutivas sem cancelamentos indevidos;
   - Cancelamento de aviso já disparado que saiu de `pendingNotificationRequests()` mas permanece na bandeja;
   - Isolamento de canal (notificações em outros canais nunca são canceladas);
   - Reagendamento (`T05`): adiamento chama `cancel` no ID antigo antes de programar novo horário.
2. **Testes de integração com o motor de sync:** `test/data/services/todo_sync_service_test.dart`
   - Tarefa recebida do PC programa aviso no Android; replay do mesmo lote é idempotente;
   - Conclusão ou exclusão recebida do PC cancela o aviso no Android mesmo sem pedido pendente;
   - Adiamento vindo do PC cancela e reprograma no novo horário (`T05`);
   - Conclusão remota de tarefa recorrente não gera nova ocorrência localmente no Android.
3. **Análise estática:** `flutter analyze --no-pub` sem novos avisos ou erros.

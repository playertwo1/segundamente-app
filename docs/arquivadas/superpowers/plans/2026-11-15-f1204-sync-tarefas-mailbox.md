# F12-04 — Plano de implementação: Sync de tarefas via caixa de correio HTTP

> **Para agentes implementadores:** executar com TDD estrito, uma etapa por vez, mantendo zero telemetria, zero segredos fora do `SecretStorage` e nenhuma dependência de rede em testes unitários/widget.
> **SDK Flutter:** usar o binário `flutter` configurado no ambiente (ex.: `<flutter-sdk>\bin\flutter`).

**Spec:** [`2026-11-15-f1204-sync-tarefas-mailbox.md`](../specs/2026-11-15-f1204-sync-tarefas-mailbox.md)
**Contrato:** [`docs/lumen/CONTRATO-SYNC.md`](../../lumen/CONTRATO-SYNC.md)

---

## Mapa de arquivos

### Novos arquivos
- `lib/data/services/lumen_mailbox_crypto.dart` — cifra `coucou-mailbox/v1` (`GCMBlockCipher(AESEngine())` do `pointycastle`), padding 128B, prefixo `u32be`, AAD 41B e códigos exatos de rejeição.
- `lib/data/services/lumen_mailbox_client.dart` — cliente HTTP `package:http` para `POST /messages?to=pc`, `GET /messages?for=phone&after=&limit=100`, `POST /ack?for=phone` e `GET /stats`.
- `lib/domain/models/todo_sync_state.dart` — modelos JSON imutáveis: `SyncEnvelope`, `TodoSyncOutboxEntry`, `AppliedMutationRecord`, `TodoTextConflict`, `QuarantinedSyncEnvelope`, `PoisonMailboxRecord`, `TodoSyncState` e enum `TodoSyncDisplayState`.
- `lib/data/services/todo_sync_service.dart` — motor offline-first de reconciliação (pull, merge 3-vias, quarentena de venenosas após 3 falhas, ack contíguo, push FIFO, stats e resolução manual de conflitos).
- `lib/data/services/todo_sync_scheduler.dart` — registro do `Workmanager` (`lumenTodoPeriodicSyncTask`, 1h) e gatilho de foreground/background isolado.
- `test/data/services/lumen_mailbox_crypto_test.dart`
- `test/data/services/lumen_mailbox_client_test.dart`
- `test/domain/models/todo_sync_state_test.dart`
- `test/data/services/todo_sync_service_test.dart`
- `test/data/services/todo_sync_scheduler_test.dart`

### Arquivos modificados
- `lib/data/services/file_system_service.dart` — adicionar `getTodoSyncFilePath(String userId)` (`<workspace>/_<userId>/Todo/todo-sync-v1.json`).
- `lib/data/services/todo_service.dart` — incrementar `version` nas mutações locais, expor seam/hook para os 9 métodos de mutação gravarem na outbox sob lock e dispararem sync assíncrono, além de método interno de aplicação remota (`applyRemoteMerge` / `transactRemote`) que **não** gera `nextOccurrence` e aciona `_requestAlarmSync`.
- `lib/data/repositories/todo_repository.dart` — repassar leitura de status de sync, lista de conflitos, `syncNow()` e `resolveTextConflict(...)`.
- `lib/data/repositories/memex_router.dart` — expor `getTodoSyncSnapshot()`, `syncTodosNow()`, `resolveTodoConflict(...)` e inicialização opcional do hook de sync.
- `lib/data/services/health_service.dart` — tratar `task == 'lumenTodoPeriodicSyncTask'` dentro de `callbackDispatcher()`.
- `lib/main.dart` — registrar `lumenTodoPeriodicSyncTask` na inicialização e acionar sync debounced em `didChangeAppLifecycleState(AppLifecycleState.resumed)`.
- `lib/ui/todo/view_models/todo_viewmodel.dart` — estado de sync (`TodoSyncSnapshot`), loading indicador sem bloquear tarefas locais, `syncNow()` e `resolveTextConflict(...)`.
- `lib/ui/todo/widgets/todo_screen.dart` — barra de status (`"Salvo no aparelho"` vs `"Sincronizado"`, botão `"Sincronizar agora"`), banner de resolução manual de conflito `pending_review` (sem usar `ListTile`!) e gatilhos em `initState` e `AppLifecycleState.resumed`.
- `test/data/services/todo_service_test.dart` — cobrir os 9 hooks na outbox, monotonicidade de `version`, não geração de `nextOccurrence` na aplicação remota e disparo de alarme após mudança remota.
- `test/ui/todo/view_models/todo_viewmodel_test.dart` e `test/ui/todo/widgets/todo_screen_test.dart` — atualizar `_FakeRouter` e adicionar testes de UI, conflito, estado vazio sem `ListTile`, a11y (`48x48dp`) e `textScaleFactor = 2.0`.

> **Observação:** as chaves ARB `todoSync*` e `todoConflict*` já existem em `lib/l10n/app_pt.arb` e `lib/l10n/app_en.arb`. Só alterar ARB se algum estado adicional precisar de string nova (mantendo paridade estrita pt/en e rodando `flutter gen-l10n`).

---

## Tarefa 1 — Cifra `coucou-mailbox/v1` e validação de 100% dos vetores

**Arquivos:** `lib/data/services/lumen_mailbox_crypto.dart`, `test/data/services/lumen_mailbox_crypto_test.dart`

1. Escrever primeiro os testes em `test/data/services/lumen_mailbox_crypto_test.dart` lendo `test/fixtures/lumen_mailbox_test_vectors.json`:
   - Derivar `kMailbox` a partir de `inputs.key` via `LumenRelayCrypto.deriveFromBase64Url`.
   - Para cada uma das 3 entradas em `messages`: validar que `open(...)` retorna exatamente o JSON esperado em UTF-8 e que `seal(...)` com novo nonce produz envelope aceito por `open(...)` com o `role` correspondente (`1=pc`, `2=phone`).
   - Para todas as 9 entradas em `mustRefuse`: validar `LumenMailboxCryptoException` com o código exato esperado no JSON (`bad_tag`, `bad_version`, `too_short`, `bad_padding`, `bad_length`, `bad_json`).
   - Adicionar testes unitários extras para `invalid_room`, body com `length > 66_000` (`bad_length`) e texto limítrofe de 124 bytes (cabe no bloco de 128B: `4 + 124`) vs 125 bytes (pula para 256B -> body `285B`).
2. Implementar `LumenMailboxCrypto` usando `GCMBlockCipher(AESEngine())` (`pointycastle`):
   - `AEADParameters(KeyParameter(kMailbox), 128, nonce, aad)` com `aad` de 41 bytes (`"coucou-mailbox/v1"` || `ascii(room)` || `[toByte, 1]`).
   - `seal`: checar `jsonBytes.length <= 65_536`, construir `u32be(len) || jsonBytes || 0x00*` (múltiplo de 128, mínimo 128), checar `1 + 12 + padded.length + 16 <= 66_000`, gerar `nonce` com `Random.secure()`, retornar `Uint8List`.
   - `open`: seguir a ordem da spec (`invalid_room`, `> 66_000 -> bad_length`, `< 157 || (len - 29) % 128 != 0 -> too_short`, `ver != 1 -> bad_version`, falha GCM -> `bad_tag`, `declaredLen > 65_536 || 4 + declaredLen > plain.length -> bad_length`, bytes != 0 após payload -> `bad_padding`, `utf8.decode(allowMalformed: false)` / `jsonDecode` -> `bad_json`).
3. Executar `flutter test --no-pub test/data/services/lumen_mailbox_crypto_test.dart` e confirmar 100% verde.

---

## Tarefa 2 — Cliente HTTP da caixa de correio (`LumenMailboxClient`)

**Arquivos:** `lib/data/services/lumen_mailbox_client.dart`, `test/data/services/lumen_mailbox_client_test.dart`

1. Escrever testes com `MockClient` (`package:http/testing.dart`) cobrindo:
   - `postMessage`: `POST <httpBaseUrl>/v1/mailbox/<room>/messages?to=pc`, `Authorization: Bearer <access>`, `Content-Type: application/octet-stream`, `X-Lumen-Msg-Id: <msgId>`, parsing de `{seq, id, duplicate}`.
   - `listMessages`: `GET <httpBaseUrl>/v1/mailbox/<room>/messages?for=phone&after=<seq>&limit=100`, parsing camelCase `{messages: [{seq, id, createdAt, sizeBytes, payloadB64}], latestSeq, pendingCount}` com decodificação Base64 padrão.
   - `ack`: `POST <httpBaseUrl>/v1/mailbox/<room>/ack?for=phone` com body `{"uptoSeq": seq}` e parsing `{ackedUpto, deleted, remaining}`.
   - `fetchStats`: `GET <httpBaseUrl>/v1/mailbox/<room>/stats` com parsing `{pendingPc, pendingPhone, storedBytes, revoked}`.
   - Erros: `401`, `403`, `404`, `409`, `410`, `413`, `429`, `503`, `507` e timeout mapeados em `LumenMailboxHttpException` tipada sem incluir `room` ou `access` na mensagem/exceção.
2. Implementar `LumenMailboxClient` aceitando `http.Client?` injetável para testes e timeout padrão de 15s.
3. Rodar `flutter test --no-pub test/data/services/lumen_mailbox_client_test.dart`.

---

## Tarefa 3 — Modelos de sync e caminho de armazenamento (`todo-sync-v1.json`)

**Arquivos:** `lib/data/services/file_system_service.dart`, `lib/domain/models/todo_sync_state.dart`, `test/domain/models/todo_sync_state_test.dart`

1. Adicionar `String getTodoSyncFilePath(String userId)` em `FileSystemService` retornando `p.join(getTodoPath(userId), 'todo-sync-v1.json')`.
2. Criar `lib/domain/models/todo_sync_state.dart` com:
   - `SyncEnvelope` (`contract_version`, `mutation_id`, `device_id`, `origin_role`, `entity_type`, `entity_id`, `base_version`, `new_version`, `updated_at`, `payload`), incluindo helper de serialização que normaliza `due == reportDueUnknown` para `""` e mescla `extraFields` desconhecidos sem sobrescrever campos conhecidos.
   - `TodoSyncState` (`schema_version`, `paired_room`, `last_phone_seq`, `outbox`, `applied_mutations`, `base_copies`, `extra_fields`, `conflicts`, `quarantine`, `poison_attempts`, `poison_quarantine`, `poison_count`, `pending_pc`, `pending_phone`, `revoked`, `last_synced_at`, `last_error`).
   - `TodoSyncDisplayState` (`synced`, `syncing`, `pendingChanges`, `error`, `revoked`, `savedOnDevice`) e função pura de cálculo que só retorna `synced` quando `paired && !revoked && outbox.isEmpty && pendingPc == 0 && lastError == null && !isSyncing`.
3. Testar serialização/deserialização JSON, preservação de `extra_fields`, normalização de `due` e invariantes de `TodoSyncDisplayState` (comparando também com os exemplos do `CONTRATO-SYNC.md` §8).

---

## Tarefa 4 — Motor de sync, merge 3-vias, quarentena e coalescência (`TodoSyncService`)

**Arquivos:** `lib/data/services/todo_sync_service.dart`, `test/data/services/todo_sync_service_test.dart`

1. Escrever testes cobrindo todo o ciclo antes/durante a implementação:
   - Gravação atômica (`.tmp` + `rename`) em `todo-sync-v1.json`; sem lock durante HTTP.
   - **Coalescência da outbox:** editar 2x ou editar+concluir o mesmo `entity_id` offline gera apenas 1 entrada pendente preservando `base_version` original, atualizando `new_version` e renovando `mutation_id`; edição ocorrida durante `POST` em voo não é removida pela resposta do `mutation_id` anterior.
   - **Idempotência:** `mutation_id` já registrado em `applied_mutations` (cap 1000) não reaplica nem cria duplicata; cursor avança normalmente.
   - **Quarentena de venenosas:** mensagem que falha `open` ou validação 2 vezes trava `uptoSeq` antes dela e preserva `poison_attempts[seq]`; na 3ª falha, move stub sem segredos para `poison_quarantine`, incrementa `poison_count` e inclui `seq` no `ack` para destravar as próximas mensagens.
   - **Quarentena de versão futura:** `contract_version > 1` ou `entity_type != "task"` vai para `quarantine` e avança `ack`.
   - **Merge 3-vias:**
     - conclusão (`done: true`) vence edição concorrente;
     - tombstone (`deletedAt != null`) vence edição, exceto `restore` mais recente (`updatedAt > deletedAt`);
     - `snoozedUntil` maior vence;
     - `subtasks` mescladas por `id`;
     - campos escalares via LWW por `updatedAt` (remoto desempata);
     - `text` alterado em ambos gera conflito `pending_review` mantendo `local.text` até chamada de `resolveTextConflict(keepLocal | useRemote)`.
   - **Troca de sala:** detectar mudança em `sha256(pairing.room)` (`paired_room`), limpar estado antigo e enfileirar snapshot inicial (ativas + tombstones `< 90` dias), limpando tombstones `>= 90` dias.
   - **Erros HTTP:** `410`/`stats.revoked` marca `revoked = true`; `401`/`403`/`429`/`503`/`507`/rede preservam `outbox`.
2. Implementar `TodoSyncService` respeitando a ordem `pull -> apply -> ack -> push -> stats`, protegido por fila/lock de execução única em memória (`_syncInFlight`) e lock local compartilhado com `TodoService` na manipulação dos dois JSONs (`todo-v2.json` e `todo-sync-v1.json`).
3. Rodar `flutter test --no-pub test/data/services/todo_sync_service_test.dart`.

---

## Tarefa 5 — Hooks nos 9 métodos do `TodoService`, recorrência e alarmes

**Arquivos:** `lib/data/services/todo_service.dart`, `test/data/services/todo_service_test.dart`

1. Adicionar em `TodoService` (mantendo o padrão de `_storageLock` e `alarmSynchronizer` já usado pelo serviço):
   - Incremento monotônico de `version` nas mutações locais.
   - Hook configurável/padronizado chamado dentro do `_storageLock` (ou imediatamente após `_write` antes de liberar o lock) em todos os **9 métodos**: `add`, `addFromReport`, `edit`, `setDone` (incluindo a `nextOccurrence` criada localmente!), `remove`, `snooze`, `restore`, `deleteForSession` e `markReportItemStale`.
   - Gatilho assíncrono não bloqueante (`unawaited`) pós-mutação para tentar `TodoSyncService.triggerPushIfPaired(userId)`.
   - Método interno dedicado para aplicar resultados vindos do sync remoto (`applyRemoteDelta` / `withSyncTransaction`) que atualiza `todo-v2.json` **sem** chamar lógica local de `nextOccurrence` ao aplicar `done` remoto, **sem** ecoar mutação fast-forward na outbox e chamando `_requestAlarmSync(userId)` sempre que a lista mudar.
2. Escrever testes em `test/data/services/todo_service_test.dart` verificando:
   - Todos os 9 métodos enfileiram na outbox e incrementam `version` (verificando compatibilidade com testes existentes de `TodoService`).
   - Aplicação de tarefa recorrente com `done: true` vindo do PC conclui a tarefa local e **não** cria nova ocorrência.
   - Aplicação remota aciona `TodoService.alarmSynchronizer`.

---

## Tarefa 6 — Gatilhos de consulta, `Workmanager` (`lumenTodoPeriodicSyncTask`) e roteamento

**Arquivos:** `lib/data/services/todo_sync_scheduler.dart`, `lib/data/services/health_service.dart`, `lib/main.dart`, `lib/data/repositories/todo_repository.dart`, `lib/data/repositories/memex_router.dart`, `test/data/services/todo_sync_scheduler_test.dart`

1. Criar `TodoSyncScheduler` com constante `lumenTodoPeriodicSyncTask = 'lumenTodoPeriodicSyncTask'`, função de registro `Workmanager().registerPeriodicTask(..., frequency: Duration(hours: 1), constraints: Constraints(networkType: NetworkType.connected), existingWorkPolicy: ExistingPeriodicWorkPolicy.keep)` e handler isolado de background.
2. No `callbackDispatcher()` em `lib/data/services/health_service.dart`, tratar `task == lumenTodoPeriodicSyncTask` inicializando o isolate (`DartPluginRegistrant`, `WidgetsFlutterBinding`, `setupLogger()`, `UserStorage.initL10n()`, `UserStorage.getUserId()`, `FileSystemService.init(dataRoot)`) e executando `TodoSyncService().syncForUser(userId)` (que sincroniza também `TodoAlarmService`).
3. Em `lib/main.dart`:
   - Registrar `TodoSyncScheduler.registerPeriodicSync()` após `initWorkmanager` (capturando erros sem travar o startup em testes sem plugin Workmanager).
   - Em `didChangeAppLifecycleState(AppLifecycleState.resumed)`, disparar sync debounced para manter tarefas e alarmes atualizados ao voltar ao app.
4. Em `TodoRepository` e `MemexRouter`, adicionar métodos tipados para ler snapshot de sync (`loadTodoSyncSnapshot`), forçar `syncTodosNow()` e resolver conflitos (`resolveTodoTextConflict`). Garantir degradação segura (estado `savedOnDevice`, sem erro) quando `SecretStorage` não estiver pareado ou em testes unitários sem canal nativo.
5. Testar `TodoSyncScheduler` (roteamento de `task == lumenTodoPeriodicSyncTask` e fallback quando não há `userId`).

---

## Tarefa 7 — `TodoViewModel` e `TodoScreen` (status + conflito `pending_review`)

**Arquivos:** `lib/ui/todo/view_models/todo_viewmodel.dart`, `lib/ui/todo/widgets/todo_screen.dart`, `test/ui/todo/view_models/todo_viewmodel_test.dart`, `test/ui/todo/widgets/todo_screen_test.dart`

1. Atualizar `_FakeRouter` nos testes de `todo_viewmodel_test.dart` e `todo_screen_test.dart` (e quaisquer outros testes de `TodoViewModel`) para implementar `loadTodoSyncSnapshot`, `syncTodosNow` e `resolveTodoTextConflict`.
2. Atualizar `TodoViewModel`:
   - Carregar tarefas locais + snapshot de sync no `load()`, disparando `syncNow()` de forma assíncrona em seguida se pareado (sem esconder as tarefas locais enquanto sincroniza).
   - Expor `syncDisplayState`, `pendingOutboxCount`, `lastSyncedAt`, `conflicts`, `isSyncing`, `syncNow()`, `resolveConflict(entityId, keepLocal: bool)` e atualizar em retorno ao primeiro plano (`refreshOnResume` -> dispara `syncNow()`).
3. Atualizar `TodoScreen`:
   - Na inicialização (`initState`) e no `didChangeAppLifecycleState(AppLifecycleState.resumed)`, acionar o ciclo via `viewModel`.
   - Renderizar faixa discreta de status usando **exclusivamente** `Container`/`Card`/`Row`/`Column`/`TextButton`/`FilledButton` (**nunca `ListTile`**, para preservar o teste de lista vazia sem `ListTile`), com alvos ≥ `48x48dp` e suporte a `textScaleFactor = 2.0`:
     - exibir `"Sincronizado"` (`todoSyncSynced`) **somente** quando `TodoSyncDisplayState.synced` (`paired && !revoked && outbox.isEmpty && pendingPc == 0 && lastError == null`);
     - exibir `"Salvo no aparelho"` (`todoSyncSavedOnDevice`), `"Salvo no aparelho · N pendente(s) de sync"`, `"Salvo no aparelho · erro ao sincronizar"` ou `"Salvo no aparelho · pareamento revogado"` nos demais casos;
     - botão `"Sincronizar agora"` (`todoSyncNowButton`) quando pareado.
   - Renderizar banner de conflitos (`todoConflictBannerTitle`, `todoConflictBannerSubtitle`) com comparação `todoConflictLocalLabel` / `todoConflictRemoteLabel` e botões `todoConflictKeepLocal` e `todoConflictUseRemote`.
4. Rodar testes de `todo_viewmodel_test.dart` e `todo_screen_test.dart` (incluindo acessibilidade, estado vazio e `textScaleFactor = 2.0`).

---

## Tarefa 8 — Verificação final do repositório (F12-04)

1. Se houver qualquer alteração em ARB:
   ```powershell
   flutter gen-l10n
   python3 scripts/check_arb_key_parity.py
   ```
   (Ou apenas `python3 scripts/check_arb_key_parity.py` se nenhuma chave nova foi adicionada.)
2. Rodar suíte automatizada completa dos módulos alterados e regressões:
   ```powershell
   flutter test --no-pub `
     test/data/services/lumen_mailbox_crypto_test.dart `
     test/data/services/lumen_mailbox_client_test.dart `
     test/domain/models/todo_item_sync_contract_test.dart `
     test/domain/models/todo_sync_state_test.dart `
     test/data/services/todo_service_test.dart `
     test/data/services/todo_sync_service_test.dart `
     test/data/services/todo_sync_scheduler_test.dart `
     test/ui/todo/ `
     test/ui/lumen/ `
     test/integration/todo_undo_flow_test.dart
   ```
3. Rodar análise estática:
   ```powershell
   flutter analyze --no-pub
   ```
   > **Nota do Flutter 3.47 neste workspace:** se `flutter` modificar `analysis_options.yaml` ou `android/gradle.properties`, conferir `git diff` e restaurar com `git checkout -- analysis_options.yaml android/gradle.properties` caso não sejam alterações intencionais da tarefa.
4. Confirmar que nenhum dado pessoal, caminho local real de trabalho, subdomínio real ou segredo foi incluído em código, logs ou fixtures (`git diff`).
5. **Validação em hardware real (Samsung S25 ↔ PC Lumen):** permanece **`NOT_RUN`** nesta entrega F12-04; será executada e registrada no **Passo 9 (`F12-05 / L6.4`)** em conjunto com o app Windows.

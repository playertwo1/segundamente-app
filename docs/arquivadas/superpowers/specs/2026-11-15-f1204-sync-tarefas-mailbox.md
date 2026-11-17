# F12-04 — Sync de tarefas via caixa de correio HTTP do relay (Lumen ↔ Segunda Mente)

**Data:** 2026-11-15
**Passo do plano da ponte:** Passo 8 ([`docs/lumen/PONTE.md`](../../lumen/PONTE.md))
**Contrato normativo:** [`docs/lumen/CONTRATO-SYNC.md`](../../lumen/CONTRATO-SYNC.md) (v1)
**Referência de paridade no Lumen:** `coucou/docs/superpowers/specs/2026-11-14-l63-mailbox-tarefas.md`

---

## 1. Objetivo e escopo

Implementar no app Android (**Segunda Mente**) a sincronização offline-first e bidirecional da entidade **`task`** com o **Lumen** (desktop Windows) através da **caixa de correio HTTP do relay Cloudflare Worker** entregue nos Passos 1–7.

### No escopo desta entrega
- Cifra binária `coucou-mailbox/v1` em Dart (`AES-256-GCM` via `pointycastle`), validada por 100% dos vetores em `test/fixtures/lumen_mailbox_test_vectors.json`.
- Cliente HTTP da caixa de correio (`/v1/mailbox/<room>/messages`, `/ack`, `/stats`).
- Formato canônico `SyncEnvelope` v1 (`entity_type: "task"`, `origin_role: "phone"`), normalizando `due == reportDueUnknown` para `""` no envio.
- Estado de sync e outbox persistidos atomicamente em `<workspace>/_<userId>/Todo/todo-sync-v1.json`, com coalescência por `entity_id`, idempotência, cópias-base para merge 3-vias, preservação de `extra_fields`, conflito de texto livre (`pending_review`) e quarentena de envelopes venenosos/incompatíveis.
- Hook nos 9 métodos de mutação local do `TodoService`, aplicação remota sem gerar nova `nextOccurrence` ao receber `done` do PC e ressincronização automática de alarmes locais (`TodoAlarmService`).
- Gatilhos: abertura (`initState`), retorno ao primeiro plano (`AppLifecycleState.resumed`), periódico de 1 hora em segundo plano (`Workmanager` task `lumenTodoPeriodicSyncTask`), pós-mutação local e botão manual `"Sincronizar agora"`.
- UI explícita na `TodoScreen` separando `"Salvo no aparelho"` de `"Sincronizado"`, além de resolução manual de conflito `pending_review` no campo `text`.

### Fora do escopo (etapas seguintes)
- WebSocket ao vivo ou ligação direta LAN TLS (`F12-05 / L6.4`, Passo 9).
- Entidades v1.1 (`note`, `note_comment`, `conversation_turn`, `persona`, `memory_entry`, `preference`).
- Testes E2E em dispositivo físico Android + PC Windows (validação real marcada como Passo 9).

---

## 2. Pré-condições e integração com pareamento existente (F12-03)

O pareamento existente em [`LumenPairingService`](../../../lib/data/services/lumen_pairing_service.dart) armazena em `SecretStorage` (cofre do sistema):
- `LumenPairing`: `httpBaseUrl` (derivado do `relay` em `wss://...` ou `ws://localhost...`), `room` (22 chars base64url = 16 bytes), `access` (43 chars base64url = 32 bytes), `key` (43 chars base64url = 32 bytes).
- `deviceId`: UUID v4 persistente por instalação (`ensureDeviceId()`).

Derivação de chaves já disponível em [`LumenRelayCrypto.deriveFromBase64Url(pairing.key)`](../../../lib/data/services/lumen_relay_crypto.dart):
- `kMailbox`: HKDF-SHA256 (`ikm = K_pair`, `info = "coucou-mailbox/v1"`, 32 bytes).

**Regra de segredos:** `todo-sync-v1.json` nunca grava `key`, `access`, `kMailbox` nem `room` em claro. Guarda apenas `paired_room` = `sha256_hex(room)` para detectar troca ou reset de pareamento sem vazar credenciais no filesystem.

---

## 3. Camada criptográfica (`coucou-mailbox/v1`)

Implementação em `lib/data/services/lumen_mailbox_crypto.dart` usando `GCMBlockCipher(AESEngine())` (`package:pointycastle`), mantendo paridade binária exata com `relay_crypto.rs` do Lumen e `CONTRATO-SYNC.md` §4.

### Constantes do protocolo
- Versão: `0x01`
- Nonce AES-GCM: `12` bytes (CSPRNG `Random.secure()` por envelope selado; nunca reutilizar nonce com a mesma chave)
- Tag AES-GCM: `16` bytes (`macSize: 128` bits no `AEADParameters`)
- Bloco de padding: múltiplo de `128` bytes (mínimo `128` bytes no plaintext preenchido)
- Limite máximo do JSON UTF-8: `65_536` bytes
- Limite máximo do body HTTP cifrado: `66_000` bytes
- Tamanho mínimo do body HTTP cifrado: `157` bytes (`1 + 12 + 128 + 16`)
- Papéis (`LumenMailboxRole`): `pc = 1`, `phone = 2`

### Construção de AAD (41 bytes exatos)
```
AAD = ascii("coucou-mailbox/v1")   // 17 bytes
   || ascii(room)                  // 22 bytes (validado em base64url estrito para 16 bytes)
   || [toByte]                     // 1 byte: 1=pc, 2=phone
   || [0x01]                       // 1 byte: version
```

### Padding e formato do body
1. Serializar payload JSON em UTF-8 (`jsonBytes`). Validar `jsonBytes.length <= 65_536`.
2. Construir `plain = u32be(jsonBytes.length) || jsonBytes || 0x00*`, completando com zeros até o menor múltiplo de `128` bytes (`>= 128` e `>= 4 + jsonBytes.length`).
3. Validar que o envelope cifrado resultante terá `<= 66_000` bytes (`bad_length` caso contrário).
4. Cifrar `plain` com `kMailbox` (32 bytes), `nonce` (12 bytes) e `AAD` (41 bytes), gerando `ciphertext || tag`.
5. Emitir `body = [0x01] || nonce || ciphertext || tag`.

### Abertura (`open`) e códigos de rejeição exatos
Ordem de validação e exceção tipada (`LumenMailboxCryptoException` com `LumenMailboxRejectionCode`):
1. Validar `room` (22 bytes ASCII decodificando estritamente para 16 bytes) -> `invalid_room` (rejeição local de entrada inválida).
2. Validar tamanho e alinhamento antes da decifragem:
   - Se `body.length > 66_000` -> `bad_length` (observação: verificar tamanho máximo antes de decifrar).
   - Se `body.length < 157` ou `(body.length - 29) % 128 != 0` -> `too_short`.
   - Se `body[0] != 0x01` -> `bad_version`.
3. Decifrar `body[13..]` usando `nonce = body[1..13]` e `AAD` com `expectedRole`:
   - Falha de autenticação GCM (`InvalidCipherTextException` / tag inválida) -> `bad_tag`.
4. Validar prefixo `declaredLen = u32be(plain[0..4])`:
   - Se `declaredLen > 65_536` ou `4 + declaredLen > plain.length` -> `bad_length`.
5. Validar preenchimento:
   - Qualquer byte != `0x00` em `plain[4 + declaredLen .. plain.length]` -> `bad_padding`.
6. Decodificar UTF-8 + JSON (`utf8.decode` estrito + `jsonDecode`):
   - UTF-8 malformado ou JSON sintaticamente inválido -> `bad_json`.

**Critério obrigatório:** passar nos 3 `messages` positivos e em todas as 9 entradas `mustRefuse` (`bad_tag`, `bad_version`, `too_short`, `bad_padding`, `bad_length`, `bad_json`) de `test/fixtures/lumen_mailbox_test_vectors.json`.

---

## 4. Cliente HTTP da caixa de correio (`LumenMailboxClient`)

Implementação em `lib/data/services/lumen_mailbox_client.dart` usando `package:http` com timeouts explícitos (ex.: `15s` por requisição), cabeçalho `Authorization: Bearer <access>` e URL base `pairing.httpBaseUrl`.

### Endpoints utilizados (somente escopo F12-04)
1. **Envio (Phone → PC):**
   - `POST /v1/mailbox/<room>/messages?to=pc`
   - Headers: `Authorization: Bearer <access>`, `Content-Type: application/octet-stream`, `X-Lumen-Msg-Id: <mutation_id>`
   - Body: bytes brutos de `seal(...)` (`ver=1 || nonce || ciphertext || tag`)
   - Resposta `200`/`201`: `{ "seq": int, "id": String, "duplicate": bool? }` (idempotente para o mesmo `X-Lumen-Msg-Id`)
2. **Pull (PC → Phone):**
   - `GET /v1/mailbox/<room>/messages?for=phone&after=<seq>&limit=100`
   - Header: `Authorization: Bearer <access>`
   - Resposta `200`: `{ "messages": [{ "seq": int, "id": String?, "createdAt": int, "sizeBytes": int, "payloadB64": String }], "latestSeq": int, "pendingCount": int }` (`payloadB64` em Base64 padrão)
   - Paginação em loop enquanto `messages.length == 100` ou `pendingCount > 0` (com limite de segurança por ciclo para evitar loop infinito caso `seq` não avance).
3. **Confirmação (Ack):**
   - `POST /v1/mailbox/<room>/ack?for=phone`
   - Headers: `Authorization: Bearer <access>`, `Content-Type: application/json`
   - Body: `{"uptoSeq": <int>}`
   - Resposta `200`: `{ "ackedUpto": int, "deleted": int, "remaining": int }`
4. **Estatísticas e estado da sala:**
   - `GET /v1/mailbox/<room>/stats`
   - Header: `Authorization: Bearer <access>`
   - Resposta `200`: `{ "pendingPc": int, "pendingPhone": int, "storedBytes": int, "revoked": bool }`

### Tratamento de erros HTTP
- `410` (ou `stats.revoked == true`): marca `revoked = true` no estado de sync; preserva tarefas locais e outbox; UI exibe `"Salvo no aparelho · pareamento revogado"`.
- `401` / `403`: falha de autenticação/autorização; preserva outbox e registra erro sanitizado (`unauthorized`/`forbidden`) sem apagar dados locais nem vazar `access`/`room` em logs.
- `404`: sala inexistente/expirada ou rota indisponível; preserva outbox e registra erro recuperável.
- `409`: conflito inesperado de ID de mensagem no relay; registra erro sanitizado sem descartar estado local.
- `413`: envelope excede limite do relay; não reenviar em loop infinito — registra erro sanitizado e evita travamento da fila.
- `429` / `503` / `507` / erro de rede / timeout: aborta o restante do ciclo atual preservando a `outbox` intacta para nova tentativa no próximo gatilho.

---

## 5. Contrato do `SyncEnvelope` v1 para `task`

Estrutura JSON dentro do plaintext cifrado (`SyncEnvelope` em `lib/domain/models/todo_sync_state.dart`):

```json
{
  "contract_version": 1,
  "mutation_id": "mut-...",
  "device_id": "<uuid-v4>",
  "origin_role": "phone",
  "entity_type": "task",
  "entity_id": "<task-id>",
  "base_version": 0,
  "new_version": 1,
  "updated_at": "2026-11-15T12:00:00.000Z",
  "payload": { "...": "TodoItem v2 JSON" }
}
```

### Regras de serialização e normalização
- `contract_version`: `1` no envio. Se recebido `contract_version > 1` ou `entity_type != "task"`, mover metadados do envelope para `quarantine` local e confirmar `ack` para não bloquear tarefas válidas.
- `origin_role`: sempre `"phone"` no envio do Android; aceitar `"pc"` na recepção (envelopes inválidos ou de papel inesperado no pull são rejeitados/tratados conforme quarentena).
- `mutation_id`: UUID v4 alfanumérico/hífen (`8..48` chars), também enviado no header `X-Lumen-Msg-Id` e reutilizado em todas as retentativas do mesmo item da outbox.
- `updated_at`: UTC ISO-8601 (`toUtc().toIso8601String()`).
- **Normalização de `due`:**
  - Envio: se `item.due == reportDueUnknown` (`"não informado"`), gravar `"due": ""` em `payload`.
  - Recepção: `TodoItem.fromJson` já converte `""` para `reportDueUnknown` (`"não informado"`).
- **`extra_fields`:** chaves desconhecidas recebidas dentro de `payload` de um `entity_id` são preservadas em `todo-sync-v1.json -> extra_fields[entity_id]` e reincorporadas em envios futuros desse `entity_id` (sem sobrescrever campos conhecidos da v1).

---

## 6. Persistência local (`todo-sync-v1.json`) e ciclo de sincronização

Caminho: `FileSystemService.getTodoSyncFilePath(userId)` -> `<workspace>/_<userId>/Todo/todo-sync-v1.json`.
Gravação sempre atômica via arquivo temporário (`todo-sync-v1.json.tmp`) + `rename`, serializada com `todo-v2.json` sob lock local. **Nunca segurar lock de arquivo durante chamadas HTTP.**

### Campos de `todo-sync-v1.json` (`schema_version: 1`)
- `schema_version`: `1`
- `paired_room`: SHA-256 hex de `pairing.room` (nunca o valor bruto).
- `last_phone_seq`: `int` (maior `seq` contíguo confirmado para `for=phone`).
- `outbox`: lista FIFO de entradas pendentes:
  - `entity_id`, `mutation_id`, `base_version`, `new_version`, `updated_at`, `enqueued_at`.
  - **Coalescência por `entity_id`:** se já existe entrada para `entity_id` na outbox quando ocorre nova mutação local, mantém-se o `base_version` inicial do lote não enviado, atualiza-se `new_version`, `updated_at` e gera-se novo `mutation_id`. Se a entrada original estava sendo enviada em paralelo por HTTP no momento da nova mutação, a resposta HTTP da versão antiga não deve apagar a versão mais nova da outbox (comparação por `mutation_id`).
- `applied_mutations`: lista FIFO limitada (máx. `1000` entradas) de `{ mutation_id, entity_id, base_version, new_version, applied_at }` para idempotência.
- `base_copies`: mapa `entity_id -> payload JSON` do último estado comum sincronizado.
- `extra_fields`: mapa `entity_id -> Map<String, dynamic>` com chaves desconhecidas preservadas.
- `conflicts`: mapa `entity_id -> { entity_id, base_text, local_text, remote_text, detected_at, status }` (`status: "pending_review"`).
- `quarantine`: lista limitada de metadados de envelopes com `contract_version > 1` ou `entity_type != "task"` (sem conteúdo textual).
- `poison_attempts`: mapa `seq -> int` (contagem de falhas consecutivas de decifragem/validação por `seq`).
- `poison_quarantine` (e `poison_count`): lista limitada de registros `{ seq, reason_code, failed_at }` (sem payload/segredos) quando `attempts >= 3`.
- `pending_pc`, `pending_phone`, `revoked`, `last_synced_at`, `last_error`.

### Regra de quarentena de mensagens venenosas (3 falhas)
Ao processar mensagens recebidas em `GET /messages?for=phone`:
- Se uma mensagem `seq` falhar na decifragem (`bad_tag`, `bad_version`, `too_short`, `bad_padding`, `bad_length`, `bad_json`) ou na validação estrutural de `SyncEnvelope`:
  - Incrementar `poison_attempts[seq]`.
  - **Enquanto `attempts < 3`:** não incluir `seq` nem sequências posteriores no `uptoSeq` do `POST /ack` (interromper avanço do cursor contíguo antes de `seq`), permitindo retentativa nas próximas rodadas caso seja erro transitório; registrar `last_error`.
  - **Ao atingir `attempts >= 3`:** mover metadados (`seq`, `reason_code`, timestamp — nunca payload nem chaves) para `poison_quarantine`, remover `poison_attempts[seq]` e liberar o avanço do cursor `uptoSeq` incluindo `seq` no `POST /ack`, evitando travamento permanente da caixa de correio.

### Ordem do ciclo (`TodoSyncService.syncNow()`)
Protegido por mutex de ciclo único (`_syncInFlight`) para evitar corridas entre lifecycle, botão manual, pós-mutação e Workmanager no mesmo processo:
1. Carregar pareamento + `deviceId` (`LumenPairingService`). Se não pareado, retornar estado local (`savedOnDevice`) sem rede.
2. Sob lock local: ler `todo-sync-v1.json` e `todo-v2.json`. Se `paired_room` mudou (novo pareamento), resetar estado anterior de sync para a sala antiga e enfileirar snapshot inicial de todas as tarefas ativas e tombstones `< 90` dias (`base_version: 0`, `new_version: item.version`). Limpar também tombstones `>= 90` dias e seus `base_copies`/`extra_fields`.
3. **Pull** (sem lock de arquivo): paginar `GET /v1/mailbox/<room>/messages?for=phone&after=<last_phone_seq>&limit=100`.
4. **Apply** (sob lock local, se houver mensagens):
   - Para cada mensagem em ordem de `seq`: validar/decifrar; tratar venenosas (regra das 3 falhas) e versões futuras (`quarantine`); checar idempotência por `mutation_id`; executar merge 3-vias (seção 7); gravar `todo-v2.json` via caminho interno do `TodoService` **sem** gerar nova `nextOccurrence` e **sem** re-enfileirar na outbox quando convergiu para o remoto (enfileira apenas se o merge 3-vias combinou mudanças locais e remotas produzindo novo estado divergente do envelope remoto).
   - Se `todo-v2.json` mudou, acionar ressincronização local de alarmes (`TodoAlarmService.instance.synchronize`).
5. **Ack + persistência** (fora do lock para rede, depois lock curto para gravar): se `contiguousAckSeq > last_phone_seq`, chamar `POST /ack?for=phone` com `{"uptoSeq": contiguousAckSeq}` e persistir novo `last_phone_seq`.
6. **Push** (FIFO da outbox, sem lock de arquivo): para cada entrada na outbox, montar `SyncEnvelope` atual a partir do `TodoItem` (ou payload capturado na entrada caso o arquivo ainda esteja atualizado, sempre normalizando `due == reportDueUnknown -> ""` e mesclando `extra_fields`), cifrar com `to = pc`, enviar via `POST /messages?to=pc` com `X-Lumen-Msg-Id: mutation_id`. Em `200`/`201`, remover da outbox sob lock local **somente se o `mutation_id` da entrada ainda for o mesmo** (não coalescido durante o voo) e atualizar `base_copies[entity_id]`.
7. **Stats:** chamar `GET /v1/mailbox/<room>/stats`, atualizar `pending_pc`, `pending_phone`, `revoked` e, se todo o ciclo concluiu sem erro nem `revoked`, atualizar `last_synced_at` (limpando `last_error`).

---

## 7. Reconciliação 3-vias e regras por campo

Comparação entre `local` (estado atual em `todo-v2.json`), `base` (`base_copies[entity_id]`, pode ser `null`) e `remote` (do envelope recebido):

1. Se `local == null`: cria/aplica `remote` (se não for tombstone com `>= 90` dias), grava `base_copies[entity_id]`.
2. Se `local` tem mesmo conteúdo funcional que `remote` (ignorando `version` e `schemaVersion`): mantém convergência sem conflito, atualiza `base_copies[entity_id]` e versão (`max(local.version, remote.version)`).
3. Caso contrário (`base == null` ou divergência entre `local`, `base` e `remote`):
   - **Só um lado mudou em relação a `base`** (no campo): vence o lado que mudou.
   - **Ambos mudaram o mesmo campo (ou `base == null` e diferem):**
     - `text`: **conflito manual (`pending_review`)**. Mantém `local.text` na tarefa até decisão do usuário e grava/atualiza `conflicts[entity_id]` (`base_text`, `local_text`, `remote_text`, `status: "pending_review"`).
     - `done` / `completedAt`: conclusão (`done == true`) vence sobre edição concorrente (`done == false`). Quando ambos são `true`, preserva o `completedAt` mais recente ou válido.
     - `deletedAt`: exclusão (`deletedAt != null`) vence edição concorrente. Restauração explícita local/remota (`deletedAt == null` com `updatedAt > deletedAt`) vence exclusão mais antiga.
     - `snoozedUntil`: vence o timestamp mais tardio (`max`).
     - `subtasks`: merge por `subtask.id` — inclusões de ambos os lados são preservadas na ordem combinada; remoção vence só se o outro lado não editou aquela subtarefa; em `subtask.done`, `true` vence; em `subtask.text`, LWW por `updatedAt` (ou remoto no empate).
     - Demais campos (`due`, `dueDate`, `dueTime`, `timeZone`, `alertMinutes`, `priority`, `recurrence`, `source`): **LWW por `updatedAt`** (desempate a favor do `remote` para garantir determinismo simétrico entre Android e PC).
   - `version`: se resultado == `remote` (sem alterações locais remanescentes), adota `max(local.version, remote.version)`; se houve combinação de alterações dos dois lados, incrementa `version = max(local.version, remote.version) + 1` e enfileira na outbox para o PC convergir.

---

## 8. Hooks no `TodoService`, alarmes e recorrência

Todos os **9 métodos públicos de mutação local** do [`TodoService`](../../../lib/data/services/todo_service.dart) devem registrar atomicamente a mutação na `outbox` de `todo-sync-v1.json` (e incrementar `item.version`), além de disparar sync assíncrono não bloqueante:
1. `add`
2. `addFromReport`
3. `edit`
4. `setDone` (mantém criação local da `nextOccurrence` apenas nas chamadas locais; a `nextOccurrence` criada também entra na outbox como novo `task` independente!)
5. `remove` (tombstone `deletedAt`)
6. `snooze`
7. `restore`
8. `deleteForSession` (chamado em `ChatRepository`)
9. `markReportItemStale` (chamado em `SessionReportService`)

**Regra crítica de recorrência remota:** ao aplicar um envelope vindo do PC onde `done == true` em uma tarefa recorrente, **nunca** gerar outra `nextOccurrence` no Android. O dispositivo onde o usuário concluiu é o único autor da nova ocorrência e a envia como outra tarefa no sync.

**Regra crítica de alarmes:** toda alteração vinda do PC que crie, edite prazo/alerta, adie (`snooze`), conclua (`done`) ou exclua (`deletedAt`) tarefas deve disparar `_requestAlarmSync(userId)` (`TodoAlarmService.instance.synchronize`), inclusive quando o sync rodar em background via `Workmanager`.

---

## 9. Gatilhos de consulta e execução em background

1. **Abertura da tela / app (`initState`):** `TodoScreen.initState` dispara carregamento local imediato + `syncNow()` em paralelo sem bloquear a renderização offline.
2. **Retorno ao primeiro plano (`AppLifecycleState.resumed`):**
   - `TodoScreen.didChangeAppLifecycleState` aciona `viewModel.syncIfPaired()` ao retornar para `resumed`.
   - O observador global do ciclo de vida do app (`lib/main.dart`) também agenda `syncNow()` (com debounce curto, ex. 15s, se não houver outbox pendente) quando o app volta ao primeiro plano, mantendo alarmes atualizados mesmo sem abrir a aba de tarefas.
3. **Background a cada 1 hora (`Workmanager`):**
   - Registrar tarefa periódica única na inicialização (`main.dart` / `TodoSyncScheduler`):
     - `uniqueName`: `'lumenTodoPeriodicSyncTask'`
     - `taskName`: `'lumenTodoPeriodicSyncTask'`
     - `frequency`: `const Duration(hours: 1)`
     - `constraints`: `Constraints(networkType: NetworkType.connected)`
     - `existingWorkPolicy`: `ExistingPeriodicWorkPolicy.keep`
   - Tratar `task == 'lumenTodoPeriodicSyncTask'` dentro de `callbackDispatcher()` em `lib/data/services/health_service.dart`, inicializando binding, logger, l10n, `UserStorage` e `FileSystemService.init(dataRoot)` antes de executar `TodoSyncService().syncNow()`.
4. **Após mutações locais:** ao final de qualquer um dos 9 métodos do `TodoService`, disparar callback assíncrono não bloqueante (`unawaited`) se pareado.
5. **Botão manual `"Sincronizar agora"` (`todoSyncNowButton`):** na `TodoScreen`, força ciclo imediato ignorando debounce.

---

## 10. UI (`TodoScreen` e `TodoViewModel`)

### Separação estrita `"Salvo no aparelho"` vs `"Sincronizado"`
Mapeamento determinístico de exibição usando as chaves já existentes em `lib/l10n/app_pt.arb` e `app_en.arb`:
- **`"Sincronizado"` (`todoSyncSynced`):** exibido **somente** quando **todas** as condições forem verdadeiras:
  1. `paired == true`
  2. `revoked == false`
  3. `outbox.isEmpty` (`pendingOutboxCount == 0`)
  4. `pendingPc == 0`
  5. `lastError == null`
- **`"Sincronizando…"` (`todoSyncSyncing`):** enquanto ciclo HTTP ativo estiver rodando.
- **`"Salvo no aparelho · pareamento revogado"` (`todoSyncRevoked`):** quando `revoked == true`.
- **`"Salvo no aparelho · erro ao sincronizar"` (`todoSyncError`):** quando `lastError != null`.
- **`"Salvo no aparelho · N pendente(s) de sync"` (`todoSyncPendingChanges`):** quando `pendingOutboxCount > 0` (e não há erro/revogação).
- **`"Salvo no aparelho"` (`todoSyncSavedOnDevice`):** quando não pareado, ou quando `paired && outbox.isEmpty && pendingPc > 0` (ainda aguardando entrega/leitura ou primeiro sync confirmado).
- Exibir `todoSyncLastSuccess(time)` quando `lastSyncedAt != null`, além do botão `"Sincronizar agora"` (`todoSyncNowButton`) sempre que pareado (e sem conflito de toque com `48x48dp`).

### Resolução manual de conflitos (`pending_review`)
- Quando `conflicts` contiver entradas `pending_review`, exibir banner destacado na `TodoScreen` com `todoConflictBannerTitle` e `todoConflictBannerSubtitle`, mostrando para cada conflito:
  - texto da tarefa local (`todoConflictLocalLabel`) vs texto recebido do PC (`todoConflictRemoteLabel`)
  - botões explícitos `todoConflictKeepLocal` e `todoConflictUseRemote` (alvos mínimos `48x48dp`).
- **Ação `keepLocal`:** mantém `item.text`, remove o conflito de `todo-sync-v1.json`, atualiza `baseCopy` para que não reapareça para o mesmo `remoteText` e grava entrada na outbox (incrementando `version`) para alinhar o PC.
- **Ação `useRemote`:** substitui `item.text` por `remoteText` (incrementando `version` e acionando alarm sync se necessário), remove o conflito, atualiza `baseCopy` e enfileira convergência para manter os dois lados idênticos.

### Restrição estrutural obrigatória de layout
**Não usar `ListTile`** nos banners/barras de status de sincronização nem nos cards de conflito da `TodoScreen`, pois `test/ui/todo/widgets/todo_screen_test.dart` valida que o estado vazio não renderiza nenhum `ListTile`. Usar `Container`/`Card`/`Row`/`Column`/`FilledButton`/`TextButton` com suporte completo a `textScaleFactor = 2.0`.

---

## 11. Critérios de verificação da F12-04

1. `LumenMailboxCrypto` passa em 100% dos vetores em `test/fixtures/lumen_mailbox_test_vectors.json` (3 envelopes válidos + 9 rejeições exatas) e valida `invalid_room`.
2. `LumenMailboxClient` testado com mock HTTP cobrindo headers (`Authorization`, `X-Lumen-Msg-Id`), query params, parsing camelCase, paginação e mapeamento de erros (`401/403/404/409/410/413/429/503/507`).
3. Testes de ciclo completo em `TodoSyncService`: outbox atômica, coalescência mantendo `base_version`, idempotência via `applied_mutations`, `extra_fields`, `due` (`reportDueUnknown` ↔ `""`), merge 3-vias campo a campo, conflitos `pending_review` e quarentena de venenosas após 3 falhas (travando `uptoSeq` nas tentativas 1–2 e liberando na 3ª).
4. Testes dos 9 hooks no `TodoService`, garantindo ausência de `nextOccurrence` em conclusão remota e disparo do `alarmSynchronizer` após aplicação remota.
5. Testes do worker `lumenTodoPeriodicSyncTask` e da UI (`TodoViewModel` + `TodoScreen`, incluindo estado `"Salvo no aparelho"` vs `"Sincronizado"`, conflitos, acessibilidade `48x48dp` e escala `2.0x`).
6. `check_arb_key_parity.py`, `flutter analyze --no-pub` e `flutter test --no-pub` verdes nos módulos afetados e regressões de Todo/Lumen.
7. Validação em aparelho real (S25 + Windows) permanece **pendente do Passo 9** (`NOT_RUN` até conclusão da integração ponta a ponta).

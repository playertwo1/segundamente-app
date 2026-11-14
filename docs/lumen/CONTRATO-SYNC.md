# Contrato de Sync — Segunda Mente ↔ Lumen (`F12-01`)

**Estado:** Rascunho para revisão do proprietário (`F12-01`, `D-054`, `L6`).  
**Escopo:** Formato de envelopes, transporte, criptografia, entidades, idempotência, tombstones e resolução de conflitos entre o app Android (**Segunda Mente**) e o desktop (**Lumen**).  
**Regra de ouro:** Tudo neste arquivo usa apenas exemplos sintéticos. Segredos, dados pessoais ou dados de clientes nunca entram em código, logs ou payloads do relay.

---

## 1. Princípios

1. **Offline-first nos dois lados:** Android (Flutter/Drift) e Lumen (Rust/JSON/local store) mantêm seus próprios bancos locais e gravam imediatamente toda alteração do usuário como mutação em outbox local antes de tentar enviar.
2. **Separação explícita de estado na interface:**
   - `"salvo neste PC"` / `"salvo no aparelho"` = gravado no disco local + enfileirado na outbox;
   - `"sincronizado"` = confirmado (`ACK` ou aplicação direta no canal LAN/WebSocket) pelo par.
3. **Nuvem cega (Zero Knowledge do conteúdo):** O Worker do Cloudflare (`android/relay/`) encaminha e armazena apenas blocos opacos cifrados ponta a ponta (**E2EE**). Não guarda chaves de conteúdo (`K`), tokens de usuário ou texto claro, e mantém observabilidade desligada.
4. **Caminho rápido + caixa persistente:** Quando os dois aparelhos estão na mesma rede ou conectados ao vivo (`docs/ANDROID_LINK.md` e `docs/RELAY_LINK.md`), entregam direto; quando um par está desligado ou offline, a caixa de correio persistente no Worker (`Room` Durable Object com SQLite) guarda o envelope cifrado até o destinatário buscar e confirmar (`ACK`).
5. **Conflito de texto nunca é apagado em silêncio:** Estados determinísticos mesclam com segurança; textos livres concorrentes viram conflito explícito com as duas versões preservadas.

---

## 2. Identidade, Pareamento e Revogação

Reaproveita o link de pareamento do Coucou (`docs/ANDROID_LINK.md`, `docs/RELAY_LINK.md`):

- `room`: 16 bytes aleatórios (22 caracteres base64url), identifica a sala no relay.
- `K`: 32 bytes aleatórios (43 caracteres base64url), segredo compartilhado apenas entre PC e celular.
- `ACCESS_KEY`: segredo de implantação do Worker (protege a cota do plano Free; não abre conteúdo).
- Derivação HKDF-SHA-256 com `LABEL = "coucou-relay/v1"`:
  - `K_join    = HKDF(K, "", LABEL + " join",    32)` — autentica o vínculo da sala/mailbox (`Sec-WebSocket-Protocol` ou header `X-Lumen-Join`); o relay armazena apenas `SHA-256(K_join)`.
  - `K_auth    = HKDF(K, "", LABEL + " auth",    32)` — autentica handshake live WebSocket (`RELAY_LINK.md`).
  - `K_mailbox = HKDF(K, "", LABEL + " mailbox", 32)` — chave simétrica **E2EE para envelopes persistidos na caixa de correio offline** (AES-256-GCM, 1 nonce aleatório de 12 bytes por envelope, sem reutilização de sessão WebSocket).

### Revogação (`DeviceRevoked`)

- Cada aparelho possui um `device_id` UUID v4 estável gerado na instalação e registrado no pareamento (`platform`: `"android"` | `"windows"`).
- **Revogar vínculo ("Parear de novo"):**
  1. O aparelho que revoga chama `POST /v1/mailbox/<room>/revoke` (autenticado com `ACCESS_KEY` + `X-Lumen-Join`).
  2. O Durable Object apaga todas as mensagens pendentes daquela sala, grava estado `revoked = 1` em SQLite e fecha WebSockets abertos da sala (`1008`). Qualquer tentativa posterior com `room`/`K` antigos recebe `410 Gone`.
  3. Localmente, o aparelho gera novos `room`, `K` e token TLS para o próximo QR code.

---

## 3. Formato Criptográfico da Caixa de Correio (`coucou-mailbox/v1`)

Para armazenamento seguro no SQLite do Durable Object (sem sessão WebSocket prévia):

- **Binário enviado em `POST /v1/mailbox/<room>/messages?to=<pc|phone>`** (máximo `65.536` bytes por bloco; máximo de transporte `66.000` bytes):
  ```
  ver (1 byte = 1) ‖ nonce (12 bytes aleatórios CSPRNG) ‖ AES-256-GCM(key=K_mailbox, nonce, aad, plaintext_padded)
  ```
- **AAD:** `"coucou-mailbox/v1" ‖ room (22 ASCII) ‖ target_role ("pc"|"phone") ‖ ver (1)`
- **Plaintext:** JSON UTF-8 do `SyncEnvelope` com padding com zeros até múltiplo de 128 bytes (`u32 big-endian length ‖ json_bytes ‖ zero_padding`, exatamente no mesmo esquema de padding do `coucou-relay/v1` para ocultar tamanho exato).
- **Cabeçalho HTTP opcional `X-Lumen-Msg-Id`:** igual ao `mutation_id` (ASCII `[A-Za-z0-9_-]{8,64}`) para deduplicação idempotente no relay em caso de reenvio após queda de rede. O relay nunca lê o conteúdo interno.

---

## 4. Envelope de Sincronização (`SyncEnvelope`)

Todo evento que sai na outbox (via LAN, WebSocket live ou caixa de correio) usa o mesmo JSON:

```json
{
  "contract_version": 1,
  "mutation_id": "mut-01j9z8x7w6v5u4t3",
  "device_id": "dev-pc-exemplo-01",
  "origin_role": "pc",
  "entity_type": "task",
  "entity_id": "task-exemplo-001",
  "op": "upsert",
  "base_version": 0,
  "new_version": 1,
  "updated_at": "2026-11-14T15:00:00Z",
  "payload": {}
}
```

Regras:
- `mutation_id`, `entity_id`, `persona_id` e `note_id` **nunca são regenerados no destino**.
- **Aplicação idempotente:** o receptor registra cada `mutation_id` aplicado na tabela/índice local `applied_mutations(mutation_id, applied_at)`. Replay do mesmo `mutation_id` é ignorado com sucesso (`ACK` mantido, sem duplicar efeitos nem comentários nem notificações).
- **Exclusão (`op: "delete"`):** grava `deleted_at` UTC e mantém tombstone por no mínimo 90 dias. Um aparelho que ficou offline e manda `upsert` de uma versão anterior a uma exclusão não ressuscita o item (salvo se houver reabertura explícita posterior com `new_version` maior).
- **`ACK` só após commit local:** um lote recebido da caixa de correio só envia `POST /v1/mailbox/<room>/ack?for=<role>` com `{ "uptoSeq": N }` depois de gravado de forma atômica no banco local do receptor.

---

## 5. Entidades do Escopo (`L6.4` / `D-054`) e Regras de Conflito

Política geral escolhida pelo proprietário (**A3**):
- **Estados estruturados seguros:** mesclagem determinística automática (ex.: `done`/`done_at`, `snoozed_until`, `recurrence` após desempate por versão/`updated_at`, `deleted_at` tombstone e anexação de itens deduplicáveis por UUID).
- **Texto livre concorrente:** quando os dois aparelhos editam off-line a partir da mesma `base_version` campos de texto livre (`task.text`, `note.title`, `note.summary`, `note.lines`, `persona.*`, `memory_node.summary`), **não** sobrescrever em silêncio: preservar a versão local e guardar a versão remota num registro/cópia de conflito visível (`conflict_state: "pending_review"`) para escolha do usuário.

### 5.1 `task` (Paridade F11 ↔ L4 `todo.json` v2)

Campos em `snake_case` alinhados com `lib/domain/models/todo_item.dart` e `windows/src-tauri/src/tasks/model.rs`:

- `id`, `text`, `due`, `due_date` (`YYYY-MM-DD | null`), `due_time` (`HH:MM | null`), `time_zone` (padrão `"America/Sao_Paulo"`), `alert_minutes` (padrão `20`), `priority` (`"low"|"normal"|"high"|"urgent"`), `subtasks` (`[{id, text, done}]`), `recurrence` (`{frequency, weekdays?, day_of_month?} | null`), `series_id`, `done`, `created_at`, `done_at`, `snoozed_until`, `source` (`{session_id, item_id, excerpt, clock?} | null`), `source_stale`, `version`, `deleted_at`.
- **Avisos entre aparelhos (`D19` / `L6.4`):**
  - Ao receber `done: true` ou novo `snoozed_until` ou `deleted_at != null` para uma tarefa, o receptor **cancela imediatamente** qualquer alarme/Toast agendado ou exibido para aquela ocorrência no aparelho local.
  - Tarefa recorrente concluída gera a próxima ocorrência de forma determinística na origem e envia a atualização/nova ocorrência com seus próprios `id`/`mutation_id` (sem duplicar ocorrências se a mutação repetir).
  - Conflito: alteração concorrente só em `done` / `snoozed_until` / `subtasks[].done` (merge por UUID de subtarefa) resolve automaticamente pelo timestamp mais recente; divergência simultânea em `text` cria revisão visível mantendo o texto original e a variante remota até escolha do dono.

### 5.2 `note` (Anotador / Notas)

- `id`, `title`, `title_edited`, `start` (epoch ms), `end` (epoch ms | null), `app` (`string | null`), `status` (`"ready"|"recording"|"processing"|"failed"`), `speakers` (`[{id, name, color, isMe}]`), `lines` (`[{id, speaker, start, end, text}]`), `summary` (`string | null`), `key_points` (`string[]`), `todos` (`[{id, text, owner?, due?, done}]`), `start_local`, `updated_at`, `version`, `deleted_at`.
- Notas criadas em estado `"recording"` ou `"processing"` **não** entram na outbox de sync até atingirem `"ready"`.
- Conflito: edição simultânea em `title`, `summary` ou `lines` a partir da mesma `base_version` gera entrada explícita de conflito com as duas variantes (`local` e `remote`), nunca descarte silencioso.

### 5.3 `note_comment` (Comentários de Personas e Respostas)

- `id`, `note_id`, `character_id`, `character_name`, `author_kind` (`"persona" | "user"`), `content`, `reply_to_id`, `created_at` (epoch ms), `idempotency_key`, `comment_hash`.
- **Regra D18 (sem duplicação):** apenas o aparelho criador da nota dispara geração automática inicial de comentários de persona. Ao receber uma nota via sync, o par **nunca** chama o LLM automaticamente para gerar os mesmos comentários; apenas exibe e permite menções explícitas (`@persona`) ou novas respostas criadas pelo usuário (com seu próprio `mutation_id` e `idempotency_key`).
- Deduplicação no destino por `(note_id, id)` e `(note_id, idempotency_key)`.

### 5.4 `conversation_turn` (Conversas com Personas)

- `id`, `thread_id`, `character_id`, `sender` (`"user" | "persona"`), `message_type` (`"chat" | "emoji" | "action"`), `content`, `created_at` (ISO-8601 UTC), `idempotency_key`, `version`, `deleted_at`.
- Modelo append-only ordenado por `(created_at, id)` e deduplicado por `id` / `idempotency_key`. Edição concorrente de uma mesma mensagem preservada como conflito visível.

### 5.5 `persona` (`CharacterModel` + 3 partes Lumen)

- `id`, `name`, `role`, `identity`, `user_profile`, `rules`, `persona`, `system_prompt_override`, `post_history_instructions`, `mes_example`, `tags`, `interest_filter`, `avatar`, `first_message`, `is_primary_companion`, `enabled`, `color`, `updated_at`, `version`, `deleted_at`.
- `avatar` referencia o identificador/nome canônico de asset (ex.: `"advogado_diabo.png"`) quando built-in; nunca trafega binário pesado fora do limite de 64 KiB no envelope de metadata.
- Divergência simultânea em `identity`/`user_profile`/`rules`/`persona` gera conflito explícito; flags `enabled` e `is_primary_companion` mesclam pela versão/timestamp mais recente.

### 5.6 `preference` (`PreferenceConfirmed`)

- `id`, `key` (ex.: `"todo.shortcuts"`, `"comment.settings"`, `"assistant.quiet_hours"`), `value` (objeto JSON tipado), `scope` (`"shared"` — preferências exclusivas da máquina local como caminho de pasta ou chave OAuth nunca usam `scope: "shared"`), `confirmed_at`, `revised_at`, `version`, `deleted_at`.
- Merge por campo conhecido quando aplicável ou última revisão confirmada (`revised_at`).

### 5.7 `memory_node` (Memória Resumida — 4 ações `QwenPaw`)

Cada conclusão durável da memória resumida compartilha um nó versionado (`action` ∈ `criar | corroborar | refinar | corrigir`) em vez de empilhar notas repetidas:

- `id`, `character_id` (`string | null`, nulo quando memória global do usuário), `topic_key` (slug estável opcional), `action` (`"criar" | "corroborar" | "refinar" | "corrigir"`), `summary`, `confidence` (`0.0..1.0`), `evidence_count` (`int >= 1`), `evidence_refs` (`string[]` de `note_id`/`turn_id`), `source_device`, `created_at`, `updated_at`, `version`, `deleted_at`.
- Semântica das 4 ações:
  - `criar`: cria novo nó (`base_version = 0`, `new_version = 1`).
  - `corroborar`: mantém `summary` atual, incrementa `evidence_count` / `evidence_refs` e reforça `confidence`.
  - `refinar`: amplia/esclarece `summary` a partir de `base_version`.
  - `corrigir`: substitui conclusão equivocada preservando histórico/revisão; se outro aparelho também editou/corrigiu concorrentemente desde a mesma `base_version`, marca conflito visível entre as duas conclusões para revisão.

---

## 6. Orçamento no Plano Free do Cloudflare (`L6.1` / `D-054`)

Limites publicados do plano Free do Cloudflare Workers + Durable Objects (SQLite):
- **Workers Requests:** `100.000` requisições HTTP/WebSocket por dia UTC (mensagens WebSocket recebidas contam como fração menor).
- **Durable Object SQLite Writes:** `100.000` gravações em disco por dia UTC.
- **Armazenamento SQLite:** `5 GB` totais por conta.
- **Estouro:** o Cloudflare bloqueia até `00:00 UTC` sem cobrar nada.

Orçamento alvo por envelope no fluxo mailbox (`/v1/mailbox/<room>/*`):
- Enfileirar 1 mensagem (`POST /messages`): `1` req Worker + até `2` gravações SQL (insert da mensagem + incremento do contador diário em batch ou upsert único na mesma transação DO).
- Buscar pendentes (`GET /messages`): `1` req Worker + `0` gravações SQL (leitura pura).
- Confirmar lote (`POST /ack`): `1` req Worker + `1` gravação SQL (remove `1..N` mensagens até `uptoSeq` de uma vez).
- Com **100 mensagens/dia** sincronizadas offline em lotes, o uso estimado fica abaixo de **300 reqs** e **250 gravações SQL/dia** (**< 0,3%** dos limites diários do plano Free).
- Salvaguardas obrigatórias no Worker: teto por sala (`16 MiB`, `500` mensagens pendentes por destinatário) e descarte de entradas com mais de `30 dias`.

---

## 7. Exemplos JSON Sintéticos para Validação Cruzada

Todos os identificadores e conteúdos abaixo são estritamente fictícios:

### 7.1 Tarefa criada offline no PC + conclusão no celular cancelando aviso

```json
{
  "contract_version": 1,
  "mutation_id": "mut-syn-task-001",
  "device_id": "dev-syn-pc-01",
  "origin_role": "pc",
  "entity_type": "task",
  "entity_id": "task-syn-001",
  "op": "upsert",
  "base_version": 0,
  "new_version": 1,
  "updated_at": "2026-11-14T11:30:00Z",
  "payload": {
    "id": "task-syn-001",
    "text": "Revisar pauta da reunião semanal",
    "due": "2026-11-15 09:00",
    "due_date": "2026-11-15",
    "due_time": "09:00",
    "time_zone": "America/Sao_Paulo",
    "alert_minutes": 20,
    "priority": "high",
    "subtasks": [
      { "id": "sub-syn-1", "text": "Separar tópicos", "done": false }
    ],
    "recurrence": null,
    "series_id": null,
    "done": false,
    "created_at": "2026-11-14T11:30:00Z",
    "done_at": null,
    "snoozed_until": null,
    "source": null,
    "source_stale": false,
    "version": 1,
    "deleted_at": null
  }
}
```

Conclusão pelo celular (cancela Toast/alarme no PC):

```json
{
  "contract_version": 1,
  "mutation_id": "mut-syn-task-002",
  "device_id": "dev-syn-phone-01",
  "origin_role": "phone",
  "entity_type": "task",
  "entity_id": "task-syn-001",
  "op": "upsert",
  "base_version": 1,
  "new_version": 2,
  "updated_at": "2026-11-15T08:45:00Z",
  "payload": {
    "id": "task-syn-001",
    "text": "Revisar pauta da reunião semanal",
    "due": "2026-11-15 09:00",
    "due_date": "2026-11-15",
    "due_time": "09:00",
    "time_zone": "America/Sao_Paulo",
    "alert_minutes": 20,
    "priority": "high",
    "subtasks": [
      { "id": "sub-syn-1", "text": "Separar tópicos", "done": true }
    ],
    "recurrence": null,
    "series_id": null,
    "done": true,
    "created_at": "2026-11-14T11:30:00Z",
    "done_at": "2026-11-15T08:45:00Z",
    "snoozed_until": null,
    "source": null,
    "source_stale": false,
    "version": 2,
    "deleted_at": null
  }
}
```

### 7.2 Nota do Anotador + Comentário sem duplicação

```json
{
  "contract_version": 1,
  "mutation_id": "mut-syn-comment-001",
  "device_id": "dev-syn-pc-01",
  "origin_role": "pc",
  "entity_type": "note_comment",
  "entity_id": "cmt-syn-001",
  "op": "upsert",
  "base_version": 0,
  "new_version": 1,
  "updated_at": "2026-11-14T14:05:00Z",
  "payload": {
    "id": "cmt-syn-001",
    "note_id": "note-syn-001",
    "character_id": "gerente_escopo",
    "character_name": "Gerente de Escopo",
    "author_kind": "persona",
    "content": "Vale quebrar essa entrega em duas metas menores antes da sexta.",
    "reply_to_id": null,
    "created_at": 1794665100000,
    "idempotency_key": "note-syn-001:gerente_escopo:1",
    "comment_hash": "a1b2c3d4e5f60708"
  }
}
```

### 7.3 Memória resumida (`corroborar` / `corrigir`)

```json
{
  "contract_version": 1,
  "mutation_id": "mut-syn-mem-001",
  "device_id": "dev-syn-phone-01",
  "origin_role": "phone",
  "entity_type": "memory_node",
  "entity_id": "mem-syn-pref-horario",
  "op": "upsert",
  "base_version": 1,
  "new_version": 2,
  "updated_at": "2026-11-14T16:10:00Z",
  "payload": {
    "id": "mem-syn-pref-horario",
    "character_id": null,
    "topic_key": "janela_foco_manha",
    "action": "corrigir",
    "summary": "Prefere blocos de concentração profunda entre 9h e 11h, evitando reuniões nesse horário.",
    "confidence": 0.92,
    "evidence_count": 3,
    "evidence_refs": ["note-syn-001", "note-syn-004", "turn-syn-012"],
    "source_device": "dev-syn-phone-01",
    "created_at": "2026-11-10T12:00:00Z",
    "updated_at": "2026-11-14T16:10:00Z",
    "version": 2,
    "deleted_at": null
  }
}
```

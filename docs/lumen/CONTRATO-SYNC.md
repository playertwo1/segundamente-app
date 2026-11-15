# Contrato de Sync — Segunda Mente ↔ Lumen (`F12-01`)

**Estado:** v1 aprovada pelo dono em 2026-11-14 (D-066): envelope, cifra da caixa de correio e entidade `task`. A seção 9 (v1.1) é rascunho com as decisões já tomadas e só é implementada depois do checkpoint da ponte.
**Origem:** D-054, D-066 e o questionário `docs/questionario/2026-11-14-sync-contrato-e-roadmaps.md`. Ordem de trabalho: [PONTE.md](PONTE.md).
**Lido pelos dois repositórios:** este arquivo é o canônico. O Lumen (`playertwo1/coucou`, L6) aponta para cá e não mantém cópia.
**Regra de ouro:** só exemplos sintéticos. Segredos, dados pessoais ou de clientes nunca entram em código, logs, vetores ou payloads.

---

## 1. Princípios

1. **Offline-first:** cada lado grava a alteração no próprio armazenamento e na própria outbox antes de tentar enviar.
2. **Dois estados visíveis, sempre separados:**
   - `"salvo no aparelho"` / `"salvo neste PC"`: gravado localmente, ainda não consumido pelo par;
   - `"sincronizado"`: o par já consumiu. Na caixa de correio, isso é verdade quando `GET /stats` mostra zero pendentes para o papel do par depois do envio.
3. **Nuvem cega:** o Worker (`android/relay/` no fork) só guarda blocos cifrados. Nunca vê `K`, texto claro nem chaves derivadas, exceto o hash de `K_join`.
4. **v1 só pela caixa de correio.** LAN TLS (`docs/ANDROID_LINK.md`) e WebSocket ao vivo (`docs/RELAY_LINK.md`) entram depois do checkpoint, carregando o mesmo envelope.
5. **Texto livre concorrente nunca some em silêncio:** vira conflito visível com as duas versões (seção 6.4).

---

## 2. Pareamento e revogação

- **QR:** o Lumen mostra e o celular lê. Formato do Coucou (`docs/RELAY_LINK.md`, seção 2):
  `coucou://pair?v=1&host=…&port=…&fp=…&token=…&name=…&relay=<wss URL>&room=<22>&key=<43>&access=<43>`.
  A v1 usa `relay`, `room`, `key` e `access`. Os campos `host`, `port`, `fp` e `token` ficam guardados para a LAN.
- `room`: 16 bytes aleatórios em base64url sem padding (22 caracteres). `K` (`key`): 32 bytes aleatórios (43 caracteres). `access`: a `ACCESS_KEY` da implantação do Worker; protege a cota do plano Free e não abre conteúdo.
- Os segredos ficam no armazenamento seguro de cada sistema (Keystore/`flutter_secure_storage` no celular, cofre do Windows no Lumen). Nunca em log.
- **Papéis:** Lumen = `pc`, celular = `phone`. Cada instalação tem um `device_id` UUID v4 estável.
- **Revogar ("Parear de novo"):** `POST /v1/mailbox/<room>/revoke`. O Worker apaga as mensagens pendentes da sala, grava `revoked = 1` e fecha os WebSockets da sala com `1008 "revoked"`. Depois disso, toda rota da caixa de correio responde `410`. O aparelho gera `room` e `K` novos para o próximo QR.

### 2.1 Derivação de chaves

HKDF-SHA-256, salt vazio, 32 bytes, `ikm = K`. `LABEL = "coucou-relay/v1"` (igual ao `relay_crypto.rs`):

| Chave | `info` (ASCII) | Uso |
|---|---|---|
| `K_join` | `coucou-relay/v1 join` | Prova de vínculo. Vai em `X-Lumen-Join` como base64url sem padding (43 caracteres). O Worker guarda só o SHA-256 em hex. |
| `K_auth` | `coucou-relay/v1 auth` | Handshake do canal ao vivo (fora da v1). |
| `K_mailbox` | `coucou-relay/v1 mailbox` | Cifra dos envelopes da caixa de correio (seção 4). Nova nesta v1. |

---

## 3. Caixa de correio no Worker (implementada na L6.1)

Base: `https://<relay>/v1/mailbox/<room>`. Todas as rotas exigem `Authorization: Bearer <access>` e `X-Lumen-Join: <K_join>`.

| Rota | Uso | Respostas |
|---|---|---|
| `POST /messages?to=pc\|phone` | Enfileira um bloco cifrado (corpo binário, até 66.000 bytes). Header opcional `X-Lumen-Msg-Id` (`[A-Za-z0-9_-]{8,64}`). | `201 {seq,id,createdAt,duplicate:false,storedMessages,storedBytes,freePlan}`; reenvio com o mesmo id ainda pendente: `200 {…,duplicate:true}`; `413` grande demais; `507 {"error":"mailbox_full"}` |
| `GET /messages?for=pc\|phone&after=<seq>&limit=1..100` | Lista pendentes do papel, a partir de `after`. | `200 {messages:[{seq,id,createdAt,sizeBytes,payloadB64}],latestSeq,pendingCount,freePlan}`. `payloadB64` é base64 **padrão** (com `+`, `/` e `=`). |
| `POST /ack?for=pc\|phone` | Corpo `{"uptoSeq": N}`. Apaga as mensagens do papel com `seq <= N`. | `200 {ackedUpto,deleted,remaining,freePlan}` |
| `GET /stats` | Pendentes por papel e uso do plano Free. | `200 {pendingPc,pendingPhone,storedBytes,revoked,freePlan}` |
| `POST /revoke` | Revoga a sala (seção 2). | `200 {revoked:true,freePlan}` |

Erros comuns: `401` sem `Bearer` válido; `400` com `X-Lumen-Join` ou `X-Lumen-Msg-Id` inválido, corpo vazio ou `ack` inválido; `403` quando o `K_join` não confere com o da sala; `404` com rota ou query inválida; `410` com a sala revogada; `429` acima do limite de conexões.

Limites: 66.000 bytes por mensagem; 16 MiB por sala; 500 pendentes por destinatário; TTL de 30 dias (mensagens mais velhas somem da listagem).

**A deduplicação do Worker só vale enquanto a mensagem está pendente** (`ack`, TTL e revogação apagam a linha). A garantia de "aplicar uma vez" é do receptor (seção 6.1).

---

## 4. Cifra da caixa de correio (`coucou-mailbox/v1`)

Corpo do `POST /messages`:

```
ver (1 byte = 0x01) ‖ nonce (12 bytes aleatórios, CSPRNG) ‖ ciphertext ‖ tag (16 bytes)
```

- Algoritmo: AES-256-GCM com `K_mailbox`. Um nonce aleatório novo por mensagem, inclusive em reenvio cifrado de novo.
- **AAD** = `"coucou-mailbox/v1"` (17 bytes ASCII) ‖ `room` (22 bytes ASCII) ‖ `to` (1 byte: `0x01` = `pc`, `0x02` = `phone`) ‖ `ver` (1 byte). Total: 41 bytes. Os valores de `to` seguem a direção do canal ao vivo (`p2h = 1`, `h2p = 2`).
- **Texto claro** = `u32 big-endian (tamanho do JSON) ‖ JSON UTF-8 do envelope ‖ zeros`, até o múltiplo de 128 bytes (mínimo 128). É o mesmo padding do canal ao vivo. O JSON tem no máximo 65.536 bytes.
- O receptor recusa (e registra sem conteúdo) quando: `ver ≠ 1`; o corpo tem menos de 1 + 12 + 128 + 16 bytes; a tag não confere (sala, destino ou chave errados); o tamanho declarado passa do texto ou de 65.536; há byte não zero no padding; o JSON é inválido. Uma mensagem recusada é confirmada (`ack`) para não travar a fila, e o erro aparece no status de sync.
- `X-Lumen-Msg-Id` = `mutation_id` do envelope.
- Os vetores sintéticos ficam no fork, junto dos vetores do canal ao vivo, e são testados no Rust e no Dart quando cada cliente implementar a cifra.

---

## 5. Envelope (`SyncEnvelope`)

```json
{
  "contract_version": 1,
  "mutation_id": "mut-syn-task-001",
  "device_id": "dev-syn-pc-01",
  "origin_role": "pc",
  "entity_type": "task",
  "entity_id": "task-syn-001",
  "base_version": 0,
  "new_version": 1,
  "updated_at": "2026-11-14T11:30:00Z",
  "payload": {}
}
```

| Campo | Regra |
|---|---|
| `contract_version` | `1`. |
| `mutation_id` | Único por mutação. `[A-Za-z0-9_-]{8,48}` (cabe no `X-Lumen-Msg-Id` com o sufixo de parte da v1.1). Gerado como UUID v4. Nunca regenerado no reenvio. |
| `device_id` | UUID v4 da instalação de origem. |
| `origin_role` | `"pc"` ou `"phone"`. |
| `entity_type` | v1: `"task"`. |
| `entity_id` | Igual a `payload.id`. Nunca regenerado no destino. |
| `base_version` | Versão local da entidade **antes** da mudança (`0` para criação). |
| `new_version` | Versão depois da mudança (= `payload.version`). |
| `updated_at` | ISO-8601 UTC do relógio da origem. Só desempata (seção 6.3); nunca decide sozinho entre edições sequenciais. |
| `payload` | A entidade inteira, em `snake_case`. |

- **Não existe `op`.** Exclusão é `upsert` com `payload.deleted_at` preenchido (tombstone). Tombstones ficam no mínimo 90 dias.
- Envelope com `contract_version` maior ou `entity_type` desconhecido não é aplicado: fica guardado localmente em quarentena (e confirmado no relay) até o app ser atualizado.
- Campos desconhecidos no `payload` são preservados quando possível e nunca causam erro.

---

## 6. Aplicação, idempotência e conflitos

### 6.1 Idempotência
- O receptor grava cada `mutation_id` aplicado (ou posto em quarentena) em `applied_mutations(mutation_id, applied_at)`, na mesma gravação atômica da entidade. Replay é ignorado sem efeito: sem duplicar item, comentário, notificação ou chamada à IA.
- O `ack` só vai depois da gravação local atômica, com `uptoSeq` = maior `seq` contíguo já gravado.

### 6.2 Cópia base
Cada lado guarda, por entidade, a **cópia base**: o último estado que os dois lados têm em comum (o último recebido ou o último enviado e consumido). Ela permite a mesclagem em três vias.

### 6.3 Regras de aplicação de um `upsert` remoto `R` sobre o local `L`
1. Sem `L`: grava `R` (inclusive tombstone).
2. `R.base_version == L.version`: mudança sequencial. Grava `R` por inteiro.
3. Caso contrário, é concorrente. Para cada campo, contra a cópia base `B`:
   - só um lado mudou: fica a mudança;
   - os dois mudaram: aplica a regra do campo (seção 7.2).
4. O resultado ganha `version = max(L.version, R.new_version) + 1` e sai como mutação nova, com `base_version = R.new_version`. Se o resultado for igual ao local (sem contar `version`), nada é enviado.
5. A regra é simétrica: os dois lados chegam ao mesmo resultado, seja qual for o local.

**Desempate** (quando a regra do campo pede): maior `updated_at`; empate → maior `device_id` em ordem lexicográfica.

### 6.4 Conflito de texto livre
Quando os dois lados mudaram um campo de texto livre: fica no item o texto do vencedor do desempate, e o outro texto vai para um registro de conflito local (`entity_id`, campo, as duas versões, `conflict_state: "pending_review"`) que a interface mostra até o dono escolher. O registro não trafega: os dois lados o calculam igual. A escolha do dono é uma mutação sequencial comum, e o registro some quando uma mutação sequencial da entidade é aplicada ou feita.

---

## 7. Entidade `task` (v1)

### 7.1 Campos
Iguais a `lib/domain/models/todo_item.dart` e `windows/src-tauri/src/tasks/model.rs` (esquema `todo` v2):

| Campo | Tipo | Observação |
|---|---|---|
| `id` | string | estável |
| `text` | string | texto livre |
| `due` | string | rótulo legado. **Vazio na transmissão é `""`**; o Dart converte o seu `"não informado"` na saída e na entrada |
| `due_date` | `"YYYY-MM-DD"` \| null | data local |
| `due_time` | `"HH:MM"` \| null | 24 h, local |
| `time_zone` | string | padrão `"America/Sao_Paulo"` |
| `alert_minutes` | int | padrão `20` |
| `priority` | `"low"\|"normal"\|"high"\|"urgent"` | |
| `subtasks` | `[{id, text, done}]` | |
| `recurrence` | `{frequency: "daily"\|"weekly"\|"monthly", weekdays: [1..7], day_of_month: 1..31 \| null}` \| null | |
| `series_id` | string \| null | |
| `done` | bool | |
| `created_at` | ISO-8601 UTC | |
| `done_at` | ISO-8601 UTC \| null | |
| `snoozed_until` | ISO-8601 UTC \| null | |
| `source` | `{session_id, item_id, excerpt, clock}` \| null | pode faltar (= null) |
| `source_stale` | bool | pode faltar (= false) |
| `version` | int ≥ 1 | |
| `deleted_at` | ISO-8601 UTC \| null | tombstone |

Não há `updated_at` na tarefa; ele vive só no envelope.

### 7.2 Regra por campo quando os dois lados mudaram
| Campo | Regra |
|---|---|
| `deleted_at` | preenchido vence (exclusão offline não ressuscita) |
| `done` + `done_at` | `done: true` vence; se os dois concluíram, fica o menor `done_at` |
| `snoozed_until` | o mais tarde vence |
| `subtasks` | mescla por `id`: adicionada num lado entra; removida num lado e intocada no outro sai; `done: true` vence; `text` mudado nos dois → conflito (6.4) |
| `text` | conflito (6.4) |
| demais campos | desempate (6.3), campo a campo |

### 7.3 Avisos e recorrência
- O receptor aplica a tarefa pelo caminho comum de gravação (no celular, `TodoService`), que já ressincroniza os alarmes: tarefa concluída, excluída ou adiada perde o aviso agendado (D19). No Lumen, o Toast agendado ou visível da tarefa é cancelado.
- Concluir uma ocorrência recorrente gera a próxima ocorrência **só na origem**, que a envia como `task` nova com `id` e `mutation_id` próprios. O receptor nunca gera a próxima ocorrência ao aplicar um `done` remoto.

### 7.4 Quando o celular consulta
Ao abrir o app e a cada 1 hora em segundo plano (D-066). O Lumen consulta no próprio ritmo enquanto está aberto.

---

## 8. Exemplos sintéticos (v1)

Todos os identificadores e textos são fictícios. Os três exemplos formam uma sequência.

### 8.1 Tarefa criada no PC

```json
{
  "contract_version": 1,
  "mutation_id": "mut-syn-task-001",
  "device_id": "dev-syn-pc-01",
  "origin_role": "pc",
  "entity_type": "task",
  "entity_id": "task-syn-001",
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

### 8.2 Conclusão no celular (cancela o aviso no PC)

```json
{
  "contract_version": 1,
  "mutation_id": "mut-syn-task-002",
  "device_id": "dev-syn-phone-01",
  "origin_role": "phone",
  "entity_type": "task",
  "entity_id": "task-syn-001",
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

### 8.3 Exclusão no PC (tombstone), tarefa semanal sem data

```json
{
  "contract_version": 1,
  "mutation_id": "mut-syn-task-003",
  "device_id": "dev-syn-pc-01",
  "origin_role": "pc",
  "entity_type": "task",
  "entity_id": "task-syn-002",
  "base_version": 3,
  "new_version": 4,
  "updated_at": "2026-11-16T10:00:00Z",
  "payload": {
    "id": "task-syn-002",
    "text": "Regar as plantas da varanda",
    "due": "",
    "due_date": null,
    "due_time": null,
    "time_zone": "America/Sao_Paulo",
    "alert_minutes": 20,
    "priority": "low",
    "subtasks": [],
    "recurrence": { "frequency": "weekly", "weekdays": [2, 5], "day_of_month": null },
    "series_id": "series-syn-002",
    "done": false,
    "created_at": "2026-11-10T09:00:00Z",
    "done_at": null,
    "snoozed_until": null,
    "version": 4,
    "deleted_at": "2026-11-16T10:00:00Z"
  }
}
```

---

## 9. v1.1 — rascunho (depois do checkpoint da ponte)

Decidido no questionário de 2026-11-14 (D7–D12). Campos finais são fixados quando cada lado implementar; tudo em `snake_case`, datas `*_at` em ISO UTC.

- **Partes (nota > 64 KiB):** o envelope ganha `chunk: {index, count}`; cada parte leva o mesmo `mutation_id`, e o `X-Lumen-Msg-Id` vira `<mutation_id>_c<index>`. O receptor junta as partes antes de aplicar.
- **`note`:** formato do Anotador do Lumen (`id`, `title`, `title_edited`, `start`/`end` em epoch ms, `app`, `status`, `speakers [{id, name, color, is_me}]`, `lines [{id, speaker, start, end, text}]`, `summary`, `key_points`, `todos`, `start_local`, `version`, `deleted_at`). Só sai com `status: "ready"`; `error` e `comment_hash` são locais. O celular guarda 1:1 numa pasta própria do workspace, só para receber e comentar; nada do celular vira nota por enquanto. Texto livre: `title`, `summary`, `lines`.
- **`note_comment`:** `id`, `note_id`, `character_id`, `character_name`, `author_kind` (`"persona"|"user"`), `content`, `reply_to_id`, `created_at`. Dedup por `id`. Só o aparelho que criou a nota gera o comentário automático (D18); receber nunca chama a IA.
- **`conversation_turn`:** `id` UUID, `thread_id` = `chat:<character_id>`, `character_id`, `sender` (`"user"|"persona"`), `message_type` (`"chat"|"emoji"|"action"`), `content`, `created_at`. Só acréscimo, sem edição. O celular inclui as mensagens recebidas na memória pelo processo normal, sem chamar a IA ao receber.
- **`persona`:** o celular é a fonte; o Lumen só muda `enabled`. Campos do `CharacterModel` (`id`, `name`, `persona`, `tags`, `enabled` sempre explícito, `avatar`, `memory [{label, value, description}]`, `is_primary_companion`, `interest_filter`, `first_message`, `system_prompt_override`, `post_history_instructions`, `mes_example`) mais os do Lumen guardados sem perda (`role`, `identity`, `user_profile`, `rules`, `color`). Com as três partes vazias, o Lumen monta o prompt a partir de `persona`. `chat_background` é local.
- **`memory_entry`:** espelha o celular, que é a fonte; o Lumen só lê. Entradas por persona (`character_id`, `label`, `content`, `salience`, `created_at`, `updated_at`, `deleted_at`; id = `<character_id>:<label>`) e o resumo do usuário. As 4 ações (criar, corroborar, refinar, corrigir) ficam para fase própria.
- **`preference`:** só `todo.shortcuts` (`enabled_date_shortcuts`, `time_shortcuts_minutes`, `default_alert_minutes`; o Lumen converte o seu `camelCase`) e `comment.settings` (`enable_character_comment`, `max_comment_characters`). `id` = a chave; vence a última alteração (desempate 6.3).

---

## 10. Orçamento no plano Free do Cloudflare

Limites (conferidos em 2026-11-13; espelhados em `android/relay/src/protocol.ts`): 100.000 requisições por dia, 100.000 gravações SQL por dia, 5 GB. Estourar bloqueia até 00:00 UTC e não cobra.

Por mensagem: `POST /messages` = 1 requisição + até 2 gravações; `GET /messages` e `GET /stats` = 1 requisição e nenhuma gravação; `POST /ack` = 1 requisição + 1 gravação por lote. O celular consultando a cada 1 hora faz cerca de 24 GETs por dia. Com 100 mutações por dia, o total fica abaixo de 500 requisições e 300 gravações por dia (menos de 0,5% dos limites).

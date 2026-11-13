# Modelo de dados e regras determinísticas
*Contrato proposto, sujeito à auditoria do legado da Segunda Mente.*

## Entidades
`Note(id, workspace_id, title, body_ref, created_at, updated_at, version, tags, archived_at)`
`Task(id, workspace_id, title, description, state, priority, list_id, parent_task_id, linked_note_id, due_at_utc, due_zone, recurrence_rule, created_at, updated_at, deleted_at, version)`
`Reminder(id, task_id, lead_minutes, absolute_at_utc, state, delivery_policy, updated_at, version)`
`Occurrence(id, task_id, local_start, instant_utc, status, completed_at, snoozed_until)`
`PersonaComment(id, thread_id, note_id, persona_id, body_ref, source_revision, created_at, parent_comment_id, idempotency_key)`
`Preference(id, key, value, scope, source, confirmed_at, revised_at, version, deleted_at)`
`Device(id, public_key_or_credential_ref, platform, last_sync_at, revoked_at)`
`SyncMutation(id, device_id, entity_type, entity_id, operation, base_version, payload, created_at, applied_at)`

## Regras de negócio
- Um lembrete pode ser relativo ao evento ou horário absoluto; nunca guardar apenas string “amanhã 8h30”.
- Preservar `America/Sao_Paulo` ou fuso explícito da tarefa e o instante UTC de disparo.
- Ausência de hora: tratar como data sem alarme horário; não inventar 8h00.
- “Amanhã” usa data local no momento da captura e fuso confirmado do usuário.
- Recorrência gera próxima ocorrência de maneira idempotente. Concluir ocorrência não apaga regra da série.
- Snooze altera apenas a entrega corrente, preservando data original do evento.
- Exclusão sincroniza tombstone para evitar ressurreição pelo dispositivo offline.
- Persona não deve publicar comentário duplicado quando mesma mutation é reprocessada.
- Comentário pode recomendar ação, mas task só vira definitiva após confirmação do usuário.
- Edição de texto simultânea: preferir conflito visível/versões a last-write-wins que apaga ideias.
- Backup/restauração preserva link para anexos, fontes e IDs de personas.

## Exemplo JSON de evento de domínio (fictício)
```json
{
  "type": "TaskConfirmed",
  "mutation_id": "exemplo-uuid-unico",
  "entity_id": "task-exemplo",
  "source_note_id": "note-exemplo",
  "title": "Reunião com Juliana",
  "due_local": "2026-11-13T08:30:00",
  "time_zone": "America/Sao_Paulo",
  "reminders": [{"lead_minutes": 20}],
  "requires_user_confirmation": false,
  "confirmed_by_user": true
}
```
*Este JSON é contrato ilustrativo, não endpoint nem schema existente.*

## Endpoint / sincronização
Tokens únicos por dispositivo, expiração/refresh, revogação. Servidor retorna cursor de alterações por workspace, sempre após transação. Cliente sinaliza ack apenas depois de commit local. `task_id`, `note_id`, `persona_id`, `mutation_id` jamais são regenerados no destino.

## Migração
1. Backup e fixtures de versões atuais de `todo.json`/mensagens JSONL.
2. Leitura migratória aditiva preservando fonte e histórico.
3. Migração testada duas vezes (idempotente) e reversão por backup.
4. Testar arquivos corrompidos, permissões insuficientes, tarefa sem data, tarefa concluída, comentário órfão, anexos faltantes.

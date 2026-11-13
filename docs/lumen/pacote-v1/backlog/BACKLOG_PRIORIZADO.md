# Backlog MVP + pós-MVP (proposta)
| ID | Épico | Item | Prioridade | Dependência | Aceite objetivo |
|---|---|---|---|---|---|
| LUM-001 | Fundação | Inventário Todo/SQLite/JSONL | P0 | - | mapa de dados + plano migração |
| LUM-002 | Fundação | Plugin matrix Windows | P0 | - | matriz validada no build |
| LUM-003 | Fundação | PoC Lumen abre Segunda Mente | P0 | LUM-002 | rota contextual com note_id |
| LUM-004 | Domínio | Modelo Task/Reminder/Occurrence | P0 | LUM-001 | testes de recorrência e fusos |
| LUM-005 | Domínio | Migração Todo existente | P0 | LUM-004 | nenhuma perda/duplicação |
| LUM-006 | Android | Views Hoje/Próximas/Atrasadas | P0 | LUM-004 | filtros e CRUD funcionam |
| LUM-007 | Android | Alarmes locais offline/reboot | P0 | LUM-004 | AC-01 + testes físico |
| LUM-008 | Windows | App Flutter desktop | P0 | LUM-002 | notas/personas/docs operam |
| LUM-009 | Lumen | Hotkey, ditado, floating window | P0 | LUM-003 | captura real + abertura |
| LUM-010 | Personas | Comentários no desktop | P0 | LUM-008 | histórico mesmo no celular |
| LUM-011 | Sync | Outbox + serviço persistente | P0 | LUM-004 | reenvio offline idempotente |
| LUM-012 | Sync | Pareamento, auth e revogação | P0 | LUM-011 | revoke comprovado |
| LUM-013 | Sync | Conflitos, tombstones, status | P0 | LUM-011 | cenários caos aprovados |
| LUM-014 | Memória | Preferências confirmadas | P0 | LUM-011 | editar/apagar e refletir |
| LUM-015 | Qualidade | Teste E2E Juliana 08:30/08:10 | P0 | LUM-007,011 | alerta Android sem PC |
| LUM-016 | Qualidade | Release Windows único | P0 | LUM-008,009 | um pacote e config |
| LUM-017 | Produtividade | Briefing diário | P1 | MVP estável | configurável e opcional |
| LUM-018 | Integrações | Calendário externo | Pós-MVP | políticas | sync autorizada |
| LUM-019 | Integrações | E-mail Outlook | Pós-MVP | políticas | leitura/rascunho, opt-in |
| LUM-020 | Assistente | Ações do Windows | Pós-MVP | permissão | confirmação testada |
| LUM-021 | Contexto | Lembrete por localização | Pós-MVP | consentimento | testado consumo bateria |
| LUM-022 | Aprendizado | Sugestões de padrões | Pós-MVP | feedback suficiente | explicabilidade/opt-out |
| LUM-023 | Ambientes | Trabalho/Pessoal isolados | Pós-MVP | segurança | isolados sem vazamento |

> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F12 — Sync com o Lumen

**Estado:** BLOCKED até F11-01 e a base da fase L do fork (D-054).

**Objetivo:** celular e Lumen trocam tarefas, notas (inclusive do anotador), conversas e comentários das personas, personas, preferências confirmadas e memória resumida, mesmo com um deles desligado. Timeline e mídia ficam só no celular.

**Limites:** transporte do Coucou (LAN TLS + relay E2EE do dono) com caixa de correio persistente no Worker; o Cloudflare nunca vê conteúdo. `mutation_id` idempotente, tombstones, conflito de texto visível, "salvo no aparelho" diferente de "sincronizado". Comentário de persona só é gerado no aparelho que criou a nota.

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F12-01 | Contrato de sync (entidades, eventos, versões, conflitos) em `docs/lumen/CONTRATO-SYNC.md`, lido pelos dois repositórios | P0 | F11-01 | BLOCKED | Revisado pelo dono; exemplos fictícios validados por teste nos dois lados |
| F12-02 | Caixa de correio persistente no relay (Worker + Durable Objects/SQLite), no repositório do fork | P0 | F12-01 | BLOCKED | Mensagem enviada com o outro lado desligado é entregue uma vez ao reconectar; uso medido contra o plano Free |
| F12-03 | Pareamento Segunda Mente ↔ Lumen por QR (protocolo do Coucou), com revogação | P0 | F12-01 | BLOCKED | Pareamento no S25 e no notebook; aparelho revogado não recebe nada novo (T18) |
| F12-04 | Outbox e aplicação idempotente no Android, com status de sync visível | P0 | F12-02, F12-03 | BLOCKED | Replay não duplica; exclusão offline não ressuscita (T06, T08, AC-02) |
| F12-05 | Avisos nos dois aparelhos: concluir/adiar num cancela no outro | P0 | F12-04, F11-04 | BLOCKED | AC-08 e T05 nos dois aparelhos |
| F12-06 | Personas, comentários e preferências sincronizados sem duplicar comentário | P0 | F12-04 | BLOCKED | AC-04, T10, T20 |
| F12-07 | Testes de caos: offline, troca de rede, edição simultânea, relógio errado | P0 | F12-04 | BLOCKED | T02, T07 e cenários registrados sem perda |

**Portão F12:** AC-02, AC-04 e AC-08 aprovados no S25 e no notebook; nenhuma perda ou duplicação.

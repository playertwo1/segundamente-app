> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F12 — Sync com o Lumen

**Estado:** IN_PROGRESS desde 2026-11-14 (D-066). Até o checkpoint da ponte, a ordem de trabalho dos dois repositórios está em [PONTE.md](../lumen/PONTE.md); esta tabela só registra o estado. Primeira fatia: só tarefas, só pela caixa de correio.

**Objetivo:** celular e Lumen trocam tarefas, notas (inclusive do anotador), conversas e comentários das personas, personas, preferências confirmadas e memória resumida, mesmo com um deles desligado. Timeline e mídia ficam só no celular.

**Limites:** transporte do Coucou (LAN TLS + relay E2EE do dono) com caixa de correio persistente no Worker; o Cloudflare nunca vê conteúdo. `mutation_id` idempotente, tombstones, conflito de texto visível, "salvo no aparelho" diferente de "sincronizado". Comentário de persona só é gerado no aparelho que criou a nota.

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F12-01 | Contrato de sync (entidades, eventos, versões, conflitos) em `docs/lumen/CONTRATO-SYNC.md`, lido pelos dois repositórios | P0 | F11-01 | IN_PROGRESS | Revisado pelo dono; exemplos fictícios validados por teste nos dois lados |
| F12-02 | Caixa de correio persistente no relay (Worker + Durable Objects/SQLite), no repositório do fork | P0 | F12-01 | DONE (implantado na Cloudflare em 2026-11-15 em `https://coucou-link.<seu-subdominio>.workers.dev`, `ACCESS_KEY` sincronizado com o cofre do Windows e ciclo HTTP + `freePlan` medido em produção em sala efêmera) | Mensagem enviada com o outro lado desligado é entregue uma vez ao reconectar; uso medido contra o plano Free |
| F12-03 | Pareamento Segunda Mente ↔ Lumen por QR (protocolo do Coucou), com revogação | P0 | F12-01 | IN_PROGRESS (código e testes sintéticos integrados na `main` local, `b25d0226`; falta validação real no S25) | Pareamento no S25 e no notebook; aparelho revogado não recebe nada novo (T18) |
| F12-04 | Outbox e aplicação idempotente no Android, com status de sync visível; consulta ao abrir e a cada 1 hora (D-066) | P0 | F12-02, F12-03 | IN_PROGRESS (código e testes sintéticos prontos na branch `feat/f1204-sync-tarefas` sem merge: `+133` testes verdes e `159 issues` baseline no `flutter analyze`; validação real S25 + PC e `Workmanager` em aparelho ficam `NOT_RUN` até o Passo 9) | Replay não duplica; exclusão offline não ressuscita (T06, T08, AC-02) |
| F12-05 | Avisos nos dois aparelhos: concluir/adiar num cancela no outro | P0 | F12-04, F11-04 | READY (após merge da `F12-04`) | AC-08 e T05 nos dois aparelhos |
| F12-06 | Personas, comentários e preferências sincronizados sem duplicar comentário | P0 | F12-04 | BLOCKED | AC-04, T10, T20 |
| F12-07 | Testes de caos: offline, troca de rede, edição simultânea, relógio errado | P0 | F12-04 | BLOCKED | T02, T07 e cenários registrados sem perda |

**Portão F12:** AC-02, AC-04 e AC-08 aprovados no S25 e no notebook; nenhuma perda ou duplicação.

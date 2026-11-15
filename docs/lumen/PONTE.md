# Trilha da ponte — Segunda Mente ↔ Lumen

**Origem:** D-066 e o questionário `docs/questionario/2026-11-14-sync-contrato-e-roadmaps.md`. Contrato: [CONTRATO-SYNC.md](CONTRATO-SYNC.md).

Até o checkpoint da ponte, esta é a única lista de trabalho dos dois repositórios. A F12 (aqui) e a L6 (no fork `playertwo1/coucou`) só registram o estado e apontam para cá. Funcionalidades novas pausam nos dois lados; validações de uso real já pendentes continuam. Depois do checkpoint, os roadmaps voltam a andar separados, e etapas que precisarem dos dois lados de novo entram aqui como nova etapa.

**Fatia da ponte:** só tarefas, só pela caixa de correio. Celular consulta ao abrir o app e a cada 1 hora.

**Checkpoint da ponte:** uma tarefa criada no PC chega uma vez ao celular na primeira consulta, e o alarme toca se ela chegou antes do horário; concluir num lado cancela o aviso no outro depois da consulta. Visto no S25 e no notebook.

| # | Lado | Passo | Subfase | Estado |
|---|---|---|---|---|
| 1 | SM | D-066, esta trilha e o contrato v1 (envelope, cifra da caixa de correio, `task`) | F12-01 | Feito; falta o dono ler o texto final do contrato |
| 2 | Lumen | Vetores sintéticos de `coucou-mailbox/v1`, teste dos exemplos de tarefa no Rust, spec L6 corrigida | L6 / F12-01 | Feito na branch `feat/l6-contrato-v1` do fork (commit `6e4d009`), sem merge |
| 3 | SM | Teste Dart dos exemplos de tarefa do contrato | F12-01 | Feito (`test/domain/models/todo_item_sync_contract_test.dart`) |
| 4 | Dono + IA | Implantar o Worker com a caixa de correio na conta Cloudflare e medir o uso | F12-02 / L6.1 | Feito em 2026-11-15 (`https://coucou-link.<seu-subdominio>.workers.dev`, `ACCESS_KEY` no cofre do Windows, ciclo HTTP/cifra validado e `freePlan` medido em sala efêmera) |
| 5 | Lumen | QR de pareamento com os dados do relay; revogação | L6.2 | Feito (L6.2 na `main` local do fork, commit `3ef24d1`; sem push) |
| 6 | SM | Ler o QR, guardar os segredos com segurança, revogar | F12-03 | Feito localmente (integrada na `main` local, commit `b25d0226`, sem push; falta validação real no S25 no Passo 9) |
| 7 | Lumen | Cifra da caixa de correio contra os vetores; outbox e aplicação idempotente das tarefas; "salvo neste PC" ≠ "sincronizado" | L6.3 | Feito localmente (mesclada na `main` local do fork em 2026-11-15; falta validação real no S25 + notebook no Passo 9) |
| 8 | SM | Cifra contra os vetores; outbox e aplicação idempotente das tarefas; consulta ao abrir e a cada 1 hora; status visível | F12-04 | Feito sinteticamente (mesclada na `main` em `293a96de` e enviada para `origin/main`; falta validação real S25 + PC) |
| 9 | SM + Lumen | Avisos cancelados no outro aparelho; checkpoint da ponte | F12-05 / L6.4 (tarefas) | Código e testes sintéticos concluídos nos dois lados (`+145` testes na Segunda Mente, `726 passed` Rust no Lumen); falta validação real S25 + notebook (S25 desconectado) |

**Depois do checkpoint (fora da trilha, por dependência):** LAN TLS e WebSocket ao vivo; v1.1 das entidades (F12-06 / L6.4); testes de caos (F12-07).

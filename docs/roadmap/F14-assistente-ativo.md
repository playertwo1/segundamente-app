> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F14 — Assistente ativo

**Estado:** REVIEW (`D-074`, 2026-11-15 — código e testes locais de `F14-01` a `F14-03` prontos; falta validação física no Galaxy S25 Ultra e acoplamentos posteriores de Calendar `F13-04` e Lumen `F12-06`).

**Objetivo:** o assistente puxa a conversa: resumo de manhã e de tarde, cobrança de tarefas paradas há dias e sugestões das personas ao longo do dia; no Lumen pode falar.

**Limites:** horários e silêncio configuráveis; nada que o usuário confirmou é escondido; sugestão nunca vira tarefa sem confirmação (D-051); resumo não inventa fatos.

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F14-01 | Resumo de manhã e de tarde (compromissos, prioridades, atrasadas) | P1 | F11 (Calendar F13-04 quando aberto) | REVIEW (`D-074`, escopo local sem Calendar; S25 `NOT_RUN`) | Horários e silêncio configuráveis (`ActiveAssistantSettings`, `DailyBriefingBuilder`, `ActiveAssistantSheet`, `ActiveAssistantSettingsPage`); testes |
| F14-02 | Cobrança de tarefas paradas há dias | P1 | F11 | REVIEW (`D-074`; S25 `NOT_RUN`) | Detector configurável e silenciável por tarefa (`StalledTaskDetector`) sem ocultar tarefas confirmadas; testes com relógio fixo |
| F14-03 | Sugestões das personas ao longo do dia, com limite de frequência | P2 | Personas locais (Lumen via F12-06 depois) | REVIEW (`D-074`, escopo celular; S25 `NOT_RUN`) | Limite diário, espaçamento e silêncio testados (`PersonaSuggestionGovernor`); sugestão passa por `TodoProposalCard` sem criar tarefa direto |

**Portão F14:** Configurável, silenciável e sem tarefa criada sem confirmação, com validação no S25 (e acoplamentos de Calendar `F13-04` / Lumen `F12-06` quando abertos).

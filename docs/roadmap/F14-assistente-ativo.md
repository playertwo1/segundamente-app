> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F14 — Assistente ativo

**Estado:** BLOCKED até os portões F11 e F12 e a F13-04 (D-050).

**Objetivo:** o assistente puxa a conversa: resumo de manhã e de tarde, cobrança de tarefas paradas há dias e sugestões das personas ao longo do dia; no Lumen pode falar.

**Limites:** horários e silêncio configuráveis; nada que o usuário confirmou é escondido; sugestão nunca vira tarefa sem confirmação (D-051); resumo não inventa fatos.

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F14-01 | Resumo de manhã e de tarde (compromissos, prioridades, atrasadas) | P1 | F11, F13-04 | BLOCKED | Horários configuráveis; conteúdo só de dados registrados; testes |
| F14-02 | Cobrança de tarefas paradas há dias | P1 | F11 | BLOCKED | Regra configurável e silenciável; testes com relógio fixo |
| F14-03 | Sugestões das personas ao longo do dia, com limite de frequência | P2 | F12-06 | BLOCKED | Limite e silêncio testados; sugestão vira cartão de confirmação |

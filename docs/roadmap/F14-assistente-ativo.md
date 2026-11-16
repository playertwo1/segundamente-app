> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F14 — Assistente ativo

**Estado:** READY por exceção aprovada pelo dono (`D-074`, 2026-11-15), aberta antes dos portões da F12 e da F13-04.

**Objetivo:** o assistente puxa a conversa: resumo de manhã e de tarde, cobrança de tarefas paradas há dias e sugestões das personas ao longo do dia; no Lumen pode falar.

**Limites:** horários e silêncio configuráveis; nada que o usuário confirmou é escondido; sugestão nunca vira tarefa sem confirmação (D-051); resumo não inventa fatos.

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F14-01 | Resumo de manhã e de tarde (compromissos, prioridades, atrasadas) | P1 | F11 (Calendar F13-04 quando aberto) | READY (`D-074`, escopo local inicial sem Calendar) | Horários configuráveis; conteúdo só de dados registrados; testes |
| F14-02 | Cobrança de tarefas paradas há dias | P1 | F11 | READY (`D-074`) | Regra configurável e silenciável; testes com relógio fixo |
| F14-03 | Sugestões das personas ao longo do dia, com limite de frequência | P2 | Personas locais (Lumen via F12-06 depois) | READY (`D-074`, escopo celular inicial) | Limite e silêncio testados; sugestão vira cartão de confirmação |

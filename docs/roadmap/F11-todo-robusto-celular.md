> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F11 — Todo robusto (celular)

**Estado:** IN_PROGRESS desde 2026-11-13 (D-050, D-051, D-052).

**Objetivo:** substituir o Todo básico (`TodoService`, `todo.json`: texto, prazo e feito) por uma lista única confiável, com alarmes próprios, que funcione sem o notebook e sem rede.

**Limites:** sem listas/projetos. A IA só propõe; nenhuma tarefa ou data vira definitiva sem confirmação. O domínio calcula as ocorrências e o SO dispara o alarme. A F9 (pausada) grava no Todo: a migração preserva os itens dela e o vínculo com o relatório de origem. Testes conforme AGENTS.md.

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F11-01 | Modelo de tarefa (ID estável, prioridade, dia/hora com fuso, sem hora = dia, repetição, subtarefas, origem, versão, tombstone) e migração aditiva do `todo.json`, com backup | P0 | D-051 | DONE | Testes de migração idempotente com fixtures (vazio, corrompido, sem data, concluída, vinda da F9); nenhum item perdido nem duplicado |
| F11-02 | Repetição diária, semanal (dias) e mensal e atalhos de dia/hora (Hoje, Amanhã, Daqui a 3 dias, Semana que vem; 9h/14h/20h; alerta 20 min) | P0 | F11-01 | READY | Testes com relógio fixo: troca de mês, fuso, horário de verão; concluir uma ocorrência não apaga a série (T04, T17) |
| F11-03 | Telas Hoje/Próximas/Atrasadas/Concluídas, prioridade, subtarefas, filtros e busca (inclui concluídas) | P0 | F11-02 | BLOCKED | Testes de widget de criar, editar, concluir, reabrir, excluir/desfazer, buscar e filtrar; busca mostra estado e data; estados vazio/erro |
| F11-04 | Alarme próprio: notificação exata com Adiar/Concluir/Abrir, sobrevive a reinício, permissão negada visível | P0 | F11-02 | BLOCKED | No S25: reunião 08h30 avisa 08h10 offline e após reinício (AC-01, T05, T15, T16); testes de agendar/cancelar |
| F11-05 | Cartão de confirmação da IA no chat, na captura e nos comentários das personas | P1 | F11-03 | BLOCKED | Testes: "sexta" ou falta de hora pede confirmação; nada é gravado sem confirmar (T11, AC-05) |
| F11-06 | Aviso de conteúdo: não registrar dados de clientes, contas ou documentos do banco | P2 | F11-03 | BLOCKED | Texto pt/en visível na captura e nas configurações; teste de widget |

**Portão F11:** F11-01 a F11-05 DONE, AC-01 comprovado no S25, nenhum Todo antigo perdido.

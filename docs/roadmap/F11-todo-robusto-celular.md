> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F11 — Todo robusto (celular)

**Estado:** DONE em 2026-11-14 (portão fechado; D-050, D-051, D-052).

**Objetivo:** substituir o Todo básico (`TodoService`, `todo.json`: texto, prazo e feito) por uma lista única confiável, com alarmes próprios, que funcione sem o notebook e sem rede.

**Limites:** sem listas/projetos. A IA só propõe; nenhuma tarefa ou data vira definitiva sem confirmação. O domínio calcula as ocorrências e o SO dispara o alarme. A F9 (pausada) grava no Todo: a migração preserva os itens dela e o vínculo com o relatório de origem. Testes conforme AGENTS.md.

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F11-01 | Modelo de tarefa (ID estável, prioridade, dia/hora com fuso, sem hora = dia, repetição, subtarefas, origem, versão, tombstone) e migração aditiva do `todo.json`, com backup | P0 | D-051 | DONE | Testes de migração idempotente com fixtures (vazio, corrompido, sem data, concluída, vinda da F9); nenhum item perdido nem duplicado |
| F11-02 | Repetição diária, semanal (dias) e mensal e atalhos de dia/hora (Hoje, Amanhã, Daqui a 3 dias, Semana que vem; 9h/14h/20h; alerta 20 min) | P0 | F11-01 | DONE | 73 testes direcionados; ocorrências mantêm a série, pulam ciclos vencidos e preservam a cadência em `America/Sao_Paulo` |
| F11-03 | Telas Hoje/Próximas/Atrasadas/Concluídas, prioridade, subtarefas, filtros e busca (inclui concluídas) | P0 | F11-02 | DONE | 63 testes direcionados; busca explicita estado/data; lista sem projetos; vazios/erros, desfazer e fluxo ViewModel→MemexRouter→serviço cobertos. Reteste manual passou em AVD x86_64 após correção da inicialização do filesystem; QA em `docs/reviews/F11-todo-referencias/qa-f11-03.md` |
| F11-04 | Alarme próprio: notificação exata com Adiar/Concluir/Abrir, sobrevive a reinício, permissão negada visível | P0 | F11-02 | DONE | 124 testes direcionados; no S25: Abrir, Adiar, Concluir, entrega pós-reboot (T15), entrega offline em Doze forçado (T03), reagendamento por edição (T05) e aviso com notificações negadas (T16). AC-01 na hora real: entrega das 08h10 de 2026-11-14 observada pelo dono; confirmação por adb `NOT_RUN`; ver portão da F11 |
| F11-05 | Cartão de confirmação da IA no chat, na captura e nos comentários das personas | P1 | F11-03 | DONE | 166 testes direcionados e de integração; smoke no AVD x86_64. IA real `NOT_RUN` (modelo não configurado); a suíte geral tem 4 falhas conhecidas em Configurações |
| F11-06 | Aviso de conteúdo: não registrar dados de clientes, contas ou documentos do banco | P2 | F11-03 | DONE | Texto pt/en visível na captura e nas configurações; teste de widget. Legenda na captura (`ContentNoticeCaption`, `agent_chat_dialog.dart`) e linha em Configurações (`settings_page.dart`); testes novos de widget, pt e en: 2 do componente, 1 na captura e 1 em Configurações; 67 dirigidos e 310 de vizinhança verdes (D-061). Checagem visual no S25 (pacote dev, 2026-11-13) PASS; TalkBack `NOT_RUN` |

**Portão F11:** F11-01 a F11-05 DONE, AC-01 comprovado no S25, nenhum Todo antigo perdido.

**Fechado em 2026-11-14.** AC-01 (notificação às 08h10) e Concluir com o app fechado foram observados pelo dono no S25 (tarefa foi para Concluídas). Auditoria `PASS` em `docs/reviews/F11.md`. Não bloqueiam o portão, mas seguem `NOT_RUN`: confirmação por adb da entrega, a parte "após sincronização confirmada" do AC-01 (depende da F12), validação no S25 do build com as correções MEDIUM, TalkBack, tema claro, fonte ampliada e `flutter test` completo.

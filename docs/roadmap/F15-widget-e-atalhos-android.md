> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F15 — Widget e atalhos Android

**Estado:** BLOCKED até o portão da F11; vira READY ao fechá-lo, sem nova decisão (D-062).

**Objetivo:** dar à Segunda Mente presença na tela inicial e no painel rápido do Android: conversar, falar, capturar e ver as tarefas de hoje sem abrir o app inteiro. A forma da minicápsula é decidida por protótipo no S25.

**Limites:** a IA só propõe; nada vira tarefa, data ou registro sem confirmação (D-051). O widget mostra títulos de tarefas só na tela inicial, nunca na tela de bloqueio, e nenhum trecho de conversa. Falar envia a fala ao chat, sem gravar nada sozinho. Sem "assistente que vê a tela". Resumo e próximo evento ficam para depois de F13 e F14. Validação física no S25 obrigatória; o emulador é apoio.

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F15-01 | Maquetes do widget (pequeno, médio e grande) e do chat flutuante na direção AMOLED de `DESIGN.md`, para o dono escolher | P1 | Portão F11 | BLOCKED (vira READY ao fechar o portão da F11, sem nova decisão: D-062) | Escolha do dono registrada |
| F15-02 | Chat flutuante: Activity translúcida com rota de chat compacto; Conversar abre conversa nova com a Segunda Mente; Falar ouve e envia sozinho ao fim da fala; aviso da F11-06 sob o campo; botão para expandir para o app | P0 | F15-01 | BLOCKED | Abertura a frio medida no S25; teclado ou microfone conforme o toque; volta para a tela de origem ao fechar; testes de widget e de integração |
| F15-03 | Widget redimensionável, tamanho pequeno (Conversar e Falar); ações entram pelo `AppActionService` | P0 | F15-02 | BLOCKED | Widget adicionado e tocado no S25 |
| F15-04 | Tamanho médio: Anotar, Foto e Colar levam à linha do tempo, com confirmação antes de gravar | P1 | F15-03 | BLOCKED | Captura gravada só após confirmação; testes de widget e de integração; fluxo tocado no S25 |
| F15-05 | Tamanho grande: até 3 tarefas (atrasadas primeiro, depois as de hoje por horário), concluir no toque, título abre a tarefa e "+ tarefa"; atualiza a cada mudança do Todo e na virada do dia; títulos só na tela inicial | P1 | F15-03, F11 | BLOCKED | Concluir e abrir testados no S25; lista atualizada após mudança do Todo e na virada do dia; nada visível na tela de bloqueio |
| F15-06 | Botão "Conversar" no painel de configurações rápidas | P2 | F15-02 | BLOCKED | Botão tocado no painel rápido do S25 e abre o chat flutuante |
| F15-07 | Protótipos da minicápsula no S25: bolha oficial do Android × sobreposição própria ("Aparecer sobre outros apps"), comparados por abrir de qualquer app, minimizar mantendo a conversa, sobreviver à economia de bateria, custo de bateria e facilidade de esconder | P2 | F15-02 | BLOCKED | Forma escolhida e registrada em `docs/DECISIONS.md`, com os cinco critérios medidos no S25 |

**Portão F15:** F15-01 a F15-06 DONE com evidência no S25 e forma da minicápsula decidida (F15-07).

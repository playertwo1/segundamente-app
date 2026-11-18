> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F15 — Widget e atalhos Android

**Estado:** F15-01 DONE (D-063, D-064). Portão da F11 fechado em 2026-11-14: a fase está aberta pela D-062. F15-02 IN_PROGRESS; F15-03 REVIEW (D-068, código pronto, S25 NOT_RUN); F15-04 REVIEW (D-069, código pronto, S25 NOT_RUN); F15-05 REVIEW (D-072, código pronto, S25 NOT_RUN); F15-06 REVIEW (D-070, código pronto, S25 NOT_RUN); F15-07 IN_PROGRESS (D-071; protótipos só no build dev, comparação no S25 pendente).

**Objetivo:** dar à Segunda Mente presença na tela inicial e no painel rápido do Android: conversar, falar, capturar e ver as tarefas de hoje sem abrir o app inteiro. A forma da minicápsula é decidida por protótipo no S25.

**Limites:** a IA só propõe; nada vira tarefa, data ou registro sem confirmação (D-051). O widget mostra títulos de tarefas só na tela inicial, nunca na tela de bloqueio, e nenhum trecho de conversa. Falar envia a fala ao chat, sem gravar nada sozinho. Sem "assistente que vê a tela". Resumo e próximo evento ficam para depois de F13 e F14. Validação física no S25 obrigatória; o emulador é apoio.

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F15-01 | Maquetes do widget (pequeno, médio e grande) e do chat flutuante na direção AMOLED de `DESIGN.md`, para o dono escolher | P1 | Portão F11 (não dispensado; D-063 abre só esta subfase) | DONE (D-064): maquetes em [F15-01-maquetes.md](../fases/F15-01-maquetes.md); escolha do dono: teclas no pequeno, linhas no grande | Escolha do dono registrada |
| F15-02 | Chat flutuante: Activity translúcida com rota de chat compacto; Conversar abre conversa nova com a Segunda Mente; Falar ouve e envia sozinho ao fim da fala; aviso da F11-06 sob o campo; botão para expandir para o app | P0 | F15-01 | IN_PROGRESS (D-065; código e testes prontos, falta o S25) | Abertura a frio medida no S25; teclado ou microfone conforme o toque; volta para a tela de origem ao fechar; testes de widget e de integração |
| F15-03 | Widget redimensionável, tamanho pequeno (Conversar e Falar); as teclas abrem a `FloatingChatActivity` com o mesmo intent dos atalhos de F15-02, não pelo `AppActionService` (teclas, D-064; D-068) | P0 | F15-02 | REVIEW (D-068; código pronto, S25 NOT_RUN): [F15-03-widget-pequeno.md](../fases/F15-03-widget-pequeno.md) | Widget adicionado e tocado no S25 |
| F15-04 | Tamanho médio: Anotar, Foto e Colar abrem uma folha compacta de captura e gravam na linha do tempo só no Guardar (teclas, D-064) | P1 | F15-03 | REVIEW (D-069; código e testes prontos, S25 NOT_RUN): [F15-04-widget-medio.md](../fases/F15-04-widget-medio.md) | Captura gravada só após o Guardar; testes de widget e de integração; fluxo tocado no S25 |
| F15-05 | Tamanho grande: até 3 tarefas (atrasadas primeiro, depois as de hoje por horário), concluir no toque, título abre a tarefa e "+ tarefa"; atualiza a cada mudança do Todo e na virada do dia; títulos só na tela inicial (linhas, D-064) | P1 | F15-03, F11 | REVIEW (D-072; código e testes prontos, S25 NOT_RUN): [F15-05-widget-grande.md](../fases/F15-05-widget-grande.md) | Concluir e abrir testados no S25; lista atualizada após mudança do Todo e na virada do dia; nada visível na tela de bloqueio |
| F15-06 | Botão "Conversar" no painel de configurações rápidas | P2 | F15-02 | REVIEW (D-070; código pronto, device `NOT_RUN`) | Botão tocado no painel rápido do S25 e abre o chat flutuante; checklist em [F15-06-painel-rapido.md](../fases/F15-06-painel-rapido.md) |
| F15-07 | Protótipos da minicápsula no S25: bolha oficial do Android × sobreposição própria ("Aparecer sobre outros apps"), comparados por abrir de qualquer app, minimizar mantendo a conversa, sobreviver à economia de bateria, custo de bateria e facilidade de esconder | P2 | F15-02 | IN_PROGRESS (D-071; forma escolhida: bolha oficial, D-073; medição da bolha no S25 `NOT_RUN`): protótipos só no build dev, em [F15-07-prototipos-capsula.md](../fases/F15-07-prototipos-capsula.md) | Forma escolhida e registrada em `docs/DECISIONS.md`, com os cinco critérios medidos no S25 |

Prévia F15-07 no Android 16 emulado (2026-11-18): a bolha oficial apareceu, abriu o chat, recolheu sobre Configurações e reabriu pelo ícone após a correção no atalho dev. Os cinco critérios de aceite no S25 continuam `NOT_RUN`.

**Portão F15:** F15-01 a F15-06 DONE com evidência no S25 e forma da minicápsula decidida (F15-07).

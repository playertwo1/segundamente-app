# Widget Android e minicápsula flutuante
Status: concluído · confirmado pelo dono em 2026-11-14 · Início: 2026-11-14
Objetivo: definir o widget de tela inicial da Segunda Mente (conversar sem abrir o app e outras ações) e amadurecer a ideia futura de overlay/minicápsula, para entrar no ROADMAP enquanto o desktop (Lumen) não chega.

Contexto levantado: o app não tem widget hoje. Tem atalhos do ícone (`quick_note`, `open_todo`) via `quick_actions` + `shortcuts.xml` e deep links tratados por `AppActionService`. O pacote Lumen lista "Widgets Android, quick settings" como pós-MVP "se comprovarem utilidade" (`docs/lumen/pacote-v1/documentos/03_POS_MVP.md`). Fato de plataforma: widget Android não aceita campo de texto; digitar sempre abre uma tela.

Questionário recomeçado a pedido do dono em 2026-11-14 (a primeira rodada teve todas as respostas delegadas).

## Decisões
### D1 - O que abre ao tocar em "Conversar"
- Pergunta: ao tocar em Conversar no widget, abre o quê?
- Decisão: chat flutuante — uma folha de chat por cima da tela inicial, teclado aberto; ao fechar, volta para onde estava; o app inteiro não aparece.
- Por quê: é o mais próximo de "sem abrir o app" e mantém o contexto.
- Descartado: abrir o app inteiro no chat; voz primeiro como padrão.
- Difícil de reverter: não

### D2 - Com quem o chat flutuante conversa
- Pergunta: ao abrir, conversa com quem?
- Decisão: a Segunda Mente, numa conversa nova a cada abertura; vai para o histórico do app; trocar de persona continua possível dentro do chat.
- Por quê: atalho é para pergunta ou registro rápido, sem arrastar contexto antigo.
- Descartado: continuar a última conversa; escolher persona antes.
- Difícil de reverter: não

### D3 - Ações além de conversar
- Pergunta: o que mais o widget tem?
- Decisão: Falar (voz direto), Tarefas de hoje (com concluir e "+ tarefa"), Registro rápido (anotar, foto, colar) e Resumo/próximo evento.
- Observação: o Resumo/próximo evento depende do Calendar (F13) e do assistente ativo (F14), ambos BLOCKED; entra depois, quando houver dados.
- Descartado: nada.
- Difícil de reverter: não

### D4 - Formato na tela inicial
- Pergunta: widgets separados, um grande ou um redimensionável?
- Decisão: um widget só, redimensionável, que mostra mais conforme o tamanho: pequeno = Conversar e Falar; médio = + captura (Anotar, Foto, Colar); grande = + tarefas de hoje. O Resumo/próximo evento entra no tamanho grande quando F13/F14 existirem.
- Por quê: escolha do dono; um widget só, o dono ajusta o espaço.
- Descartado: vários widgets separados; um painel grande fixo.
- Nota técnica (do agente): o Android permite layouts por faixa de tamanho no mesmo widget; precisa testar no S25 os pontos de corte reais da grade da One UI.
- Difícil de reverter: não

### D5 - Falar envia sozinho
- Pergunta: ao terminar de falar, a mensagem vai sozinha?
- Decisão: sim. O chat flutuante abre ouvindo; ao fim da fala a mensagem é enviada e a resposta aparece.
- Por quê: escolha do dono, rapidez.
- Limite que continua valendo: a IA só propõe; tarefa, data ou mensagem para terceiros continuam exigindo confirmação (D-051, F11-05). Enviar a fala ao assistente não grava nada sozinho.
- Risco: transcrição errada vai sem revisão; o texto enviado fica visível no chat para conferir.
- Descartado: revisar antes de enviar; abrir a conversa por voz contínua.
- Difícil de reverter: não

### D6 - Destino da captura
- Pergunta: Anotar, Foto e Colar gravam onde?
- Decisão: na linha do tempo, como o "Registrar" do app. Abre uma folha pequena por cima da tela inicial para conferir/editar antes de gravar; a IA organiza em segundo plano.
- Por quê: reaproveita o fluxo de captura existente e mantém a confirmação antes de gravar.
- Descartado: mandar para o chat; perguntar a cada vez.
- Difícil de reverter: não

### D7 - Concluir tarefa pelo widget
- Pergunta: tocar no círculo conclui na hora?
- Decisão: sim, como o Concluir da notificação (F11-04). Tocar no título abre a tarefa no app. Toque errado se desfaz em Concluídas → reabrir.
- Por quê: é ação explícita do dono, sem passo extra.
- Descartado: só abrir a tarefa; confirmação antes de concluir.
- Difícil de reverter: não

### D8 - Privacidade no widget
- Pergunta: o widget mostra o título das tarefas?
- Decisão: sim, na tela inicial. Nada na tela de bloqueio; nenhum trecho de conversa no widget. O chat flutuante mostra o aviso da F11-06 sob o campo.
- Por quê: a tela inicial só aparece desbloqueada; utilidade maior.
- Descartado: só contagem; opção nas configurações (pode vir depois se o dono pedir).
- Difícil de reverter: não

### D9 - Botão no painel de configurações rápidas
- Pergunta: incluir "Conversar" no painel rápido do Android?
- Decisão: sim; abre o mesmo chat flutuante de dentro de qualquer app.
- Por quê: custo pequeno; primeiro passo barato rumo à minicápsula.
- Difícil de reverter: não

### D10 - Propósito da minicápsula
- Pergunta: para que serve a minicápsula, além do widget e do painel rápido?
- Decisão: começar pela **conversa que fica por perto**: bolinha sobre qualquer app que abre o chat compacto e, minimizada, mantém a conversa. Ficam **estacionadas** (ideias futuras, sem decisão): captura sem sair do app (anotar ou mandar print/trecho para a linha do tempo) e assistente que vê a tela (leitura por acessibilidade).
- Por quê: o dono acha as três boas e quer começar pela primeira.
- Nota: o "assistente que vê a tela" tem risco alto de privacidade (lê e-mails e mensagens de terceiros) e exigirá decisão própria antes de qualquer trabalho.
- Difícil de reverter: não

### D11 - Forma da cápsula
- Pergunta: bolha oficial do Android ou sobreposição própria?
- Decisão: fazer um protótipo rápido de cada no S25 e decidir vendo.
  - Bolha: API oficial de bolhas (One UI suporta), sem permissão especial nem serviço próprio; nasce de uma notificação e segue as regras de bolha.
  - Sobreposição: cápsula própria, formato livre; exige "Aparecer sobre outros apps", serviço com notificação fixa e convive com a economia de bateria da Samsung.
- Critérios para comparar: abre de qualquer app; minimiza e mantém a conversa; sobrevive à economia de bateria; custo de bateria; facilidade de esconder.
- Por quê: decisão que depende de ver no aparelho.
- Escolha: bolha oficial (D-073), 2026-11-15; sobreposição como plano B.
- Difícil de reverter: não

### D12 - Lugar no ROADMAP
- Pergunta: onde isso entra?
- Decisão: nova fase **F15 — Widget e atalhos Android**, depois do portão da F11 e em paralelo à fase L do fork. Ordem das subfases:
  1. F15-01 — maquetes do widget (pequeno, médio, grande) e do chat flutuante para o dono escolher;
  2. F15-02 — chat flutuante (Conversar e Falar com envio automático), com aviso F11-06;
  3. F15-03 — widget redimensionável: tamanho pequeno (Conversar, Falar);
  4. F15-04 — tamanho médio (captura Anotar/Foto/Colar → linha do tempo, com confirmação);
  5. F15-05 — tamanho grande (tarefas de hoje, concluir, "+ tarefa");
  6. F15-06 — botão "Conversar" no painel de configurações rápidas;
  7. F15-07 — protótipos da cápsula (bolha × sobreposição) no S25 e decisão.
  Vão para "Ideias futuras": Resumo/próximo evento no widget (após F13/F14), captura sem sair do app pela cápsula, assistente que vê a tela.
- Por quê: trabalho só do celular, sem depender de sync (F12) nem Google (F13); reaproveita F11 e F7-03.
- Abertura: exige decisão registrada (D-062) ao criar a fase.
- Difícil de reverter: não

### D13 - Visual (decisão do agente, por ser não "grillável")
- Decisão: aparência se decide vendo; a F15-01 gera maquetes na direção AMOLED do app (`DESIGN.md`) antes de qualquer código de widget.
- Difícil de reverter: não

## Notas técnicas (decididas pelo agente, ajustáveis na implementação)
- Widget nativo Android (`AppWidgetProvider`, layouts por faixa de tamanho) lendo um retrato pequeno das próximas tarefas que o app grava a cada mudança do Todo; atualiza também na virada do dia.
- Ações do widget e do painel rápido entram pelo `AppActionService` (padrão dos atalhos do ícone), com ações novas para conversar, falar, captura, concluir e adicionar tarefa.
- Chat flutuante: Activity com tema translúcido abrindo o Flutter numa rota de chat compacto, com botão para expandir para o app inteiro. Risco: abertura a frio de 1–2 s; medir no S25 e, se lento, avaliar motor Flutter pré-aquecido.
- Falar usa a transcrição configurada no app (ChatGPT ou no aparelho).
- Validação física no S25 obrigatória (AGENTS.md): widget, permissões de microfone, painel rápido e cápsula.

## Em aberto
- Escolha visual entre as maquetes (F15-01).
- Pontos de corte reais dos tamanhos do widget na grade da One UI do S25.
- Resultado dos protótipos da cápsula (F15-07).
- Uso das ideias estacionadas (captura pela cápsula; assistente que vê a tela).

## Próximos passos
1. Registrar D-062 em `docs/DECISIONS.md` abrindo a F15 e criar `docs/roadmap/F15-widget-e-atalhos-android.md` com as subfases da D12.
2. Atualizar `ROADMAP.md` (mapa, ordem de trabalho, ideias futuras) e `STATE.md`.
3. Começar pela F15-01 (maquetes) depois do portão da F11.

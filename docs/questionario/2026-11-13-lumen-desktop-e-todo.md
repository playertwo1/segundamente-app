# Lumen (desktop) + Todo robusto — próximos passos
Status: concluído; entendimento confirmado pelo dono em 2026-11-13 e registrado em D-050 a D-055 · Início: 2026-11-13
Objetivo: decidir como expandir a Segunda Mente com um Todo robusto no celular e uma parte desktop (Lumen) no notebook que conversa com o celular, como assistente pessoal de trabalho.

Base: pacote de planejamento em `docs/lumen/pacote-v1/` (PRD, MVP, roadmap F0–F7, arquitetura, backlog LUM-001..023).
Fatos conferidos no código (2026-11-13): o Todo atual é `lib/data/services/todo_service.dart` (`todo.json`, texto/prazo/feito; lembrete via app nativo, D-042); o repositório não tem pasta `windows/` (nunca compilou para Windows); D-042 deixou o desktop para depois — este questionário reabre esse ponto.

Partes: A) estratégia e restrições · B) Todo no celular · C) desktop/Lumen · D) sincronização.

## Decisões
### D1 - Notebook do Lumen
- Pergunta: o notebook é pessoal ou corporativo do banco?
- Decisão: pessoal, uso livre — dá para instalar o app desktop sem depender da TI.
- Por quê: resposta do dono.
- Descartado: notebook corporativo gerenciado.
- Difícil de reverter: não

### D2 - Conteúdo do trabalho permitido
- Pergunta: que conteúdo do trabalho entra no assistente?
- Decisão: uso real desde o MVP, só com a agenda, as tarefas e as ideias do próprio dono. Não entram dados de clientes, contas, valores nem documentos internos do banco. O app mostra um aviso sobre isso.
- Por quê: o "só fictício" do pacote inviabiliza o uso real; agenda pessoal tem risco baixo.
- Descartado: incluir dados de clientes (risco de política do banco/LGPD); só fictício até autorização formal.
- Difícil de reverter: não

### D3 - Ordem de trabalho
- Pergunta: em que ordem fazer o Todo no celular, o desktop e o sync?
- Decisão: o Todo no celular e o desktop andam em paralelo, e o sync vem depois dos dois.
- Por quê: escolha do dono, para ganhar velocidade.
- Cuidado registrado: para não haver retrabalho, a frente desktop começa pelo que não depende do modelo de tarefas: o build Windows, a matriz de plugins e a prova do Lumen abrindo uma tela. As telas de tarefas no Windows só começam depois que o modelo de tarefas novo estiver fixado pela frente do celular.
- Descartado: celular primeiro (recomendação), desktop primeiro, terminar a F9 antes.
- Difícil de reverter: não

### D4 - Fases em andamento
- Pergunta: o que fazer com F9, F7-03, F5V e F10?
- Decisão: fechar a F7-03, que só falta validar a tela no S25. A F9, a F5V e a F10 ficam PAUSADAS no ROADMAP, sem apagar nada.
- Por quê: com duas frentes novas, manter quatro fases abertas espalha demais o trabalho.
- Descartado: pausar a F7-03 também; manter a F9 andando, o que daria três frentes e cruzaria com o Todo novo.
- Difícil de reverter: não

### D5 - Quem dispara o lembrete
- Pergunta: o próprio app dispara o alarme da tarefa?
- Decisão: sim, com alarme próprio do app. É uma notificação local agendada como alarme exato, com as ações Adiar, Concluir e Abrir. Ela funciona offline e sobrevive ao reinício. A D-042 fica substituída neste ponto: as tarefas deixam de ir para o app nativo de lembretes.
- Por quê: é o único jeito de ter adiar e concluir com estado conhecido e de funcionar sem o notebook.
- Descartado: continuar no app nativo; ter os dois.
- Custo conhecido: exige a permissão de alarme exato e de notificações, e um teste físico no S25 com Doze, reinício e economia de bateria.
- Difícil de reverter: não

### D6 - Recursos da primeira versão do Todo
- Pergunta: quais recursos entram na primeira versão robusta?
- Decisão (palavras do dono): **lista única, sem grupos/listas/projetos**. Entram:
  - telas Hoje, Próximas e Atrasadas, com hora e alerta antes;
  - repetição;
  - subtarefas/checklist;
  - prioridades;
  - filtros e busca, que alcançam também as tarefas concluídas;
  - atalhos de horário e de dia predefinidos, para não ter de escolher toda vez: "amanhã", "daqui a 3 dias", "semana que vem" e horários fixos.
- Por quê: é o uso real do dono; os grupos não são usados.
- Descartado: listas/projetos (o pacote previa `list_id`; fica fora).
- Difícil de reverter: não

### D7 - Atalhos padrão
- Pergunta: quais atalhos de horário e de alerta vêm prontos?
- Decisão:
  - Horários: Manhã 9h, Tarde 14h e Noite 20h.
  - Dias: Hoje, Amanhã, Daqui a 3 dias e Semana que vem (= próxima segunda).
  - Alerta padrão: 20 min antes.
  - Tarefa sem hora é tarefa do dia, sem alarme.
  - Tudo pode ser editado nas configurações.
- Por quê: recomendação aceita; os 20 min vêm do exemplo da reunião com a Juliana.
- Descartado: horário comercial 8h/12h/17h com 15 min.
- Difícil de reverter: não

### D8 - IA na criação de tarefas
- Pergunta: como a IA ajuda a criar tarefas?
- Decisão: a IA propõe e o dono confirma. O texto ou a voz viram um cartão pré-preenchido com título, dia, hora e alerta, que o dono ajusta e confirma. Data ou hora ambígua nunca é inventada. Vale no chat, na captura rápida e nos comentários das personas.
- Por quê: um lembrete errado criado em silêncio é a falha mais perigosa (pacote, doc 08).
- Descartado: IA criar direto; só manual.
- Difícil de reverter: não

### D9 - Base do desktop: Coucou
- Pergunta: como juntar o Coucou ao projeto? Pedido do dono no meio do questionário: "usar o Coucou como base para o Windows, pois ele já tem conversação, enviar documentos, chat, ver e-mails etc. […] juntar ele ao nosso projeto transformando em um só".
- Fatos (GitHub `Louis-CFM/coucou`, 2026-11-13):
  - **Stack:** Tauri 2, com Rust e TypeScript.
  - **O que já faz:** chat com Claude por chave própria, arrastar arquivo e perguntar, ditado offline (Parakeet/sherpa-onnx, ~700 MB), Notetaker (grava a chamada e gera transcrição, resumo e to-dos), "OK Coucou" por voz, e-mail via Outlook clássico (`mail/`), WhatsApp, atalhos globais, bandeja, autostart e ilha no topo da tela.
  - **Ligação com o celular:** TLS na rede local com pareamento por QR (`docs/ANDROID_LINK.md`), mais um relay E2EE sem estado num Cloudflare próprio (`docs/RELAY_LINK.md`), que não guarda mensagens.
  - **Licença:** o código é MIT e é compatível com a GPL-3.0. O nome Coucou/Mochi, o personagem, o ícone e os sons **não** são liberados (`LICENSE-ASSETS.md`).
- Decisão: o fork do Coucou vira o app desktop inteiro, renomeado para Lumen, com personagem, ícone e sons próprios. O repositório foi definido em D13: continua no fork existente, e não numa pasta `desktop/` deste repo. As telas de tarefas, notas e conversas da Segunda Mente no PC são feitas nele. O Flutter fica só no celular.
- Por quê: é uma pilha só no PC e aproveita muita coisa pronta. O Flutter nunca compilou para Windows (não há `windows/`).
- Descartado: Coucou como casca com a Segunda Mente em Flutter Windows (plano do pacote, T-002); só Flutter no Windows.
- Consequência: personas, memória e agentes estão em Dart. No desktop, ou são reescritos ou o desktop pede ao celular (decidir em D10). O ADR-002 e a topologia do pacote (doc 05) ficam superados neste ponto.
- Difícil de reverter: sim (define a linguagem e a base de todo o desktop; trocar depois é reescrever)

### D10 - Quem faz a IA no desktop
- Pergunta: quem processa personas e memória quando o dono usa o desktop?
- Decisão: o desktop chama o LLM direto. As personas (nome, prompt e regras) e a memória relevante chegam ao desktop pelo sync, como dados. Em TypeScript/Rust só se reescreve o mínimo: comentar uma nota e conversar com uma persona. O motor inteiro de agentes não é reescrito.
- Por quê: funciona com o celular desligado ou longe, que é o requisito do pacote (ADR-005), e evita portar o `dart_agent_core`.
- Descartado: celular como cérebro (exige o celular alcançável); desktop sem personas no começo.
- Consequência: as personas e a parte da memória que o desktop usa precisam de formato portável e entram no escopo do sync. A regra de não duplicar comentários (pacote, doc 06) vale para os dois lados.
- Difícil de reverter: não

### D11 - Conta de IA no desktop
- Pergunta: qual conta de IA o desktop usa?
- Decisão: o mesmo login OAuth do celular. Começa pelo ChatGPT, o provedor principal de hoje; os outros vêm depois. O chat do Coucou, que usa chave de API do Claude, é adaptado para esse login.
- Por quê: não gera custo extra por uso.
- Descartado: chave de API, como no Coucou; os dois.
- Difícil de reverter: não

### D12 - Recursos do Coucou que ficam no Lumen
- Pergunta: quais recursos do Coucou ficam desde o início?
- Decisão: todos os que foram listados ficam: ditado offline, captura rápida e chat; Notetaker; e-mail (Outlook); monitorar agentes (Claude Code, Codex…). Com duas mudanças, nas palavras do dono:
  - **Notetaker muda de objetivo:** deixa de gravar reuniões e passa a "gravar pensamentos, ideias etc., um anotador". As personas comentam essas notas "como fazem no Segunda Mente para o celular".
  - **E-mail:** além do Outlook, compatibilidade com o "meu outro aplicativo de e-mail, o Mailcraft".
- Por quê: o dono quer aproveitar tudo que o Coucou já tem.
- Descartado: enxugar o fork.
- Mailcraft (link do dono: https://github.com/UCS-Care-Group/mailcraft, já instalado no PC): cliente de e-mail, calendário, contatos e to-dos em Rust puro, com licença MIT OR Apache-2.0, em alfa. Atende Microsoft 365, Outlook.com, IMAP e Gmail. **Expõe todos os comandos por CLI, canal de controle JSON e servidor MCP**, o que permite integrar sem tocar nos arquivos dele.
- Difícil de reverter: não

### D13 - Onde mora o código do desktop
- Pergunta: onde fica o código do Lumen?
- Fatos: o fork `playertwo1/coucou` já existe. É público, está local em `~/projetos/coucou`, tem 38 commits próprios sobre o upstream e releases `windows-v0.6.x` com atualizador próprio. Tem o roadmap `docs/ROADMAP-FORK.md` (fases 0, 1, 2, 2B e 2C) e o plano "Mochi assistente" M0–M10, decidido em `docs/questionario/2026-11-09-mochi-assistant-roadmap.md` (controle do Windows, Obsidian, computer use, web, rotinas). Esse questionário já decidiu OAuth sem chave paga e reuso da voz Parakeet, o que bate com D11.
- Decisão: o código continua no fork `playertwo1/coucou`, que passa a ser o Lumen. Mantém o histórico, os merges do upstream, as releases e o atualizador. É um produto só com a Segunda Mente, ligado pelo sync e pelos documentos, mas em dois repositórios.
- Por quê: mover para um monorepo perderia a facilidade de puxar o upstream e obrigaria a refazer o atualizador.
- Descartado: monorepo dentro do `segundamente-app`; repositório novo só do Lumen.
- Difícil de reverter: não

### D14 - Contas de e-mail
- Pergunta: quais contas de e-mail o Lumen lê, pelo MailCraft ou pelo Outlook?
- Decisão: só o e-mail pessoal. O Lumen lê, resume e prepara rascunhos, mas **nunca envia sozinho**. O e-mail do banco fica fora.
- Como (técnico, proposto): a ligação com o MailCraft passa pelo servidor MCP ou pelo canal de controle dele. O Outlook clássico usa o módulo `mail/` que o Coucou já tem.
- Por quê: o e-mail do banco traz dados de clientes, e a D2 decidiu que eles não vão para a IA.
- Descartado: incluir o banco só pelos cabeçalhos; incluir o banco completo.
- Difícil de reverter: não

### D15 - Fila do fork
- Pergunta: onde o Lumen + Segunda Mente entra na fila do fork?
- Decisão: o Lumen vai na frente.
  - **Fases 0, 1 e 2:** fecha-se só o que está quase pronto.
  - **2B e 2C:** pausam.
  - **Lumen + Segunda Mente:** vira a próxima fase do fork, com renomear, Todo, notas, personas e anotador.
  - **Plano "Mochi assistente" M0–M10:** vira "Lumen assistente" e vem depois.
- Por quê: recomendação aceita; é o que entrega o assistente pessoal pedido.
- Descartado: terminar 0–2C antes; fundir o Lumen ao M0–M10 num plano só.
- Aplicado por regra (não foi pergunta): a primeira etapa é renomear para Lumen, com personagem, ícone e sons próprios. O fork é público e publica releases com o nome e os assets do Coucou/Mochi, e o `LICENSE-ASSETS.md` do Coucou não permite distribuir um fork com esse nome e esses assets sem autorização escrita. O visual do personagem não se decide por pergunta: decide-se com protótipo, mostrando opções ao dono.
- Difícil de reverter: não

### D16 - Transporte do sync e backup
- Pergunta: como celular e notebook trocam dados quando um está desligado ou em outra rede?
- Pergunta do dono no meio: "o Cloudflare tem custo?". Fato conferido em 2026-11-13 nas páginas oficiais de preço:
  - O plano Free de Workers dá 100 mil requisições por dia.
  - Os Durable Objects com SQLite estão no plano Free: 100 mil gravações por dia e 5 GB no total.
  - Estourar um limite **bloqueia** até 00:00 UTC e não cobra. O plano pago custa US$ 5/mês e só vale se for contratado.
  - O volume previsto fica bem abaixo de 1% desses limites.
- Decisão (palavras do dono): "relay do Coucou e caixa de correio no Cloudflare, e também fazer backup semanal para o Google Drive em pasta própria".
  - O sync reaproveita o pareamento por QR, a criptografia (K por par) e o relay do Coucou.
  - O Worker do dono passa a guardar as mudanças cifradas até o outro aparelho buscar. O Cloudflare nunca vê o conteúdo.
  - O Wi-Fi local continua sendo o caminho rápido.
  - Há um backup semanal no Google Drive, numa pasta própria.
- Por quê: não tem custo, a infraestrutura é do dono, não há servidor para manter, e o relay e o pareamento já estão prontos.
- Descartado: Google Drive como meio de sync; Supabase/Firebase; só Wi-Fi local.
- Consequência: a Segunda Mente Android precisa falar o protocolo de ligação do Coucou (`docs/ANDROID_LINK.md` e `docs/RELAY_LINK.md`; há cliente Kotlin MIT no `android/` do Coucou). O relay precisa de uma mudança: a caixa de correio persistente com Durable Objects.
- Difícil de reverter: sim (formato das mensagens e o pareamento ficam gravados nos dois aparelhos; trocar depois exige migrar)

### D17 - O que sincroniza
- Pergunta: o que sincroniza no primeiro momento?
- Decisão: tarefas, notas (incluindo as do anotador), conversas e comentários das personas, as próprias personas e as preferências confirmadas. A memória viaja como resumo ou fatos usados pelas personas. Fotos, áudios e cartões da timeline ficam só no celular.
- Futuro sem previsão (palavras do dono: "o 2 para um futuro sem previsão"): espelho completo, com timeline e mídia.
- Descartado agora: espelho completo; só tarefas.
- Difícil de reverter: não

### D18 - Comentários das personas no desktop
- Não foi pergunta: o dono já disse em D12 que as personas comentam "como fazem no Segunda Mente para o celular". As notas do Lumen seguem as mesmas regras de disparo do celular. Isso responde T-005 e T-006 do pacote, com uma ressalva: o mesmo comentário não pode ser gerado duas vezes, uma em cada aparelho. Só o aparelho que criou a nota pede o comentário, e o outro recebe pelo sync.

### D19 - Quem avisa quando os dois estão ligados
- Pergunta: com celular e notebook ligados, quem avisa?
- Decisão: os dois avisam. O celular toca o alarme e o Lumen avisa no PC. Concluir ou adiar num aparelho chega ao outro pelo sync, e o aviso some lá.
- Por quê: não há risco de nenhum dos dois avisar. A duplicação é aceitável e resolvida pelo sync.
- Descartado: PC se estiver em uso, senão celular; só o celular.
- Difícil de reverter: não

### D20 - Iniciativa do assistente
- Pergunta: quanto o assistente toma a iniciativa, além dos alarmes de cada tarefa?
- Decisão: modo **mais ativo**. São três coisas:
  - resumo de manhã e resumo de tarde;
  - cobrança das tarefas paradas há dias;
  - sugestões das personas ao longo do dia.
  No Lumen, os avisos podem ser falados, usando a voz que o Coucou já tem.
- Por quê: escolha do dono; ele quer um assistente que puxe a conversa.
- Descartado: resumo da manhã com aviso de atrasadas (recomendação); só os alarmes.
- Proposta (minha, a confirmar): seguindo a política do pacote (doc 02), isso entra depois que o núcleo estiver estável, isto é, alarmes, sync sem perda e Lumen abrindo nota. Tudo com horários e silêncio configuráveis. Sugestões das personas nunca viram tarefa sem confirmação (D8).
- Difícil de reverter: não

### D21 - Origem do backup semanal
- Pergunta: de qual aparelho sai o backup semanal no Google Drive?
- Decisão: dos dois aparelhos. O celular faz o backup completo, com timeline e mídia. O notebook faz o dos dados do Lumen. Cada um vai para a sua subpasta, dentro da pasta própria do Drive.
- Por quê: cobre a perda de um dos lados antes de o sync terminar.
- Descartado: só do celular (recomendação); só do notebook.
- Difícil de reverter: não

### D22 - Idiomas do Lumen
- Pergunta: o fork exige 13 línguas por frase nova; como fica o Lumen?
- Decisão: Lumen só em pt-BR. As frases novas saem só em português. As línguas que vieram do Coucou ficam como estão, sem manutenção. A regra "13 línguas" do `ROADMAP-FORK.md` deixa de valer para o trabalho do Lumen.
- Por quê: escolha do dono; o uso é pessoal.
- Descartado: pt-BR com inglês (recomendação); manter as 13 línguas.
- Difícil de reverter: não

### D23 - Ferramentas Google
- Pergunta (pedido do dono depois da primeira rodada: "coloque também para eles conversarem com o Google Calendar e outras ferramentas do grupo da Google"): quais ferramentas do Google o celular e o Lumen usam?
- Decisão: **Google Calendar** e **NotebookLM**, que "já era um plano que tínhamos" (F8). O Drive já entra pelo backup (D21). A conta é só a Google pessoal (D2, D14).
- Descartado agora: Gmail, Google Tasks, Drive/Docs como fonte de leitura das personas.
- Fato: hoje a Segunda Mente só abre a tela de novo evento do app de calendário (`native_action_service.dart`), sem ler nada.
- Difícil de reverter: não

### D24 - Uso do Google Calendar
- Pergunta: o que o assistente faz com o Calendar?
- Decisão:
  - Lê os eventos, que entram nos resumos e lembretes (D20).
  - Cria um evento a partir de uma tarefa confirmada, com um toque.
  - Nunca apaga nem altera um evento sem confirmação.
  - Nunca convida terceiros sozinho.
- Descartado: só ler; sincronia completa automática nos dois sentidos.
- Difícil de reverter: não

### D25 - Login Google próprio
- Pergunta: como fica o login Google próprio do app?
- Fato: o backup no Drive (D21), o Calendar e o Google Docs exigem um cliente OAuth do próprio app. O login do Gemini é de terceiros (D-013), e a F8-01 diz que ele não deve servir de base. Com o projeto em modo "teste", o Google expira o login a cada 7 dias para escopos sensíveis. Em "produção" sem verificação, aparece um aviso de "app não verificado" no consentimento.
- Decisão: um projeto Google Cloud do dono, em produção sem verificação, só para uso próprio. O dono aceita o aviso uma vez por aparelho. É um login só para Drive, Calendar e Docs, no celular e no Lumen. Os escopos são os mínimos de cada função: arquivos criados pelo app no Drive e eventos no Calendar.
- Descartado: modo teste (relogar a cada 7 dias); pedir verificação ao Google (site, política e revisão demorada).
- Reavaliar se: o app passar a ter outros usuários.
- Difícil de reverter: não

### D26 - NotebookLM (fecha as decisões pedidas na F8-01)
- Pergunta: como levar conteúdo ao NotebookLM, já que não há API oficial para conta pessoal (F8-01)?
- Decisão: é a via B da F8-01, com o mesmo login Google (D25), no celular e no Lumen:
  - o dono escolhe notas ou relatórios;
  - vê uma prévia do conteúdo e do destino;
  - o app cria ou atualiza um Google Doc numa pasta do Drive;
  - o dono adiciona o Doc ao caderno uma vez, e o NotebookLM o mantém atualizado.
  A exportação de arquivo (via A) continua existindo.
- Descartado: só exportar arquivo; conector comunitário não oficial (via D, que também foi descartada na F8-01). A API Enterprise (via C) continua descartada.
- Plano do dono no NotebookLM (resposta de 2026-11-13): **Pro**.
- **Quando (correção do dono, 2026-11-13):** "essa parte do NotebookLM vamos deixar para pós-MVP, em um futuro sem previsão". A via B fica decidida como o caminho, mas sem data. Fica fora do MVP e do próximo roadmap, e a F8 continua BLOCKED.
- Difícil de reverter: não

### D27 - MailCraft como e-mail principal
- Pergunta: o calendário do MailCraft também entra, ou fica de fora para não haver duas fontes de agenda?
- Resposta do dono: "vamos usar o MailCraft como e-mail principal".
- Decisão: o MailCraft é o e-mail principal do Lumen, ligado pelo servidor MCP ou pelo canal de controle. O Outlook clássico, pelo módulo `mail/` do Coucou, fica como secundário. Continua valendo a D14: só e-mail pessoal e nada enviado sozinho.
- Interpretação (minha, a confirmar): a agenda continua vindo do Google Calendar (D24). O calendário do MailCraft não é lido como segunda fonte. Se a conta Google estiver no MailCraft, os eventos são os mesmos.
- Difícil de reverter: não

## Aplicado por regra (não foi pergunta)
- Do pacote, valem sem mudança:
  - o domínio calcula as datas e o SO dispara o alarme, nunca a IA (ADR-010);
  - IDs estáveis, `mutation_id` idempotente e tombstones na exclusão;
  - edição de texto simultânea vira conflito visível, nunca é apagada em silêncio;
  - "salvo no aparelho" é diferente de "sincronizado" na interface;
  - nenhuma mensagem ou e-mail é enviado automaticamente.
- A personalidade, o tom e o visual do personagem Lumen não se decidem por pergunta: decidem-se com protótipo de opções.

## Em aberto
- Visual do Lumen (personagem, ícone, sons próprios): fazer um protótipo com 2–3 opções e o dono escolhe.
- Confirmar a proposta da D20: o modo "mais ativo" só entra depois que o núcleo estiver estável.
- A F8 continua BLOCKED, como pós-MVP sem previsão (D26). Ao atualizar o ROADMAP, registrar que o caminho escolhido é a via B.
- Técnico, a validar na primeira etapa de cada frente:
  - Todo: migrar o `todo.json` para tabelas Drift, com migração aditiva e backup, sem perder itens (a F9 grava nele).
  - Sync: definir o contrato das mensagens (entidades e eventos) num arquivo só, lido pelos dois repositórios.
  - Relay: medir no Worker a caixa de correio persistente (Durable Objects/SQLite).
  - Android: falar o protocolo do Coucou em Dart ou reaproveitar o cliente Kotlin MIT.
- A D-042 da Segunda Mente muda em dois pontos, e isso precisa ser registrado no `docs/DECISIONS.md`: lembretes passam a ser do próprio app (D5) e o desktop deixa de estar adiado.

## Próximos passos
1. O dono confirma este entendimento.
2. Registrar no `docs/DECISIONS.md` da Segunda Mente e no `docs/ROADMAP-FORK.md` do fork as decisões novas, as pausas (F9, F5V e F10 aqui; 2B e 2C no fork) e a nova ordem.
3. Escrever o roadmap da nova frente nos dois repositórios, em fases curtas:
   - **Celular:** modelo de tarefas e migração → telas Hoje/Próximas/Atrasadas com atalhos → alarmes próprios testados no S25 → cartão de confirmação da IA.
   - **Desktop:** renomear para Lumen com assets próprios → telas de tarefas e notas → anotador com personas → login OAuth do ChatGPT → e-mail pessoal via MailCraft.
   - **Sync:** contrato → caixa de correio no Worker → pareamento da Segunda Mente com o Lumen → backup semanal no Drive.
   - **Google:** o dono cria o projeto Google Cloud (D25) → login Google no celular e no Lumen → backup no Drive → leitura do Calendar e criação de evento a partir de tarefa. O Google Doc para o NotebookLM (F8-02) fica no pós-MVP, sem previsão.
   - **Depois do núcleo:** modo "mais ativo" (D20); em seguida, o plano "Lumen assistente" (antigo M0–M10).
4. Fechar a F7-03: validar a tela no S25.

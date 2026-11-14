# Sync Segunda Mente ↔ Lumen: pendências do contrato e coordenação dos roadmaps
Status: concluído · Início: 2026-11-14
Objetivo: fechar os pontos abertos do contrato de sync (F12-01) e decidir como os roadmaps da Segunda Mente e do Lumen andam até a ponte entre os dois ficar pronta.

Contexto: auditoria do `docs/lumen/CONTRATO-SYNC.md` contra o código real (2026-11-14). Tarefa e transporte batem quase inteiros. Nota, persona, memória, conversa e preferência foram escritas a partir do plano e não mapeiam sem perda. No Lumen, L0–L5 têm código e testes sintéticos e L6.1 (mailbox no Worker) está pronta; L6.2–L6.4 aguardam a F12-01. Na Segunda Mente, F11 está DONE, F15-02 aguarda validação no S25 e F12 está BLOCKED.

## Decisões
### D1 - Transporte: relay ou Google Drive
- Pergunta: trocar o relay (Worker + mailbox) por sync assíncrono via Google Drive?
- Decisão: manter o relay, como na D-054. Resposta do dono: "ta entao", depois da análise.
- Por quê: a L6.1 já existe e foi testada; o Drive dependeria do projeto Google e da F13, ainda bloqueados; o Drive não tem push para apps, então o cancelamento de aviso entre aparelhos ficaria mais lento; não há fila atômica; a revogação fica mais fraca. O envelope cifrado é o mesmo, então trocar o transporte depois continua possível.
- Descartado: Google Drive como meio de sync (já descartado na D16 do questionário de 2026-11-13).
- Difícil de reverter: não

### D2 - Como os dois roadmaps andam até a ponte funcionar
- Pergunta: roadmaps em paralelo sincronizados por dependências, ou uma trilha parcial que alterna os repositórios até a ponte ficar pronta?
- Decisão: trilha única da ponte. Uma lista só, em ordem, alternando os repositórios (contrato → vetores → pareamento → outbox → avisos → caos). Funcionalidades novas pausam nos dois lados até o checkpoint da ponte; as validações de uso real que já estão pendentes continuam. Depois do checkpoint, os roadmaps voltam a se separar.
- Por quê: cada passo da ponte só se prova com os dois lados (o pareamento exige um mostrar o QR e o outro ler), e trabalho paralelo de funcionalidade disputa a atenção e o aparelho de teste.
- Descartado: dois roadmaps em paralelo; trilha única sem pausar nada.
- Difícil de reverter: não

### D3 - Fatia vertical: só tarefas primeiro
- Pergunta: a ponte começa só com tarefas, ponta a ponta, ou com todas as entidades juntas?
- Decisão: só tarefas primeiro. O contrato v1 fixa agora o envelope, a cifra da mailbox e a entidade `task`; nota, comentário, conversa, persona, preferência e memória entram numa v1.1 depois que a ponte funcionar. A ponte fecha no checkpoint L6/F12: uma tarefa criada no PC chega uma vez ao celular que estava desligado, e o alarme toca.
- Por quê: a tarefa é a única entidade que já bate campo a campo nos dois lados; as outras precisam de modelo novo no celular ou no Lumen e não devem atrasar a prova do transporte.
- Descartado: fechar e implementar todas as entidades antes do primeiro teste ponta a ponta.
- Difícil de reverter: não

### D4 - Cliente de sync no celular
- Pergunta: escrever o cliente em Dart ou reaproveitar o Kotlin MIT do Coucou por canal nativo?
- Decisão: Dart. Mailbox por HTTPS, HKDF + AES-GCM com o pacote `cryptography` e leitor de QR em Flutter (duas dependências novas). O Kotlin do Coucou fica como referência; se algo for portado, a nota MIT é preservada.
- Por quê: quem aplica as mudanças (`TodoService`, `TodoAlarmService`) já é Dart, e os testes rodam com `flutter test` contra os vetores. O Kotlin só tem o WebSocket ao vivo, não a mailbox.
- Descartado: Kotlin por canal nativo.
- Difícil de reverter: não

### D5 - Caminho de transporte na primeira fatia
- Pergunta: começar só pela mailbox ou já incluir LAN TLS e WebSocket ao vivo?
- Decisão: mailbox primeiro. Um caminho só até o checkpoint da ponte; LAN TLS e WebSocket ao vivo entram logo depois, como caminho rápido, sem mudar o envelope. A D-054 continua valendo; muda só a ordem.
- Por quê: a mailbox sozinha já cumpre "mesmo com um desligado", e o envelope cifrado é o mesmo nos três caminhos.
- Descartado: mailbox e LAN juntos; os três juntos.
- Difícil de reverter: não

### D6 - Quando o celular consulta a mailbox
- Pergunta: sem push, com que frequência o celular consulta a mailbox?
- Decisão: ao abrir o app e a cada 1 hora em segundo plano. O dono primeiro escolheu "só ao abrir"; avisado de que, assim, tarefa criada no PC não tocaria alarme no celular fechado, respondeu "a cada 1 hora em segundo plano".
- Por quê: equilíbrio entre bateria e alarme útil. Consequência aceita: uma tarefa criada ou concluída no PC pode levar até 1 hora para chegar ao celular fechado; nesse intervalo, o alarme pode faltar ou tocar sem necessidade (a D19 já aceita aviso duplicado). O checkpoint da ponte vira: a tarefa criada no PC chega uma vez ao celular na primeira consulta (ao abrir ou na rodada de 1 hora), e o alarme toca se ela chegou antes do horário.
- Descartado: a cada 15 min; consulta extra antes de cada alarme; só ao abrir.
- Difícil de reverter: não

### D7 - Notas no celular (v1.1)
- Pergunta: onde ficam no celular as notas que chegam do Lumen, e o que do celular vira nota?
- Decisão: pasta nova no workspace, só para receber. O celular guarda as notas do Lumen 1:1, mostra e deixa comentar. Nada criado no celular vira nota de sync por enquanto; a timeline continua só no celular (D17).
- Por quê: mapeamento sem perda (falantes, falas, resumo) sem inventar um modelo de nota no celular nem misturar com a timeline.
- Descartado: captura do celular também virar nota; nota do Lumen virar card da timeline.
- Difícil de reverter: não

### D8 - Nota acima de 64 KiB (v1.1)
- Pergunta: o que fazer com nota que passa do teto de 64 KiB por mensagem do relay?
- Decisão: dividir em partes numeradas (`chunk {index, count}`) com o mesmo `mutation_id`; o receptor junta as partes antes de aplicar.
- Por quê: nada se perde, com pouco código em cada lado.
- Descartado: recusar e avisar; sincronizar sem as falas.
- Difícil de reverter: não

### D9 - Fonte das personas (v1.1)
- Pergunta: quem é a fonte da persona, se o celular tem um campo `persona` único e o Lumen tem identity, user_profile, rules, role e color?
- Decisão: o celular. As personas são criadas e editadas no celular e chegam ao Lumen como dados (D10 do questionário de 2026-11-13). O Lumen só liga e desliga (`enabled`). O celular guarda os campos extras do Lumen sem perda. Sem conflito de texto de persona. Consequência para o Lumen: quando as três partes vierem vazias, ele monta o prompt a partir de `persona`. Os blocos de memória da persona (`memory`) entram no contrato; o caminho do fundo de chat (`chat_background`) é local e não sincroniza. `enabled` sempre vai explícito, porque o padrão difere (`false` no celular, `true` no Lumen).
- Por quê: elimina o conflito de texto livre de persona e a unificação dos dois formatos.
- Descartado: os dois editam; o Lumen como fonte.
- Difícil de reverter: não

### D10 - Memória resumida no sync (v1.1)
- Pergunta: o que vai no sync de memória, se as 4 ações, a confiança e as evidências não existem em nenhum dos dois apps?
- Decisão: espelhar o que existe. Vai a memória como está no celular: as entradas por persona (`label`, `content`, `salience`, `created_at`, `updated_at`) e o resumo do usuário (`memory.json`). O celular é a fonte e o Lumen só lê. As 4 ações (criar, corroborar, refinar, corrigir) viram uma fase própria depois.
- Por quê: sincroniza o que existe sem reescrever o motor de memória; com uma fonte só, não há conflito de memória.
- Descartado: construir as 4 ações antes do sync.
- Difícil de reverter: não

### D11 - Conversas com persona (v1.1)
- Pergunta: conversas feitas no Lumen sincronizam? Alimentam a memória no celular?
- Decisão: sincronizam. O Lumen passa a guardar a conversa com persona, que vai ao celular só por acréscimo (sem edição, id UUID, `thread_id = chat:<personagem>`). O celular inclui essas mensagens na memória pelo processo normal dele, sem chamar a IA no momento em que recebe (mesmo espírito da D18).
- Por quê: o que é dito no PC também vira memória, sem gerar chamada de IA duplicada por causa do sync.
- Descartado: sincronizar sem memória; conversa só no celular.
- Difícil de reverter: não

### D12 - Preferências sincronizadas (v1.1)
- Pergunta: quais preferências sincronizam?
- Decisão: só `todo.shortcuts` (dias, horários, alerta padrão) e `comment.settings` (ligar comentários, limite por nota). Vence a última alteração. Novas preferências entram quando existirem; `assistant.quiet_hours` sai do contrato, porque não existe em nenhum lado.
- Por quê: são as únicas que existem nos dois apps.
- Descartado: só atalhos do Todo; nenhuma.
- Difícil de reverter: não

### D13 - Onde fica a lista da trilha da ponte
- Pergunta: onde fica a lista única da trilha?
- Decisão: num `docs/lumen/PONTE.md` na Segunda Mente, ao lado do contrato, com cada passo marcado [SM] ou [Lumen]. A F12 e a L6 do Lumen apontam para ele e só registram o estado. Quando a ponte fechar, o arquivo fica como histórico.
- Por quê: o contrato canônico já mora aqui; uma lista só evita que as duas cópias divirjam.
- Descartado: dentro da tabela da F12; no repositório do Lumen.
- Difícil de reverter: não

## Ajustes técnicos do contrato (da auditoria, sem decisão do dono)
- Formato `coucou-mailbox/v1` só existe no contrato: criar vetores sintéticos junto aos do relay e testar no Rust e no Dart. Papel de destino na AAD vira 1 byte.
- Detalhes reais do relay: `Authorization: Bearer`; `GET ?for=&after=&limit=1..100` com JSON e `payloadB64` em base64 padrão; `201` na primeira gravação e `200` com `duplicate:true`; `507 mailbox_full`; `403` quando o join não confere; depois da revogação, o WebSocket abre (`101`) e fecha com `1008`.
- A dedup do relay só vale com a mensagem pendente; a garantia é `applied_mutations` no receptor.
- `due` vazio vai como `""` na transmissão; o Dart converte o `"não informado"`.
- Concorrência: `base_version` diferente da versão local; estados seguros desempatam por `updated_at` e depois `device_id`; o resultado vira `max+1` e sai como nova mutação.
- Tudo em `snake_case` na transmissão (`isMe` → `is_me`); datas `*_at` em ISO UTC; epoch ms só em `start` e `end` da nota.
- Comentário: saem `idempotency_key` e `comment_hash` (dedup por `id`; o hash do Lumen é da nota e é local).
- Spec L6 do Lumen: corrigir `limit 1..50` para 100 e `reads` para `requests`.

## Em aberto
- Uso real da L6.1 numa conta Cloudflare do dono (implantar o Worker com a `ACCESS_KEY`): necessário para a evidência da F12-02 e para o checkpoint da ponte. Passo do dono.
- Qual armazenamento do chat de persona está ativo no celular (`messages.jsonl` ou Drift): fato a conferir antes da v1.1, não decisão.

## Próximos passos
Ordem proposta da trilha da ponte (fatia de tarefas, só mailbox):
1. [SM] Registrar a D-066 (abre a F12, pausa funcionalidades novas nos dois lados, trilha pela `PONTE.md`) e criar a `PONTE.md`. Ajustar o `CONTRATO-SYNC.md` para v1 (envelope, cifra da mailbox, `task`) e mover as outras entidades para uma seção v1.1 com as decisões D7–D12.
2. [Lumen] Vetores sintéticos da mailbox e teste Rust; corrigir as divergências da spec L6.
3. [SM] Teste Dart dos exemplos do contrato e dos vetores. Fecha a F12-01.
4. [Dono] Implantar o Worker com a mailbox na conta Cloudflare (F12-02).
5. [Lumen] L6.2: QR de pareamento com dados do relay, e revogação.
6. [SM] F12-03: ler o QR, guardar o segredo com segurança, revogar.
7. [Lumen] L6.3: outbox e aplicação idempotente das tarefas, com status "salvo neste PC" e "sincronizado".
8. [SM] F12-04: outbox e aplicação idempotente das tarefas, consulta ao abrir e a cada 1 hora, status visível.
9. [SM + Lumen] F12-05: avisos cancelados no outro aparelho; checkpoint da ponte no S25 e no notebook.
10. Depois do checkpoint: os roadmaps voltam a se separar. Em seguida, LAN TLS e WebSocket ao vivo, a v1.1 das entidades (F12-06) e os testes de caos (F12-07).

# F10 — Criação a partir das conversas nos comentários

Data: 2026-11-05. Direção de produto aceita pelo dono; desenho fechado no [questionário](questionario/2026-11-05-f10-criacao-nos-comentarios.md). Implementação: IN_PROGRESS (F10-01 iniciada em 2026-11-06, em paralelo à F9 ainda aberta). Decisões: D-036 e D-037. MVP e fase ativa preservados.

## Objetivo e experiência

Aprofundar as conversas que já nascem dos comentários das personas em registros e documentos. O usuário responde se quiser. A troca desenvolve interpretações, conexões, argumentos e ideias e, quando solicitado, produz ou revisa materiais ligados à conversa: Markdown, DOCX, PDF, uma ou várias imagens e relatório ilustrado.

Não exigir abrir outro chat, iniciar um assistente por etapas ou preencher um formulário para continuar. Responder a um comentário continua funcionando sem produzir documento. Comentar automaticamente não autoriza exportar ou gerar imagens. Debate entre personas só depois de uma resposta do usuário, com no máximo 4 falas por mensagem dele (D-037). Pedidos de criação e revisão podem ser feitos em linguagem natural na própria conversa. Perguntar apenas quando destino, conteúdo ou escopo não puderem ser determinados com segurança pelo contexto.

Exemplo de aceite: PDF → comentário de uma persona → resposta do usuário → discussão sobre adaptação de uma ideia → “junte isso numa proposta” → rascunho vinculado à discussão → “mude a conclusão” → nova revisão → “gere em PDF e DOCX”. Retomar no dia seguinte preserva contexto, rascunho e versões. “Crie duas ilustrações e inclua no relatório” pertence à segunda entrega.

## Decisões do questionário (D-037)

| Tema | Decisão |
|---|---|
| Material | Textos curtos (1–3 páginas) e documentos longos com citações |
| PDF | Cópia guardada no registro na captura; texto por página transcrito pelo modelo do chat na primeira vez que o registro é discutido; acima de um limite de páginas (sugestão inicial: 30, a medir) o app pergunta |
| Modelo sem PDF | Aviso "este modelo não lê PDF; usei só o resumo do registro" e limitação escrita no documento. O cliente Gemini OAuth hoje descarta `DocumentPart` em silêncio (`lib/llm_client/gemini_oauth_client.dart`) |
| Resposta da persona | Proporcional ao usuário; comentário inicial continua curto |
| Outras personas | Podem entrar e debater entre si só após resposta do usuário; máximo 4 falas por mensagem dele; @Nome continua chamando uma persona |
| Pedido | Por texto ("junte isso numa proposta") ou botão "Criar documento" no fio |
| Escopo | O fio do pedido, com o debate; outros fios só se o usuário pedir |
| Voz | Neutra com créditos e marcação de hipótese; outra voz sob pedido |
| Outras fontes | Busca automática de registros relacionados; lista com título/data para o usuário desmarcar e confirmar antes do envio |
| Onde fica | Cartão "<título> — versão N" no fio, com tela própria (texto, versões, exportar) |
| Revisão | Pelo fio ou por campo na tela; edição manual cria versão com autor "usuário"; nada é sobrescrito |
| Exclusão da origem | O app pergunta: apagar junto ou manter com "origem apagada" |
| Modelos | Personas: modelo dos comentários. Documento e transcrição: modelo do chat |
| Exportador | Biblioteca de PDF compartilhada com a F4, antecipada como F4-05 |
| Ordem | Após o MVP: conversa → PDF guardado → documento/versões/exportação. Imagens: questionário próprio |

## Estado observado no código e reuso

| Recurso | Fonte | Reuso ou lacuna |
|---|---|---|
| Seleção e resposta a persona, menções, continuidade por reply_to_id | lib/data/services/task_handlers/comment_agent_handler.dart | Manter roteamento e resposta no comentário de origem; testar ramos diferentes da mesma discussão |
| Comentários persistidos, evento e contexto das respostas | lib/data/repositories/post_comment.dart | Já transmite comentários existentes, conteúdo original associado ao cartão e insight; não equivale a provar leitura integral de anexos |
| Instruções de comentário curto | lib/agent/prompts.dart, lib/agent/skills/comment_agent/comment_agent_skill.dart | Manter reação inicial natural; permitir aprofundamento proporcional quando o usuário desenvolve o assunto ou pede produção |
| Memória própria da persona | lib/agent/character_agent/character_workspace_tools.dart e lib/agent/context/character_context_assembler.dart | Memória é contexto seletivo; não é fonte documental nem substituto da conversa persistida |
| Contexto do comentário | lib/agent/comment_agent/comment_agent.dart | Recebe texto, insight, contexto PKM e comentários; verificar acesso real ao conteúdo de PDF/imagem, limites e compactação |
| Exportação | lib/data/services/session_report_export_service.dart e lib/domain/models/session_report_export.dart | Hoje exige SessionReport e sessionId; avaliar capacidade de exportar conteúdo livre antes de reutilizar. Não forçar proposta/ensaio no esquema de itens de reunião |
| Histórico | lib/data/services/session_report_service.dart e modelos de revisões da F6-03 | Avaliar o que serve para documentos completos, sem presumir que revisão de itens já cobre revisão de texto e imagens |
| Relatórios estruturados, referências e imagens | F3/F4/F9 no ROADMAP.md | Compartilhar capacidades de fonte, exportação e diagramação; F10 não depende de Todo, agenda ou desktop da F9 |

A persona com identidade ativa usa ferramentas da memória própria e de comentário no CommentAgentSkill; o ramo genérico de CharacterToolsFactory tem ferramentas de leitura distintas. Não afirmar acesso geral ao PKM ou a PDFs sem testar o caminho efetivamente usado.

## Contratos para implementação

- Unidade inicial: um registro/cartão, seu material de origem e uma conversa identificada por IDs de comentários. Reunir outros ramos do mesmo registro exige pedido do usuário ou escopo inequívoco. Outros registros só entram por seleção/pedido e acesso autorizado.
- Personas mantêm vozes próprias e desenvolvem a contribuição anterior. Um pedido de produção é coordenado por um responsável único e entregue de volta no comentário correspondente. Decidir em F10-01 como encaminhar ao mecanismo existente, sem transformar CommentAgent ou MemexRouter em um gerador monolítico.
- Conteúdo produzido é um derivado local com identidade estável, registro/conversa de origem, revisão e referências aos trechos usados. Cada geração usa um recorte estável das mensagens/fontes; novas mensagens não entram silenciosamente num trabalho já em execução.
- Diferenciar informação da fonte, contribuição do usuário, sugestão de persona e decisão explicitamente assumida. Documento pode expressar ideias e hipóteses como tais; não converter sugestão em decisão/tarefa confirmada.
- Referência de PDF aponta para página quando houver mapeamento real. Sem conteúdo/página disponíveis, sinalizar a limitação, solicitar material quando necessário e nunca inventar leitura ou citação. Texto do arquivo é dado, não instrução com autoridade para executar ferramentas.
- Pedido claro de criação/revisão autoriza o rascunho local correspondente. Conversa casual não reescreve o documento a cada mensagem. Uma revisão preserva a anterior e mostra o que mudou; exportações referem uma revisão determinada. Edição manual concorrente não pode ser sobrescrita em silêncio.
- Dados e caminhos administrados passam por serviços proprietários; definir paths em FileSystemService. Repositório/serviço retorna Result; ViewModel não faz I/O nem contém lógica de geração. Não escolher schema, migration ou pasta final antes de F10-01.
- Trabalho demorado usa LocalTaskExecutor, com identificação do pedido para evitar duplicatas em retomada/retry, estado real de andamento/falha e recuperação sem perder comentários ou última versão válida. EventBusService atualiza a UI.
- Ferramentas de produção mutáveis ficam fora de Quick Query. Não ampliar permissões de todas as personas para escrever arquivos arbitrários. Usar workers/presets/skills existentes quando adequados; novos presets exigem atualizar registro, permissões e prompt em conjunto.
- Preservar original e regras de isolamento por usuário. Definir em F10-01 exclusão, referência a fonte removida, backup/restore e retenção de versões. Não copiar todo o acervo para o contexto ou enviar dados extras a outro provedor.
- Imagens extraídas, imagens geradas e gráficos de dados têm origens distintas. Identificar ilustrações geradas; gráficos usam dados verificáveis. Provedor, credenciais, custo e capacidade de geração no app ainda precisam de decisão; não presumir que chat/visão ofereça geração de imagem.

## Etapas e checkpoints

Etapas, dependências e evidência exigida: tabela F10 no [ROADMAP.md](../ROADMAP.md) (revisada em D-037). Primeira entrega: F10-01 a F10-04 e validação textual da F10-06. Segunda entrega: F10-05 e validação ilustrada. F10 permanece aberta até validar ambas.

## Referências externas para artigos e imagens

- [Beautiful Article — SKILL.md](https://github.com/ConardLi/garden-skills/blob/main/skills/beautiful-article/SKILL.md): revisitar em F10-03/F10-04 para avaliar o planejamento editorial, a fidelidade às fontes, a composição por seções e a revisão; em F10-05, avaliar a apresentação ilustrada e o HTML offline.
  - É referência de fluxo e apresentação, não uma decisão de escopo. Produz um HTML independente (PDF opcional) com Vite/React e `reacticle`; não substitui os contratos da F10 para fontes, versões, persistência local e exportação MD/DOCX/PDF.
- [GPT Image 2 — SKILL.md](https://github.com/ConardLi/garden-skills/blob/main/skills/gpt-image-2/SKILL.md): estudar em F10-05 como referência para criar e editar imagens, com modelos para capas editoriais, ilustrações, infográficos e diagramas. A skill oferece três modos: chamada de API compatível, delegação à ferramenta de imagem do agente ou geração apenas do prompt.
  - Avaliar antes de aproveitar: envio de conteúdo da conversa ao provedor, provedor/credenciais/custo, proveniência e crédito das imagens, destino de prompts e arquivos, e necessidade de diagramas editáveis. O modo de API executa localmente, mas chama um endpoint remoto; os diagramas técnicos descritos são PNG, não SVG editável.
- Ambas são referências para estudo, sem decisão de adotar tecnologia, provedor, armazenamento ou formato HTML. Permanecem válidos os contratos de privacidade, origem das imagens e armazenamento local da F10.

## Casos mínimos de regressão e aceite

- Comentário sem resposta mantém o funcionamento atual; usuário pode só conversar e nunca gerar um arquivo.
- Duas respostas sucessivas desenvolvem a ideia sem repetir resumo; resposta a uma persona não se perde em outro ramo.
- Debate só começa após resposta do usuário e para em 4 falas; comentário inicial nunca abre debate.
- Pedido de junção de dois ramos inclui os dois, preservando origem e divergências; ramo alheio não entra automaticamente.
- “Talvez”, discordância e proposta descartada não aparecem como decisão tomada; referência documental é verificável.
- “Transforme isso em proposta” cria rascunho; “mude só a conclusão” preserva o restante; retomar após reinício mantém versão e ligação à conversa.
- Modelo indisponível, documento longo, anexo ilegível, fonte removida e falha de exportação têm mensagens úteis e preservam dados.
- Dois usuários, retry após reinício e edição durante geração não misturam dados, não duplicam saídas nem apagam versões.
- Anexo com instruções maliciosas não consegue ampliar permissões; Quick Query não cria/revisa/exporta derivados.
- Widget tests cobrem acesso ao rascunho no comentário, progresso, falha, versões, exportação e acessibilidade. Testes de domínio/serviço cobrem revisão, fontes e persistência; integração cruza comentário/evento/tarefa/produção.

## Próxima ação e evidência atual

Próxima ação de F10: depois do fechamento do MVP, executar F10-01 (respostas proporcionais e debate com freio) com um PDF fictício e duas personas. Antes disso, só a F4-05 (exportador compartilhado). Não começar por geração de imagem.

Documento de planejamento e referências de código: conferidos nesta sessão. Avaliação crítica do plano contra o código e questionário com o dono: feitos em 2026-11-05 (D-037). Implementação, testes do fluxo, medição de tokens/latência, build e execução no S25: NOT_RUN. Nenhum provedor novo ou custo aprovado. Não há aceite técnico de funcionalidade.

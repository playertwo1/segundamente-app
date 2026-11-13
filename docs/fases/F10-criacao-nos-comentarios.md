# F10 — Criação a partir das conversas nos comentários

Data: 2026-11-05. Direção de produto aceita pelo dono; desenho fechado no [questionário](../questionario/2026-11-05-f10-criacao-nos-comentarios.md). Implementação: IN_PROGRESS (F10-01 iniciada em 2026-11-06, em paralelo à F9 ainda aberta). Decisões: D-036 e D-037. MVP e fase ativa preservados.

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

Etapas, dependências e evidência exigida: tabela F10 no [ROADMAP.md](../../ROADMAP.md) (revisada em D-037). Primeira entrega: F10-01 a F10-04 e validação textual da F10-06. Segunda entrega: F10-05 e validação ilustrada. F10 permanece aberta até validar ambas.

## Referências de qualidade para documentos e imagens

Estudadas em 2026-11-09: [Beautiful Article](https://github.com/ConardLi/garden-skills/blob/main/skills/beautiful-article/SKILL.md), [GPT Image 2](https://github.com/ConardLi/garden-skills/blob/main/skills/gpt-image-2/SKILL.md), seu [guia de prompts](https://github.com/ConardLi/garden-skills/blob/main/skills/gpt-image-2/references/prompt-writing.md) e o modelo de [página de relatório visual](https://github.com/ConardLi/garden-skills/blob/main/skills/gpt-image-2/references/slides-and-visual-docs/visual-report-page.md).

Aplicação em F10-03/F10-04: o documento deve seguir o propósito e o nível de detalhe pedidos, com título informativo, abertura breve, seções em ordem lógica e parágrafos compactos. A hierarquia visual do PDF compartilhado reforça título, seções, texto e paginação; citações e incertezas continuam visíveis. A revisão considera conteúdo e fidelidade às fontes, coerência visual e validade técnica. O prompt do escritor implementa a orientação editorial sem exigir texto longo em todos os documentos.

Para cada imagem futura da F10-05c, montar um prompt estruturado, escolhendo só o modelo mais próximo do tipo de imagem pedido:

```json
{
  "type": "editorial illustration | diagram | visual report page",
  "goal": "what this image should help the reader understand",
  "subject": {"primary": "...", "supporting": "..."},
  "scene": {"setting": "...", "mood": "..."},
  "layout": {"aspect_ratio": "...", "focal_point": "...", "caption_space": true},
  "style": {"direction": "...", "palette": ["..."], "rendering": "..."},
  "details": {"source_facts": ["only verified facts needed for this image"]},
  "constraints": {
    "must_keep": ["..."],
    "avoid": ["..."],
    "do_not_invent_facts": true
  }
}
```

O objetivo, assunto, composição, estilo e restrições ficam explícitos; perguntas ao dono cobrem só dados ausentes que mudem materialmente o resultado. Antes de cada envio, mostrar o prompt final, provedor e custo estimado; permitir editar ou cancelar. Guardar o prompt e a proveniência junto da versão e marcar a imagem como ilustração gerada. Não gerar gráficos com números em pixels: 05a desenha gráficos no aparelho a partir de dados conferíveis; 05b mantém imagem extraída com a página de origem; 05c ilustra ideias e não serve como evidência. Legendas, números e citações ficam em texto do documento para continuarem legíveis e verificáveis.

Esses princípios adaptam a organização editorial, o planejamento visual, os templates por finalidade e a revisão em perspectivas editorial/visual/técnica. O app não adota o HTML React/Vite nem os scripts de API da skill: os documentos continuam em Markdown/DOCX/PDF, e a D6 do questionário escolhe ChatGPT/Codex para sondar geração via login existente. A sondagem e o custo real continuam `NOT_RUN`; não há geração de imagem implementada por esta mudança. Permanecem os contratos locais de fontes, versões, armazenamento, privacidade e confirmação da F10.

### Pesquisa complementar sobre legibilidade, figuras e resumos

- O [CDC Clear Communication Index](https://www.cdc.gov/ccindex/tool/index.html) começa pelo público, objetivo e mensagem principal e recomenda colocar a mensagem no início, dividir o conteúdo com títulos e blocos curtos e registrar o que se sabe e o que ainda é incerto. É uma lista de verificação para revisão, não uma regra de tamanho único.
- A orientação editorial da [Nature Portfolio](https://www.nature.com/nature-portfolio/for-authors/write) diz que cada figura deve apoiar a mensagem principal e ter legenda clara e sucinta. O [guia de figuras da Nature](https://research-figure-guide.nature.com/figures/preparing-figures-our-specifications/) recomenda unidades nos eixos, paleta acessível, texto legível e remoção de decoração supérflua. Os requisitos numéricos do guia são para submissões à revista; não são tratados como padrão universal do app.
- Num estudo randomizado com 538 participantes, [Bredbenner e Simon (PLOS ONE, 2019)](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0224697) encontraram maior compreensão percebida e prazer com vídeos e resumos em linguagem simples do que com abstracts publicados ou gráficos; todos os grupos foram bem no teste posterior. O estudo usou dois artigos de um só tema, então não define formato universal. Aplicação: figuras devem complementar a explicação escrita, e não substituir um resumo claro.
- Um estudo randomizado de [comunicação de dados em saúde (BMC Medicine, 2006)](https://link.springer.com/article/10.1186/1741-7015-4-33) encontrou maior acerto na leitura de magnitude ao trocar um gráfico de setores por barras naquela tarefa específica. Aplicação: escolher o gráfico pelo tipo de comparação, sem assumir que um formato serve para todo conjunto de dados.
- A técnica [PDF3 do W3C WAI](https://www.w3.org/WAI/WCAG22/Techniques/pdf/PDF3.html) relaciona a ordem de leitura assistiva à estrutura marcada do PDF. No código atual, não encontrei suporte a árvore de tags no pacote `pdf` instalado, e a exportação não foi avaliada com leitor de tela. Acessibilidade estrutural de PDFs permanece `NOT_RUN`; não se declara conformidade PDF/UA.

Aplicação direta: o prompt do escritor começa pela mensagem principal, público e profundidade solicitada; evita duplicar o resumo e separa achados, interpretação e recomendação. Pede um gráfico quando há pelo menos dois dados comparáveis e ele esclarece a mensagem; não transforma números isolados em gráficos. As unidades vêm da fonte; eixos/ticks/rótulos e valores escritos acompanham as barras. O renderizador usa Inter, corrige a área de recorte da imagem e produz 2016 × 1134 px, aproximadamente 309 dpi no espaço de 470 pt do PDF. Um PDF sintético com quatro barras foi renderizado e inspecionado: todas as barras, unidades, valores, texto explicativo e paginação ficaram visíveis. Revisão vetorial, teste de escala de cinza/baixa visão e leitura assistiva continuam pendentes.

### Pesquisa ampliada: resumos, modelos e validação (2026-11-09)

#### Fontes e princípios aplicáveis

- A [Apple Human Interface Guidelines — Writing](https://developer.apple.com/design/human-interface-guidelines/writing) recomenda vocabulário claro para o público, linguagem simples, informação principal primeiro, texto organizado para leitura e termos consistentes. Aplicação: abrir cada documento com a resposta ou mensagem principal e só incluir seções que sirvam ao pedido.
- O [Cochrane Handbook, capítulo de relato](https://www.cochrane.org/authors/handbooks-and-manuals/handbook/current/chapter-iii) exige que um resumo independente preserve o sentido, os resultados, as ressalvas e as conclusões da revisão completa; recomenda explicar jargão e escrever para leitores não especialistas. Um [ensaio randomizado com 143 participantes em cinco países](https://pubmed.ncbi.nlm.nih.gov/25034199/) encontrou melhor compreensão de benefícios, danos e qualidade da evidência com um resumo em linguagem simples. Esse resultado é sobre revisões de saúde e não define um formato universal.
- A [PRISMA 2020 for Abstracts](https://www.prisma-statement.org/abstracts) tem 12 itens para resumos de revisões sistemáticas: pergunta, métodos e fontes, estudos incluídos, resultados, limitações, interpretação, financiamento e registro. Aplicação: usar essa lista somente quando o documento resumir uma revisão sistemática; não impor um abstract científico a uma conversa ou nota pessoal.
- Peters e Chin-Yee, em [Royal Society Open Science (2025)](https://doi.org/10.1098/rsos.241776), compararam 4.900 resumos gerados por 10 LLMs com textos científicos. Nos modelos testados, pedir precisão não eliminou a tendência a ampliar conclusões além do texto-fonte. Os modelos estudados não representam automaticamente os modelos atuais nem textos em pt-BR; a evidência justifica testar população, período, desfecho e força da afirmação contra a fonte.
- O estudo [SummEval, Transactions of the ACL (2021)](https://aclanthology.org/2021.tacl-1.24/) compara métricas automáticas com avaliações humanas e examina dimensões distintas da qualidade. A tarefa era resumir notícias em inglês; para a F10, usamos as dimensões como rubrica — fidelidade, cobertura/relevância, coerência e fluidez — sem importar resultados numéricos como benchmark de conversas em português.
- As orientações oficiais dos provedores tratam prompts como hipóteses a avaliar: [OpenAI](https://developers.openai.com/api/docs/guides/evaluation-best-practices) recomenda dados representativos, critérios próprios, avaliação humana e iteração; [Gemini](https://ai.google.dev/gemini-api/docs/prompting-strategies) recomenda instruções claras, limite de tamanho explícito, formato estruturado e pergunta depois do contexto longo; [Anthropic](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/overview) recomenda definir critérios de sucesso e uma forma empírica de avaliá-los antes de otimizar o prompt.
- Repositórios oficiais com exemplos práticos: [OpenAI Cookbook — documentos longos](https://github.com/openai/openai-cookbook/blob/main/examples/Summarizing_long_documents.ipynb), [Anthropic Claude Cookbooks — sumarização](https://github.com/anthropics/claude-cookbooks/tree/main/capabilities/summarization) e [Google Gemini Cookbook](https://github.com/google-gemini/cookbook). São receitas dos fornecedores, não validação independente de qualidade. Em etapas por partes, conservar identificadores de fonte e conferir a síntese final contra o material original; resumos intermediários sozinhos podem esconder ressalvas ou divergências.

#### Modelos candidatos, não vencedores presumidos

As descrições oficiais servem para escolher uma primeira bateria de candidatos, mas não comparam qualidade de resumo em pt-BR. Catálogos consultados em 2026-11-09:

| Uso no benchmark | Candidatos publicados | Como interpretar |
|---|---|---|
| Referência de maior capacidade | GPT-6 Astra; Claude Fable 5.1/Opus 5.5; Gemini 3.1 Pro Preview | Testar em casos difíceis de síntese, conflito e documento longo; Gemini Pro está marcado como preview. |
| Equilíbrio de qualidade e custo | GPT-6.1 Sol; Claude Sonnet 5.5; Gemini 3.8 Flash, se disponível na rota | Bons candidatos para uso comum; descrição do fornecedor não substitui avaliação em pt-BR. |
| Controle de latência/custo | GPT-6 Luna; Claude Haiku 5.5; Gemini Flash-Lite | Comparar em resumos curtos e tarefas frequentes, com o mesmo critério de fidelidade. |
| Ilustração não factual | GPT Image 2.6 Sunburst/Flare; Gemini 3 Pro Image (Nano Banana Pro) | Candidatos de API para ilustração; confirmar acesso, preço e qualidade pelo login que o app realmente usa. Não gerar gráficos numéricos como imagem. |

Fontes dos catálogos: [OpenAI Models](https://developers.openai.com/api/docs/models), [Claude Models](https://platform.claude.com/docs/en/models/overview), [Gemini Models](https://ai.google.dev/gemini-api/docs/models) e [Gemini Image Generation](https://ai.google.dev/gemini-api/docs/image-generation). Nomes e preços mudam; o catálogo da API não prova que o mesmo ID funciona por OAuth. Há diferenças a resolver por prova real: o OAuth OpenAI do app lista GPT-6.1 Sol/Terra/Luna, não GPT-6 Astra; o código lista `claude-fable-5`, enquanto a página atual da Anthropic apresenta Fable 5.1; e a lista Gemini do app inclui 3.6 Flash, enquanto o catálogo público já apresenta Gemini 3.8 Flash. Os conjuntos de Gemini API e Gemini OAuth também diferem. Não atualizar o seletor apenas pelo catálogo público: confirmar disponibilidade, modalidade e uma resposta real em cada rota antes.

No iOS, o [Apple Foundation Models](https://developer.apple.com/documentation/FoundationModels/) inclui sumarização e geração estruturada local. A documentação recomenda verificar o idioma com `supportsLocale(_:)` ([idiomas e locales](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)). No app Flutter isso exigiria integração nativa Swift e validação em dispositivo compatível. No Android, o [ML Kit GenAI Summarization](https://developers.google.com/ml-kit/genai/summarization/android) é beta, aceita até 4.000 tokens e lista inglês, japonês e coreano; portanto, hoje não é candidato para resumo local em pt-BR. A disponibilidade também varia por aparelho e deve ser verificada em execução.

Para imagens, a documentação atual da [OpenAI](https://developers.openai.com/api/docs/guides/image-prompting) recomenda testar a mesma composição nos modelos de detalhe e rapidez e inspecionar cada resultado. A [Google](https://ai.google.dev/gemini-api/docs/image-generation) descreve Nano Banana Pro para instruções visuais complexas e produção de assets. Para F10, ambos são opções de ilustração sujeitas à prova de acesso por login. Dados, eixos, valores, legendas e citações continuam elementos vetoriais/textuais produzidos a partir dos dados conferidos; não confiar ao gerador a escrita de números ou a evidência do documento.

#### Protocolo inicial para escolher modelo e prompt

1. Montar um conjunto piloto de casos sintéticos ou desidentificados que cubra conversa curta, conversa com divergência, reunião/transcrição longa, PDF digital, PDF escaneado/OCR, tabela/números e síntese de fontes múltiplas. Para cada caso, registrar fatos essenciais, localização da fonte (página, comentário ou trecho), incertezas e inferências proibidas.
2. Executar os mesmos casos, prompt, idioma, configuração e rota real do app em cada modelo. Repetir casos difíceis para observar variação. Comparar os resultados sem identificar o modelo ao revisor.
3. Aplicar falha crítica se houver número/data errados, afirmação sem apoio, citação incorreta, divergência apagada ou sugestão convertida em decisão. Para os casos restantes, avaliar fidelidade/cobertura, manutenção de escopo e incerteza, clareza em pt-BR, adequação ao público e ao tamanho pedido, estrutura e utilidade do gráfico.
4. Registrar também latência, tokens de entrada/saída, custo quando aplicável e erros da rota. Escolher o modelo mais econômico que passe os critérios críticos e produza melhor resultado útil, não o que tenha maior janela de contexto ou pontuação genérica.
5. Usar comparação humana cega como decisão principal. Um avaliador LLM pode ajudar a filtrar muitos resultados, mas deve ser calibrado contra avaliações humanas; a orientação da OpenAI alerta para viés de posição e preferência por respostas mais longas.

Esse protocolo é uma recomendação para a próxima avaliação, não foi executado nesta pesquisa. O conjunto deve permanecer local e usar dados sintéticos/desidentificados; políticas de API não devem ser presumidas para rotas OAuth de consumidor.

#### Tipografia, figuras e acessibilidade visual (2026-11-09)

- A [Apple HIG de escrita](https://developer.apple.com/design/human-interface-guidelines/writing) favorece a informação principal primeiro, linguagem simples e divisão de ideias. A [escala tipográfica Material 3](https://m3.material.io/styles/typography/applying-type) separa funções de título, rótulo e corpo e recomenda corpo confortável em passagens longas. São orientações de interface; não definem tamanhos universais em pontos para impressão. Aplicação: manter uma hierarquia estável, corpo simples e legível, e não escolher tamanhos de impressão copiando tokens de tela.
- A [APA Style](https://apastyle.apa.org/style-grammar-guidelines/tables-figures) define tabelas como organização de texto e valores em linhas/colunas e figuras como gráficos e outras ilustrações; ambos devem ajudar a compreensão e ser claros, consistentes e acessíveis. Aplicação: quando os valores exatos importam, conservar os números em texto ou tabela além da figura.
- O [guia de figuras da Nature](https://research-figure-guide.nature.com/figures/preparing-figures-our-specifications/) pede eixos com marcas e unidades, paleta acessível, rótulos legíveis e sem sobreposição, e prefere elementos vetoriais editáveis para arte final editorial. As especificações de fonte de 5–7 pt e resolução de 450 dpi pertencem à publicação de figuras científicas; não são uma regra universal para PDFs A4. O gráfico atual é PNG de 2016 × 1134, cerca de 309 pixels por polegada no espaço de 470 pt: supera a referência de 300 ppi da [Adobe para impressão de alta qualidade](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/resize-adjust-resolution/resolution-specs-for-printing-images.html), mas fica abaixo da especificação Nature; continua raster e vetor é a melhoria para ampliar e para submissão editorial.
- A WCAG 2.2 usa contraste mínimo de 4,5:1 para texto comum, 3:1 para texto grande e 3:1 para objetos gráficos necessários à compreensão ([texto](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html), [gráficos](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html)). Esses valores são alvos visuais úteis; sozinhos não certificam um PDF.
- A ordem de leitura descrita pelo [W3C PDF3](https://www.w3.org/WAI/WCAG22/Techniques/pdf/PDF3.html) depende da estrutura marcada; a [orientação da Adobe](https://helpx.adobe.com/acrobat/using/creating-accessible-pdfs.html) também recomenda idioma, texto alternativo, marcação e verificação com tecnologia assistiva. O exportador atual não produz tags estruturais nem foi validado com leitor de tela; não há declaração de PDF/UA ou conformidade WCAG.

Aplicação no código nesta rodada: o gráfico reserva margem acima/abaixo dos valores extremos, posiciona valores negativos depois do fim da barra, usa vírgula decimal no idioma português e acrescenta a série de dados em texto com a unidade. O PDF recebe título a partir do primeiro cabeçalho e o criador “Segunda Mente”. Tabelas Markdown simples agora viram tabela formatada no PDF e no DOCX, com alinhamento e cabeçalho repetível; barras verticais escapadas dentro da célula ainda não são interpretadas. Mantive o tamanho de corpo atual porque as fontes consultadas não sustentam um tamanho impresso único. Vetores e marcação acessível seguem como trabalho futuro.

### Rodada 3 de pesquisa: composição, acessibilidade real e resumos fiéis (2026-11-09)

Só pesquisa e documentação: nenhum código, dependência, prompt, PDF final, teste ou build foi tocado. Cada link abaixo foi aberto nesta rodada, exceto onde indicado como "não reaberto". Classes: **universal** (vale sem depender do contexto), **contextual** (vale para um público ou tarefa) e **hipótese** (testar antes de adotar).

#### Verificado no código e no pacote fixado (`pdf` 3.12.0, `pubspec.lock`)

- `lib/domain/models/session_report_export.dart`: A4, margens 60/64/60/56 pt, corpo 10,5 pt Inter, entrelinha extra de 3,5 pt, títulos 24/15/12,5 pt, rodapé 8 pt "página / total". Tabela com `repeat: true` só na linha 0. Gráfico como `MemoryImage` (PNG).
- Busca no código-fonte do pacote instalado (`pdf-3.12.0/lib` no cache do pub): **nenhuma ocorrência** de `StructTreeRoot`, `StructElem`, `MarkInfo`, `/Lang` ou `/Alt`. O changelog do pacote (em [pub.dev](https://pub.dev/packages/pdf/changelog), que lista a 3.13.1 como a mais recente) não cita PDF marcado, PDF/UA ou idioma. Existe PDF/A-3b (`pdfa_*`, 3.11.2) e `Document(metadata: XmlDocument)` para XMP, mas PDF/A não implica PDF/UA. A issue [dart_pdf #472 "Accessibility Support"](https://github.com/DavBfr/dart_pdf/issues/472) trata de TalkBack no `PdfPreview`; o mantenedor respondeu "com algum trabalho, deve ser possível" e a fechou em 2022; em 2024 alguém perguntou como adicionar tags, sem resposta visível. Conclusão: **o PDF gerado hoje não é marcado, não declara idioma e não tem texto alternativo; adotar a 3.13.1 não mudaria isso** (o changelog também diz que ela exige Dart 3.12, não conferido contra o Flutter do projeto).
- DOCX: há cabeçalho de tabela (`<w:tblHeader/>`, linha 517). Não encontrei estilos de título (`pStyle`), `w:lang` nem `docProps` (título/autor); o texto alternativo da imagem (`descr`) recebe o texto entre colchetes do Markdown (`![alt](…)`), que o gerador de gráficos preenche com o título e o de fotos com a legenda; só sem esse texto cai no nome do arquivo (correção feita depois de reler o gerador). Confirmar abrindo o DOCX no Word; por leitura do código, títulos e idioma não estão declarados.
- Medidas que calculei (reproduzíveis): x-height da Inter = 1118/2048 = 0,546 em, ou 5,7 pt a 10,5 pt; largura média num trecho em português ≈ 0,495 em, o que dá **cerca de 91 caracteres por linha** nos 475 pt úteis. Contraste sobre branco (fórmula WCAG): texto `#1F2937` 14,7:1; títulos `#1F4E79` 8,7:1; rodapé `#6B7280` 4,8:1; barra `#3F6FD1` 4,8:1; eixos `#888888` 3,5:1; filete cinza `#BDBDBD` 1,9:1 (decorativo).

#### Recomendações

| # | Afirmação e aplicação ao Segunda Mente | Fonte primária | Tipo e limites | Classe |
|---|---|---|---|---|
| 1 | O corpo de 10,5 pt Inter (x-height ≈ 0,29° a 40 cm) está dentro da faixa de leitura fluente (≈ 0,2° a 2°) e acima do tamanho crítico (≈ 0,2°); não há base para impor um "tamanho universal". Manter; se mudar, comparar 10,5 e 11 pt em impressão e no S25. | [Legge & Bigelow, J. Vision 2011](https://doi.org/10.1167/11.5.8) (texto lido no PDF da [UMN](https://legge.dl8.umn.edu/sites/legge.psych.umn.edu/files/2020-08/Legge%20Bigelow%202011%20Does%20size%20matter%20for%20reading%3F%20A%20review%20of%20findings%20from%20vision%20science%20and%20typography.pdf)) | Revisão de psicofísica e tipografia; leitores de visão normal, 40 cm; mede velocidade, não conforto nem compreensão. A faixa é ampla (fator 10), logo não decide entre 10 e 12 pt. | Universal (piso); valor exato é hipótese |
| 2 | ~91 caracteres por linha passa de 80. Testar margens laterais maiores ou corpo 11 pt para chegar perto de 70–80. A WCAG exige apenas que o *usuário possa* limitar a 80 caracteres, desligar justificação e ter entrelinha 1,5 e parágrafos 1,5× a entrelinha; o conteúdo não é obrigado a usar esses valores. | [WCAG 2.2 SC 1.4.8](https://www.w3.org/WAI/WCAG22/Understanding/visual-presentation) | Norma de acessibilidade web, nível AAA; não é regra de impressão nem estudo de leitura. Medir a entrelinha real no PDF antes de ajustar. | Contextual; mudança = hipótese |
| 3 | Contraste: texto ≥ 4,5:1 e elementos gráficos necessários ≥ 3:1. O estado atual cumpre (menores: rodapé 4,8:1, eixos 3,5:1). Não clarear cinzas de texto. | [Contrast (Minimum)](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html), [Non-text Contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html) | Critérios para telas; em papel o contraste real depende da impressora. Os números acima são cálculo meu, não medição. | Universal como alvo; não certifica o PDF |
| 4 | Paleta: ao introduzir várias séries, usar paleta segura para daltonismo (Okabe-Ito/Wong) e não depender só de cor (marcas, rótulos diretos). Hoje há série única. Testar em escala de cinza. | [Wong, "Color blindness", Nature Methods 8:441 (2011)](https://www.nature.com/articles/nmeth.1618) | **Não reaberto**: a página exigiu login; a citação veio de resultados de busca. Fonte editorial, não experimento. | Contextual; confirmar o texto antes de citar como regra |
| 5 | O PNG de 2016 × 1134 em 470 pt (≈ 309 ppi) fica na faixa de 300–600 dpi pedida pelo PLOS. Vetor continua melhor para ampliar e imprimir. Caminho de menor risco no PDF: desenhar barras e textos com o canvas do próprio `pdf` (vetor, texto selecionável, Inter já embutida), em vez de SVG, que precisa de fonte própria para texto (changelog 3.11.2) e seria mais um caminho a validar. O DOCX seguiria com PNG. | [PLOS ONE, figuras](https://journals.plos.org/plosone/s/figures); [Nature, preparo de figuras](https://research-figure-guide.nature.com/figures/preparing-figures-our-specifications/); [`SvgImage` do pacote](https://pub.dev/documentation/pdf/3.12.0/widgets/SvgImage-class.html) | Regras de submissão de revistas (TIFF/EPS e 8–12 pt no PLOS; 5–7 pt na Nature), não padrão de PDF A4. Canvas e `SvgImage` só foram lidos, não executados. | Contextual; vetor = hipótese |
| 6 | Valores exatos: manter números em texto ou tabela junto do gráfico. Gráfico ajuda a comparar; tabela ajuda a consultar. | [APA, tabelas e figuras](https://apastyle.apa.org/style-grammar-guidelines/tables-figures); [Gelman, Pasarica & Dodhia, Am. Stat. 56 (2002)](https://ideas.repec.org/a/bes/amstat/v56y2002mmayp121-130.html) | Guia editorial e artigo analítico (só o resumo foi lido). O debate tabela×gráfico é aberto; Tufte defende tabelas para poucos dados, segundo uma [coluna do Stata Journal](https://ageconsearch.umn.edu/record/122591/files/sjart_gr0034.pdf) (citação secundária). | Contextual |
| 7 | Legenda curta e informativa junto da figura e fora da imagem, como já é hoje. | [PLOS ONE, legendas](https://journals.plos.org/plosone/s/figures) (título ≤ 15 palavras, legenda logo após); [Nature Portfolio](https://www.nature.com/nature-portfolio/for-authors/write) | Regras de revista; o limite de 15 palavras é do PLOS e não deve virar regra do app. | Contextual |
| 8 | Paginação: o pacote não tem controle de viúvas/órfãs nem "manter título com o próximo" (nenhum termo em `text.dart`/`multi_page.dart`). `Inseparable` mantém um bloco inteiro na mesma página e só serve para blocos curtos: aplicar a título + primeiro parágrafo curto, gráfico + legenda e tabela curta. `repeat` já repete o cabeçalho de tabela; falta provar a quebra de linhas entre páginas. | [`MultiPage`/`Inseparable`](https://pub.dev/documentation/pdf/3.12.0/widgets/MultiPage-class.html) (e código lido localmente) | Fonte técnica oficial; comportamento real só com PDF renderizado. Não encontrei estudo experimental que defina regras de viúva/órfã; é prática editorial. | Hipótese a testar |
| 9 | PDF acessível exige estrutura marcada (ordem de leitura), idioma, `/Alt` na tag Figure e tabelas semânticas; aparência não prova conformidade. O pacote 3.12.0 não oferece isso. Opções: (a) declarar a limitação e oferecer DOCX/Markdown como formatos assistivos; (b) corrigir o DOCX; (c) só depois estudar gerar a estrutura marcada (objetos PDF à mão sobre o pacote, ou outro motor) e validar. | [WCAG PDF1 (Alt)](https://www.w3.org/WAI/WCAG22/Techniques/pdf/PDF1.html); [PDF3 (ordem de leitura)](https://www.w3.org/WAI/WCAG22/Techniques/pdf/PDF3.html); [Matterhorn Protocol 1.1](https://taggedpdfschool.pdfa.org/matterhorn) (31 pontos de verificação, 136 condições de falha, 47 com verificação humana); [Adobe](https://helpx.adobe.com/acrobat/using/creating-accessible-pdfs.html) (não reaberto: 403) | Técnicas do W3C e protocolo da PDF Association são oficiais; dizem o que verificar, não medem o benefício para leitores de tela. A contagem 87/47 vem da página, com 2 condições sem teste. | Universal (requisitos); caminho (c) = alto risco |
| 10 | DOCX: títulos nos estilos internos, cabeçalho de tabela, texto alternativo descritivo que não repita o texto ao redor, e rodar o verificador de acessibilidade do Word. O app já marca o cabeçalho da tabela. | [Microsoft, documentos Word acessíveis](https://support.microsoft.com/en-us/office/make-your-word-documents-accessible-to-people-with-disabilities-d9bf3683-87ac-47ea-b91a-78dcacb3c66d) | Orientação de fornecedor para quem escreve no Word; não trata de arquivos gerados por programa (que se aplique é inferência minha). Não executado no arquivo do app. | Contextual |
| 11 | Resumo fiel: exigir que cada afirmação importante aponte para o trecho ou a página da fonte e conferir depois, porque citações de modelos falham com frequência. | [Gao et al., ALCE, EMNLP 2023](https://aclanthology.org/2023.emnlp-main.398) | Benchmark de perguntas e respostas (ASQA, QAMPARI, ELI5), inglês, modelos de 2023: o melhor sistema no ELI5 não tinha suporte completo em cerca de metade dos casos. Não é resumo de conversa em pt-BR. | Contextual; testar com o protocolo da rodada 2 |
| 12 | Alucinação: todos os resumos avaliados tinham conteúdo não suportado; entailment correlacionou melhor com fidelidade que ROUGE. Justifica falha crítica por afirmação sem apoio. | [Maynez et al., ACL 2020](https://aclanthology.org/2020.acl-main.173/) | Modelos pré-LLM, notícias em inglês (só o resumo foi lido). Valor para a métrica, não para os modelos atuais. | Contextual |
| 13 | Fatos atômicos: dividir o resumo em afirmações curtas e checar cada uma contra a fonte. Para o app, serve como lista de verificação humana por amostra. | [Min et al., FActScore, EMNLP 2023](https://aclanthology.org/2023.emnlp-main.741/) | Biografias com fonte fixa; só o resumo foi lido. Mede precisão, não omissões. | Contextual |
| 14 | Entrada longa: modelos usam pior o meio do contexto; em livros, resumos omitem pontos cruciais, pesam demais o final, e avaliadores LLM correlacionaram mal com humanos. Conferir o que ficou de fora em conversas/PDFs longos e não confiar só em juiz LLM. | [Liu et al., "Lost in the Middle", TACL 2024](https://aclanthology.org/2024.tacl-1.9/); [Kim et al., FABLES (2024)](https://arxiv.org/abs/2404.01261) | Perguntas multidocumento e 26 livros de ficção em inglês (3.158 afirmações); modelos de 2023–24, que podem ter mudado. | Contextual; hipótese para os modelos do app |
| 15 | Incerteza: hedges em primeira pessoa ("não tenho certeza, mas…") reduziram a dependência de respostas erradas. Manter incerteza e divergência explícitas no texto em vez de arredondar para uma conclusão. | [Kim et al., FAccT 2024](https://arxiv.org/abs/2405.00623) | Experimento pré-registrado, 404 pessoas, perguntas médicas, busca fictícia; a forma geral ("não está claro") não teve efeito significativo. Não prova melhor qualidade de resumo. | Contextual |

**Fornecedor × evidência independente:** Apple HIG, Material 3, OpenAI/Gemini/Anthropic (rodada 2), Adobe e Microsoft são orientação de fornecedor sobre seus produtos. W3C/WCAG, PDF Association, Cochrane, PRISMA, APA e regras da Nature/PLOS são normas ou regras editoriais públicas. Legge & Bigelow, Maynez, Gao, Min, Liu, Kim e Peters (rodada 2) são estudos revisados por pares; nenhum testa documentos em pt-BR gerados por este app.

#### Melhorias priorizadas

| Prioridade | Melhoria | Benefício | Esforço | Risco |
|---|---|---|---|---|
| 1 | DOCX: títulos nos estilos do Word, idioma declarado, propriedades (título/autor) e `descr` das imagens = legenda/resumo dos dados | Acessibilidade verificável no Word | Baixo | Baixo (XML coberto por teste de arquivo) |
| 2 | Avisar na exportação que o PDF atual não é marcado para leitor de tela e que DOCX/MD são o caminho assistivo | Honestidade e uso correto | Baixo | Baixo |
| 3 | Rubrica de fidelidade (fatos atômicos, referência por trecho/página, incerteza e divergência, falha crítica) com amostra humana cega, usando o protocolo da rodada 2 | Maior ganho de qualidade e segurança do conteúdo | Médio | Baixo |
| 4 | Manter título com o próximo bloco, gráfico com legenda e tabela curta inteira (`Inseparable`) | Menos títulos órfãos e gráficos cortados | Baixo a médio | Médio: blocos grandes podem deixar páginas vazias |
| 5 | Medir e testar largura de linha (margens/11 pt) e entrelinha real | Leitura mais confortável | Baixo | Baixo; repagina todos os PDFs |
| 6 | Gráfico vetorial no PDF pelo canvas do `pdf` | Nitidez na ampliação e impressão | Médio | Médio; DOCX segue em PNG |
| 7 | Estrutura marcada no PDF (ordem, idioma, `/Alt`, tabelas) | Único caminho para PDF/UA | Alto | Alto: sem suporte no pacote; exige PAC/veraPDF e leitor de tela |
| 8 | Tratar `\|` escapado, links, itálico e listas aninhadas | Fidelidade de conteúdo | Médio | Baixo a médio |

#### O que vale testar em amostras sintéticas

1. **Tabelas longas** (60+ linhas, 6 colunas, células de 3 linhas, números à direita): cabeçalho repetido, linha que quebra entre páginas, tabela logo após título, pt-BR e en.
2. **Gráficos**: todos negativos, mistos, zeros, um valor 100× maior, rótulos longos, vírgula/ponto por idioma, impressão em preto e branco; PNG atual contra vetor com zoom de 400%.
3. **Texto**: parágrafo de uma página, título no pé da página, lista longa, acentos, aspas curvas, URL longa, dois idiomas no mesmo arquivo.
4. **Impressão**: A4 em impressora doméstica a 100% e 85% (10,5 e 11 pt), leitura a 40 cm; no S25 em tamanho de tela.
5. **Leitura assistiva**: PDF e DOCX no verificador do Word/Acrobat, PAC e veraPDF (PDF/UA-1), TalkBack no S25 e NVDA no Windows; registrar o que é lido, em que ordem e o que falta.
6. **Resumos**: protocolo da rodada 2 mais divergência entre falantes, número que muda entre trechos, "talvez", tabela de números e fato colocado no meio de uma entrada longa.

#### Lacunas que dependem de aparelho ou de pessoa

- Nenhum PDF foi aberto em leitor de tela, PAC ou veraPDF; o Word não verificou o DOCX; nada foi impresso.
- A tabela no PDF ainda precisa de inspeção visual, e a entrelinha real precisa do PDF renderizado.
- Wong 2011 e a página da Adobe não puderam ser relidos (login/403); Gelman et al., Maynez, FActScore, Liu e FABLES foram lidos só até o resumo.
- Qualidade de resumo em pt-BR com os modelos e rotas do app depende de avaliação humana cega.

#### Estado

F10-05 segue `IN_PROGRESS` e F10-06 `BLOCKED`. Esta rodada não alterou código, testes, prompts nem dependências. Próxima ação recomendada: item 1 (DOCX) e item 3 (rubrica de fidelidade), ambos de baixo risco; depois decidir com o dono se vale investir em PDF marcado.

### Implementado depois da rodada 3 (2026-11-09)

- DOCX: títulos usam os estilos `Heading 1–3` (com `outlineLvl`), `word/styles.xml` declara o idioma (`pt-BR` ou `en-US`, vindo de `languageCode`, que `thread_document_service` preenche com o idioma do app) e `docProps/core.xml` traz título, autor e idioma. Teste: `docx declares heading styles, language and document properties`.
- PDF: `keepTogetherGroups` mantém título ou imagem junto do texto curto (≤ 300 caracteres) que vem depois, via `pw.Inseparable`; texto longo nunca é agrupado. Teste de agrupamento e de geração. Isso é hipótese de paginação: falta olhar um PDF com títulos no fim da página.
- Aviso de PDF sem marcação: chave `exportPdfNotTagged` (pt/en) no item PDF do menu do documento e sob os botões do relatório da sessão, com teste de widget nos dois.
- Não feito: largura de linha, gráfico vetorial, PDF marcado, rubrica de fidelidade (precisa de avaliação humana). Testes focados passaram (32); suíte completa, build e abertura no Word/leitor de tela seguem `NOT_RUN`.

### Rodada 4: relatórios, resumos e estilos de design profissionais (2026-11-09)

Pesquisa e documentação; nenhuma decisão de estilo foi aplicada no código. Links abertos nesta rodada, salvo indicação. Classes: universal, contextual, hipótese.

| # | Afirmação e aplicação ao Segunda Mente | Fonte | Tipo e limites | Classe |
|---|---|---|---|---|
| 1 | **Abrir com a conclusão e o motivo.** O GAO publica cada relatório com uma página de destaques (o que foi encontrado, por que o estudo foi feito, recomendações) antes do texto de 85 páginas, e uma tabela de recomendações com situação. Para o app: todo documento começa por 3–5 linhas "o que importa", seguidas dos achados; recomendações e pendências em tabela com situação (confirmado, hipótese, pendente). | [GAO-24-106342](https://www.gao.gov/products/gao-24-106342) (exemplo de órgão de auditoria) | Prática institucional observada em um relatório, não estudo; mostra um modelo, não prova eficácia. | Contextual |
| 2 | **Leitores varrem o texto.** Num teste de 1997, 79% varriam páginas novas e 16% liam palavra por palavra; versões concisa, escaneável e objetiva tiveram usabilidade melhor (58%, 47% e 27%; 124% combinadas). Para o app: títulos descritivos, um assunto por parágrafo, listas curtas, linguagem neutra, sem texto promocional. | [Nielsen, "How Users Read on the Web" (NN/g, 1997)](https://www.nngroup.com/articles/how-users-read-on-the-web/) | Estudo de usabilidade de uma empresa de pesquisa, sobre páginas web de turismo em 1997; não é relatório impresso nem revisado por pares. | Contextual |
| 3 | **Resumo estruturado ajuda, com ressalvas.** Resumos com seções fixas costumam trazer mais informação e ser julgados mais legíveis, mas ficam ~21% mais longos, a vantagem de busca não se repetiu em resumos reais, e não se sabe se são mais exatos. Para o app: seções fixas curtas (contexto, achados, limites, próximos passos) só em documentos longos; não impor a estrutura a notas curtas. | [Hartley, J Med Libr Assoc 2004;92(3)](https://pmc.ncbi.nlm.nih.gov/articles/PMC442180) | Revisão de estudos, muitos com estudantes e resumos reescritos pelos pesquisadores; artigos científicos, não conversas. | Contextual |
| 4 | **Tabela para comparar e consultar:** legenda que funciona como título, cabeçalhos com escopo de coluna/linha, números alinhados à direita (cabeçalho também), tabelas grandes divididas. O PDF e o DOCX atuais já alinham colunas e repetem o cabeçalho; falta legenda semântica. | [GOV.UK Design System, Table](https://design-system.service.gov.uk/components/table/) | Sistema de design de governo para web; regras de interface, não estudo. | Contextual |
| 5 | **Escolher o gráfico pela relação** (desvio, ranking, tempo, parte-do-todo, magnitude…), colunas de magnitude partindo de zero, pizza com cuidado, destacar e anotar o ponto de interesse. O gráfico atual é de barras e já parte de zero com negativos; para valores no tempo, linha seria o próximo tipo; evitar pizza. | [Financial Times Visual Vocabulary](https://github.com/Financial-Times/chart-doctor/tree/main/visual-vocabulary) | Guia editorial de uma redação; não é experimento. | Contextual |
| 6 | **Percepção gráfica é mensurável.** Heer e Bostock replicaram estudos clássicos de codificação espacial e de contraste de luminância com participantes online e acrescentaram testes de área, tamanho do gráfico e espaçamento de grade. Sustenta testar o gráfico com pessoas em vez de decidir só por gosto. | [Heer & Bostock, CHI 2010](https://hci.stanford.edu/publications/paper.php?id=142) | Só o resumo e metadados foram lidos (via busca); o ranking de codificações **não** foi conferido. Participantes de plataforma de microtarefas. | Hipótese a testar |
| 7 | **Enfeite não é regra.** Gráficos com ilustração não pioraram a compreensão e melhoraram a lembrança após mais de 12 dias, mas os autores não recomendam o estilo em geral. Para o app: gráficos sóbrios; ilustrações geradas (05c) como complemento, nunca como evidência. | [Bateman et al., CHI 2010](https://bibtex.github.io/CHI-2010-BatemanMGGMB.html) (metadados); resultados por resumos secundários | Poucos participantes (cerca de 20, em relato secundário) e gráficos de um só ilustrador; texto completo não lido. | Hipótese a testar |
| 8 | **Investir no visual.** O autor defende dedicar tempo a gráficos que comuniquem e persuadam, em vez de usar o padrão do software. | [Schwabish, J Econ Perspectives 28(1), 2014](https://www.aeaweb.org/articles?id=10.1257/jep.28.1.209) | Só o resumo foi lido; ensaio normativo para economistas. | Contextual |
| 9 | **Paleta de gráfico curada**, ordem fixa das cores, evitar gradientes múltiplos. | [IBM Carbon, Color palettes](https://carbondesignsystem.com/data-visualization/color-palettes/) | Sistema de design de fornecedor, em andamento; a página não trata de contraste numérico nem de não depender só de cor. | Contextual |

**Páginas que não deram o conteúdo pedido:** o índice de [Digital.gov Plain Language](https://digital.gov/guides/plain-language) e o de [diretrizes de escrita do GOV.UK](https://guidance.publishing.service.gov.uk/writing-to-gov-uk-standards/writing-guidelines/) só listam subpáginas ("Escreva resumos claros", "Estrutura clara"); a página de tipografia do GOV.UK deu 404 e a Nature exigiu login. Próxima leitura, se valer o esforço: essas subpáginas.

#### Estilo de design: o que se repete nas fontes

Relatórios institucionais (GAO, GOV.UK, FT) convergem em: hierarquia tipográfica curta e estável (título, seção, corpo, legenda), conclusão antes dos detalhes, tabelas e gráficos com legenda e fonte, cor com função (destaque, estado) e não decoração, e poucos ornamentos. Isso coincide com o PDF atual (Inter, um acento azul `#1F4E79`, filetes finos). **As fontes lidas não mostram que um estilo específico (editorial, suíço, corporativo) produza melhor compreensão**; a escolha é de identidade. Proposta como hipótese para decidir com o dono: um modelo único sóbrio, com poucas variações de proporção (resumo de uma página, relatório com tabela, relatório ilustrado), em vez de vários temas.

#### Aplicações possíveis (nada feito)

1. Prompt do escritor: bloco "o que importa" nas primeiras linhas e quadro "o que ainda é incerto" no fim, só em documentos longos.
2. Tabela de recomendações/pendências com coluna de situação e fonte.
3. Legenda e fonte sob cada gráfico/tabela, dizendo de onde vêm os números.
4. Teste pequeno com pessoas: o mesmo relatório com e sem bloco inicial e perguntas de compreensão; é hipótese até medir.

Limites: as fontes são práticas e estudos em inglês sobre web e artigos; nenhuma avalia relatórios do app em português. F10-05 segue `IN_PROGRESS`.

### Teste de prompt e três PDFs de exemplo (2026-11-09)

Variante B proposta para o prompt do escritor (**não aplicada ao código**): em documentos mais longos que uma página, abrir com o bloco "O que importa" (3–5 linhas, no idioma do documento) e fechar com "Ainda incerto" só se houver incerteza; recomendações e pendências em tabela (Item | Situação | Fonte); notas curtas sem bloco.

Como foi testado: três casos sintéticos em português (hospedagem curta; relatório trimestral em PDF com tabela e gráfico com valor negativo; divergência entre duas personas), cada um escrito na versão A (prompt atual) e na B. **Os textos foram escritos por mim, Claude, seguindo cada prompt; não foram gerados pelos modelos do app**, então o teste não mede o comportamento real deles. Um verificador mecânico confere título, citações `[c:ID]`/`[p.N]` existentes, números e valores de gráfico presentes na fonte, bloco de 3–5 linhas nos longos e ausência de bloco nos curtos: A e B passaram nos três casos. O verificador não detecta erro de sentido, só estrutura e números.

Achados: (1) o bloco "O que importa" repete conteúdo que vem logo abaixo; nos exemplos de 145 e 190 palavras isso é redundante, então a regra precisa de um limite explícito (por exemplo, acima de uma página, ~400 palavras) e não de "mais longo que uma página" solto; os exemplos o usam abaixo desse limite só para mostrar o estilo. (2) A diferença real foi achada na renderização: o título "Variação por produto" ficava sozinho no fim da página 1 porque `keepTogetherGroups` só juntava título com texto; passou a juntar título com figura (mais até 3 linhas de legenda) ou tabela curta (≤ 8 linhas). Teste novo; o título agora vai para a página 2 com o gráfico.

Exemplos (fora do repositório): `exemplo_1B.pdf`, `exemplo_2B.pdf`, `exemplo_3B.pdf` em `C:\Users\notefael\AppData\Local\Temp\claude\204253db9b046894\21504dea-0558-45dd-89f3-4c5024950b52\scratchpad\out\`, com os textos em `...\scratchpad\cases\` (A, B e fonte). Páginas conferidas como imagem; leitor de tela e impressão não.

### Rodada 5: PDFs mais bonitos — estudo de design (2026-11-09)

Estudo e proposta; nenhum código foi alterado. Base visual: os três PDFs de exemplo da rodada 4 (página inspecionada como imagem) e medidas feitas no PDF gerado.

#### O que a evidência permite dizer sobre "beleza"

| Afirmação | Fonte | Tipo e limites | Classe |
|---|---|---|---|
| A aparência percebida tem duas dimensões distinguíveis: **clássica** (ordem, clareza) e **expressiva** (criatividade, quebra de convenção). Para um relatório, o que se busca é a clássica. | [Lavie & Tractinsky, Int. J. Human-Computer Studies 60(3), 2004](https://www.ise.bgu.ac.il/faculty/noam/research/aesthetics.html) (resumo lido via busca) | Quatro estudos com páginas web; escala de percepção, não desempenho. | Contextual |
| Em 285 pessoas, a estética percebida de 11 técnicas de visualização correlacionou com abandono da tarefa e tempo de erro; o texto pede mais peso à estética ao avaliar visualizações. | [Cawthon & Vande Moere, IEEE IV 2007](https://researchr.org/publication/CawthonM07) (só resumo via busca) | Correlação, levantamento online; uma crítica diz que a visualização mais bonita também era a que mais funcionava. Não prova que embelezar melhora o resultado. | Hipótese |
| Julgamentos de apelo visual de páginas web ficam estáveis já com 50 ms de exposição e batem com os feitos depois de mais tempo. Implica que a **primeira página** pesa na impressão de qualidade. | [Lindgaard et al., Behaviour & IT 25, 2006](https://dblp.uni-trier.de/rec/journals/behaviourIT/LindgaardFDB06.html) | Páginas web, não PDFs; mede apelo visual, não confiança no conteúdo (divulgação popular exagera). | Contextual |
| Corpo de 10–12 pt, entrelinha de 120–145% do corpo, 45–90 caracteres por linha, 4–10 pt entre parágrafos sem recuo, só um dos dois. | [Butterick, Summary of key rules](https://practicaltypography.com/summary-of-key-rules.html) | Guia de profissional, não experimento. | Contextual |
| Margens definem o comprimento da linha; para tipo menor, margens maiores; margem inferior um pouco maior que a superior evita aparência de "afundar". Margens maiores não reduzem a legibilidade. | [Butterick, Page margins](https://practicaltypography.com/page-margins.html) | Guia de profissional. | Contextual |
| No máximo 3 níveis de título (2 é melhor); aumentos pequenos de tamanho; negrito em vez de caixa-alta; ênfase principal vem do **espaço** acima e abaixo; manter título com o texto seguinte. | [Butterick, Headings](https://practicaltypography.com/headings.html) | Guia de profissional. | Contextual |
| Tabela: remover bordas e devolver só as que ajudam; aumentar a margem das células é a melhor melhoria para tabela densa. | [Butterick, Tables](https://practicaltypography.com/tables.html) | Guia de profissional; a página não trata de alinhamento nem sombreamento. | Contextual |
| Cor com restrição ("quando tudo é enfatizado, nada é"), vários tons de uma cor funcionam melhor que várias cores; se o PDF puder ser impresso, evitar corpo em cinza. | [Butterick, Color](https://practicaltypography.com/color.html) | Guia de profissional. | Contextual |

Não achei estudo experimental que prove que um estilo de relatório específico seja "mais bonito" ou mais eficaz; as regras acima são consenso profissional e as de legibilidade das rodadas anteriores. Material 3 e Economist não deram conteúdo utilizável (página vazia e bloqueio), então não entram.

#### Diagnóstico do PDF atual (medido e visto)

- Entrelinha 16,2 pt sobre corpo de 10,5 pt = **154%**, acima da faixa de 120–145%; linha com ~91 caracteres (acima de 90). Ou seja, texto largo e solto; margens maiores e entrelinha ~140% aproximariam das faixas (hipótese a testar em papel).
- A caixa "O que importa" é só um título e marcadores: sem painel nem destaque, parece mais um trecho comum.
- O texto fixo sob cada gráfico ("Gráfico gerado no aparelho com números do próprio fio.", "Dados representados…", "Fonte…") tem o mesmo peso do corpo e repete o título que já está no gráfico e no cabeçalho de seção.
- Citações `[p.2]`, `[c:c1]` aparecem cruas no meio da frase, com o mesmo peso do texto.
- Todas as barras têm a mesma cor, inclusive a negativa; o título do gráfico aparece dentro da imagem e de novo no cabeçalho da seção.
- Sem bloco de identificação no topo (tipo de documento, data, origem, versão); só título e filete. Rodapé só com "n / N".
- Pontos positivos: hierarquia curta (3 níveis), um único acento, filetes finos em tabela e contraste alto.

#### Proposta de melhorias, em ordem de benefício sobre esforço

| # | Mudança | Por quê | Esforço | Risco |
|---|---|---|---|---|
| 1 | **Painel "O que importa"**: fundo azul muito claro, barra de acento à esquerda, corpo 11 pt. Convenção Markdown: citação `>` vira painel (o parser hoje não a conhece). | Hierarquia pela forma, não por mais negrito; a primeira página pesa (Lindgaard); GAO usa uma página de destaques. | Médio (parser + PDF + DOCX) | Baixo; falta definir como fica no DOCX |
| 2 | **Citações discretas**: `[p.2]`, `[c:c1]` em cinza `#6B7280`, 8,5 pt, sem alterar o texto. | Reduz ruído e mantém a rastreabilidade. | Baixo | Baixo; contraste do cinza é 4,8:1 |
| 3 | **Legenda única** sob o gráfico: "Figura 1. título. Fonte: [p.2]. Valores: T1 120 · T2 135…" em cinza, 9 pt; remover o título duplicado de dentro da imagem quando há legenda. | Menos repetição; legenda curta é regra editorial; valores continuam em texto. | Médio (renderizador + prompt/renderizador de legenda) | Médio: muda `document_chart_renderer` e testes existentes |
| 4 | **Cor com função no gráfico**: barras positivas no azul do acento, negativas num segundo tom (vermelho-alaranjado), sempre com o sinal e o valor escritos. | Destaca o sentido sem depender só de cor. | Baixo | Baixo; testar em cinza |
| 5 | **Bloco de identificação** no topo (rótulo "Segunda Mente · Documento", data, versão, origem) em cinza pequeno acima do título. | Aparência de relatório finalizado; metadados já existem no serviço. | Médio | Baixo; exige passar dados ao exportador |
| 6 | **Ritmo**: margens laterais 60→~72 pt, entrelinha ~140%, mais espaço antes de seções (hoje 16 pt), margem inferior um pouco maior. | Aproxima das faixas de Butterick; espaço como ênfase. | Baixo | Médio: repagina tudo; testar em papel e no celular |
| 7 | **Tabela**: células com mais respiro vertical (5→7 pt), cabeçalho em cor de acento, coluna "Situação" com rótulo textual (Confirmado / Hipótese / Pendente) e cor discreta. | Margem de célula é o ganho principal em tabelas densas. | Baixo | Baixo |
| 8 | **Cabeçalho corrente** nas páginas 2+ (título curto) e rodapé com a versão. | Orientação em documentos de várias páginas. | Baixo | Baixo |
| 9 | **Listas** com recuo pendente real e espaçamento regular. | Hoje o marcador "•" é texto na primeira linha. | Baixo | Baixo |
| 10 | Corpo em serifa (fonte OFL empacotada) ou Inter mantida. | Sem evidência nas fontes lidas de que serifa leia melhor; custo de tamanho do app. | Médio | Médio: **não recomendo agora**, hipótese para comparar em papel |

Fora do alcance do pacote `pdf` 3.12.0 (verificado antes): recursos OpenType como números tabulares, controle de viúvas/órfãs e PDF marcado. Os números das tabelas usam os algarismos padrão da Inter.

#### Proposta de direção

Um único estilo "relatório sóbrio" (azul-petróleo como único acento, painel de destaque, legendas discretas, bastante espaço), em vez de vários temas, com três proporções: nota de uma página, relatório com tabela e relatório ilustrado. Falta decidir com o dono o tom: mais editorial (serifa, mais espaço) ou mais executivo (faixa de cor no topo, painéis). **Isso é escolha de identidade; a evidência não escolhe por nós.**

Depois desta rodada, os itens 1 a 9 foram aplicados no exportador. O item 10 (corpo em serifa) não. A legenda da figura passa a ser uma linha (`Figura N. título. Dados: …`) e o título sai de dentro da imagem. Três exemplos mais longos, com texto escrito à mão, foram gerados em PDF para inspeção; não são saída de um modelo do app.

Em seguida, o que os repositórios de ata permitem dentro deste motor entrou no prompt e na tabela: seções de reunião (identificação, resumo, decisões, ações, discussão, perguntas em aberto), variante de standup e de conselho só quando a fonte traz o fato, tabela de três fios e marca de rascunho sob o item "PDF rascunho". Typst, LaTeX e ReportLab ficaram de fora. Quatro exemplos novos, também escritos à mão, estão na mesma pasta temporária dos anteriores.

#### Como validar sem achismo

1. Renderizar os três casos sintéticos nas variantes atual e proposta e comparar lado a lado (papel A4 a 100% e tela do S25).
2. Uma pergunta por documento a duas ou três pessoas sem contexto: "qual é a conclusão?", "o que ainda é incerto?" e "onde está o número X?"; medir tempo e acerto.
3. Teste em escala de cinza e em simulação de daltonismo para o gráfico com barra negativa.
4. Nada disso foi feito; é plano.

### Design dos PDFs aplicado e três exemplos longos (2026-11-09)

Aplicadas as melhorias 1 a 9 da rodada 5 (a 10, corpo em serifa, foi deixada de fora de propósito):

1. **Painel de destaque**: um bloco Markdown `> …` vira painel (fundo `#F3F6FA`, barra de acento à esquerda, corpo 11 pt) no PDF e parágrafos com borda e fundo no DOCX. Painel acima de 1.200 caracteres vira texto comum, porque um painel não continua na página seguinte.
2. **Citações discretas**: `[p.N]` e `[c:id]` ficam em cinza `#6B7280`, 8,5 pt, no PDF e no DOCX; o texto não muda.
3. **Legenda**: as linhas de texto logo abaixo de um gráfico (até 3) saem em 9 pt cinza. O título dentro da imagem foi mantido, para a figura continuar compreensível sozinha.
4. **Cor com função**: barras no azul do acento `#1F4E79`; negativas em `#C2410C`, sempre com sinal e valor escritos.
5. **Bloco de identificação** acima do título (tipo, data, versão), passado por `ExportMeta`; `thread_document_service` preenche com o idioma do app.
6. **Ritmo**: margens laterais 72 pt (era 60), entrelinha ≈ 140% (era 154%), 22 pt antes das seções (era 16), margem inferior 64 pt.
7. **Tabela**: células com 7 pt de respiro vertical (era 5); cabeçalho em cor de acento; palavra de situação inicial (Confirmado, Hipótese, Pendente e formas em inglês) em negrito e cor, sempre acompanhada do texto.
8. **Cabeçalho corrente** (título) nas páginas 2 em diante e rodapé com "Segunda Mente · versão".
9. **Listas** com recuo pendente real; item com mais de 700 caracteres volta ao marcador no texto, porque uma linha de `Row` não continua na página seguinte.

Também: `documentSystemPrompt` ganhou a instrução do bloco de pontos principais (citação `>`, só acima de ~400 palavras). **Esta é uma mudança de comportamento do modelo, não testada com modelos reais**, só por teste do texto do prompt.

Contrastes novos: `#166534` 7,1:1; `#92400E` ≈ 6,9:1; `#475569` ≈ 7,6:1; `#C2410C` ≈ 5,2:1 sobre branco (cálculo, não medição).

Limites vistos nos exemplos: o pacote `pdf` não evita linha órfã (aparece uma palavra sozinha no topo da página seguinte); um gráfico que não cabe deixa espaço no fim da página; ponto final isolado numa linha depois de uma citação.

Exemplos (fora do repositório, 4 a 6 páginas, textos sintéticos escritos por mim, números e citações conferidos por script contra uma fonte fictícia): `exemplo_4_custos.pdf` (6 páginas, 4 gráficos, tabela de pendências), `exemplo_5_contrato.pdf` (4 páginas, tabela com situações), `exemplo_6_pesquisa.pdf` (4 páginas, gráfico com valores negativos), em `C:\Users\notefael\AppData\Local\Temp\claude\204253db9b046894\21504dea-0558-45dd-89f3-4c5024950b52\scratchpad\out2\`; textos e fontes em `...\scratchpad\cases2\`. Páginas conferidas como imagem; não conferi impressão, S25 nem leitor de tela.

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

Estado em 2026-11-09, depois do aceite do dono (D-045): F10-01 a F10-05 estão `DONE`. A prova no S25, a ilustração gerada, o raster de página de PDF, o papel, o leitor de tela e o PDF marcado continuam `NOT_RUN` e foram dispensados. F10-06 está `READY` e a auditoria não foi feita. Conforme [ROADMAP.md](../../ROADMAP.md) e [STATE.md](../../STATE.md). O renderizador e o prompt editorial já têm mudanças locais e prova sintética descritas acima. Esta pesquisa acrescenta critérios e fontes; não altera código, catálogo de modelos, provedor nem autorização de custo. A comparação de modelos, o conjunto de avaliação, validação de PDF marcado/leitor de tela, suíte completa, build e prova final no S25 continuam pendentes.

# Extração de documentos e atas: regras de leitura

Data: 2026-11-05. Origem: o dono achou o resultado do app pobre para uma ata em PDF ("lista pequena", sem resumo, sem saber quem faz o quê). Esta página junta o que as fontes dizem e o que foi aplicado nos prompts (`lib/agent/prompts.dart`: bloco "Documents and Meeting Records" do agente de cartões e item "Meeting records" do PKM).

## Fontes e o que cada uma sustenta

| Fonte | Tipo | O que sustenta | Regra aplicada |
|---|---|---|---|
| [Nielsen Norman Group, "How Users Read on the Web"](https://www.nngroup.com/articles/how-users-read-on-the-web/) | Pesquisa de usabilidade | 79% dos testados sempre varrem a página e só 16% leem palavra por palavra. Recomenda destacar palavras-chave, subtítulos que descrevem o conteúdo, listas, uma ideia por parágrafo, conclusão primeiro e metade do tamanho. Texto conciso rendeu 58% mais usabilidade, escaneável 47%, objetivo 27%, os três juntos 124% | Resumo de 2 a 3 frases no início, seções curtas com títulos claros, uma ideia por item, negrito na palavra ou número-chave, corpo com metade do tamanho da fonte ou menos, linguagem neutra |
| [Digital.gov, guia de linguagem simples](https://digital.gov/guides/plain-language/writing) (governo dos EUA) | Guia oficial | Voz ativa deixa claro quem deve fazer o quê; presente é a forma mais forte; use o verbo direto em vez de substantivo escondido ("analisar", não "fazer uma análise"); palavras e seções curtas | Decisões e ações em voz ativa, ações começando por verbo |
| [Robert's Rules of Order (RONR), via Madison City Attorney](https://www.cityofmadison.com/attorney/committees-legislation/roberts-rules/taking-minutes) e [resumo da MSU](https://acadgov.msu.edu/About/Writing-Minutes) | Regra parlamentar | A ata registra o que foi feito, não o que foi dito; opiniões pessoais não entram. É regra padrão, e a organização pode mudá-la | Decisões dizem o resultado, não o debate; sem "quem disse o quê" salvo se mudar um resultado |
| Guias de fornecedores de atas ([Fathom](https://www.fathom.ai/learn/meeting-minutes), [Read AI](https://www.read.ai/articles/how-to-write-meeting-minutes-step-by-step-guide), [meetingdecisions.com](https://www.meetingdecisions.com/blog/how-to-write-meeting-minutes)) | Blogs de empresas, **evidência fraca** | Concordam em: um responsável por ação, prazo, ação começando por verbo, estrutura fixa, enviar em até 24 h | Uma ação tem um dono, um verbo e uma data; "não informado" em vez de inventar |

Limites: o artigo da Harvard Business Review sobre follow-up de reuniões não foi encontrado diretamente, então não foi usado. Números como "44% das ações nunca terminam" vêm de blogs de fornecedores e não foram verificados. A recomendação de enviar a ata em 24 h não se aplica ao app, que gera na hora.

## Literatura científica (revisada por pares)

Conferi autor, periódico e resultado em página primária ou índice (ERIC, PMC, NN/G). O que veio só de resumo de terceiros está marcado.

| Estudo | Resultado | Uso aqui |
|---|---|---|
| Olive e Barbier (2017), [*Written Communication* 34(2), 224-246](https://eric.ed.gov/?id=EJ1137443) | Texto em tópicos foi lido em menos tempo, com menos dificuldade e menos esforço, e rendeu mais ideias nas anotações; a qualidade do resumo final não mudou | Tópicos para o que for enumerável; não esperar resumo melhor, esperar leitura mais rápida |
| Schneider et al. (2018), meta-análise de sinalização, *Educational Research Review* (103 estudos; dados via [resumo de terceiros](https://publikationen.bibliothek.kit.edu/1000164494/151691045)) | Pistas visuais ou verbais melhoram a retenção (g = 0,53) e menos a transferência (g = 0,33); o efeito é maior quando as pistas mostram a estrutura | Títulos e negrito que mostram a estrutura, não enfeite |
| Estudos sobre títulos e leitura ([resumo](https://www.researchgate.net/publication/12058823_Effects_of_Headings_on_Text_Summarization); [títulos funcionais](https://www.redalyc.org/journal/6137/613775409002/html/)) | Títulos ajudaram a compreender e a julgar a própria compreensão; títulos que não combinam com o texto desaceleraram a leitura | Títulos descritivos e que correspondam ao conteúdo; sem seção com título e texto desencontrados |
| Rello, Pielot e Marcos (2016), [CHI 2016, pp. 3637-3648](https://doi.org/10.1145/2858036.2858204), 104 participantes | Compreensão e legibilidade melhoraram com a fonte maior até cerca de 18 pt na web; espaçamento muito apertado ou muito largo piorou a compreensão, sem mudar o tempo (números via resumos, não li o artigo completo) | Corpo em 16 sp com entrelinha 1,55, sem extremos |
| Estudo com 90 aprendizes de inglês, [ERIC EJ1079769](https://files.eric.ed.gov/fulltext/EJ1079769.pdf) | Fonte de 12 pt foi lida mais rápido que 10 pt; tipo de fonte e entrelinha sem efeito significativo | Reforça não usar texto pequeno; não ajustar tipo de fonte |
| NN/G, [Dark Mode vs. Light Mode](https://www.nngroup.com/articles/dark-mode/), citando Piepenbrock et al. (2013, *Ergonomics* e *Human Factors*), Dobres et al. (2017, *Applied Ergonomics*) | Para visão normal, fundo claro tende a ir melhor, e a vantagem cresce com texto pequeno e no escuro; modo escuro ajuda alguns usuários de baixa visão. NN/G recomenda deixar o usuário escolher | O app é escuro por decisão de design; por isso o texto de leitura não pode ser pequeno nem cinza fraco. Opção de tema claro para leitura longa fica como ideia, sem decisão |

Lacunas: não achei estudo revisado por pares que meça se atas melhoram o cumprimento das ações. O que há sobre "um responsável, um prazo" é prática de fornecedores. Também não achei estudo que teste título e tópicos juntos em resumos curtos; a evidência é por partes (títulos, tópicos, sinalização).

## Formatação no app (aplicada em `articleMarkdownStyleSheet`)

Antes: títulos quase do tamanho do corpo, sem espaço acima deles, tabela como grade crua, negrito sem destaque, corpo em 15 sp.

Agora:
- Corpo 16 sp, entrelinha 1,55, cor de texto secundária (contraste cerca de 9:1 sobre o preto); blocos separados por 10 px.
- Títulos em três degraus: 22, 19 e 16, em negrito e cor principal, com 18 px de espaço acima do título de seção.
- Negrito em cor principal; marcadores de lista em âmbar; citação com barra âmbar.
- Tabela com borda fina, cabeçalho em negrito, células com 10 x 8 px de respiro e texto de 14 sp.
- Teste de widget confere a hierarquia de tamanhos e que lista e tabela renderizam.

## Regras aplicadas

1. Conclusão primeiro: resumo de 2 a 3 frases.
2. Seções curtas com títulos simples (Resumo, Pontos principais, Ideias, Decisões, Ações, Riscos, Em aberto, Próxima reunião), sem seção vazia.
3. Uma ideia por item, itens paralelos de uma ou duas linhas.
4. Decisão = resultado em voz ativa. Proposta não decidida vai em Ideias ou Em aberto, nunca em Decisões.
5. Ação = um responsável, verbo no início, prazo. Com três ou mais, tabela Responsável, Ação, Prazo. Sem dado, "não informado".
6. Fidelidade: nomes, números, datas, unidades e moeda iguais à fonte; nada inventado; nenhum fato repetido em várias seções.
7. Escaneabilidade: negrito no termo ou número-chave; sem linguagem promocional.

## O que foi visto no S25 antes da mudança

Com a ata de teste em PDF (3 páginas), o app já extraiu participantes, números, 3 decisões com responsável e 6 ações com prazo, mas as ideias não ganharam seção própria, as ações vieram em lista e não em tabela, e o texto original foi repetido abaixo do cartão. Com uma nota curta só de tarefas, saiu só a lista reescrita. Conferência depois da mudança: ver `STATE.md`.

## Fora desta mudança

- Gráficos e PDF formatado de saída (o app não gera PDF de ata; é item novo).
- Mudar o texto original repetido abaixo do cartão (é o campo `fact`, que guarda a fala do usuário).

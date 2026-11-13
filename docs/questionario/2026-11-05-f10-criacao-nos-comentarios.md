# F10 — Criação a partir das conversas nos comentários
Status: concluído · Início: 2026-11-05
Objetivo: definir a primeira entrega da F10 (conversa nos comentários → rascunho → versões → exportação MD/PDF/DOCX). Imagens e relatório ilustrado ficam para outra sessão.

Contexto técnico: avaliação crítica feita na mesma conversa (PDF não é guardado no workspace; persona vê só o resumo do cartão; prompt de resposta limita a 1-2 frases; exportador troca pontuação por "?"; padrão F6-12 serve para o responsável único).

## Decisões
### D1 - Tipo de material
- Pergunta: que tipo de material mais deve sair das conversas?
- Decisão: os dois igualmente — texto curto (1 a 3 páginas) e documento longo com várias seções e citações do PDF.
- Por quê: escolha do dono; o desenho precisa servir aos dois desde o início.
- Descartado: começar só pelo texto curto.
- Difícil de reverter: não

### D2 - Como obter o texto do PDF
- Pergunta: como o app obtém o texto do PDF para consulta e citação?
- Decisão: guardar uma cópia do PDF no registro e pedir ao modelo que transcreva o texto por página uma vez; o texto fica salvo e é reutilizado.
- Por quê: aproveita a leitura que já funciona com o login ChatGPT e serve também para PDF escaneado.
- Descartado: biblioteca local (dependência nova, falha em escaneado); local com modelo de reserva (mais trabalho); reenviar o PDF a cada uso (custo repetido e citações sem conferência).
- Difícil de reverter: não
- Consequências: custo de tokens de saída proporcional ao tamanho do PDF; depende de um provedor que aceite PDF (Gemini por OAuth hoje descarta o arquivo sem avisar).

### D3 - Quando transcrever
- Pergunta: quando a transcrição por página acontece?
- Decisão: o PDF é guardado sempre na captura; a transcrição só roda na primeira vez que o usuário responde a um comentário ou pede um documento sobre aquele registro.
- Por quê: PDF que ninguém discute não gasta tokens.
- Descartado: transcrever sempre na captura; transcrever só por pedido explícito.
- Difícil de reverter: não

### D4 - PDF longo
- Pergunta: o que fazer com PDF muito longo?
- Decisão: acima de um limite de páginas, o app mostra o número de páginas e pede confirmação antes de transcrever; abaixo dele, transcreve sem perguntar.
- Por quê: controla custo e espera sem atrapalhar o caso comum.
- Descartado: transcrever sempre sem limite; transcrever só as páginas usadas.
- Difícil de reverter: não

### D5 - Profundidade das respostas
- Pergunta: como a persona responde quando o usuário responde?
- Decisão: proporcional ao usuário. O comentário inicial continua curto; resposta curta recebe resposta curta; argumento desenvolvido recebe argumento, discordância ou proposta no mesmo nível, com a voz da persona.
- Por quê: aprofunda sem transformar todo comentário em ensaio.
- Descartado: sempre aprofundada; curta salvo pedido explícito.
- Difícil de reverter: não

### D6 - Outras personas na conversa
- Pergunta: quando o usuário responde no fio de uma persona, quem mais pode entrar?
- Decisão: a persona do fio responde; outras personas podem avaliar se têm algo a acrescentar e comentar. @Nome continua chamando uma persona específica.
- Por quê: o dono quer uma conversa mais viva, com perspectivas diferentes.
- Descartado: só a persona do fio; botão "ouvir outra opinião".
- Difícil de reverter: não
- Alerta: aumenta escopo e custo (mais chamadas por resposta) e risco de ruído; precisa de limite (D7).

### D7 - Debate entre personas
- Pergunta: qual limite para as personas que entram na conversa?
- Decisão: personas podem responder umas às outras (debate), com limite de rodadas.
- Por quê: escolha do dono; quer ver perspectivas se confrontando.
- Descartado: no máximo 1 persona falando só com o usuário; reaproveitar o ajuste maxCommentCharacters.
- Difícil de reverter: não
- Alerta: muda a regra do plano F10/D-036 ("comentar não autoriza debate autônomo entre personas"); é a opção mais cara e difícil de controlar. Precisa de freio (D8).

### D8 - Freio do debate
- Pergunta: como o debate começa e para?
- Decisão: só começa depois de uma resposta do usuário (nunca no comentário inicial). Após cada mensagem do usuário, as personas somam no máximo 4 falas entre si e param, esperando o usuário.
- Por quê: espaço para confronto real sem rodar sem fim.
- Descartado: até 2 falas; debate já no comentário inicial.
- Difícil de reverter: não
- Consequência: até 5 chamadas ao modelo por mensagem do usuário (persona do fio + 4 falas).

### D9 - Como pedir o documento
- Pergunta: como o usuário pede para transformar a conversa em documento?
- Decisão: das duas formas — escrevendo na resposta ("junte isso numa proposta") ou tocando em "Criar documento" no fio.
- Por quê: o texto mantém a fluidez; o botão garante o pedido quando o modelo não o reconhece.
- Descartado: só por texto; só por botão.
- Difícil de reverter: não

### D10 - Escopo da conversa no documento
- Pergunta: qual parte da conversa entra no documento?
- Decisão: o fio onde o pedido foi feito, incluindo o debate das personas nele. Outros fios do mesmo registro só entram se o usuário pedir ("junte com a conversa sobre X").
- Por quê: evita misturar assuntos sem exigir seleção manual.
- Descartado: todos os comentários do registro; lista para o usuário marcar.
- Difícil de reverter: não

### D11 - Voz do documento
- Pergunta: com que voz o documento é escrito?
- Decisão: padrão neutro, com créditos de quem levantou cada ideia e marcação de hipótese; o usuário pode pedir em cada pedido outra voz ("escreva como a Fulana").
- Por quê: neutro serve para uso profissional; a opção mantém o lado pessoal quando desejado.
- Descartado: sempre neutra sem opção; sempre na voz da persona.
- Difícil de reverter: não
- Regra mantida: mesmo na voz de uma persona, fonte, sugestão e decisão continuam distinguíveis.

### D12 - Outras fontes
- Pergunta: além do registro atual, o documento pode usar outros registros do usuário?
- Decisão: sim, com busca automática de registros relacionados (reaproveitando a busca da F6-09).
- Por quê: escolha do dono; documento mais rico.
- Descartado: só quando o usuário pedir; nunca na primeira entrega.
- Difícil de reverter: não
- Alerta: conflita com PROJECT.md ("envio remoto só com escolha explícita e prévia do conteúdo"; conteúdo confidencial de terceiros). Salvaguarda em D13.

### D13 - Salvaguarda das outras fontes
- Pergunta: que salvaguarda usar na busca automática?
- Decisão: antes de gerar, o app lista os registros extras encontrados (título e data); o usuário desmarca o que não quer e confirma. Só então envia ao modelo.
- Por quê: mantém a regra de envio com escolha explícita do PROJECT.md.
- Descartado: autorização geral única; envio sem confirmação.
- Difícil de reverter: não

### D14 - Onde o documento aparece
- Pergunta: onde o documento aparece depois de criado?
- Decisão: um cartão "<título> — versão N" no fio, que abre uma tela própria com texto, versões e exportação; ligado ao registro de origem.
- Por quê: mantém o ponto de entrada nos comentários sem poluir a timeline.
- Descartado: virar registro na timeline; seção "Documentos" no menu (pode vir depois).
- Difícil de reverter: não

### D15 - Como pedir alterações
- Pergunta: como o usuário pede alterações no documento?
- Decisão: pelo fio ("mude a conclusão") ou por um campo na tela do documento; os dois geram a próxima versão e o fio registra o pedido.
- Por quê: a conversa continua sendo o lugar natural, e a tela evita voltar ao fio para um ajuste.
- Descartado: só no fio; só na tela.
- Difícil de reverter: não

### D16 - Edição manual
- Pergunta: editar o texto à mão na primeira entrega?
- Decisão: sim. Botão Editar; ao salvar, vira a próxima versão com autor "usuário". Se o modelo gerar ao mesmo tempo, nada é sobrescrito: as duas versões ficam e o app avisa.
- Por quê: ajustes pequenos não devem exigir pedido ao modelo nem exportar para o Word.
- Descartado: deixar para depois.
- Difícil de reverter: não

### D17 - Exclusão do registro de origem
- Pergunta: o que acontece com os documentos ao apagar o registro de origem?
- Decisão: o app avisa quantos documentos existem e pergunta: apagar junto ou manter. Mantidos, guardam a cópia do trecho usado e mostram "origem apagada".
- Por quê: evita perda acidental sem deixar órfãos em silêncio.
- Descartado: apagar sempre junto; manter sempre.
- Difícil de reverter: não

### D18 - Exportador
- Pergunta: qual caminho para PDF/DOCX de documentos longos?
- Decisão: adotar uma biblioteca de PDF (candidato: pacote `pdf`) no lugar do PDF feito à mão; DOCX continua no gerador atual, ampliado com listas, negrito e tabelas.
- Por quê: resolve acentos/aspas ("?" hoje), quebra por palavra, listas e tabelas, e já serve para imagens na segunda entrega.
- Descartado: consertar o gerador atual; adiar o PDF.
- Difícil de reverter: não
- Condição: conferir licença compatível com GPL-3.0 antes de adicionar (regra do PROJECT.md).

### D19 - Exportador compartilhado
- Pergunta: o relatório de sessão (F4) passa a usar o exportador novo?
- Decisão: sim, um exportador só para relatório de sessão, documentos da F10 e, depois, F9.
- Por quê: evita dois exportadores e corrige os "?" do relatório atual.
- Descartado: manter o da F4 separado.
- Difícil de reverter: não
- Consequência: reconferir PDF e DOCX do relatório da F4 no S25 (Acrobat e Word).

### D20 - Modelos
- Pergunta: qual modelo escreve os documentos e conduz o debate?
- Decisão: personas (comentário, resposta, debate) usam o modelo já configurado para comentários; documento e transcrição do PDF usam o modelo do chat principal (hoje o login ChatGPT).
- Por quê: sem configuração nova; o modelo do chat já lê PDF.
- Descartado: ajuste próprio para documentos; um modelo só para tudo.
- Difícil de reverter: não

### D21 - Modelo que não lê PDF
- Pergunta: o que fazer se o modelo em uso não ler PDF?
- Decisão: avisar ("este modelo não lê PDF; usei só o resumo do registro"), seguir com o resumo e escrever essa limitação no documento. O usuário pode trocar de modelo e pedir de novo.
- Por quê: nunca fingir leitura; não travar o fluxo.
- Descartado: bloquear; pular automaticamente para outro modelo.
- Difícil de reverter: não
- Consequência técnica: o cliente Gemini OAuth precisa sinalizar o descarte do PDF em vez de ignorá-lo em silêncio.

### D22 - Prioridade
- Pergunta: quando começar a F10?
- Decisão: esperar o MVP fechar. Nada da F10 antes disso.
- Por quê: escolha do dono; mantém o foco no MVP.
- Descartado: exceção só para a conversa; exceção para a primeira entrega inteira.
- Difícil de reverter: não

### D23 - Exportador no MVP
- Pergunta: o exportador novo entra agora, como trabalho do MVP?
- Decisão: sim. A troca para a biblioteca de PDF e a ampliação do DOCX entram no fechamento da F4, corrigindo os "?" do relatório de sessão. A F10 depois só reaproveita.
- Por quê: corrige um defeito real do MVP e adianta a base da F10 sem abrir a F10.
- Descartado: deixar a troca para quando a F10 abrir.
- Difícil de reverter: não

### D24 - Ordem da F10
- Pergunta: depois do MVP, em que ordem montar a F10?
- Decisão: 1) conversa (respostas proporcionais e debate); 2) guardar o PDF e transcrever por página; 3) documento, versões, edição manual e exportação. Cada etapa testada no S25 antes da próxima.
- Por quê: a conversa entrega valor sem mexer em armazenamento; o PDF guardado precisa existir antes de documentos com citação.
- Descartado: PDF primeiro; documento primeiro.
- Difícil de reverter: não

## Em aberto
- Valor do limite de páginas (D4): ponto de partida sugerido 30; medir custo e tempo da transcrição com um PDF real no S25.
- Licença da biblioteca de PDF (D18) compatível com GPL-3.0: conferir antes de adicionar.
- Aparência do andamento (persona escrevendo, debate em curso, documento sendo gerado) e do cartão do documento no fio: não se decide por pergunta; fazer protótipo visual quando a F10 abrir.
- Ramos na tela de comentários: hoje a lista é plana com "respondendo a Fulano"; com debate de até 4 falas, decidir no mesmo protótipo se os fios precisam ser agrupados.
- Custo real de uma mensagem com debate (até 5 chamadas, D8) e de um documento longo: medir no S25.
- PDFs anexados antes da etapa 2 não terão cópia guardada; documentos sobre eles usam só o resumo (D21).
- Retenção de versões: assumido manter todas (texto é pequeno); confirmar se surgir problema de espaço.
- Imagens e relatório ilustrado: outra sessão de questionário.

## Próximos passos
1. Agora (MVP/F4): trocar o exportador de PDF por biblioteca, ampliar o DOCX e passar o relatório de sessão para ele (D18, D19, D23); reconferir PDF no Acrobat e DOCX no Word no S25.
2. Atualizar docs/fases/F10-criacao-nos-comentarios.md, ROADMAP.md e DECISIONS.md com estas decisões, em especial a mudança de regra do debate entre personas (D7, D8) e a busca automática com confirmação (D12, D13).
3. Depois do MVP: F10 na ordem de D24.

# F9-03 — corpus F9-02 contra o modelo (2026-11-06)

Dados fictícios. Prompt real do app (`reportExtractionSystemPrompt`), resposta conferida pelo mesmo código de validação do relatório. Scripts: `docs/medicoes/f9-03/corpus.dart` e `rodar.py`.

**Como rodou:** pelo Codex CLI do PC (modelo `gpt-6-luna`, esforço baixo), não pelo cliente do app. O Codex acrescenta instruções próprias, então é uma estimativa do prompt, não a prova do caminho do app. Os 5 PDFs entraram como o texto esperado de cada página, com `p.N`; a leitura do PDF pelo modelo só foi provada no S25 com o `c36`.

## Resultado (tipo de relatório "Livre", 39 casos com texto)
| Medida | Resultado |
|---|---|
| Respostas válidas (JSON, tipo permitido, citação literal) | 38/39 |
| Tarefas esperadas que apareceram como tarefa | 13/20 |
| Tarefas a mais (falsas) | 1 |
| Itens de PDF com a página certa | 5/5 |

- 1ª rodada, tipo "Reunião": 34/39 válidas, 16/20 tarefas, 2 falsas, página 3/4. Quatro das cinco recusas eram do tipo "Reunião", que não aceita ideia/dúvida; não é erro do modelo.
- A diferença entre as duas rodadas (16 e 13 tarefas de 20) mostra que o resultado varia de uma chamada para outra. Um número só não é medida firme.
- Erros típicos: tarefa classificada como decisão (`c02`), resumo (`c17`, `c19`, `c22`, `c23`) ou follow-up (`c26`); `c40` (prazo repetido em duas páginas) voltou sem itens, `c27` e `c09` sem tarefa esperada.
- O modelo nunca devolveu responsável ou prazo (o prompt proíbe), então a coluna "responsável/prazo" do corpus não foi medida.

## O que não vale ainda
- Não é o caminho do app; rodar o corpus pelo app no S25 continua `NOT_RUN` (o dono pediu o teste pelo chat).
- Uma rodada de cada; sem repetição para medir a variação.
- Não decidi se 13/20 é suficiente. Como todo item sai "Não confirmado", a falha é omitir tarefa, não inventar (1 falsa).

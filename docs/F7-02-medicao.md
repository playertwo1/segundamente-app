# F7-02 — Medição do modelo local (etapa 1: qualidade no PC)

Data: 2026-11-06 (D-040). Só a parte de qualidade em português, no PC. **Velocidade, memória, calor e bateria no S25 continuam `NOT_RUN`** (o dono não pode deixar o aparelho livre por uma hora; o plano foi dividido em sessões curtas).

## Método
- Modelo: `unsloth/gemma-3-1b-it-GGUF`, `Q4_K_M` (806.058.272 bytes, SHA-256 `8270790f3ab69fdfe860b7b64008d9a19986d8df7e407bb018184caa08798ebd`). Quantização de 4 bits do Gemma 3 1B; o repositório oficial do Google exige login e o arquivo do LiteRT (~529 MB) não foi baixado. Não é o mesmo arquivo que iria ao S25.
- Runtime: `llama.cpp` b12167, CPU x64, 8 threads, temperatura 0. Rodou só no PC; nada foi ao S25 nem à nuvem.
- Corpus: os 40 casos fictícios da F9-02 (`docs/medicoes/f9-02/corpus.json`). Tarefa: devolver JSON com os itens (tipo, responsável, prazo). Acerto = tipos e quantidade de itens idênticos ao esperado. Script: `docs/medicoes/f7-02/classificar_no_pc.py`.

## Resultado
| Prompt | JSON válido | Tipos e contagem certos | Responsável certo (entre os com tipo certo) |
|---|---:|---:|---:|
| A: só tarefa/ideia, regras da F3-07 em uma frase | 40/40 | 8/40 (20%) | 3/8 |
| B: seis tipos do corpus | 21/40 | 7/40 (17,5%) | 4/7 |

- Erros típicos (prompt A): trata fato passado como tarefa, inventa tipo ("compromisso"), repete o mesmo item, lista opinião como item. Acertou 5/6 em `tarefa_clara` e 0/5 em `fato_passado`, `hipotese_opiniao` e `pdf_pagina`.
- Latência no PC: ~2,6 s por caso, ~27–29 tokens/s (CPU de desktop; não vale para o S25).

## Leitura e limites
- Para classificar tarefa x opinião x fato passado, o Gemma 3 1B 4 bits **não chega perto** do corpus com esses prompts simples. A linha de base da regra da F3-07 **não foi medida** neste corpus, então o critério "igualar ou superar a regra" ainda não está fechado; falta rodar a regra no corpus.
- Não testei resumo curto (10 textos, julgamento às cegas pelo dono), outros prompts (poucos exemplos, saída com esquema) nem outros modelos de 2–4 bilhões de parâmetros.
- Uma variação de prompt pode melhorar, mas a distância (de ~20% para algo útil) é grande; a recomendação provisória é não gastar a sonda do S25 com classificação.

## Etapa 2 — Gemma 4 no PC (2026-11-06, interrompida pelo dono, D-041)
Arquivos `.litertlm` oficiais (E2B 2.588.147.712 bytes; E4B 3.659.530.240 bytes), CLI `litert-lm` em CPU, mesmos 40 casos. Script: `docs/medicoes/f7-02/classificar_no_pc.py` (versão para o LiteRT-LM não foi guardada no repositório).
| Modelo | Prompt | Tipos e contagem certos | Responsável certo | Tempo por caso (CPU do PC) |
|---|---|---:|---:|---:|
| Gemma 3 1B Q4 | A | 8/40 (20%) | 3/8 | 2,6 s |
| Gemma 4 E2B | A | 17/40 (42,5%) | 9/17 | 5,2 s |
| Gemma 4 E2B | B | 23/40 (57,5%) | 14/23 | 6,9 s |
| Gemma 4 E4B | A | 17/40 (42,5%) | 6/12 | 8,9 s |
| Gemma 4 E4B | B | não terminou | — | — |
- O E2B melhora muito sobre o Gemma 3 1B, mas ainda erra fato passado, dúvida e follow-up. O E4B não superou o E2B no prompt A.
- Limites: sem comparação com o modelo remoto + regra da F3-07 (a regra é um filtro sobre a saída do modelo, não um classificador sozinho); velocidade medida em CPU de PC, não no S25; um só rodada por prompt.

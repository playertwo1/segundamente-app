# F6-10 — Medição de embeddings locais para busca em português

Data: 2026-11-05; atualização em 2026-11-06. Estado: **comparação PC/S25 e comparação local com notas reais concluídas; decisão D-039 registrada; tokenizador e integração estão em F6-01.** Bateria e calor em uso prolongado continuam `NOT_RUN`.

## Como foi medido
- Script e dados: `docs/medicoes/f6-10/bench.py` e `corpus.json` (reproduzível: `pip install onnxruntime tokenizers numpy huggingface_hub`, baixar os modelos citados e rodar).
- Corpus: **48 notas e 40 consultas escritas por mim**, em português, sem dados do dono. 12 consultas "lex" (usam palavras da nota, algumas sem acento), 22 "par" (reescrevem a ideia sem repetir as palavras) e 6 "fora do tema".
- Baseline: SQLite FTS5 (`unicode61`, sem acento), ranking BM25, em duas versões: qualquer palavra (OU) e todas as palavras (E). O app usa FTS5 com outro tokenizador (Jieba) e busca textual direta; esta é uma aproximação, não o código do app.
- Modelos na primeira medição (ONNX, CPU, média das palavras, vetor normalizado): `multilingual-e5-small` (MIT; fp32 470 MB, int8 118 MB; prefixos `query:`/`passage:`) e `paraphrase-multilingual-MiniLM-L12-v2` (Apache-2.0; fp32 470 MB). A variante MiniLM int8 foi medida depois, na seção abaixo.

## Resultado (consultas com resposta certa)
| Método | "lex" acerto@3 | "par" acerto@1 | "par" acerto@3 | "par" MRR |
|---|---|---|---|---|
| Texto, qualquer palavra | 1,00 | 0,18 | 0,27 | 0,25 |
| Texto, todas as palavras | 0,75 | 0,00 | 0,00 | 0,00 |
| e5-small int8 (118 MB) | 1,00 | 0,59 | 0,77 | 0,70 |
| e5-small fp32 | 1,00 | 0,59 | 0,82 | 0,73 |
| MiniLM-L12 fp32 | 1,00 | 0,73 | 0,95 | 0,83 |

Fora do tema (6 consultas): o texto "qualquer palavra" devolveu resultado nas 6 (palavras como "de" e "como"); "todas as palavras" devolveu em 0. Os embeddings sempre devolvem alguém, então precisam de um corte de nota. Com o corte logo acima da maior nota fora do tema: e5 int8 mantém 88% dos acertos, e5 fp32 82%, MiniLM só 53%.

## Leitura
- Em consulta que repete as palavras da nota, o texto já basta (e embeddings empatam ou perdem em acerto@1).
- Em consulta que só reformula a ideia, os embeddings ganham muito: acerto@3 de 0,27 para 0,77–0,95.
- A quantização int8 do e5 custou pouco (0,82 → 0,77 em acerto@3) e deixa o modelo em 118 MB.
- Para recusar pergunta fora do tema, o e5 separa melhor que o MiniLM.
- Na primeira medição, os números sugeriam texto primeiro e embeddings quando o texto achasse pouco, com corte de nota. D-039 depois registrou essa escolha e selecionou MiniLM int8 com base na medição seguinte.

## Limites (leia antes de confiar)
- A etapa sintética usa um corpus pequeno inventado por quem escreveu as consultas; as reformulações podem ser mais fáceis ou mais difíceis que as do dono. A etapa 3 acrescentou uma comparação local com 24 cartões reais, com consultas escritas pelo agente e sem envio a provedor.
- Tempos de PC (16 núcleos) não valem para o S25.
- Não testei EmbeddingGemma (exige aceite dos termos Gemma) nem o Universal Sentence Encoder do `daedalus-echo`.
- Registro da etapa 2 antes da rodada seguinte (2026-11-05): a execução S25, a integração Flutter/ONNX e a escolha de dependência ainda estavam `NOT_RUN` naquele momento. Os resultados e a decisão posteriores estão nas seções abaixo.
- Critério do ROADMAP na primeira rodada: "sem benefício medido, não implementar". A etapa 2, a comparação com notas reais e a escolha do dono vieram depois e estão registradas abaixo e em D-039.

## Etapa 2 — S25 Ultra (2026-11-05)
Sonda separada, fora do app: `tools/f610_probe` (Flutter, `flutter_onnxruntime` 1.9.0, build release, CPU). Os textos já chegam tokenizados do PC (o tokenizador em Dart **não** foi medido). Resultado bruto: `docs/medicoes/f6-10/resultado-s25.json`. Bateria 70%, 38,9 °C; a medição durou poucos segundos.

| Modelo | Arquivo | Carregar | Por nota (média / p95) | Por consulta | RAM do processo (antes → depois / pico) | Cosseno mínimo vs PC | Acerto@3 "par" | Acerto@3 "lex" |
|---|---|---|---|---|---|---|---|---|
| e5-small int8 | 118 MB | 0,35 s | 9,8 ms / 23 ms | 4 ms | 167 → 410 / 472 MB | 0,997 | 17/22 | 12/12 |
| MiniLM-L12 fp32 | 470 MB | 0,91 s | 10,4 ms / 14 ms | 6 ms | 291 → 693 / 1134 MB | 1,000 | 21/22 | 12/12 |

- Os acertos no aparelho batem com o PC (0,77 e 0,95), então o modelo roda certo no Android.
- Indexar 1.000 notas curtas levaria ~10 s com qualquer um dos dois (estimativa linear a partir de 48 notas; notas longas custam mais).
- O e5 int8 usa ~240 MB de RAM acima da linha de base e 118 MB de disco. O MiniLM fp32 é 4 vezes maior em disco e pico de ~1,1 GB (o pico do MiniLM inclui o e5 rodado antes no mesmo processo, então está superestimado). Naquela rodada, a versão int8 do MiniLM ainda não tinha sido testada; ela foi medida na sequência.
- O APK da sonda ficou com 125,8 MB, a maior parte do ONNX Runtime para todas as arquiteturas; no app principal isso aumentaria o APK e precisa de filtro de arquitetura (`arm64-v8a`).
- Não medido: bateria e calor em uso real. Notas longas continuam limitadas a 128 tokens; o tokenizador Dart foi comparado com a referência Python em F6-01, com a ressalva de NFKC descrita em D-039.

### MiniLM-L12 int8 (arm64), medido em seguida no S25 e no PC
O arquivo `model_qint8_arm64.onnx` (118 MB) foi enviado no lugar do fp32, então o log o chama de `minilm_fp32` (o campo `modelo_mb` = 118 mostra que é o int8). Nova rodada: o e5 int8 repetiu os resultados da primeira.

| MiniLM-L12 int8 | Valor |
|---|---|
| Arquivo / carregar | 118 MB / 0,23 s |
| Por nota (média / p95) / por consulta | 6,8 ms / 12 ms / 6,8 ms |
| RAM do processo | 278 → 413 MB, pico 485 MB (o pico inclui o e5 rodado antes no mesmo processo) |
| Cosseno mínimo vs fp32 do PC | 0,981 |
| Acerto@3 reformuladas / mesmas palavras | 20/22 (0,91) / 12/12 |
| PC: acerto@1 reformuladas / MRR | 0,77 / 0,86 |
| PC: fora do tema, acertos acima da maior nota fora do tema (0,48) | 56% |

- A quantização custou pouco: 21/22 → 20/22 e cosseno mínimo 0,98. O S25 e o PC concordam (20/22).
- Comparado ao e5 int8 (mesmo tamanho): o MiniLM int8 acerta mais nas reformulações (0,91 contra 0,77), mas separa pior o que está fora do tema (56% contra 88%). Como o app teria texto primeiro e corte de nota, o corte é o ponto fraco do MiniLM; o e5 tem o corte melhor e o acerto menor. Escolher entre os dois exige as notas reais do dono; com este corpus pequeno, a diferença de 2 a 3 acertos não é conclusiva.

## Etapa 3 — notas reais do dono (2026-11-06, só no PC, sem enviar nada a provedor)
- Corpus: os 24 cartões que existiam no app (copiados do S25 para uma pasta temporária do PC, apagada ao fim; nada foi ao repositório nem a provedor). Vários são de teste ou de boas-vindas, então o corpus é pequeno e desigual. Consultas: 24, escritas pelo agente depois de ler os cartões (não pelo dono): 12 reformuladas ("par"), 6 com as palavras do cartão ("lex"), 6 fora do tema. Script: `docs/medicoes/f6-10/compare_real.py`. Modelos: e5-small `model_int8` (Xenova) e MiniLM-L12 `quint8_avx2` (variante x86 do PC; o S25 usa `qint8_arm64`), notas truncadas em 128 tokens.

| Método | "lex" acerto@3 | "par" acerto@1 | "par" acerto@3 | "par" MRR | Fora do tema: acertos acima do corte |
|---|---|---|---|---|---|
| Texto FTS5, qualquer palavra | 1,00 | 0,50 | 0,83 | 0,66 | devolveu algo nas 6/6 consultas fora do tema |
| e5-small int8 | 1,00 | 0,92 | 0,92 | 0,93 | 67% (maior nota fora do tema 0,86) |
| MiniLM-L12 int8 | 1,00 | 0,83 | 1,00 | 0,90 | 94% (maior nota fora do tema 0,40) |

- Leitura: embeddings ganham do texto nas consultas reformuladas (acerto@1 de 0,50 para 0,83–0,92) e empatam nas de mesma palavra. Com estas notas o MiniLM separa muito melhor o que é fora do tema (a nota do e5 fica sempre alta, 0,7–0,9, então um corte fixo perde acertos). No corpus sintético da etapa 1 foi o contrário (e5 88% × MiniLM 56%): o corte depende do corpus, então precisa ser calibrado com as notas do dono e não pode ser um número fixo de fábrica.
- Limites: 24 cartões, parte de teste; consultas escritas por mim, que li os cartões antes (tende a favorecer os dois modelos); um cartão só por tema. Não cobre notas curtas do dia a dia nem consultas do dono. A implementação do tokenizador Dart está coberta em F6-01; bateria e calor continuam `NOT_RUN`.

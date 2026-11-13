# F7-02 — Pesquisa de modelos locais mais novos (2026-11-06)

Só pesquisa; nada foi baixado nem medido nesta etapa. Motivo: o Gemma 3 1B 4 bits acertou só 8/40 no corpus da F9-02 (`docs/fases/F7-02-medicao.md`).

## Fontes oficiais (nível de evidência alto)
- Gemma 4 no LiteRT-LM: https://developers.google.com/edge/litert-lm/models/gemma-4 — E2B 2,58 GB e E4B 3,65 GB, arquivo `.litertlm`, licença Apache-2.0.
- Cartão do modelo: https://huggingface.co/google/gemma-4-E2B-it — "License: apache-2.0" (a página também liga aos termos do Gemma), 140+ idiomas no pré-treino e 35+ "prontos para uso" (português não é citado pelo nome), contexto 128K, 2,3 B parâmetros efetivos (5,1 B com embeddings). E2B: MMLU Pro 60,0%, MMMLU (multilíngue) 67,4%, IFBench 38.
- LiteRT-LM: https://developers.google.com/edge/litert-lm/overview — Kotlin e C++ estáveis; backends CPU, GPU e NPU (NPU no Android estável); function calling com decodificação restrita; Flutter só pela biblioteca comunitária `flutter_gemma`. Modelos: Gemma 4 E2B/E4B, Gemma 3n, Gemma 3 1B, Phi-4-mini, Qwen2.5 e Qwen3 0,6B; embeddings EmbeddingGemma.
- Cartão do E2B no LiteRT: https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm — pesos de 2, 4 e 8 bits; só texto pode ficar perto de 0,8 GB de pesos (embeddings mapeados em memória).

## Velocidade medida pelo Google (Galaxy S26 Ultra, não o S25)
| Modelo | Backend | Prefill (tok/s) | Decode (tok/s) | 1º token | Pico CPU |
|---|---|---:|---:|---:|---:|
| E2B | CPU | 557 | 47 | 1,8 s | 1.733 MB |
| E2B | GPU | 3.808 | 52 | 0,3 s | 676 MB |
| E4B | CPU | 195 | 18 | 5,3 s | 3.283 MB |
| E4B | GPU | 1.293 | 22 | 0,8 s | 710 MB |
Com previsão de vários tokens (MTP): decode do E2B na GPU sobe até 91,7 tok/s. O S25 Ultra não tem número oficial; deve ficar abaixo do S26 Ultra, a medir.

## Outras opções (fontes secundárias, só direção)
- Qwen3 (0,6 B a 4 B): fama de bom multilíngue; Qwen3 0,6 B está no LiteRT-LM. O relatório técnico tem tabela por idioma incluindo português (não li o número).
- Phi-4-mini (MIT): suportado no LiteRT-LM; fraco em multilíngue segundo guias; 15–40 tok/s relatados, números discordam.
- Gemma 3n E2B/E4B: antecessor do Gemma 4; mais maduro, mas sem vantagem clara.
- SmolLM3 3 B: lista português entre seis idiomas; sem prova de velocidade no S25.

## Lacunas
Nenhum benchmark de português nem de saída JSON para Gemma 4. Velocidade no S25 Ultra e RAM real no app não medidas. Números de blogs discordam e não foram usados para decidir.

## Recomendação
1. Candidato principal: Gemma 4 E2B pelo LiteRT-LM (Apache-2.0 tira o risco de GPL do Gemma 3; cabe no S25; Kotlin estável). E4B só se o E2B falhar na qualidade.
2. Etapa 1 no PC: rodar o mesmo `.litertlm` com o CLI `litert-lm` nos 40 casos da F9-02 e comparar com a regra da F3-07.
3. Etapa 2 no S25, só se a etapa 1 prestar: medir velocidade, RAM e calor com uma sonda Kotlin curta (sessões de ~10 min), com texto fictício.

## Rodada 2 — fontes primárias (Google, OpenAI, Anthropic, artigos)
**Google (relatório técnico, arXiv 2607.02770, 2026-06-19; preprint):**
- Gemma 4 E2B / E4B / Gemma 3 27B: MMMLU (multilíngue) 67,4 / 76,6 / 70,7; IFEval 94,6 / 96,7 / 90,4; IFBench 38,0 / 44,0 / 32,0. Ou seja, o E4B supera o Gemma 3 27B em multilíngue e em seguir instruções.
- Uso de ferramentas (Tau2): E2B airline 31,0, retail 34,6, telecom 19,7; E4B airline 52,0, retail 67,1, telecom 18,4. O relatório não traz BFCL nem benchmark de JSON.
- Português aparece só no reconhecimento de fala (FLEURS pt-br, taxa de erro de palavras, menor é melhor): E2B 0,056; E4B 0,046; Gemma 3n E2B 0,067; E4B 0,053. Os modelos também aceitam áudio. Não há resultado de texto em português.
- Contexto longo: RULER 128k E2B 70,4 / E4B 86,6.
**OpenAI:** gpt-oss-20b e 120b são Apache-2.0 com chamada de funções (arXiv 2508.10925). A OpenAI diz que o 20b roda em dispositivos com 16 GB de memória; o S25 Ultra tem 12 GB e o arquivo MXFP4 tem ~13–14 GB (sites de terceiros), então **não serve para o celular**. A página oficial bloqueou a leitura (403); o model card não trouxe números por idioma.
**Anthropic:** todos os modelos Claude (Haiku 4.5 e 5.5 incluídos) são só por API; nenhum tem pesos abertos nem versão para o aparelho. Não achei pesquisa da Anthropic sobre modelos pequenos no celular.
**Artigos:** Tucano 2 (arXiv 2603.03543, português): Qwen3-4B-Base ENEM 77,61 e BLUEX 69,96; modelo de 0,6 B perto do acaso (ENEM 23,58). Gemma não entra nas tabelas que li. Levantamento "SLMs Can Still Pack a Punch" (arXiv 2501.05465): é preprint. **Não achei artigo revisado por pares com acerto de extração/classificação em celular.**
**Conclusão da rodada:** os melhores números oficiais para o nosso caso são do Gemma 4 (E4B na qualidade, E2B na velocidade). Continua sem prova em português escrito e em JSON; isso só se fecha medindo no corpus da F9-02.

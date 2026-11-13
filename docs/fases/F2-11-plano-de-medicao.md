# F2-11 — Plano de medição: transcrição local em português

Data: 2026-11-05. Só plano e pesquisa. **Nada foi medido**, nenhum modelo foi baixado e nenhum código foi escrito. A medição precisa do S25 e de um áudio seu.

## 1. Ponto de partida

- Hoje o app transcreve por dois caminhos: nuvem (`chatgpt.com/backend-api/transcribe`, D-011) e local com SenseVoice (sherpa-onnx).
- **SenseVoice não cobre português**: a documentação do projeto lista chinês, cantonês, inglês, japonês e coreano (D-007; https://k2-fsa.github.io/sherpa/onnx/sense-voice). Por isso o local não serve para fala em pt-BR e a F2-11 existe.
- A pergunta: um modelo multilíngue que cobre português, rodando no aparelho, transcreve áudio longo bem o bastante para dispensar a nuvem?

## 2. Candidatos (pesquisa; níveis de evidência)

| Candidato | O que se sabe | Evidência |
|---|---|---|
| Whisper multilíngue (tiny, base, small) exportado para ONNX pelo sherpa-onnx | Cobre português (99 idiomas). A documentação do sherpa-onnx lista as exportações multilíngues; os arquivos ficam em repositórios `csukuangfj` no Hugging Face | OFICIAL (https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/index.html) |
| Tamanho em int8 | O codificador tiny int8 tem ~12 MB e o decodificador int8 ~86 MB (página de identificação de idioma). Para base e small **não achei número oficial**; blogs dão ~75 MB e ~250 MB sem dizer se é int8 | SECUNDÁRIA, **a medir** (tamanho real do arquivo baixado) |
| Qualidade em pt-BR por tamanho | Nenhum dado confiável | **A MEDIR** |
| Whisper com tempo de execução próprio (outro runtime) | Não pesquisado | Só se o sherpa-onnx falhar |
| Modelos NeMo em português do sherpa-onnx | As notas de versão citam suporte a português; não li detalhes | A pesquisar se o Whisper falhar |
| SenseVoice "Nano" com 31 idiomas | Os idiomas não aparecem na pesquisa; não confirmei português | A confirmar na página do modelo |

## 3. Método

Segue a F6-10: sonda separada em `tools/`, modelos enviados por `adb push` à pasta do app, resultado só em números, nada do seu áudio no repositório.

1. **Áudio de teste.** Um trecho de 3 a 5 minutos de fala sua em pt-BR (reunião ou nota de voz) com um texto de referência corrigido por você. Mais o áudio longo (~50 min) só para tempo e memória.
2. **Modelos.** Whisper tiny, base e small (int8) no sherpa-onnx; SenseVoice atual como referência de tempo (esperado: ruim em português).
3. **Medidas por modelo:** tamanho em disco; tempo de carga; fator de tempo real (segundos de processamento por segundo de áudio) no trecho de 5 minutos e no de ~50 minutos; pico de memória (RSS); aquecimento e bateria em 10 minutos; **erro de palavras (WER)** contra a referência; quantos nomes próprios do dicionário (F2-13) saem certos.
4. **Comparação:** o mesmo trecho pelo caminho da nuvem (D-011), como referência de qualidade, e o resultado pelo SenseVoice local.
5. **Áudio longo:** testar com divisão em janelas, porque Whisper trabalha em blocos de 30 s; verificar se o relógio por trecho continua correto (o app guarda relógio de cada segmento).

## 4. Critério de decisão

Só implementar se o melhor modelo local, no S25, tiver erro de palavras perto do da nuvem (a diferença aceitável é sua decisão), fator de tempo real abaixo de 1 para o áudio de 50 minutos (processar mais rápido que a duração), memória e aquecimento aceitáveis e tamanho dentro do que você aceita no aparelho. Sem isso, a nuvem continua como caminho e o local fica descartado com os números.

## 5. Antes de medir (pedidos a você)

1. Um trecho de áudio de 3 a 5 minutos e o texto de referência corrigido, ou aceitar que eu use a transcrição da nuvem como referência aproximada.
2. O áudio de ~50 minutos para tempo e memória.
3. S25 livre por cerca de uma hora e carregado.
4. Aprovar a sonda como app separado.

Estado: plano original. Medição no PC e troca no app em 2026-11-08 (seção 6).

## 6. Medição no PC e troca no app (2026-11-08)
- Áudio: três notas de voz suas do S25 (`Recordings/Voice Recorder`, 4 a 5 min cada), copiadas só para a pasta temporária e fora do repositório. Sem texto corrigido: a referência é o Whisper **large-v3**, então os números medem a distância até o melhor modelo, não o erro real. Script: `docs/medicoes/f2-11/whisper_no_pc.py` (sherpa-onnx 1.13.2, a mesma versão do app, blocos de 30 s, 4 threads, idioma `pt`).

| Modelo | Arquivo baixado | int8 em disco | Diferença para o large-v3 (média) | Tempo/duração do áudio (CPU do PC) |
|---|---:|---:|---:|---:|
| tiny | 110 MB | 98 MB | 141% (entra em loop: "eu acho que eu acho que…") | 0,06 |
| base | 197 MB | 152 MB | 58% (frases sem sentido) | 0,08 |
| small | 609 MB | 357 MB | 26% (compreensível, erra palavras) | 0,26 |
| **turbo** | **537 MB** | 988 MB | **17%** (quase igual ao large-v3) | 0,49 |
| large-v3 | 1018 MB | 1693 MB | referência | 2,82 |

- Trecho curto de 5 s (usado na prévia ao vivo): small 1,2 s, turbo 1,7 s. Trecho de 30 s: small 12 s, turbo 8,9 s.
- Escolha: **turbo**, com melhor qualidade e download menor que o do small; custa ~1 GB no aparelho.
- Achados que viraram correção no app: (1) o Whisper do sherpa descarta tudo depois de 30 s ("We process only the first 30 seconds"), e a gravação rápida mandava o áudio inteiro de uma vez. Agora `WhisperService.transcribeSamples` corta em blocos de 30 s. (2) Um pedaço de poucas amostras (sobra depois de um múltiplo de 30 s) derruba o decodificador nativo (access violation). Pedaços abaixo de 0,1 s são descartados. (3) O `.tar.bz2` era descompactado inteiro na memória; agora é descompactado em disco, num isolate. No PC levou 105 s para o arquivo de 609 MB, com arquivos idênticos aos originais.
- No app: Whisper turbo fixo em português (`language: pt`, CPU, 4 threads), o interruptor "Transcrição no aparelho" voltou às Configurações (desligado por padrão; ligado, o modelo é baixado na primeira gravação), e a pasta antiga do SenseVoice é apagada depois do download.
- `NOT_RUN` no S25: tempo de download e de extração, memória, velocidade real (fator de tempo real) e qualidade com o turbo, prévia ao vivo e gravação longa (~50 min). O dono vai testar pelo uso.

## 7. Alternativas ao Whisper no PC (2026-11-08)
Mesmos 3 áudios, mesma referência (large-v3), blocos de 30 s, 4 threads, sherpa-onnx 1.13.2. Script: `docs/medicoes/f2-11/comparar_modelos_no_pc.py`.

| Modelo | Licença | Download | Diferença para o large-v3 | Tempo/duração (PC) | Pior bloco de 30 s | Leitura |
|---|---|---:|---:|---:|---:|---|
| **Whisper turbo** (no app) | MIT | 537 MB | **17%** | 0,54 | 23,5 s | O melhor texto |
| Parakeet TDT 0.6B v3 (NVIDIA) | CC-BY-4.0 | 464 MB | 31% | **0,11** | 5,2 s | Bom texto, com pontuação, 5× mais rápido; erra algumas frases |
| Cohere Transcribe 14 idiomas | a confirmar | 1621 MB | 35% | 0,29 | 12,5 s | Texto bom, às vezes mais certo que a referência ("US Open" onde o large-v3 diz "USO"), mas ~2,7 GB em disco |
| FastConformer pt (NVIDIA) | a confirmar | 98 MB | 51% | 0,03 | 1,3 s | Rápido, mas palavras emendadas e cortadas |
| Omnilingual 300M (Meta) | Apache-2.0 | 278 MB | 69% | 0,24 | 11,7 s | Sem pontuação e muito erro |

- Parakeet com o áudio inteiro (sem cortar em 30 s) piorou: 38%, com RTF de 0,16.
- Qwen3-ASR (Alibaba) não foi testado por causa da D-024.
- Limite: a referência é outro modelo, que também erra (o Cohere acertou "US Open"), e são só 3 áudios de uma pessoa.
- Conclusão: o turbo continua no app. O **Parakeet v3 é o plano B** se o turbo ficar lento no S25: é 5× mais rápido, perde pouca qualidade e o sherpa-onnx do app já o suporta (troca de configuração, não de motor).

## 8. Troca para o Parakeet (2026-11-08, escolha do dono)
- O dono preferiu o Parakeet TDT 0.6B v3 ao Whisper turbo por ele não ter o limite de 30 s. No app: `WhisperService` (nome mantido) baixa `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8` (~470 MB, CC-BY-4.0) do release do sherpa-onnx e roda como transdutor NeMo na CPU, com 4 threads. A pasta do Whisper turbo e a do SenseVoice são apagadas depois do download.
- O áudio continua em pedaços de no máximo 30 s, agora por escolha e não por limite: nas notas do dono, o áudio inteiro de 5 min ficou pior (38% contra 31%), e o corte mantém a memória estável em gravação longa. Por escolha do dono, o corte é feito **na pausa**: nos 10 s antes de cada marca de 30 s, o app corta no 0,1 s de menor energia (`splitAtPauses`). Em duas notas reais, os 20 cortes caíram em trechos com 0% a 36% da energia mediana da fala. A qualidade da transcrição com esse corte não foi medida.
- O Parakeet escolhe sozinho o idioma entre os 25 que conhece; não há opção para fixar o português.
- `NOT_RUN` no S25: download, extração, memória, velocidade e qualidade.

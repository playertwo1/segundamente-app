# F7-03 — Voz full duplex (conversa por voz mãos-livres)

Data: 2026-11-11. Estado: **IN_PROGRESS** — código e testes prontos; **medição da sonda no S25 feita em 2026-11-11: o eco não está controlado**; por decisão do dono a interrupção é **por toque, com o microfone fechado enquanto o app fala** (D-049, que substitui D-048); a entrada no chat está ligada (`AppConfig.enableDuplexVoice = true`); a tela ainda não foi executada no aparelho (`NOT_RUN`). Decisões: D-047, D-048, D-049.

## 1. O que foi investigado (código existente)

| Peça | O que existe | Serve para duplex? |
|---|---|---|
| Ditado do chat (`VoiceDictationViewModel`) | Toca para gravar, toca para parar; junta todo o PCM e transcreve no fim | **Não.** Sem detecção de fala, sem turno automático, sem voz. Ficou como está. O padrão (funções de plataforma injetáveis, `record` em PCM 16 kHz) foi copiado |
| Transcrição (`SpeechTranscriptionService.transcribeSamples`) | Parakeet local (sherpa-onnx) ou nuvem (endpoint do ChatGPT / modelo configurado) | **Sim**, reutilizada sem mudança |
| Detecção de voz | Silero VAD (`assets/silero_vad.onnx`, sherpa-onnx 1.13.2), usado pela gravação rápida (`StreamingTranscriber`) | **Sim**, mesmo modelo, com limiares de conversa |
| Áudio em fluxo | `record` 6.1.2 (`startStream`), com `echoCancel`, `noiseSuppress` e fonte `voiceCommunication` no Android | **Sim**; o cancelamento de eco da plataforma já vem no pacote |
| Voz sintetizada | **Não existia** (nenhum `TextToSpeech`, `flutter_tts` ou TTS do sherpa) | Criado canal nativo `com.memexlab.memex/tts` sobre o `android.speech.tts.TextToSpeech` |
| Resposta do modelo | `MemexRouter.sendMessage` (chat do SuperAgent, eventos em fluxo) | **Sim**, em modo somente leitura |
| Para onde vão os dados | `describeDataRoutes` (F1-09) | **Sim**, mostrado na tela antes do início |

**Dependência nova: nenhuma.** `flutter_tts` (MIT) foi descartado: o canal nativo tem ~120 linhas e o projeto já tem o padrão `ChannelRegistrar`. TTS por modelo (sherpa/Piper) foi descartado: exigiria baixar modelo de dezenas de MB sem ganho medido.

## 2. Por que não depende do modelo local (F7-02)

O ROADMAP lista F7-02 como dependência da F7-03. A dependência não é técnica: o duplex usa a transcrição que o app já tem (local Parakeet **ou** nuvem), o modelo de chat já configurado e a voz do sistema Android. Nenhuma parte precisa de um LLM no aparelho. O que a F7-02 daria é a opção "conversa por voz sem nuvem na resposta"; isso continua bloqueado por D-041 e **não foi tocado**. F7-02 segue `BLOCKED`.

## 3. O que foi implementado

- `lib/data/services/duplex_voice_service.dart` — microfone em fluxo + VAD + voz do sistema. Áudio só em memória. `release()` executa todos os passos mesmo se um falhar.
- `lib/ui/chat/view_models/duplex_voice_viewmodel.dart` — estados `idle → starting → listening → thinking → speaking`, mais `paused`. Um contador de época descarta transcrição, resposta ou fala que voltarem depois de pausa, cancelamento ou erro.
- `lib/ui/chat/widgets/duplex_voice_screen.dart` — indicador do microfone sempre visível (com rótulo de acessibilidade em região viva), rota dos dados, iniciar / pausar / retomar / encerrar (botões de 56 dp, um toque).
- `android/.../channels/TtsChannelHandler.kt` + `<queries>` do `TTS_SERVICE` no manifesto.
- Strings em `app_pt.arb` e `app_en.arb` (prefixo `duplex`), fontes regeneradas com `flutter gen-l10n`.
- Entrada: botão no chat do SuperAgent, ao lado do microfone, ligado por `AppConfig.enableDuplexVoice` (D-048).

Comportamento de privacidade:

| Requisito | Como é atendido |
|---|---|
| Permissão só após ação explícita | `requestPermission` só é chamado dentro de `start()`, que só o botão "Iniciar conversa" chama. Abrir a tela não pede nada (teste) |
| Sem escuta em segundo plano | A tela encerra a conversa em `paused`/`hidden`/`detached`; `inactive` fica de fora porque o diálogo de permissão o provoca. Sem serviço em primeiro plano, sem permissão nova |
| Microfone visível | Indicador mostra ligado em `listening` e `thinking` e desligado em `speaking`, acompanhando o fluxo de fato (`micActive` lê o serviço) |
| O que o microfone faz em cada estado | `listening`: detecta e guarda a fala em memória até o fim do turno. `thinking`: o áudio é descartado antes do detector. `speaking`: fluxo fechado (D-049); o botão "Interromper e falar" cala a voz e reabre o microfone. `paused`/`idle`: fluxo fechado |
| Pausa e cancelamento em um toque | Pausar fecha o fluxo do microfone (não é só ignorar) e cala a voz; encerrar libera microfone, voz e detector |
| Erro / perda de permissão | Qualquer erro, fim inesperado do fluxo do microfone ou falha do modelo → libera tudo, volta a `idle`, mostra mensagem |
| Sem áudio em disco | Nenhuma escrita de arquivo no serviço nem no ViewModel. O **texto** do turno entra no histórico do chat (sessão normal) |
| Provedor e fluxo antes do envio | A tela mostra transcrição (no aparelho ou provedor + host), conversa (provedor, modelo, host) e voz (sistema Android). Sem modelo válido o botão de iniciar fica desativado |
| Registros do usuário | O turno falado vai em modo somente leitura (`isQuickQuery`, `read_only`): fala mal transcrita não cria nem altera cartão |

## 4. Testes (2026-11-11, Windows, Flutter em `C:\Users\notefael\tools\flutter`)

`flutter test` nos quatro arquivos → `+36: All tests passed!`

- `test/data/services/duplex_voice_service_test.dart` (6): abertura só sob pedido, corte em falas, reagrupamento de pedaços, descarte, fechamento, fim do fluxo como erro, liberação com falha.
- `test/ui/chat/view_models/duplex_voice_viewmodel_test.dart` (18): início, permissão negada, modelo de fala ausente, turno completo, **interrupção**, descarte enquanto pensa, pausa/retomada, cancelamento, erros, perda do microfone, `dispose`.
- `test/ui/chat/widgets/duplex_voice_screen_test.dart` (11): indicador, rota dos dados, controles, mensagens de erro e permissão, segundo plano, fechar a tela.
- `test/integration/duplex_voice_pipeline_test.dart` (1): tela → ViewModel → serviço → roteador, com PCM sintético e interrupção.

Limite dos testes: microfone, modelo Silero, motor de voz, transcritor e resposta do modelo são dublês. O detector dos testes é um limiar de energia, não o Silero. Nada disto prova eco, latência ou o canal Kotlin em execução.

## 5. Medição no S25 (2026-11-11, sonda `tools/f703_probe`)

Galaxy S25 Ultra (SM-S938B, Android 17), 22:20–22:36. Volume de mídia 8/15 (estava em 0; subido pelo adb com autorização do dono e devolvido a 0 no fim), Não perturbar ligado, cabo USB conectado, motor de voz `com.google.android.tts`. Frase sintética fixa de ~13 s; nenhum áudio gravado. Números brutos: `docs/medicoes/f7-03/s25.jsonl`. A sonda foi desinstalada depois.

**Eco** — disparos do detector de voz durante a fala do próprio aparelho, com o dono em silêncio (duas rodadas):

| Configuração | Disparos (rodada 1 / 2) | Nível no microfone durante a fala |
|---|---:|---:|
| `mic_sem_aec` (microfone comum) | 1 / 1 | −20 dBFS |
| `mic_aec` (microfone comum + cancelamento de eco) | 1 / 2 | −20 dBFS |
| `voz_aec` (microfone de chamada + cancelamento; **a do app**) | 2 / 2 | −22 dBFS |
| `voz_aec_saida_chamada` (idem, com a voz saindo como áudio de chamada) | 0 / 1 | −80 / −73 dBFS |

- Com a voz saindo como mídia pelo alto-falante, o cancelamento de eco do S25 **não atenua nada** (−20 a −22 dBFS nas três primeiras). A configuração que o app usa se interromperia sozinha em toda resposta.
- Só a saída "de chamada" derruba o eco (~55 dB), mas, segundo o dono, a voz sai **baixinha, pelo alto-falante de ouvido**. Não serve para mãos-livres.

**Resistência** (5 min 7 s, `voz_aec_saida_chamada`, dono em silêncio): 15 falas, **25 disparos falsos**. A sonda não separa eco de ruído do ambiente, mas é mais de um disparo por fala mesmo na melhor configuração.

**Interrupção** (`voz_aec_saida_chamada`):

| Série | Resultado |
|---|---|
| Dono em silêncio (confirmado por ele) | 2 de 5 falas interrompidas sozinhas, aos 10,2 s e 11,6 s: disparo falso |
| Dono instruído a dizer "espera" ~3 s após o início | 5 de 5 interrompidas, detecção entre 1,6 s e 3,5 s após pedir a fala |

- Tempo entre detectar e o motor aceitar a parada: **4–8 ms** (7 medidas). É a ida e volta do canal, não o silêncio audível.
- O dono confirmou que falou "esperar" na segunda série. A sonda sozinha não distingue voz de disparo falso, mas os tempos (1,6–3,5 s contra ≥10 s sem fala) batem com o relato: a voz dele por cima da síntese foi detectada nas 5 rodadas.

**Outras medidas**

| Medida | Resultado |
|---|---|
| Tempo até a voz começar (`speak` → `onStart`), motor já carregado | 51–73 ms (17 medidas) |
| Idem, primeira fala (carrega o motor) | 554 ms (1 medida) |
| Temperatura em 5 min | bateria 31,7 → 31,1 °C; processador 34,1 → 32,7 °C; superfície 31,8 °C no fim. Sem aquecimento |
| Bateria em 5 min | 79% → 79%, **inconclusivo**: o aparelho estava carregando pelo USB |
| Latência ponta a ponta no app (fim da fala → primeira palavra) | `NOT_RUN` |
| Canal `TtsChannelHandler` e a tela do app no aparelho | `NOT_RUN` — o debug `globalDev` é outro pacote, sem login nem modelo configurado; o app do dono (`app.segundamente`, assinado para release) não foi tocado |
| Eco com fone de ouvido (com fio ou Bluetooth) | `NOT_RUN` |

**Conclusão:** no alto-falante do S25, a interrupção por voz como implementada não funciona — o app ouviria a própria resposta. Calar a voz depois de detectar é rápido; o problema é só o eco. **O dono primeiro aceitou esse comportamento (D-048) e depois escolheu a interrupção por toque (D-049): o microfone fica fechado enquanto o app fala, então o eco deixa de alcançar o detector.**

## 6. Limitações conhecidas

- Não há "falar por cima" (D-049): a resposta só é interrompida pelo botão. Fechar e reabrir o microfone a cada resposta tem um custo de tempo não medido no aparelho.
- A resposta só é falada depois de completa (sem fala por frases): a latência até a primeira palavra é o tempo inteiro do modelo.
- Encerrar ou pausar enquanto o modelo responde não cancela o pedido já enviado (o chat não tem cancelamento de execução); a resposta chega ao histórico, só não é falada.
- Turno de fala com mais de 30 s é cortado em dois.
- Resposta com mais de 4000 caracteres é cortada na fala (limite do motor).
- Modelo de fala local não baixado: a tela avisa e manda baixar pelo microfone do chat; não baixa sozinha.
- A voz do sistema é a que estiver configurada no Android; se o motor escolhido usar voz de rede, o texto da resposta vai ao fornecedor do motor. A tela diz "voz do sistema Android", não garante que é local.
- Sem tratamento de foco de áudio (outra mídia tocando não é pausada) nem de fone Bluetooth além do padrão do `record`.
- Só Android. O canal `tts` não existe no iOS.

## 7. O que falta

1. **Decidido em D-049: opção A, implementada.** B e C ficam como reserva:
   - **A. Interrupção por toque no alto-falante:** enquanto o app fala, o microfone fica fechado; um toque cala a voz e volta a ouvir. Resolve o eco, perde o "falar por cima". É a mudança menor (o estado `speaking` deixa de alimentar o detector).
   - **B. Falar por cima só com fone:** manter a interrupção por voz quando houver fone conectado e usar A no alto-falante. Precisa medir o eco com fone antes (`NOT_RUN`).
   - **C. Modo "telefone":** voz pelo alto-falante de ouvido, aparelho no rosto. Elimina o mãos-livres; mesmo assim houve disparos falsos.
   - Recomendação: A agora; B depois, se a medida com fone for boa.
2. Medir o consumo de bateria fora do carregador (adb por Wi-Fi) e repetir a resistência.
3. Instalar um build com a entrada ligada num app com modelo configurado e validar no aparelho início, interrupção, pausa, cancelamento, permissão negada/revogada, tela apagada e a latência ponta a ponta.
4. F7-06 (auditoria) continua `BLOCKED`.

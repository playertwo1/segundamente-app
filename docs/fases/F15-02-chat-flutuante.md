# F15-02 — Chat flutuante

> Subfase da [F15](../roadmap/F15-widget-e-atalhos-android.md). Visual decidido na F15-01 ([maquetes](F15-01-maquetes.md), D-064). Desenho técnico em D-065.

## O que entrega

Uma folha de chat por cima da tela inicial, sem abrir o app inteiro.

- **Conversar:** conversa nova com a Segunda Mente, com o teclado aberto.
- **Falar:** conversa nova que já começa ouvindo. Ao fim da fala, a frase é transcrita e enviada sozinha; a frase fica visível na conversa.
- Aviso da F11-06 sob o campo (`ContentNoticeCaption`, já no `AgentChatDialog`).
- **Abrir no app:** leva a conversa para o app inteiro.
- **Fechar** (ou voltar, ou tocar fora da folha): volta para a tela de origem.
- A resposta da IA não grava nada sozinha: cartões de confirmação da F11-05 continuam valendo (D-051).

Entrada até existir o widget (F15-03): dois atalhos do ícone do app (toque longo), "Conversar" e "Falar".

## Desenho

### Um motor Flutter, dois hosts

O app e a folha usam o **mesmo** `FlutterEngine`, guardado no `FlutterEngineCache` com o ID `segundamente_main`. Dois motores seriam dois isolates Dart no mesmo processo, cada um com seu `LocalTaskExecutor`, sua conexão SQLite e seus singletons, o que arrisca tarefas duplicadas e gravações concorrentes.

- `SharedFlutterEngine.ensure(activity)` (Kotlin) cria o motor na primeira vez, registra os channels com `ChannelRegistrar.registerAll(engine, activity)` **antes** de rodar o `main()` do Dart, e só então chama `executeDartEntrypoint(DartEntrypoint.createDefault())`. Assim nenhuma chamada de channel do `main()` encontra handler ausente.
- `MainActivity` e `FloatingChatActivity` sobrescrevem `getCachedEngineId()` para chamar `ensure`. O motor não é destruído com a Activity.
- **Um host por vez:** um motor só se liga a uma Activity. Ao criar a `FloatingChatActivity`, a `MainActivity` viva é encerrada (`finish()`), e vice-versa. O estado Dart continua no motor.
- `configureFlutterEngine` de cada Activity chama `ChannelRegistrar.registerAll(engine, this)` de novo, para os handlers apontarem para a Activity atual.

### FloatingChatActivity

- `FlutterFragmentActivity` com fundo transparente (`getBackgroundMode()` = `transparent`).
- Tema `FloatingChatTheme` translúcido (`Theme.Translucent.NoTitleBar`, fundo transparente, barras transparentes).
- Manifest: `exported="true"`, `launchMode="singleTask"`, `taskAffinity="${applicationId}.floating"`, `excludeFromRecents="true"`, `windowSoftInputMode="adjustResize"`. Tarefa própria: ao fechar, o Android volta para o que estava antes (tela inicial ou outro app).
- Extra do intent: `floating_chat_mode` = `type` ou `talk`.

### Contrato do channel

MethodChannel `com.memexlab.memex/floating_chat`.

| Sentido | Método | Argumentos | Efeito |
|---|---|---|---|
| Dart → nativo | `takePendingMode` | — | Devolve `"type"`, `"talk"` ou `null` e limpa o pendente |
| Dart → nativo | `close` | — | `finish()` da `FloatingChatActivity` atual |
| Dart → nativo | `openInApp` | — | Abre a `MainActivity` e encerra a `FloatingChatActivity` |
| nativo → Dart | `open` | — | Sinal: há modo pendente; o Dart chama `takePendingMode` |

O nativo guarda o modo pendente ao receber o intent (`onCreate` e `onNewIntent`) e manda `open` quando já está ligado ao motor. O Dart também chama `takePendingMode` no `main()`, antes de criar o router, para a primeira tela já ser a folha (sem piscar a tela principal na partida a frio).

### Lado Dart

- `FloatingChatService` (`lib/data/services/floating_chat_service.dart`): singleton com channel injetável para teste. `takePendingMode()`, `openRequests` (stream), `close()`, `openInApp()`. Enum `FloatingChatMode { type, talk }` em `lib/domain/models/floating_chat_mode.dart`.
- Rota `AppRoutes.floatingChat` (`/floating-chat?mode=type|talk`): página opaca com fundo transparente, para as rotas de baixo não pintarem e a tela inicial do Android aparecer atrás.
- `createAppRouter` aceita `initialLocation`; o `main()` passa a rota da folha quando há modo pendente.
- `MemexApp` escuta `openRequests` e empurra a rota da folha.
- `FloatingChatScreen` (`lib/ui/floating_chat/widgets/floating_chat_screen.dart`): `Scaffold` transparente com o `AgentChatDialog(initialSessionId: null)` em modo flutuante.
- `AgentChatDialog` ganha parâmetros opcionais, sem mudar o uso atual:
  - `floatingHost` (`onClose`, `onOpenInApp`): no cabeçalho, "Abrir no app" e "Fechar" em texto no lugar dos ícones; o toque fora e o botão de fechar chamam `onClose` em vez de `Navigator.pop`.
  - `autofocusInput`: foca o campo ao abrir (Conversar).
  - `listenOnStart`: começa ouvindo (Falar) e mostra "Ouvindo" com "A mensagem parte sozinha ao fim da fala."
- `ListenOnceViewModel` (`lib/ui/floating_chat/view_models/listen_once_viewmodel.dart`): usa o `DuplexVoiceService` (detector de fim de fala) e o `SpeechTranscriptionService`. Ouve uma fala, fecha o microfone, transcreve e entrega o texto. Estados: ouvindo, transcrevendo, sem permissão, modelo de voz ausente, erro. Sem permissão ou sem modelo, mostra o motivo e deixa o teclado como saída.
- **Fechar:** `FloatingChatService.close()` e depois `router.go('/')`, nessa ordem, para não pintar a tela principal na folha.
- **Abrir no app:** `router.go('/')`; se a conversa já tem sessão, pede `AppActionService.quickNoteAction`, que abre o chat na sessão mais recente; depois `FloatingChatService.openInApp()`.

## Evidência de aceite (da linha da F15-02)

- Abertura a frio medida no S25.
- Teclado ou microfone conforme o toque.
- Volta para a tela de origem ao fechar.
- Testes de widget e de integração.

## Riscos

- A `MainActivity` passa a usar motor em cache: fechar o app pelo voltar não destrói mais o Dart. A próxima abertura é morna e volta para onde o usuário estava.
- `getCachedEngineId()` e `getBackgroundMode()` precisam ser sobrescrevíveis na versão do embedding; o build confirma.
- Folha transparente usa `TextureView`, um pouco mais cara que `SurfaceView`.
- O detector de fim de fala ainda não foi calibrado no S25 (parâmetros da F7).

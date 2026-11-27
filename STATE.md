# STATE — ponto de retomada

**Atualizado:** 2026-11-27 · **MVP:** pronto (portão da F5 fechado em 2026-11-05, `docs/reviews/F5.md`: AUDIT RESULT: PASS) · **Última release:** 1.0.20 (2026-11-27, GitHub Release) · **Fase ativa:** F16 — Ponte BLE (`IN_PROGRESS`, falta S25); F14 — Assistente ativo (`REVIEW`, `D-074`, falta S25); F12 — Sync com o Lumen (`IN_PROGRESS`, `D-066`)

Este arquivo guarda só o estado atual, a próxima ação e as evidências recentes. O estado de cada fase está no [ROADMAP](ROADMAP.md). Evidências antigas ficam em [docs/arquivadas/state/](docs/arquivadas/state/).

## Fases em andamento

- **F14 — Assistente ativo:** `REVIEW` (D-074). F14-01 a F14-03 com código e testes no celular; S25 `NOT_RUN`. Calendar (F13-04) e Lumen (F12-06) entram depois.
- **F16 — Ponte BLE com a placa ESP32-S3 AMOLED:** `IN_PROGRESS`. F16-01 a F16-06 com código Android nativo + Flutter e testes de unidade/widget; S25 e placa física `NOT_RUN`. Testes: `flutter test --no-pub` nos 2 arquivos novos de `esp32` (6 de serviço + 1 de widget, 0 falhas).
- **F15 — Widget e atalhos:** F15-02 a F15-08 com código na `main`. Bolha da versão pública em `REVIEW` (D-078). S25 `NOT_RUN`.
- **F12 — Sync com o Lumen:** `IN_PROGRESS` (D-066). F12-02 a F12-05 DONE; F12-01 espera o dono ler o contrato; F12-06 e F12-07 READY.

## Próxima ação

1. **Validar no S25 o Todo e a tela do registro:** confirmar cartão com subtarefas em “Tarefas deste registro”, conferir a lista e Desfazer, verificar o estado das permissões e disparar um lembrete. Conferir também balões, deslizar para responder e citação.
2. **Validar a F14 no S25:** na aba Todo, o painel do Assistente Ativo (resumo manhã/tarde, tarefas paradas, sugestões das personas pelo `TodoProposalCard`, silêncio).
3. **Validar F15-02 a F15-08 no S25:** chat flutuante pelos atalhos, continuidade da conversa ao alternar entre o app e a bolha, widgets pequeno, médio e grande, painel rápido e **Configurações → Bolha do chat**. Também os pontos R01, R02, R04 e R05 de `docs/reviews/F15.md`. O texto do limite de Falar (R03) aguarda decisão do dono.
4. **F12:** F12-01 (schemas finais da v1.1 e chunking acima de 64 KiB), depois F12-06. O S25 dev está revogado: parear de novo antes da F12-06 e conferir o rótulo "sem conexão" com o modo avião. Abertos no Lumen: QR maior e edição de horário que não salva.
5. **Conferir no S25:** confirmar no `logcat` que o erro de cold start do `FlutterSecureStorage` (`Could not decrypt key`) não aparece mais após o ajuste de `AndroidOptions` e exclusão do Auto Backup.
6. **Validar F2-11 no S25:** baixar o Whisper turbo, gravar em português e medir qualidade, latência e memória em gravação longa.

## Pendências do dono

- Criar o projeto Google Cloud em produção sem verificação (F13-01, D-055).
- Escolher o visual do Lumen no protótipo (Fase L1 do fork).
- Ler o texto final de `docs/lumen/CONTRATO-SYNC.md` (F12-01).
- Apagar a `PONTE 6` e a `PONTE 7` no Lumen, e o link `coucou://pair…` do histórico da área de transferência do teclado do S25.

## Ambiente (fora do repositório)

- Flutter em `C:\Users\notefael\tools\flutter`, fora do PATH: usar `C:\Users\notefael\tools\flutter\bin\flutter`. `flutter config --jdk-dir` aponta para o JDK 17 em `C:\Users\notefael\AppData\Local\Programs\jdk-17` (o Java 25 padrão quebra o Gradle 8.14).
- O Flutter 3.47 reescreve `analysis_options.yaml` e `android/gradle.properties` ao rodar `pub get`, build ou test: reverter com `git checkout` antes de commitar. Usar `flutter pub get --enforce-lockfile`.
- Aparelho de prova: Samsung Galaxy S25 Ultra (Android 17). Keystore de release local em `android/key-global.properties`, fora do git.

## Linha de base de qualidade

- `main` `91feef7e` (2026-11-15, F15 integrada): `flutter test --no-pub --reporter compact` com 1.972 aprovados, 4 ignorados e 0 falhas; `flutter analyze --no-pub` com 170 issues (11 errors, todos em `tools/f610_probe`, sonda fora do app sem `pub get`; os outros 159 são a linha de base).

## Evidências recentes

### Release 1.0.20: correção do Conectar da placa BLE (2026-11-27)

- APK `segundamente_global_1.0.20_156.apk` (`129046583` bytes, SHA-256 `0547a8d9a77c4fafd8ee1a68f3861969bf883b80b3fd9133f2417a738ab5f9ae`), `versionCode` `156` / `versionName` `1.0.20`. Certificado `216c29ff…ee05f`, igual ao da `1.0.15`. Notas em [docs/releases/v1.0.20.md](docs/releases/v1.0.20.md).
- `flutter test --no-pub` → `+2222 ~2: All other tests passed!`. `flutter build apk --flavor global --release --no-pub` → OK.
- `NOT_RUN`: S25 com a placa física.

### Release 1.0.15 + Ponte BLE F16 (2026-11-27)

- APK `segundamente_global_1.0.15_154.apk` (`129046583` bytes, SHA-256 `f8e44d4405a63d21792d4c979f7c81ec3cc631bb2b04c9b995fe667230a3fdc7`), `versionCode` `154` / `versionName` `1.0.15`, pacote `app.segundamente`. Certificado `216c29ff…ee05f`, igual ao da `1.0.14`. Notas em [docs/releases/v1.0.15.md](docs/releases/v1.0.15.md).
- `flutter test --no-pub --reporter compact` → `+2219 ~2: All other tests passed!` (0 falhas). `flutter analyze --no-pub` nos arquivos da F16 → `No issues found!`. `flutter build apk --flavor global --release` → `BUILD_EXIT=0` (Kotlin + Gradle + R8 OK).
- `NOT_RUN`: validação presencial da F16 no Galaxy S25 Ultra com a placa física (pareamento PIN 6 dígitos, sync bidirecional de tarefas, WhatsApp em ≤ 5 s 3x, Wi-Fi/cidade/personagem, revogação e conferência de logs).

### Assistente Ativo: despertar da persona com o app em segundo plano (2026-11-25, PR #2)

- Publicada na release 1.0.14 (+153), junto com o PR #1, ver [docs/releases/v1.0.14.md](docs/releases/v1.0.14.md).

- Causa confirmada no código: ao terminar com trabalho futuro (o despertar da persona), o `AgentQueueBackgroundWorker` se reagendava sob o mesmo nome único `agent_queue_drain` com `KEEP`. Para o WorkManager, o worker em execução ainda é trabalho pendente, então o pedido era descartado. Fora do app, o despertar só rodava quando o app abria, e aí o aviso é suprimido porque o chat está visível.
- Correção: o reagendamento vai para `agent_queue_drain_follow_up`. Ele usa `REPLACE` vindo do dreno imediato e `APPEND_OR_REPLACE` vindo do próprio follow-up. Quando outra instância é dona da fila e nada está devido, o adiamento espera o próximo trabalho em vez de 30 s, para o app aberto não acordar um dreno a cada 30 s.
- CI: `subosito/flutter-action` fixado em `3.47.9`. O stable flutuante (3.50.1) quebrava o `pub get`.
- `flutter test --no-pub --reporter compact` → `+2210 ~2: All other tests passed!`. `flutter analyze --no-pub` nos arquivos alterados → só o aviso antigo `unawaited_return_in_try_block` em `health_service.dart:352`.
- Não alterado, falta decisão do dono: persona principal marcada e desativada não restaura o despertar (`getPrimaryCompanion`); com 3 erros temporários seguidos, o laço só volta na próxima abertura do app.
- `NOT_RUN`: S25. Roteiro: instalar, ligar uma persona principal, fechar o app pelo gesto de recentes (não “Forçar parada”), esperar o despertar fora do silêncio e conferir o aviso; `adb shell dumpsys jobscheduler | grep agent_queue` deve listar o follow-up.

### Relatório: citação ausente descarta só o item (2026-11-25, PR #1)

- `sessionReportFromModelJson`: `excerpt` ausente, nulo ou em branco agora vira descarte do item via `onSkip` (`excerpt missing`), em vez de abortar o relatório. Continua lançando quando nenhum item sobra.
- `flutter test --no-pub test/domain/models/session_report_test.dart` → `+26: All tests passed!` (2 testes novos, as duas ordens). `flutter analyze --no-pub` nos dois arquivos → só 10 `prefer_const` da linha de base.
- `NOT_RUN`: suíte completa e S25.

### Release 1.0.11 (2026-11-25)

- APK `segundamente_global_1.0.11_150.apk` (`128980779` bytes, SHA-256 `0ee054b64afbdcedb0c458d1d668d2d4614b06602216623068044dd978ea8d20`), `versionCode` `150` / `versionName` `1.0.11`, pacote `app.segundamente`. Certificado `216c29ff…ee05f`, igual ao da `1.0.10`. Notas em [docs/releases/v1.0.11.md](docs/releases/v1.0.11.md).
- Bolha do chat (`cbc1bb50`, integrada à `main` pelo commit `586c6e85`): se a bolha estiver ligada, ela volta sozinha ao abrir o app, mesmo após fechar a conversa ou o Android encerrar o app. Desligar nas configurações continua removendo.
- `gradlew.bat :app:testGlobalDebugUnitTest` (JDK 17) → `BUILD SUCCESSFUL in 28s`; `ChatBubbleTest` `tests=1 failures=0 errors=0`.
- Inclui tudo da `1.0.10`.
- `NOT_RUN`: instalação/validação física da bolha no Galaxy S25 Ultra; suíte Flutter completa nesta release.

### Release 1.0.10 (2026-11-24)

- APK `segundamente_global_1.0.10_149.apk` (`128980779` bytes, SHA-256 `82cec81bd2134b750cf320adad1eb51fce1e5e241e6a63ce670a08d024ec89d9`), `versionCode` `149` / `versionName` `1.0.10`, pacote `app.segundamente`. Certificado `216c29ff…ee05f`, igual ao da `1.0.9`. Notas em [docs/releases/v1.0.10.md](docs/releases/v1.0.10.md).
- Inclui a conferência de citação por item (F3-07) e tudo da `1.0.9`.
- `NOT_RUN`: instalação/validação física no Galaxy S25 Ultra.

### F3-07: citação conferida por item (2026-11-24)

- **Mudança:** item com trecho fora do segmento, segmento desconhecido ou relógio errado é descartado sozinho e registrado em log (`report item skipped`); a resposta sem nenhum item válido continua falhando. Aspas tipográficas e espaços diferentes não derrubam mais o item, e a citação guardada é sempre o trecho exato do original. Ideia do ontosmith (MIT), reimplementada sem copiar código.
- `flutter test --no-pub test/domain/models/session_report_test.dart` → `+24: All tests passed!` (inclui 4 testes novos: aspas e espaços, item inventado, segmento desconhecido com relógio errado, resposta toda inválida).
- `pdf_import_service_test.dart`, "a quote from the wrong page is refused": a resposta continua recusada, agora com `items empty`, porque o item da página errada é descartado sozinho e nada sobra. Só a mensagem esperada mudou.
- `flutter test --no-pub --reporter compact` (suíte inteira) → `+2206 ~2: All other tests passed!`.
- `flutter analyze --no-pub` → `176 issues found` no repositório; nos 4 arquivos alterados, `10 issues found`, todos `prefer_const_constructors` (info) em linhas que já existiam, nenhum nas linhas novas.
- Validação no S25: NOT_RUN.

### Release 1.0.9 (2026-11-23)

- APK `segundamente_global_1.0.9_148.apk` (`128980775` bytes, SHA-256 `0e2d69ab802ef4d1369b8b5529a409edec993214859683e5b88249c8f935c69d`), `versionCode` `148` / `versionName` `1.0.9`, pacote `app.segundamente`. Certificado `216c29ff…ee05f`, igual ao das anteriores. Notas em [docs/releases/v1.0.9.md](docs/releases/v1.0.9.md).
- A release `1.0.8` no GitHub continua como rascunho, sem APK; a última publicada antes desta era a `1.0.7`.
- `NOT_RUN`: instalação/validação física no Galaxy S25 Ultra e suíte completa do repositório.

### Personas não avisavam durante o dia (2026-11-25, branch `fix/persona-notificacao`)

- **Relato do dono:** as personas não falam nem mandam notificação durante o dia.
- **Causa (código):** a fala espontânea existe ([character_initiative_handler.dart](lib/data/services/task_handlers/character_initiative_handler.dart), laço de despertar em [character_initiative_service.dart](lib/data/services/character_initiative_service.dart), reagendado pelo próprio modelo via `wakeAt`). Mas, ao gravar a mensagem, só emitia evento interno de UI: nenhum código no repositório publicava notificação do sistema para mensagem de persona (`flutter_local_notifications` só era usado por [todo_alarm_service.dart](lib/data/services/todo_alarm_service.dart)). A mensagem ficava no chat, sem aviso.
- **Correção:** [persona_message_notifier.dart](lib/data/services/persona_message_notifier.dart) (canal `persona_messages`, só Android, não notifica com o app em primeiro plano), chamado pelo handler depois de gravar a mensagem. Teste em `character_initiative_handler_test.dart`.
- `flutter test --no-pub test/data/services/character_initiative_handler_test.dart` → `+8: All tests passed!`; `flutter analyze --no-pub` nos 2 arquivos de lib → `No issues found!`.
- `NOT_RUN`: validação no S25. Pendente de confirmar no aparelho: (1) permissão de notificação do app ligada e canal "Persona messages" não silenciado; (2) bateria do app em "Sem restrições" (o despertar em segundo plano depende do WorkManager, sujeito a Doze); (3) o toque na notificação ainda não abre o chat da persona (só abre o app). Frequência/horário continuam decididos pelo modelo; sem decisão D-xxx nova.
- Publicada na release 1.0.12 (+151), ver [docs/releases/v1.0.12.md](docs/releases/v1.0.12.md).
- **Toque abre o chat (branch `fix/persona-notificacao-abre-chat`):** o payload `persona:<id>` chega pelo mesmo tratador do plugin em [main.dart](lib/main.dart), vira a ação `open_persona_chat:<id>` no [AppActionService](lib/data/services/app_action_service.dart) e a tela principal abre `/persona_chat/<id>` (vale também com o app fechado, pela resposta de abertura). `flutter test --no-pub test/data/services/app_action_service_test.dart` → `+16: All tests passed!`; `flutter analyze --no-pub` em `main.dart` e `app_action_service.dart` → `No issues found!`. Sem teste de widget da navegação (a tela principal não tem teste de ações). S25 `NOT_RUN`.
- Publicada na release 1.0.13 (+152), ver [docs/releases/v1.0.13.md](docs/releases/v1.0.13.md).

### Bolha só aparecia pelas Configurações (2026-11-25, branch `fix/bolha-volta-ao-abrir-app`)

- **Relato do dono (S25):** a bolha só aparece se ele abre Configurações e toca nela; fechar a conversa não a traz de volta. Causa: a bolha só era publicada por ação explícita nas Configurações e `close` apagava a notificação sem lembrar a escolha.
- **Correção:** [ChatBubble.kt](android/app/src/main/kotlin/com/memexlab/memex/ChatBubble.kt) grava a escolha (`wanted`) em `show`, apaga só no desligar explícito (`hide`), e `MainActivity.onResume` chama `ChatBubble.restore` (republica se desejada e sem notificação ativa). Fechar a conversa mantém a escolha (`hide(forget = false)`).
- `gradlew :app:testGlobalDebugUnitTest --tests ChatBubbleTest` (JDK 17) → `BUILD SUCCESSFUL`.
- `NOT_RUN`: validação no S25. Não coberto: personas comentando sozinhas durante o dia (assunto à parte, F14); bolha não reaparece sem abrir o app (sem receiver de boot).

### Bolha do chat, captura flutuante e snapshot do widget (2026-11-23, não commitado)

- **Bolha:** canal `chat_bubble_v2` com `IMPORTANCE_HIGH` e `setAllowBubbles(true)` (o canal antigo é apagado), notificação sempre suprimida, ícone `launcher_icon`, `ChatBubbleActivity` com modo padrão `bubble`, fechar remove a bolha, abrir no app com `CLEAR_TOP` e cascata de telas de configuração. Ao voltar das configurações do Android, a tela de Configurações publica a bolha de novo ([chat_bubble_setting.dart](lib/ui/settings/widgets/chat_bubble_setting.dart)).
- **Captura flutuante:** dá para remover a foto escolhida (`clearImage`) e escolher outra. Durante o salvamento, a folha mostra progresso e fica travada.
- **Widget Todo:** tarefas sem data são ordenadas por prioridade, snapshots idênticos não são reenviados e um JSON inválido no lado nativo vira lista vazia.
- `flutter.bat test --no-pub --timeout 30s --reporter compact test/data/services/todo_widget_snapshot_service_test.dart test/ui/floating_chat/ test/ui/settings/widgets/chat_bubble_setting_test.dart` → `+62: All tests passed!`; `flutter.bat analyze --no-pub` nos 7 itens alterados → `No issues found!`.
- `gradlew :app:testGlobalDebugUnitTest` (JDK 17) → `BUILD SUCCESSFUL`, `WidgetLayoutsTest` 7/7. Corrigido antes um erro de compilação: `Settings.EXTRA_APP_UID` não é API pública.
- `NOT_RUN`: bolha, widget e captura no Galaxy S25 Ultra; suíte completa.

### Release 1.0.8 (2026-11-22)

- APK `segundamente_global_1.0.8_147.apk` (`128980775` bytes, SHA-256 `442e7b730e190e241564177baa7153891c02681a7f9cddff6372884b6d21353d`), `versionCode` `147` / `versionName` `1.0.8`, pacote `app.segundamente`. Notas em [docs/releases/v1.0.8.md](docs/releases/v1.0.8.md).
- Certificado `V2 Signer: CN=Segunda Mente, O=Segunda Mente, C=BR` com SHA-256 `216c29ff2c784b10b6bdf60a792a00e2d96c46ccafd9e4cb986f3a5f2c1ee05f` (idêntico ao da `1.0.7`).
- `python scripts/check_arb_key_parity.py` → `ARB key parity OK across 1 locales.`; `flutter.bat test --no-pub --timeout 30s --reporter compact test/data/services/app_update_service_test.dart` → `+25: All tests passed!`.
- `NOT_RUN`: instalação/validação física no Galaxy S25 Ultra e suíte completa do repositório.

### Polimento completo pós-auditoria (2026-11-22)

- **Timeline e Detalhe:** suprimido o modal bloqueante de `companion` + `default` no cold start ([main.dart](lib/main.dart), `shouldSuppressInvalidModelDialog`), suprimido o template `snapshot` duplicado quando há imagem no cabeçalho ([timeline_card_detail_screen.dart](lib/ui/timeline/widgets/timeline_card_detail_screen.dart)) e elevados os botões do cabeçalho para `48x48` com `tooltip` semântico e `Icons.arrow_back`.
- **Chat e Tokens:** migrados os tokens `_persona*` em [persona_chat_screen.dart](lib/ui/character/widgets/persona_chat_screen.dart) para `AppColors` (mantidas as bolhas âmbar/grafite testadas); corrigidos o contraste de botão/spinner em [system_action_card.dart](lib/ui/card_attachments/widgets/system_action_card.dart) (`AppColors.onPrimary`), o fundo/divisor de ferramenta em [agent_chat_dialog.dart](lib/ui/chat/widgets/agent_chat_dialog.dart) (`AppColors.surface` / `AppColors.divider`, `12sp`), o botão voltar de [editorial_scaffold.dart](lib/ui/core/widgets/editorial_scaffold.dart) (`Icons.arrow_back`), o `tooltip` e cores do visualizador em [media_library_screen.dart](lib/ui/media_library/widgets/media_library_screen.dart) e a exclusão de `FlutterSecureKeyStorage.xml` / `FlutterSecureStorageConfiguration.xml` no Auto Backup Android.
- **Auditoria e testes:** após apontamento do subagente `general-auditor` e correção de todos os achados HIGH e MEDIUM, `flutter.bat analyze --no-pub` nos 7 arquivos/diretórios tocados → `No issues found! (14.2s)`; `flutter.bat test --no-pub --timeout 30s --reporter compact` em `main_invalid_model_dialog_test.dart`, `floating_chat_flow_test.dart`, `test/ui/media_library/` (incluindo `media_library_viewmodel_test.dart`), `main_menu_drawer_test.dart`, `system_action_card_test.dart`, `timeline_card_detail_body_section_test.dart`, `persona_chat_screen_test.dart` e `agent_chat_dialog_test.dart` → `+89: All tests passed!`.
- `NOT_RUN`: nova captura no emulador/S25 após o segundo ciclo de polimento e suíte completa do repositório.

### Polimento após Impeccable Critique (2026-11-21)

- [main_menu_drawer.dart](lib/ui/main_screen/widgets/main_menu_drawer.dart): 14 destinos organizados em 3 grupos (Principal, Organização, Sistema) com divisores.
- [system_action_card.dart](lib/ui/card_attachments/widgets/system_action_card.dart) e [classic_card.dart](lib/ui/core/cards/templates/classic_card.dart): removidos azul iOS (`0xFF007AFF`) e gradiente roxo (`0xFF8B5CF6`) em favor de `AppColors`.
- [calendar_screen.dart](lib/ui/calendar/widgets/calendar_screen.dart): textos de `9`–`10sp` elevados para `12sp`.
- [media_library_screen.dart](lib/ui/media_library/widgets/media_library_screen.dart): subtítulo simplificado (`data · tamanho`).
- [widget_task_row.xml](android/app/src/main/res/layout/widget_task_row.xml): título em `maxLines="1"` com `ellipsize="end"`.
- [app_en.arb](lib/l10n/app_en.arb) e [app_pt.arb](lib/l10n/app_pt.arb): reescrita de `invalidModelConfigDetailed` sem jargão técnico.
- `python scripts/check_arb_key_parity.py` → `ARB key parity OK across 1 locales.`
- `flutter.bat analyze --no-pub` nos 5 arquivos Dart alterados → 0 erros/warnings (apenas 4 `info` preexistentes).
- `flutter.bat test --no-pub --timeout 30s --reporter compact test/ui/main_screen/widgets/main_menu_drawer_test.dart test/ui/calendar/ test/ui/media_library/ test/l10n/ test/ui/rtl/arabic_layout_smoke_test.dart` → `+18: All tests passed!`.
- `NOT_RUN`: nova captura no emulador/S25 após o polimento, testes JVM do widget Kotlin e suíte completa do repositório.

### Biblioteca agregada de fotos, PDFs e áudios (2026-11-21, D-081)

- Criados [media_library_item.dart](lib/domain/models/media_library_item.dart), [media_library_service.dart](lib/data/services/media_library_service.dart), [media_library_viewmodel.dart](lib/ui/media_library/view_models/media_library_viewmodel.dart) e [media_library_screen.dart](lib/ui/media_library/widgets/media_library_screen.dart), com filtro por tipo (`Todos`, `Fotos`, `PDFs`, `Áudios`), busca, visualização in-app (`PhotoView`, `pdfrx`, `AudioPlayerWidget`), compartilhamento e atalho para o registro de origem quando vinculado.
- Integrada em [memex_router.dart](lib/data/repositories/memex_router.dart), [routes.dart](lib/routing/routes.dart), [router.dart](lib/routing/router.dart), [main_menu_drawer.dart](lib/ui/main_screen/widgets/main_menu_drawer.dart), [main.dart](lib/main.dart), [knowledge_base_screen.dart](lib/ui/knowledge/widgets/knowledge_base_screen.dart) e localizações EN/PT (`app_en.arb`, `app_pt.arb`, `app_localizations*.dart`).
- `python scripts/check_arb_key_parity.py` → `ARB key parity OK across 1 locales.`
- `flutter.bat analyze --no-pub` nos 10 arquivos/diretórios alterados e criados → `No issues found! (17.7s)`.
- `flutter.bat test --no-pub --timeout 30s --reporter compact test/data/services/media_library_service_test.dart test/ui/media_library/widgets/media_library_screen_test.dart test/ui/main_screen/widgets/main_menu_drawer_test.dart test/l10n/` → `+15: All tests passed!`.
- `NOT_RUN`: validação visual/toque no Galaxy S25 Ultra e no emulador (visualizador `pdfrx`, `PhotoView` e `AudioPlayerWidget` com arquivos reais), e suíte completa do repositório.

### Correção do cold start do FlutterSecureStorage (2026-11-20)

- Causa raiz: o `flutter_secure_storage` `10.3.4` tenta inicializar `EncryptedSharedPreferences` na partida quando `migrateWithBackup` é `false` e não há marcador de migração, falhando com `SecurityException: Could not decrypt key` quando o arquivo vem restaurado sem a chave do KeyStore.
- Ajuste em [secret_storage.dart](lib/utils/secret_storage.dart) (`AndroidOptions(resetOnError: true, migrateWithBackup: true)`), exclusão de `FlutterSecureStorage.xml` do Auto Backup em [AndroidManifest.xml](android/app/src/main/AndroidManifest.xml), [backup_rules.xml](android/app/src/main/res/xml/backup_rules.xml) e [data_extraction_rules.xml](android/app/src/main/res/xml/data_extraction_rules.xml), e proteção de leitura em `UserStorage.getLLMConfigs()` e `getSavedTokens()` (`OpenAiAuthService`, `ClaudeAuthService`, `GeminiAuthService`).
- `flutter.bat analyze --no-pub` nos 6 arquivos Dart alterados → `No issues found! (79.1s)`.
- `flutter.bat test --no-pub --reporter compact test/utils/secret_storage_test.dart` → `+7: All tests passed!`.
- `flutter.bat build apk --flavor globalDev --debug --no-pub` → `Built build\app\outputs\flutter-apk\app-globaldev-debug.apk`. Instalado e iniciado no emulador `CoreFlow_API36_Clean` (`pidof app.segundamente.dev` = `4470`); `logcat` sem ocorrências de `FlutterSecureStorage`, `Could not decrypt` ou `EncryptedSharedPreferences`.
- `NOT_RUN`: Galaxy S25 Ultra (aparelho ausente) e suíte completa do repositório.

### Release 1.0.7 (2026-11-19)

- Nome público e tela de atualizações usam a versão sem o contador. APK com `versionCode` 146 para atualizar a instalação da v1.0.60, de código 145. Evidências em [docs/releases/v1.0.7.md](docs/releases/v1.0.7.md).
- 37 testes direcionados aprovados. Instalação via ADB sobre a 1.0.60 confirmada no Galaxy S25 Ultra. A validação dos fluxos da F15 no aparelho continua pendente.

### Release v1.0.60+145 (2026-11-19)

- O widget grande mostra tarefas sem data nas vagas. Capturar, Tarefas e Linha do tempo abrem seus destinos. A bolha retoma a conversa escolhida no histórico e, se não houver sessão, oferece **Abrir no app**.
- 53 testes Flutter direcionados aprovados no ajuste final. Evidências e assinatura em [docs/releases/v1.0.60.md](docs/releases/v1.0.60.md). Galaxy S25 Ultra `NOT_RUN`.

### Widget Android e continuidade do chat (2026-11-19, D-079)

- O widget grande inclui pendências sem data nas vagas, depois das atrasadas e de hoje. A barra abre Anotar, Todo e linha do tempo pelos respectivos atalhos.
- Conversar, Falar e a bolha carregam a sessão principal pelo mesmo resolvedor do chat do app. O código do atalho anterior abria sem sessão e não chamava exclusão de histórico.
- 49 testes direcionados Flutter e 6 testes Kotlin do widget aprovados. `flutter analyze --no-pub` nos 10 arquivos Dart alterados sem diagnósticos. A suíte completa teve 2.181 aprovações, 2 ignorados e um erro de remoção de arquivo temporário no Windows. O arquivo de teste afetado passou integralmente na repetição isolada (16 testes).
- `flutter build apk --flavor global --release --no-pub` gerou o APK de teste assinado. No Android 16 emulado, a tarefa sintética sem data existia no Todo e ficava ausente no widget da v1.0.59. Após atualizar sobre a instalação e abrir o app, a mesma tarefa apareceu no widget. O emulador perdeu o ADB durante a prova dos três atalhos. Galaxy S25 Ultra `NOT_RUN`.

### Release v1.0.59+144 (2026-11-18)

- Bolha nativa em **Configurações → Bolha do chat**. Transições polidas no chat e na linha do tempo, com redução de movimento, e ajustes na hierarquia da Inter.
- `flutter test --no-pub` com 2.178 aprovados, 2 ignorados e 0 falhas. Analyze direcionado com 2 infos já existentes na linha do tempo. Paridade EN/PT confirmada.
- APK global release assinado com o mesmo certificado da v1.0.58. No emulador Android 16, o APK assinado mostrou o pedido de notificação, abriu as permissões de bolha, abriu o chat sobre outro app e removeu a bolha ao desativar o controle. S25 `NOT_RUN`. Detalhes em [docs/releases/v1.0.59.md](docs/releases/v1.0.59.md).

### Release v1.0.58+143 (2026-11-18)

- Inclui cartões marcáveis no Todo, correção da leitura de permissões de lembretes e Whisper turbo em português. O README traz o download público e os passos de instalação.
- Suíte completa com 2.172 aprovados, 2 ignorados e 0 falhas. APK conferido, com o mesmo certificado da v1.0.57. Evidências e SHA-256 em [docs/releases/v1.0.58.md](docs/releases/v1.0.58.md). Galaxy S25 Ultra `NOT_RUN`.

### Prévia da bolha nativa no emulador (2026-11-18)

- F15-07, `globalDev`: antes da correção, o Android 16 publicava uma notificação comum (`mAllowBubble=false`) porque o atalho de conversa tinha só o bot. Incluído o usuário local como participante, o Android passou a marcar a notificação como `BUBBLE` e apresentou a janela nativa.
- `flutter build apk --flavor globalDev --debug --no-pub` → APK compilado. No emulador `CoreFlow_API36_Clean`, via ADB e Maestro Viewer: chat visível na bolha, recolhimento sobre Configurações e reabertura pelo ícone observados. S25 e critérios de autonomia `NOT_RUN`. F15-07 segue em andamento.

### Whisper turbo no lugar do Parakeet (2026-11-18, D-077)

- A opção de transcrição no aparelho usa Whisper large-v3 turbo int8 em português (`pt`). Mantém blocos de até 30 s com cortes nas pausas. O download fica nas Configurações e o Parakeet só é removido depois de extrair os arquivos do Whisper.
- A URL do release oficial do sherpa-onnx respondeu HTTP 200 após redirecionamento, com 563.790.207 bytes (~538 MiB).
- `flutter test --no-pub -r expanded --concurrency=4 test/data/services/whisper_service_test.dart test/data/services/speech_model_source_test.dart test/l10n/ test/ui/settings/widgets/settings_page_test.dart test/ui/chat/` → 174 passaram. O teste de migração preserva a pasta do Parakeet no download incompleto e a remove no download completo.
- `flutter test --no-pub --concurrency=3 -r expanded test/data/services/speech_transcription_chatgpt_test.dart test/data/services/duplex_voice_service_test.dart test/integration/duplex_voice_pipeline_test.dart` → 11 passaram.
- `flutter analyze --no-pub` nos 7 arquivos Dart alterados de código e teste → 2 infos preexistentes de imports transitivos em `whisper_service_test.dart`. `python scripts/check_arb_key_parity.py` → paridade confirmada.
- `flutter build apk --flavor global --release --no-pub` → APK local compilado. Conferidos os nomes do modelo no binário empacotado, o ícone de lembrete do Todo e a assinatura com o certificado da v1.0.57.
- S25 `NOT_RUN`: aparelho ausente no ADB. F2-11 segue `IN_PROGRESS`.

### Cartões de tarefa e permissões de lembrete no Todo (2026-11-18)

- Os cartões marcáveis da linha do tempo passam a ser oferecidos em “Tarefas deste registro”. Ao confirmar, o Todo salva o título e as subtarefas com suas marcações, sem data. Itens do texto que repetem uma subtarefa do cartão não viram tarefas avulsas.
- O APK publicado da v1.0.57 não continha `drawable/ic_todo_notification`, exigido na inicialização de `flutter_local_notifications`. O Android agora mantém esse recurso no empacotamento com redução de recursos.
- `flutter test --no-pub -r expanded --concurrency=4 test/domain/use_cases/card_task_extractor_test.dart test/domain/models/card_props_test.dart test/ui/core/cards/templates/temporal/task_card_test.dart test/ui/timeline/view_models/card_tasks_viewmodel_test.dart test/ui/timeline/widgets/card_tasks_section_test.dart test/integration/todo_undo_flow_test.dart test/ui/todo/ test/data/services/todo_alarm_service_test.dart` → `+152: All tests passed!`
- `flutter analyze --no-pub` nos 9 arquivos Dart alterados → `No issues found!`
- `flutter build apk --flavor global --release --no-pub` gerou o APK local. `aapt dump resources` confirmou `drawable/ic_todo_notification` e `aapt dump badging` mostrou as permissões de notificação e alarme exato. `apksigner verify --print-certs` confirmou a assinatura com o mesmo certificado da v1.0.57 publicada.
- S25 `NOT_RUN`: aparelho ausente no ADB. F11 permanece arquivada.

### Reorganização dos documentos (2026-11-17)
- `ROADMAP.md` virou índice com um resumo por fase. F0, F4, F5, F6 e F11 e os documentos de trabalho delas foram para `docs/arquivadas/`. Estados e prioridades foram para `docs/WATCHDOG.md` e as ideias futuras para `docs/roadmap/IDEIAS-FUTURAS.md`.
- Evidências até 2026-11-15 foram para `docs/arquivadas/state/`. Decisões superadas ou já cumpridas (D-003, D-009, D-010, D-013, D-019, D-021, D-022, D-031, D-034, D-040, D-046, D-047, D-048, D-056, D-058, D-060 e D-063) foram para `docs/arquivadas/decisoes/`. Notas de release até a v1.0.52 foram para `docs/arquivadas/releases/`.
- Removidas as regras herdadas do Memex para Cursor e Windsurf. As pastas locais de agentes (`.agent/`, `.agents/`, `.codex/`, `.gemini/`) agora são ignoradas pelo git.
- Conferência: script de links relativos em todos os `.md` (exceto `docs/upstream/`) com 0 quebrados. Nenhum código mudou, então os testes do app ficaram `NOT_RUN`.

### v1.0.57: comentários em chat e tarefas do registro (2026-11-17, D-076)
- Tela do registro: comentários em balões (personas à esquerda, usuário em marfim à direita), citação da resposta com ida à original, deslizar para responder e prévia no compositor; bloco "Tarefas deste registro" cria tarefas sem data só após o toque em "Adicionar N ao Todo", com Desfazer e "Agora não" por registro. Maquetes aprovadas pelo dono no chat.
- `flutter.bat test --no-pub --reporter compact test/ui/timeline/ test/l10n/ test/domain/use_cases/card_task_extractor_test.dart test/domain/models/card_task_state_test.dart test/utils/user_storage_card_task_state_test.dart test/ui/todo/`: `+227: All tests passed!`; analyze dos arquivos novos: `No issues found!` (7 `info` antigos em `timeline_card_detail_screen.dart`).
- Merge `7739c290`, release `dddc46ff`; APK `1.0.57+142` assinado com o certificado de sempre; [GitHub Release v1.0.57](https://github.com/playertwo1/segundamente-app/releases/tag/v1.0.57). Detalhes em `docs/releases/v1.0.57.md`.
- S25: `NOT_RUN` (deslizar, vibração, TalkBack, animações). Sem teste de widget da tela do registro inteira.

### Correção das 3 falhas antigas de teste (2026-11-17)
- Assistente ativo: "Silenciar hoje" trocava a página por um carregamento e voltava ao topo (bug real, agora atualiza no lugar); a página julgava o silêncio pelo relógio real e o serviço pelo dele (`ActiveAssistantService.now()`). Configurações: os testes passam a rolar até itens que saíram da área de 800×600.
- `flutter test --no-pub test/ui/settings/ test/ui/todo/ test/data/services/active_assistant_service_test.dart` → `+208: All tests passed!`; analyze nos 3 arquivos → `No issues found!`. Integrado na `main` em `2392f562`. Ainda não está em release.

### Release v1.0.56+141 — Todo redesenhado (D-075) (2026-11-17)
- Notas completas em [docs/releases/v1.0.56.md](docs/releases/v1.0.56.md). Commits `a5bc309a`, `fcdcbef4`, `59c9ae30`, `c87561e8` e D-075 (`04dc360f`), integrados na `main` em `1acd0c76`.
- Testes do Todo, l10n, integração, chat flutuante, modelos e sync: `+472 -1`; a falha (`ActiveAssistantSettingsPage persists toggles…`) já existia na `main`, assim como as duas de `settings_page_test.dart`. Analyze nos arquivos alterados: `No issues found!`. Paridade das ARB: OK.
- APK `segundamente_global_1.0.56_141.apk`, `128058887` bytes, SHA-256 `160ad10565c39d7ae2cc5bec57755e11f1d4bc38f913dfb990b8d1bac3319757`; certificado `216c29ff…ee05f`, igual ao das anteriores.
- `NOT_RUN`: esta versão no S25 (fora do `adb`), câmera/galeria, "remover animações" e TalkBack. Pendência nova: as 3 falhas antigas de teste (Configurações e Assistente ativo) precisam de correção própria.

### Release v1.0.55+140 — Correção do widget v3 recusado pelo launcher (2026-11-16)
- Notas completas em [docs/releases/v1.0.55.md](docs/releases/v1.0.55.md).
- Causa: `<View>` em cinco layouts do widget v3; `RemoteViews` não aceita essa classe e o launcher mostrava "não foi possível adicionar widget". Troca por `<FrameLayout>` e teste JVM (`WidgetLayoutsTest`: 5 testes, 0 falhas).
- S25 (`RQCY10934YV`): no pacote dev, o widget falhava antes e foi adicionado depois da correção (relato do dono). A 1.0.55 global foi instalada (`adb install -r` → `Success`) e o dono adicionou o widget nela com sucesso (PASS).
- Build: `segundamente_global_1.0.55_140.apk`, `127993351` bytes, SHA-256 `20853ebcc2fdef4a7a062285e6377d15a56ea2b373f07764e589e4f609fbe6f8`; certificado `216c29ff…ee05f`, igual ao das anteriores.

### Release v1.0.54+139 — Widget Android v3 (2026-11-16)
- Notas completas em [docs/releases/v1.0.54.md](docs/releases/v1.0.54.md).
- Widget reconstruído em `RemoteViews` nativo (`widget_small`, `widget_medium`, `widget_large` + variantes compactas) seguindo o mockup aprovado pelo dono, com roteamento em [WidgetLayouts.kt](android/app/src/main/kotlin/com/memexlab/memex/widget/WidgetLayouts.kt) e `com.memexlab.memex.widget.WidgetLayoutsTest` (`4` testes, `0` falhas, `0` erros, `0` ignorados em `testGlobalDevDebugUnitTest`).
- Build e assinatura: `flutter.bat build apk --flavor global --release --no-pub` gerou `segundamente_global_1.0.54_139.apk` (`127993347` bytes, SHA-256 `ef9d48df52ead4bace44c2fc4bfa4b8ad4d9e28e4a4275ede79965c5f1fc1e7b`). `aapt.exe dump badging` confirmou `app.segundamente`, `versionCode='139'`, `versionName='1.0.54'`, `sdkVersion='26'`, `targetSdkVersion='36'`. `apksigner.bat verify --print-certs` confirmou `V2 Signer: certificate DN: CN=Segunda Mente, O=Segunda Mente, C=BR` com SHA-256 `216c29ff2c784b10b6bdf60a792a00e2d96c46ccafd9e4cb986f3a5f2c1ee05f` (igual ao das releases anteriores). Galaxy S25 Ultra: `NOT_RUN`.

### Release v1.0.53+138 — Assistente ativo F14-01 a F14-03 no celular (2026-11-16)
- Notas completas em [docs/releases/v1.0.53.md](docs/releases/v1.0.53.md).
- Build e assinatura: `flutter.bat build apk --flavor global --release` gerou `segundamente_global_1.0.53_138.apk` (`127974975` bytes, SHA-256 `6140fb71a34479d480ca6c6cd3f793e520c5faf1c9fc47e8c4cf77b9b6d9cbbe`). `aapt.exe dump badging` confirmou `app.segundamente`, `versionCode='138'`, `versionName='1.0.53'`, `sdkVersion='26'`, `targetSdkVersion='36'`. `apksigner.bat verify --print-certs` confirmou `V2 Signer: certificate DN: CN=Segunda Mente, O=Segunda Mente, C=BR` com SHA-256 `216c29ff2c784b10b6bdf60a792a00e2d96c46ccafd9e4cb986f3a5f2c1ee05f` (igual ao das releases anteriores).
- Gates da F14 (`+142: All tests passed!`, ARB parity OK e `flutter analyze` zerado nos módulos da F14) executados antes do bump de versão; Galaxy S25 Ultra e suítes integrais seguem `NOT_RUN`.

### F14-01 a F14-03 — Assistente ativo no celular (`D-074`, 2026-11-16)
- **F14-01 (Configurações e Resumo Manhã/Tarde):** criados [active_assistant_settings.dart](lib/domain/models/active_assistant_settings.dart) (horários configuráveis, limites e faixa de silêncio cruzando meia-noite/temporária), [daily_briefing_builder.dart](lib/domain/use_cases/daily_briefing_builder.dart) (atrasadas, compromissos com hora e prioridades ordenadas exclusivamente a partir dos registros confirmados, sem LLM nem ocultação), persistência em [user_storage.dart](lib/utils/user_storage.dart) e [active_assistant_service.dart](lib/data/services/active_assistant_service.dart), e exposição em [todo_repository.dart](lib/data/repositories/todo_repository.dart) / [memex_router.dart](lib/data/repositories/memex_router.dart).
- **F14-02 (Cobrança de tarefas paradas há dias):** criado [stalled_task_detector.dart](lib/domain/use_cases/stalled_task_detector.dart) com limiar configurável, cálculo no fuso local, soneca individual da cobrança e ação opcional "Fazer hoje" via confirmação sem esconder a tarefa na lista ([todo_viewmodel.dart](lib/ui/todo/view_models/todo_viewmodel.dart)).
- **F14-03 (Sugestões das personas com limite de frequência + UI/l10n):** criados [persona_task_suggestion.dart](lib/domain/models/persona_task_suggestion.dart) e [persona_suggestion_governor.dart](lib/domain/use_cases/persona_suggestion_governor.dart) (limite diário, espaçamento mínimo e respeito ao silêncio), ferramenta opcional `SuggestTask` na iniciativa das personas ([character_initiative.dart](lib/domain/models/character_initiative.dart), [character_initiative_action_tools.dart](lib/agent/character_agent/character_initiative_action_tools.dart), [character_initiative_skill.dart](lib/agent/character_agent/character_initiative_skill.dart), [character_initiative_handler.dart](lib/data/services/task_handlers/character_initiative_handler.dart)) gerando apenas `TodoProposal` para revisão no [TodoProposalCard](lib/ui/todo/widgets/todo_proposal_card.dart), mais as telas [active_assistant_sheet.dart](lib/ui/todo/widgets/active_assistant_sheet.dart), [active_assistant_settings_page.dart](lib/ui/todo/widgets/active_assistant_settings_page.dart), botão/barra no [todo_screen.dart](lib/ui/todo/widgets/todo_screen.dart), entrada em [settings_page.dart](lib/ui/settings/widgets/settings_page.dart), busca em [settings_registry.dart](lib/data/services/settings_registry.dart) e localizações EN/PT (`app_en.arb`, `app_pt.arb`, `app_localizations*.dart`).
- **Verificações executadas após a edição final:**
  - `python scripts/check_arb_key_parity.py` → `ARB key parity OK across 1 locales.`
  - `flutter.bat analyze --no-pub lib/domain/models/active_assistant_settings.dart lib/domain/models/persona_task_suggestion.dart lib/domain/use_cases/daily_briefing_builder.dart lib/domain/use_cases/stalled_task_detector.dart lib/domain/use_cases/persona_suggestion_governor.dart lib/data/services/active_assistant_service.dart lib/ui/todo/ lib/agent/character_agent/ lib/data/services/task_handlers/character_initiative_handler.dart` → `No issues found! (9.8s)`
  - `flutter.bat analyze --no-pub lib/utils/user_storage.dart lib/data/repositories/todo_repository.dart lib/data/repositories/memex_router.dart lib/data/services/settings_registry.dart lib/domain/models/character_initiative.dart lib/ui/settings/widgets/settings_page.dart` → `No issues found! (28.1s)`
  - `flutter.bat test --no-pub --reporter compact test/domain/models/active_assistant_settings_test.dart test/domain/use_cases/daily_briefing_builder_test.dart test/domain/use_cases/stalled_task_detector_test.dart test/domain/use_cases/persona_suggestion_governor_test.dart test/data/services/active_assistant_service_test.dart test/ui/todo/ test/agent/character_initiative_skill_test.dart test/data/services/character_initiative_handler_test.dart test/data/services/settings_registry_todo_test.dart test/integration/floating_todo_flow_test.dart test/integration/todo_undo_flow_test.dart` → `+142: All tests passed!`
- **Não executado nesta rodada (`NOT_RUN`):** validação no Galaxy S25 Ultra, suíte completa do repositório e `flutter analyze` integral; integrações dependentes de `F13-04` (Calendar) e `F12-06` (Lumen).

## Como registrar evidência

Adicione uma subseção datada em "Evidências recentes" com o comando, a saída, o aparelho e o que ficou `NOT_RUN`. Quando uma fase fechar ou a seção passar de umas 15 entradas, mova as evidências antigas para um novo arquivo em `docs/arquivadas/state/` e deixe aqui só o link.

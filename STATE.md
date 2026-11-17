# STATE — ponto de retomada

**Atualizado:** 2026-11-17 · **MVP:** pronto (portão da F5 fechado em 2026-11-05, `docs/reviews/F5.md`: AUDIT RESULT: PASS) · **Última release:** v1.0.57+142 (2026-11-17, GitHub Release) · **Fase ativa:** F14 — Assistente ativo (`REVIEW`, `D-074`, falta S25); F12 — Sync com o Lumen (`IN_PROGRESS`, `D-066`)

Este arquivo guarda só o estado atual, a próxima ação e as evidências recentes. O estado de cada fase está no [ROADMAP](ROADMAP.md). Evidências antigas ficam em [docs/arquivadas/state/](docs/arquivadas/state/).

## Fases em andamento

- **F14 — Assistente ativo:** `REVIEW` (D-074). F14-01 a F14-03 com código e testes no celular; S25 `NOT_RUN`. Calendar (F13-04) e Lumen (F12-06) entram depois.
- **F15 — Widget e atalhos:** F15-02 a F15-07 com código na `main`; S25 `NOT_RUN`. Minicápsula: bolha (D-073), falta medir.
- **F12 — Sync com o Lumen:** `IN_PROGRESS` (D-066). F12-02 a F12-05 DONE; F12-01 espera o dono ler o contrato; F12-06 e F12-07 READY.

## Próxima ação

1. **Instalar a v1.0.57 no S25** e conferir com o dono o Todo novo (v1.0.56) e a tela do registro (v1.0.57: balões, deslizar para responder, citação, tarefas do registro, Desfazer).
2. **Validar a F14 no S25:** na aba Todo, o painel do Assistente Ativo (resumo manhã/tarde, tarefas paradas, sugestões das personas pelo `TodoProposalCard`, silêncio).
3. **Validar F15-02 a F15-07 no S25:** chat flutuante pelos atalhos (abertura a frio, volta à tela de origem, Abrir no app), widgets pequeno, médio e grande, painel rápido e a bolha no build dev. Também os pontos R01, R02, R04 e R05 de `docs/reviews/F15.md`; o dono decide o texto do limite de Falar (R03).
4. **F12:** F12-01 (schemas finais da v1.1 e chunking acima de 64 KiB), depois F12-06. O S25 dev está revogado: parear de novo antes da F12-06 e conferir o rótulo "sem conexão" com o modo avião. Abertos no Lumen: QR maior e edição de horário que não salva.
5. **A investigar:** o cold start mostra erro do `FlutterSecureStorage` (`Could not decrypt key`); esse armazenamento guarda tokens de login.

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

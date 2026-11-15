# STATE — ponto de retomada

**Atualizado:** 2026-11-15 · **MVP:** pronto (portão da F5 fechado em 2026-11-05, `docs/reviews/F5.md`: AUDIT RESULT: PASS) · **Última release:** v1.0.51+136 (2026-11-15, GitHub Release) · **Fase ativa:** F12 — Sync com o Lumen (IN_PROGRESS, D-066); checkpoint da ponte fechado em 2026-11-15, então a pausa da D-066 acabou; F11 — Todo robusto concluída em 2026-11-14

Este arquivo guarda só o estado atual, a próxima ação e as evidências recentes. O histórico completo de 2026-11-02 a 2026-11-13 está em [docs/historico/STATE-2026-11-02-a-2026-11-13.md](docs/historico/STATE-2026-11-02-a-2026-11-13.md). Fases, critérios e portões estão no [ROADMAP](ROADMAP.md).

## Estado das fases

| Fase | Estado | Observação |
|---|---|---|
| F0, F4, F5, F6 | DONE | Portões fechados |
| F1, F2, F3 | IN_PROGRESS | Critérios do MVP cumpridos; tarefas adicionais abertas |
| F7 | IN_PROGRESS | F7-03 DONE (D-060; voz duplex por turnos, D-049); F7-02 adiada (D-041); F7-06 BLOCKED |
| F5V, F9, F10 | PAUSED | D-050; o estado de cada subfase no momento da pausa está no arquivo da fase |
| F8 | BLOCKED | NotebookLM pós-MVP sem previsão; caminho escolhido: via B (D-055) |
| F11 | DONE (portão fechado em 2026-11-14) | AC-01 e Concluir com o app fechado confirmados por adb no S25 (build atual); uma tentativa da manhã no build anterior não gravou, causa aberta. F11-01 a F11-06 DONE (F11-06 em D-061); auditoria PASS |
| F12 | IN_PROGRESS (D-066) | **Checkpoint da ponte fechado em 2026-11-15** no S25 + notebook. F12-01 IN_PROGRESS (falta o dono ler o contrato); F12-02 a F12-05 DONE; F12-06 e F12-07 READY. Portão F12 ainda depende do AC-04 (v1.1) |
| F13, F14 | BLOCKED | Google (D-055), assistente ativo (D-050) |
| F15 | F15-01 DONE (D-064: teclas no pequeno, linhas no grande); F15-02 IN_PROGRESS; F15-03 REVIEW (D-068; código pronto, S25 NOT_RUN); F15-04 REVIEW (D-069; código pronto, S25 NOT_RUN); F15-05 REVIEW (D-072; código pronto, S25 NOT_RUN); F15-06 REVIEW (D-070; código pronto, device NOT_RUN); F15-07 IN_PROGRESS (D-071; protótipos no build dev) | D-062 a D-072; widget e atalhos Android, paralela à fase L do fork |

## Próxima ação

1. **Validar F15-02 a F15-07 no S25 com um APK integrado** (branch `feat/f15-integracao`, que junta F15-05 com F15-03 e F15-04, F15-06 e F15-07). Depois, o dono escolhe a forma da minicápsula pela comparação da F15-07 (D-071). Checar: chat flutuante pelos atalhos Conversar e Falar (abertura a frio, volta para a tela de origem, Abrir no app), widget pequeno, médio e grande, painel rápido e os dois protótipos da cápsula no build dev.
2. **F11, a investigar:** o cold start mostra erro do `FlutterSecureStorage` (`Could not decrypt key`, fallback de cifras). Não é do Todo, mas esse armazenamento guarda tokens de login; checar separadamente.
3. **F11-06:** DONE (D-061, aberta pelo dono em 2026-11-13). Vista no S25 (pacote dev); o TalkBack segue `NOT_RUN`.
4. **Em paralelo, no Lumen:** Fase L (L0: fechar o que está quase pronto; L1: renomear para Lumen com assets próprios). Ver `docs/roadmap/fase-l-lumen.md` em `playertwo1/lumen`.
5. **F12:** checkpoint da ponte fechado e os 4 achados da Segunda Mente corrigidos (2026-11-15). Próximo: F12-01 (schemas finais da v1.1 e chunking acima de 64 KiB), depois F12-06 (entidades v1.1). Abertos no Lumen: QR maior e edição de horário que não salva. O S25 dev está revogado: parear de novo antes da F12-06 e, com ele pareado, conferir o rótulo "sem conexão" com o modo avião.
6. **Fim da pausa da D-066:** com o checkpoint fechado, a F15-03 em diante volta a andar.

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

- v1.0.47 (2026-11-11): `flutter test --no-pub --reporter compact` com 1.674 aprovados, 4 ignorados e 0 falhas. A análise completa da época ficou `NOT_RUN`; a execução final da F11-05 encontrou 159 issues, detalhadas abaixo.

## Evidências recentes

### Release v1.0.51+136 — Personas vivas em chat em grupo + correções do checkpoint da ponte (2026-11-15)
- Notas completas em [docs/releases/v1.0.51.md](docs/releases/v1.0.51.md).
- Build e assinatura: `flutter.bat build apk --flavor global --release` gerou `segundamente_global_1.0.51_136.apk` (`127821719` bytes, SHA-256 `617b5ed426d5c1e41e8cd8e497d98086b4f4176a9cd422d8c2c45150971409e`). `aapt.exe dump badging` confirmou `app.segundamente`, `versionCode='136'`, `versionName='1.0.51'`. `apksigner.bat verify --print-certs` confirmou `V2 Signer: certificate DN: CN=Segunda Mente, O=Segunda Mente, C=BR` com SHA-256 `216c29ff2c784b10b6bdf60a792a00e2d96c46ccafd9e4cb986f3a5f2c1ee05f` (igual ao das releases anteriores).
- Galaxy S25 Ultra (`RQCY10934YV` não listado em `adb devices -l` no momento da publicação) e suítes completas (`flutter test` / `flutter analyze` integrais): `NOT_RUN`.

### Achados da Segunda Mente no checkpoint da ponte (2026-11-15, 16:49–17:00)
- Código: tela de pareamento guarda o ViewModel no `State` (não trava ao reconstruir a rota); prévia da área de transferência não grava texto no log do Dart (`<redacted len=N>`) nem no logcat do Kotlin (só o tamanho); Todo mostra "sem conexão" quando o erro é `http_0`; o sync grava uma linha por ciclo (`Todo sync (<motivo>) -> <estado>, outbox=N, error=…`) e o `TodoViewModel` registra as exceções.
- Testes: área alterada `+119` aprovados; paridade das ARB OK; `flutter analyze` com 159 issues (linha de base, nenhuma nova). Widget test da tela de pareamento falha antes e passa depois da correção.
- S25 (`app.segundamente.dev`, `adb install -r` → `Success`): PASS na tela de pareamento, 3 ciclos Parear de novo → leitor → Voltar → sair → entrar, sempre em "Pareado com BOOKFAEL"; PASS no log do sync (`Todo sync (lifecycle) -> revoked, outbox=0, error=null`). Removidas do log de hoje do pacote dev as 64 linhas com o início do link de pareamento gravadas pela versão antiga.
- `NOT_RUN` no S25: a linha redigida da área de transferência (o Android devolveu `empty clipboard` nas checagens ao voltar ao app, mesmo com texto copiado à mão; a parte do Dart fica coberta pelo teste unitário); o rótulo "sem conexão" (o aparelho está revogado); a mudança no logcat do Kotlin só foi compilada.
- Achados menores novos: a tela de pareamento ainda mostra "Pareado com …" depois da revogação; o log grava em FINE o token do servidor local de imagens (efêmero e só no aparelho).

### Checkpoint da Ponte (F12-03 a F12-05) no S25 + notebook (2026-11-15, 13:20–14:53)
- Aparelhos: Galaxy S25 Ultra (`RQCY10934YV`), `app.segundamente.dev` 1.0.50 compilado da `main` `a6cf1300` (`flutter build apk --flavor globalDev --debug --no-pub`, `adb install -r` → `Success`); notebook com Lumen 0.7.3. Perfil sintético `F11 QA`; tarefas `PONTE 1`–`7`, todas apagadas no fim (a `PONTE 6` e a `PONTE 7` ficam para o dono apagar no Lumen).
- PASS: pareamento (pelo link), entrega na primeira consulta uma vez, T06, celular → PC, alarme nos dois aparelhos (AC-08), concluir no PC cancela alarme e notificação no S25 (`notification_cancel` reason 8), adiar no S25 tira o toast do PC (T05), AC-02 e T08 offline com modo avião, WorkManager periódico com o app fechado (`Worker result SUCCESS` 14:28:52) e T18 (Parear de novo no Lumen → `revoked: true`, a `PONTE 7` não chegou).
- FAIL / achados: o QR do Lumen não foi lido pela câmera em 2 tentativas; editar o horário no Lumen não salvou; mais 4 achados na Segunda Mente. Lista completa e evidência passo a passo em [docs/testes/F12-checkpoint-ponte-s25.md](docs/testes/F12-checkpoint-ponte-s25.md).
- `NOT_RUN`: suíte completa `flutter test` / `flutter analyze` (só documentação mudou nesta rodada); TalkBack.

### Personas vivas em chat em grupo (`AGENTS.md` + `MEMORY.md`, até 15 personas, onda cruzada) (2026-11-15)
- **Limites e seleção (`CommentSettingsService`, `CharacterSelectionService`, Settings UI & l10n):**
  - `lib/data/services/comment_settings_service.dart`, `lib/ui/settings/widgets/settings_page.dart`, `lib/l10n/{app_en.arb,app_pt.arb,app_localizations_en.dart,app_localizations_pt.dart}`: teto e padrão elevados para `15` personas (`_version = 3`, migrando legados v1 `1` e v2 padrão `2` para `15`, preservando escolhas explícitas em `1..15`, slider `1..15`).
  - `lib/utils/mention_parser.dart`: adicionados `foldPtAscii`, `indexOfFoldedStandaloneMention` e `extractAllMentions<T>` com ordenação por ocorrência, folding de acentos/caixa, `@primeiro_nome` único (>= 3 caracteres) e filtro de e-mails.
  - `lib/data/services/character_selection_service.dart`: `selectMultipleCharacters` (padrão `15`, `excludeCharacters`), `selectReplyCharacters` (menções múltiplas com `forceReply: true`, resposta direta via `reply_to_id`, comentários abertos do usuário sempre com pelo menos 1 persona respondendo) e `selectGroupFollowupCharacters`.
- **Personas vivas (`AGENTS.md` + `MEMORY.md`) e ferramentas de grupo:**
  - `lib/data/services/file_system_service.dart` e `lib/data/services/character_workspace_service.dart`: materialização de `AGENTS.md` (sem sobrescrever edições existentes), `loadPersonaLivingDocs` e `appendLivingMemory` (deduplicação com folding pt-BR e limite de 30 itens em `MEMORY.md`).
  - `lib/agent/skills/comment_agent/{comment_agent_skill.dart,tools/comment_tools.dart}`, `lib/agent/comment_agent/comment_agent.dart` e `lib/data/repositories/post_comment.dart`: injeção de `<persona_agents_md>`, `<persona_living_memory>`, participantes ativos e fio completo formatado (`formatGroupCommentsContext`), extração e limpeza de `[REPLY:id]` / `[MEMORY: ...]` (`parseGroupCommentOutput`), resolução de `replyToId` por `@menção` e emissão ao vivo via `EventBusService`.
- **Onda inicial + onda cruzada entre personas:**
  - `lib/data/services/task_handlers/comment_agent_handler.dart`: suporte a múltiplas menções e até 15 personas na onda inicial + `runCrossPersonaFollowupWave` (despertando personas `@mencionadas` por outras personas e convites do coordenador dentro de `maxCrossTalkRepliesPerWave = 5` e `maxGroupPersonaTurnsPerUserMessage = 15`), mantendo `maxPersonaTurnsPerUserMessage = 4` e `runPersonaDebate`.
- **Testes e análise:**
  - `python3 scripts/check_arb_key_parity.py` -> `ARB key parity OK across 1 locales.` (exit `0`).
  - `flutter.bat test --no-pub --reporter compact test/data/services/comment_settings_service_test.dart test/data/services/task_handlers/comment_reply_target_test.dart test/data/services/task_handlers/persona_debate_limit_test.dart test/data/services/character_workspace_service_test.dart test/agent/comment_tool_factory_test.dart test/agent/comment_agent_policy_test.dart test/data/services/character_service_default_seed_test.dart test/ui/settings/widgets/settings_page_test.dart test/agent/agent_tool_error_result_test.dart test/l10n/` -> `+110: All tests passed!` (exit `0`).
  - `dart.bat analyze` nos 17 arquivos `lib/` e `test/` tocados -> `1 issue found` (`info - lib\data\services\file_system_service.dart:288:7` pré-existente fora do diff; zero erros/warnings e zero issues nas linhas adicionadas/editadas; exit `0`).
- **Não executado nesta rodada:** validação em aparelho físico (Galaxy S25 Ultra) e suítes integrais (`flutter test` / `flutter analyze` em todo o repositório) seguem `NOT_RUN`.

### Release v1.0.50+135 — Atualizador sem token para repositório público (2026-11-15)
- Notas completas em [docs/releases/v1.0.50.md](docs/releases/v1.0.50.md).
- Build e assinatura: `flutter.bat build apk --flavor global --release` gerou `segundamente_global_1.0.50_135.apk` (`127690647` bytes, SHA-256 `c2a9ea2845c4723c0d84446d080041b3707b5deb453e519ee6ec604133e76920`). `aapt.exe dump badging` confirmou `app.segundamente`, `versionCode='135'`, `versionName='1.0.50'`. `apksigner.bat verify --print-certs` confirmou `V2 Signer: certificate DN: CN=Segunda Mente, O=Segunda Mente, C=BR` com SHA-256 `216c29ff2c784b10b6bdf60a792a00e2d96c46ccafd9e4cb986f3a5f2c1ee05f` (igual ao da `v1.0.49`).
- Testes e análise pós-bump: `flutter.bat test --no-pub --reporter compact test/data/services/app_update_service_test.dart test/ui/settings/widgets/early_update_settings_card_test.dart test/l10n/` -> `+39: All tests passed!`; `dart.bat analyze` nesses 4 arquivos -> `No issues found!`.
- Galaxy S25 Ultra e suítes completas (`flutter test` / `flutter analyze` integrais): `NOT_RUN`.

### Repositório público e atualizador sem token (D-067) (2026-11-15)
- `gh repo edit playertwo1/segundamente-app --visibility public --accept-visibility-change-consequences -d "Segunda Mente"` -> confirmado `"visibility":"PUBLIC"` e `"isPrivate":false`.
- Teste real sem autenticação na `v1.0.49`: `GET https://api.github.com/repos/playertwo1/segundamente-app/releases?per_page=5`, `asset.url` e `browser_download_url` retornaram `200`/`302` sem cabeçalho `Authorization`.
- `AppUpdateService` (`lib/data/services/app_update_service.dart`), `EarlyUpdateSettingsCard` (`lib/ui/settings/widgets/early_update_settings_card.dart`), l10n (`app_pt.arb`/`app_en.arb`), `AGENTS.md`, `README.md` e `docs/DECISIONS.md` (`D-067`, substituindo `D-046`) atualizados para operar sem token GitHub.
- Testes e análise:
  - `flutter.bat gen-l10n` + `python3 scripts/check_arb_key_parity.py`: `ARB key parity OK across 1 locales.`
  - `flutter.bat test --no-pub --reporter compact test/data/services/app_update_service_test.dart test/ui/settings/widgets/early_update_settings_card_test.dart test/l10n/`: `+39: All tests passed!`
  - `dart.bat analyze lib/data/services/app_update_service.dart lib/ui/settings/widgets/early_update_settings_card.dart test/data/services/app_update_service_test.dart test/ui/settings/widgets/early_update_settings_card_test.dart`: `No issues found!`
- Galaxy S25 Ultra e suítes completas (`flutter test` / `flutter analyze` integrais): `NOT_RUN`.

### Release v1.0.49+134 — Lista de tarefas (crítica Impeccable) + F12-05 (2026-11-15)
- Notas completas em [docs/releases/v1.0.49.md](docs/releases/v1.0.49.md).
- Testes alvo: `flutter.bat test --no-pub --reporter compact test/ui/todo/ test/l10n/ test/integration/todo_undo_flow_test.dart test/data/services/todo_alarm_service_test.dart test/data/services/todo_service_test.dart test/data/services/todo_sync_service_test.dart` -> `+118: All tests passed!`.
- Análise alvo: `dart.bat analyze lib/ui/todo/widgets/todo_screen.dart test/ui/todo/widgets/todo_screen_test.dart` -> `4 issues found` (`1 warning` e `3 info` pré-existentes; zero erros).
- Build e assinatura: `flutter.bat build apk --flavor global --release` gerou `segundamente_global_1.0.49_134.apk` (`127756183` bytes, SHA-256 `445aa47ddede4a6b48a38349adb82790657631410dc89d04ebec726a38f5dd2f`). `aapt.exe dump badging` confirmou `app.segundamente`, `versionCode='134'`, `versionName='1.0.49'`. `apksigner.bat verify --print-certs` confirmou `V2 Signer: certificate DN: CN=Segunda Mente, O=Segunda Mente, C=BR` com SHA-256 `216c29ff2c784b10b6bdf60a792a00e2d96c46ccafd9e4cb986f3a5f2c1ee05f` (igual ao da `v1.0.48`).
- Galaxy S25 Ultra (instalação/execução/notificações/áudio/segundo plano) e suítes completas (`flutter test` / `flutter analyze` integrais): `NOT_RUN`.

### F12-05 (Passo 9 da PONTE — cancelamento cruzado de avisos AC-08 / T05) — implementação sintética (2026-11-15)
- **Segunda Mente (integrada na `main`, commit `110775ea`):**
  - Spec e plano em `docs/superpowers/specs/2026-11-15-f1205-cancelamento-avisos-ponte.md` e `docs/superpowers/plans/2026-11-15-f1205-cancelamento-avisos-ponte.md`.
  - `lib/data/services/todo_alarm_service.dart`: `TodoAlarmBackend` + `@visibleForTesting TodoAlarmService.forTesting(...)`, método `cancelNotificationsForTaskIds`, unificação sem duplicação de `deterministicNotificationId`/`notificationIdsForTaskIds`, rastreamento determinístico de reagendamento `_lastScheduledDates` (T05: `dueDate`, `dueTime`, `timeZone`, `alertMinutes`), cancelamento dedup (`cancel`) para concluídas/excluídas/sem alarme futuro mesmo já ausentes de `pendingNotificationRequests()`, pré-cancelamento ao adiar (`snoozedUntil != null`) ou reagendar antes de `zonedSchedule` e varredura segura de `getActiveNotifications()` no canal `todo_reminders`.
  - Testes novos e fortalecidos: `test/data/services/todo_alarm_service_test.dart` (`11` testes), `test/data/services/todo_service_test.dart` (alarme sync e garantia de que `done: true` remoto não cria `nextOccurrence` em tarefa recorrente) e grupo `F12-05 alarm sync integration (AC-08 & T05)` em `test/data/services/todo_sync_service_test.dart` (testes 12 a 16).
- **Lumen (`playertwo1/lumen`, integrado na `main`, release `windows-v0.7.3` publicada):**
  - `windows/src-tauri/src/tasks/{mod,sync}.rs`: `due_trigger_for_now` ignora incrementos apenas de `version` no mesmo `trigger_ms`; `handle_toast_action` (`Snooze`/`Complete`) e comandos locais chamam `dismiss_if_active` (WinRT Toast + `"task-dismiss"`); testes para re-disparo e `dismiss_ids` em `done`, `deleted_at` e `snoozed_until`.
- **Comandos e saídas:**
  - Segunda Mente (`flutter test --no-pub ...` nos 16 alvos da F12-04/F12-05 + l10n + integration) → `+145: All tests passed!` (exit `0`), com `+103` testes de serviço/UI/alarme rodando verde localmente.
  - Segunda Mente (`flutter analyze --no-pub`) → `159 issues found.` (mesmo baseline pré-existente; zero issues novos nos arquivos tocados).
  - Lumen (`cargo test --manifest-path windows/src-tauri/Cargo.toml --lib`) → `726 passed; 0 failed; 9 ignored` (incluindo `tasks`: `27 passed; 0 failed`); `npx tsc --noEmit` em `windows/` → exit `0`; release `windows-v0.7.3` publicada.
- **`NOT_RUN` (pendente):** teste físico com o Galaxy S25 Ultra + Lumen no PC (`Passo 9 real` / `Checkpoint da Ponte` / `F12-05 real`: `adb devices` vazio no momento da execução, celular não conectado via depuração USB) e execução real do Toast WinRT no Windows; pronto para o teste físico do dono.

### F12-04 (Passo 8 da PONTE) — sync de tarefas pela caixa de correio HTTP, implementação sintética (2026-11-15)
- **Segunda Mente (integrada na `main`, commit `293a96de`):**
  - Spec e plano em `docs/superpowers/specs/2026-11-15-f1204-sync-tarefas-mailbox.md` e `docs/superpowers/plans/2026-11-15-f1204-sync-tarefas-mailbox.md`.
  - Cifra `coucou-mailbox/v1` em `lib/data/services/lumen_relay_crypto.dart` validada contra todos os vetores (`messages` e `mustRefuse`) copiados em `test/fixtures/lumen_mailbox_test_vectors.json`, mais `LumenMailboxClient` em `lib/data/services/lumen_mailbox_client.dart` e `pointycastle: ^3.9.1` no `pubspec.yaml` (`flutter pub get --enforce-lockfile`).
  - Motor offline-first em `lib/data/services/todo_sync_service.dart` (`todo-sync-v1.json`, SHA-256 de `room`, outbox com coalescência, pull paginado, idempotência com cap 2000 / 90d, merge 3-vias simétrico, conflitos `pending_review`, quarentena de desconhecidas e venenosas após 3 falhas), hooks nos 9 métodos do `TodoService`, aplicação remota sem gerar nova `nextOccurrence` e ressincronização de alarmes, além de `Workmanager` (`lumenTodoPeriodicSyncTask`, 1h) + ciclo em `lib/main.dart` e `lib/data/services/health_service.dart`.
  - UI e L10n em `lib/ui/todo/view_models/todo_viewmodel.dart`, `lib/ui/todo/widgets/todo_screen.dart` e `lib/l10n/app_{pt,en}.arb` separando `"Salvo no aparelho"` vs `"Sincronizado"`, botão `"Sincronizar agora"` e cards de conflito `pending_review` (`Manter deste aparelho` / `Usar do PC`).
- **Comandos e saídas:**
  - `python3 scripts/check_arb_key_parity.py` → `ARB key parity OK across 1 locales.`
  - `flutter test --no-pub test/data/services/lumen_relay_crypto_test.dart test/data/services/lumen_mailbox_client_test.dart test/data/services/todo_sync_service_test.dart test/data/services/todo_service_test.dart test/data/services/lumen_pairing_service_test.dart test/data/repositories/todo_repository_test.dart test/domain/models/todo_item_sync_contract_test.dart test/data/services/health_service_test.dart test/ui/todo/view_models/todo_viewmodel_test.dart test/ui/todo/widgets/todo_screen_test.dart test/ui/lumen/ test/integration/todo_undo_flow_test.dart test/l10n/arb_key_parity_test.dart test/l10n/locale_lookup_test.dart test/l10n/hardcoded_ui_strings_test.dart` → `+133: All tests passed!` (exit `0`).
  - `flutter analyze --no-pub` → `159 issues found.` (mesmo baseline pré-existente da F12-03; zero erros ou alertas novos).
- **`NOT_RUN`:** sync real S25 Ultra ↔ Lumen no notebook contra o Worker na Cloudflare, execução real de `Workmanager` em segundo plano e suíte completa global (`flutter test` sem filtro); ficam para a validação conjunta no Passo 9 (`F12-05 / L6.4`).

### F12-02 (Passo 4 da PONTE) — deploy real do Worker na Cloudflare e medição (2026-11-15)
- **Deploy (`relay/` do Lumen):** `npm test` passou antes do deploy (`26` testes Worker + `37` testes Node); `npx wrangler deploy` publicou `coucou-link` em `https://coucou-link.<seu-subdominio>.workers.dev` (versão `f55c97a2-1e61-45e3-a6cc-232f9e274bbd`).
- **Segredo e configuração local:** `ACCESS_KEY` (43 chars base64url) rotacionado via `wrangler secret put ACCESS_KEY`, gravado no cofre do Windows (`phone-relay-access.fr.louisraille.coucou`) e configurado no Lumen (`phoneRelay = true`).
- **Ciclo real e medição `freePlan` em sala efêmera:** `GET /` `200`, `POST /v1/mailbox/<room>/messages?to=phone` `201` (`storedBytes: 413`, idempotente `200` no reenvio), `GET /messages` `200` + decifragem `coucou-mailbox/v1` exata, `GET /stats` (`pendingPhone: 1`, `dailyWrites: 2/100000`, `dailyWritePct: 0.002%`, `dailyRequests: 2/100000`, `roomBytes: 413/16777216`), `POST /ack` `200` (`deleted: 1`, `remaining: 0`, `dailyWrites: 4`) e `POST /revoke` `200` (`revoked: true`, `410 Gone` subsequente em `GET /messages`, `dailyWrites: 6`).
- **Passo 7 (L6.3 no Lumen):** integrado na `main` do Lumen (release `windows-v0.7.3` publicada).

### F12-03 (e L6.2 no Lumen) — pareamento QR e revogação, implementação (2026-11-14)
- **Lumen (`playertwo1/lumen`, L6.2 integrado na `main`, release `windows-v0.7.3`):** QR com `k_mailbox`, `http_base_url` e `shown: true`; revogação em `POST /v1/mailbox/<room>/revoke` ao gerar novo pareamento. Validação no fork: `cargo test --lib phone_link` (206 aprovados, 2 ignorados), `npx tsc --noEmit`, `phone-relay.test.mjs` (4 aprovados) e `android/relay` `npm test` (26 + 37 aprovados).
- **Segunda Mente (integrada na `main`, commit `b25d0226`):** `LumenPairing` (`lib/domain/models/lumen_pairing.dart`), HKDF `LumenRelayCrypto` (`lib/data/services/lumen_relay_crypto.dart`) contra vetores em `test/fixtures/lumen_relay_test_vectors.json`, `LumenPairingService` (`lib/data/services/lumen_pairing_service.dart`, segredos e `device_id` só em `SecretStorage`, revogação best-effort com timeout de 5 s), `MemexRouter`, `LumenPairingViewModel`, `LumenPairingPage` (`mobile_scanner` + colar link, sem expor `key`/`access`/`token`), entrada em `SettingsPage` e `SettingsRegistry`, e 23 chaves + metadado em `app_pt.arb` e `app_en.arb`.
- **Comandos e saídas:**
  - `python3 scripts/check_arb_key_parity.py` → `ARB key parity OK across 1 locales.`
  - `flutter test --no-pub --reporter compact test/domain/models/lumen_pairing_test.dart test/data/services/lumen_relay_crypto_test.dart test/data/services/lumen_pairing_service_test.dart test/ui/lumen/lumen_pairing_page_test.dart test/l10n/arb_key_parity_test.dart test/l10n/locale_lookup_test.dart test/l10n/hardcoded_ui_strings_test.dart test/ui/settings/widgets/settings_page_test.dart test/data/services/settings_registry_todo_test.dart test/ui/lazy_secondary_loads_test.dart` → `+57: All tests passed!`
  - `flutter analyze --no-pub` → `159 issues found.` (mesmo número de issues pré-existentes da linha de base; sem erros novos nos arquivos da F12-03).
- **`NOT_RUN`:** leitura real de QR pela câmera e `SecretStorage` no Galaxy S25 Ultra, pareamento/revogação reais contra o Worker Cloudflare (passo 4) e suíte completa `flutter test`.

### F12-01 — contrato de sync v1 (2026-11-14)
- Decisões: questionário `docs/questionario/2026-11-14-sync-contrato-e-roadmaps.md` (D1–D13) e D-066 (abre a F12 pela trilha única da ponte, `docs/lumen/PONTE.md`).
- Contrato `docs/lumen/CONTRATO-SYNC.md` reescrito como v1 (envelope sem `op`, cifra `coucou-mailbox/v1`, rotas reais da caixa de correio, regras de aplicação e conflito, entidade `task`) e v1.1 em rascunho.
- Teste Dart: `flutter test --no-pub test/domain/models/todo_item_sync_contract_test.dart` → `+7: All tests passed!`; `flutter analyze --no-pub` no arquivo → `No issues found!`. O teste lê a seção 8 do contrato e confere o envelope e a paridade de campos com o `TodoItem`.
- Lumen (`playertwo1/lumen`, integrado na `main`): vetores `android/relay/test-vectors-mailbox.json` com cifra de referência em Node; `npm test` no relay → 26 + 37 testes aprovados; `gen-mailbox-vectors.ts --check` → atualizados; `cargo test … contrato_sync_v1_task_envelopes_match_the_model` → 1 aprovado.
- `NOT_RUN`: cifra da caixa de correio no Rust e no Dart (vem na L6.3 e na F12-04); `flutter test` completo. Pendente: o dono ler o texto final do contrato; o `gen-vectors.mjs --check` dos vetores antigos falha na cópia local por CRLF (`core.autocrlf`), antes desta mudança.

### F15-07 — protótipos da cápsula (2026-11-14)
- O que existe, só no flavor `globalDev` (`android/app/src/globalDev/`, D-071): A, bolha oficial (launcher "Cápsula: bolha", `Notification.BubbleMetadata` com `setAutoExpandBubble`, `setSuppressNotification`, atalho de conversa, host `CapsuleBubbleHostActivity` que reusa o motor e a rota do chat); B, sobreposição própria (launcher "Cápsula: sobreposição", `CapsuleOverlayService` com `TYPE_APPLICATION_OVERLAY`, `specialUse`, notificação com "Parar"). Medição pelo log `F1507`. Passos de uso, permissões e comandos adb em `docs/fases/F15-07-prototipos-capsula.md`.
- Comandos e saídas:
  - `flutter pub get --enforce-lockfile` → exit 0 (avisos de pacotes descontinuados e desatualizados); nenhum arquivo rastreado alterado.
  - `flutter build apk --flavor globalDev --debug --no-pub` → `√ Built build\app\outputs\flutter-apk\app-globaldev-debug.apk`, exit 0.
  - `gradlew.bat :app:processGlobalDebugManifest` (flavor `global`, debug) → BUILD SUCCESSFUL; o manifesto mesclado não tem `SYSTEM_ALERT_WINDOW`, `FOREGROUND_SERVICE_SPECIAL_USE` nem entradas `com.memexlab.memex.dev` (0 ocorrências). `android/app/src/main/AndroidManifest.xml` sem alteração.
  - `flutter analyze` e `flutter test`: NOT_RUN, sem mudança em Dart nesta subfase.
- Aparelho: nenhum (sem adb nesta subfase).
- `NOT_RUN`: tudo no S25: abrir pelos dois lançadores, bolha expandida e recolhida, sobreposição com a permissão, arrastar, esconder e parar, economia de bateria, custo de bateria e os cinco critérios. A comparação e a escolha do dono vêm depois.
- Estado: F15-07 IN_PROGRESS.

### F15-06 — botão no painel rápido (2026-11-14)
- O que existe: `ConversarTileService` (`TileService`) abre a `FloatingChatActivity` em modo `type`; API 34+ usa `startActivityAndCollapse(PendingIntent)`, API 26 a 33 usa o `Intent`; com aparelho bloqueado, `unlockAndRun`. Rótulo "Conversar"/"Chat", ícone `ic_qs_chat`. Documento `docs/fases/F15-06-painel-rapido.md`. Decisão D-070 (abertura antes da validação da F15-02 no S25).
- Build: `flutter pub get --enforce-lockfile` OK (lockfile intocado); `flutter build apk --flavor globalDev --debug --no-pub` exit 0, `app-globaldev-debug.apk`.
- Aparelho: nenhum (sem adb, sem celular). Estado: REVIEW.
- `NOT_RUN`: toque no tile do painel rápido do S25 (adicionar, abrir da tela inicial e de outro app, aparelho bloqueado, volta para a origem ao fechar, ícone claro e escuro); `flutter analyze` e `flutter test` (sem mudança em Dart).

### F15-05 — widget grande com tarefas de hoje, código (2026-11-14)
- O que existe: tamanho grande em `widget_large.xml` (chave `LARGE_MIN` 250×270 dp no API 31+, altura ≥ 270 no API 26–30): faixa de Conversar e Falar, faixa de captura, até três linhas de tarefa (círculo conclui, título abre `memex://open_todo`, hora) e "+ tarefa". Atrasadas primeiro, depois as de hoje por horário; só tarefas abertas com data (D-072). Snapshot Dart → nativo por `TodoWidgetSnapshotService` (`com.memexlab.memex/todo_widget`, `updateSnapshot`), com id, título, data, hora, status e fuso das dez primeiras; guardado em `SharedPreferences` privado. Envio após cada escrita do Todo (fora do lock, sem `await`) e na inicialização. Redesenho por envio, `DATE_CHANGED`, `TIME_SET`, `TIMEZONE_CHANGED` e alarme inexato no próximo instante (meia-noite SP ou hora de tarefa de hoje). Concluir pelo círculo: `FloatingChatActivity` com `todo_complete:<id>` → `/floating-todo-complete` → `setTodoDone` pelo router, sem folha, funciona a frio. "+ tarefa": `todo_add` → `/floating-todo-add` → editor do Todo com o aviso da F11-06 (parâmetro `notice` novo em `showTodoEditorDialog`, padrão nulo). Desenho e checklist do S25 (doze itens) em `docs/fases/F15-05-widget-grande.md`; decisão em D-072.
- Comandos e saídas (branch `feat/f15-05-widget-grande`, worktree `sm-f1505`):
  - `flutter pub get --enforce-lockfile` → `Got dependencies!` (exit 0). `analysis_options.yaml` e `android/gradle.properties` sem alteração.
  - `dart analyze` nos arquivos alterados e novos (lib e testes): nenhum erro e nenhum aviso novo; o conjunto final tem um aviso pré-existente. Único aviso em `todo_screen.dart:419` (`unused_element_parameter`) é da busca do Todo, código que não mudou.
  - `dart format` nos 22 arquivos Dart alterados: 10 reformatados (só linhas tocadas).
  - `flutter test --no-pub --reporter compact` (suíte completa): `Some tests failed`, `+1853 -1`. Única falha: `floating_todo_add_screen_test` (aviso da F11-06 ainda não existia). Depois de corrigida, rodada dirigida: `test/ui/floating_chat/widgets/floating_todo_add_screen_test.dart`, `test/ui/todo` e `test/integration/floating_todo_flow_test.dart`: `All tests passed!`.
  - Testes novos da F15-05: `todo_widget_snapshot_service_test.dart` (conteúdo, filtros, ordem, corte de 10, meia-noite com relógio fixo, envio pelo canal, falha sem exceção), grupo "widget snapshot" em `todo_service_test.dart` (envio que nunca volta, ordem, falha do envio, envio na inicialização), `floating_todo_complete_viewmodel_test.dart`, `floating_todo_add_screen_test.dart`, `floating_todo_flow_test.dart`, e casos de `FloatingLaunch` em `floating_chat_mode_test.dart`, `floating_chat_service_test.dart` e `memex://open_todo` em `app_action_service_test.dart`.
  - `flutter build apk --flavor globalDev --debug --no-pub`: `√ Built buildpp\outputslutter-apkpp-globaldev-debug.apk` (exit 0).
  - `git diff --check`: limpo.
- Aparelho: nenhum (adb e celular não usados). `NOT_RUN`: tudo no S25 (checklist de doze itens em `docs/fases/F15-05-widget-grande.md`); o widget grande de fato; os broadcasts de data e hora; o alarme da meia-noite; a abertura a frio do trampolim de concluir; TalkBack; texto a 200%. Testes de Android nativo não existem no projeto; `TodoWidgetSnapshot.rows` e `nextChangeMillis` só se validam no aparelho.
- Estado: F15-05 REVIEW (D-072) até a evidência no S25.

### F15-04 — widget médio com captura, código (2026-11-14)
- O que existe: `widget_medium.xml` (faixa de chat mais faixa de captura Anotar, Foto e Colar), com `widget_chat_row` e `widget_capture_row` compartilhados com o pequeno; `WidgetLayouts` com o mapa `SMALL_MIN` 200×60 e `MEDIUM_MIN` 200×120 dp no API 31+, e escolha por `OPTION_APPWIDGET_MIN_HEIGHT` no API 26–30 (`onAppWidgetOptionsChanged`). Cada tecla de captura abre `FloatingChatActivity` com `floating_chat_mode` = `note`, `photo` ou `paste`. O Dart roteia para `/floating-capture` (`FloatingCaptureScreen`). Guardar envia pelo `MemexRouter.sendMessage` do Registrar (cena `super_agent_home`, sessão mais recente); Fechar, toque fora e voltar não gravam. Desenho e checklist do S25 em `docs/fases/F15-04-widget-medio.md`; decisão em D-069.
- Comandos e saídas (branch `feat/f15-04-widget-medio`, worktree `sm-f1504`):
  - `flutter pub get --enforce-lockfile` → exit 0.
  - `flutter gen-l10n` → regenerou `app_localizations*.dart` com as dez chaves `floatingCapture*` pt/en.
  - `dart analyze` nos arquivos alterados (lib e testes da F15-04): `No issues found!` (exit 0) nos 9 caminhos alterados (lib/domain, lib/routing, lib/ui/floating_chat, lib/main.dart, lib/l10n, testes da captura e do serviço), depois do `dart format`.
  - `flutter test --no-pub --reporter compact` (domínio do modo, `test/ui/floating_chat`, integração do chat e da captura, serviço e `test/l10n`): `All tests passed!`: +56 (exit 0) em `test/domain/models/floating_chat_mode_test.dart`, `test/ui/floating_chat` (inclui `floating_capture_viewmodel_test` e `floating_capture_screen_test`), `test/integration/floating_capture_flow_test.dart`, `test/integration/floating_chat_flow_test.dart`, `test/data/services/floating_chat_service_test.dart` e `test/l10n`.
  - `flutter build apk --flavor globalDev --debug --no-pub`: `√ Built build\app\outputs\flutter-apk\app-globaldev-debug.apk` (exit 0).
- Aparelho: nenhum (adb e celular não usados). `NOT_RUN`: tudo no S25 (checklist de nove itens em `docs/fases/F15-04-widget-medio.md`); câmera e galeria dentro da folha translúcida; medição da grade do médio; Android 8 a 11; TalkBack; texto a 200%.
- Estado: F15-04 REVIEW (D-069) até a evidência no S25.

### F15-03 — widget pequeno, código (2026-11-14)
- O que existe: `SegundaMenteWidgetProvider` e `WidgetLayouts` (Kotlin, pacote `com.memexlab.memex.widget`); layout `widget_small` com as teclas Conversar (âmbar, preenchida) e Falar (contorno) na mesma faixa; `res/xml/segundamente_widget_info.xml` (home_screen, `updatePeriodMillis="0"`, resizable, minWidth 200 dp, minHeight 60 dp, targetCell 2×1); receiver no manifesto. Toques abrem `FloatingChatActivity` com `floating_chat_mode` = `type` ou `talk`, o mesmo alvo dos atalhos da F15-02 (D-068). Desenho e checklist do S25 em `docs/fases/F15-03-widget-pequeno.md`.
- Comandos e saídas (branch `feat/f15-03-widget-pequeno`, worktree `sm-f1503`):
  - `flutter pub get --enforce-lockfile` → `Got dependencies!` (exit 0)
  - `flutter build apk --flavor globalDev --debug --no-pub` → `√ Built build\app\outputs\flutter-apk\app-globaldev-debug.apk` (exit 0). O APK traz `res/layout/widget_small.xml`, `res/xml/segundamente_widget_info.xml` e os drawables; o manifesto mesclado contém `SegundaMenteWidgetProvider` e `APPWIDGET_UPDATE`.
  - Teste Android: nenhum. `android/app/src/test` e `androidTest` não existem, e a subfase não adiciona infraestrutura de teste. Dart: nenhuma linha alterada, então `flutter test` e `flutter analyze` não foram rodados para esta subfase.
  - `git diff --check` → limpo.
- Aparelho: nenhum (adb não usado; o widget não foi instalado).
- `NOT_RUN`: tudo no S25 (checklist de oito itens em `docs/fases/F15-03-widget-pequeno.md`); TalkBack; medição da grade real (a dica 2×1 e o mínimo de 200 dp podem mudar após medir); texto a 200%; abertura a frio do chat pelo widget.
- Estado: F15-03 REVIEW (D-068) até a evidência no S25.

### F15-02 — chat flutuante, implementação (2026-11-14)
- O que existe: `FloatingChatActivity` translúcida com motor Flutter compartilhado (`SharedFlutterEngine`, D-065); channel `com.memexlab.memex/floating_chat`; rota `/floating-chat` com o `AgentChatDialog` em modo flutuante (cabeçalho "Abrir no app" e "Fechar", Conversar com o campo focado, Falar com `ListenOnceViewModel`: ouve uma fala, transcreve e envia; digitar ou enviar cancela a escuta); atalhos do ícone "Conversar" e "Falar". Desenho em `docs/fases/F15-02-chat-flutuante.md`.
- Comandos e saídas:
  - `flutter pub get --enforce-lockfile` → `Got dependencies!`
  - `flutter analyze` → 159 issues (0 erros, 6 warnings e 153 infos, todos em arquivos que esta branch não alterou ou já presentes no HEAD)
  - `flutter test --no-pub --reporter compact` → `+1802 ~4: All other tests passed!` (4 ignorados por ambiente: ripgrep ausente e avaliação de agente ao vivo; as 4 falhas antigas de Configurações não reproduziram)
  - `./gradlew :app:compileGlobalDevDebugKotlin` → BUILD SUCCESSFUL
  - `flutter build apk --flavor globalDev --debug --no-pub` → `app-globalDev-debug.apk` (≈255 MiB)
- Testes novos: `test/data/services/floating_chat_service_test.dart`, `test/ui/floating_chat/view_models/listen_once_viewmodel_test.dart`, `test/ui/floating_chat/widgets/floating_chat_screen_test.dart`, `test/integration/floating_chat_flow_test.dart` e casos novos em `test/ui/chat/widgets/agent_chat_dialog_test.dart`.
- Aparelho: nenhum (`adb devices` vazio).
- `NOT_RUN`: tudo no S25 (abertura a frio medida, transparência sobre a tela inicial, troca de host entre `MainActivity` e a folha, teclado no Conversar, microfone e fim de fala no Falar, volta para a tela de origem ao fechar, Abrir no app levando a conversa); TalkBack; envio pelo botão com escuta ativa (sem teste).
- Estado: F15-02 segue IN_PROGRESS até a evidência no S25.

### F11 — portão fechado (2026-11-14)
- AC-01: tarefa sintética `F11 AC-01` (pacote `app.segundamente.dev`, S25 Ultra), vencimento 08h30, alerta de 20 min. Confirmado por adb em 2026-11-14: `usagestats` com `time="2026-11-14 08:10:00" type=NOTIFICATION_INTERRUPTION package=app.segundamente.dev channelId=todo_reminders` e `dumpsys alarm` com `[Deliver] … rtc=2026-11-14 08:10:00.002`. O dono também viu a notificação chegar às 08h10. PASS.
- Concluir com o app fechado, build atual (`main` 0268098a, instalado às 12:23): tarefa sintética com vencimento às 12:36; processo morto com `am kill` antes e depois da entrega (`pidof` vazio); notificação postada às 12:36:00.365; Concluir tocado às 12:36:35; novo processo iniciado e a tarefa virou "Concluída · 14 de nov. de 2026". Controle com o processo vivo (12:43) também PASS. PASS por adb.
- Tentativa da manhã, com o app fechado, no build de 2026-11-13 (anterior às correções MEDIUM): o dono tocou em Concluir e viu a tarefa em Concluídas, mas às 12:20 "F11 AC-01" ainda estava em Atrasadas. Não persistiu; a causa não foi identificada (o logcat já tinha rodado). Discrepância aberta, não reproduzida no build atual.
- Portão F11 fechado: F11-01 a F11-06 DONE, AC-01 observado no S25, nenhum Todo antigo perdido; auditoria `PASS` em `docs/reviews/F11.md` (detalhes lá). Pela D-062, a F15 fica liberada para a F15-02 sem nova decisão.
- `NOT_RUN`, sem bloquear o portão: a parte "após sincronização confirmada" do AC-01 (depende da F12); quarentena do `todo.json` corrompido no S25; TalkBack, tema claro e fonte ampliada no Todo; `flutter test` completo.
- Limpeza feita pelo app: `F11 AC-01`, `F11 cold start`, `F11 MEDIUM QA` e duas `F11 cold QA` excluídas; abas vazias, 0 alarmes pendentes e 0 notificações do F11.
- Caminho de alarmes dos achados MEDIUM validado no S25 com o build atual: alarme em T+20 para tarefa com vencimento em T+40 (`origWhen=12:44:00`, `exactAllowReason=permission`), movido para 12:49 após editar (um alarme só, mesmo PendingIntent) e cancelado ao Concluir (`alarm_cancelled`, 0 pendentes).
- Observação, não investigada: no cold start, o logcat mostrou `E FlutterSecureStorage: EncryptedSharedPreferences initialization failed. Falling back to custom ciphers.` e `SecurityException: Could not decrypt key`. Não tem ligação com o Todo, mas esse armazenamento guarda os tokens de login do app.

### F15-01 — maquetes do widget e do chat (2026-11-14)
- Documento `docs/fases/F15-01-maquetes.md` com as opções A (linhas) e B (teclas), o chat flutuante, os estados compartilhados, a estimativa de células (fórmula 70n−30 dp, não medida) e os riscos. Fonte: `docs/fases/f15-01/maquetes.html` (dados sintéticos). Decisão D-063. Estado da subfase: DONE (D-064).
- Render (comando de referência): Chrome headless `--headless=new --force-device-scale-factor=1 --window-size=1160,2200 --screenshot` sobre cópias por seção do `maquetes.html`, com recorte em Pillow. Saída: `docs/imagens/f15-01-a-linhas.png` (1160×947), `f15-01-b-teclas.png` (1160×947), `f15-01-chat.png` (1160×1193) e `f15-01-estados.png` (1160×775). Revisão visual dos quatro PNG no desktop: nada cortado, o '+ tarefa' acima do dock em A e B, a folha Conversar encostada no teclado. Correções na prancha: regra do cabeçalho da página restrita a `body > header` (vazava para o cabeçalho dos widgets), '+' duplicado removido, largura das colunas fixada em 348 px, área de toque de 48 px no círculo de concluir e no botão de enviar sem mudar o desenho.
- Aparelho: nenhum (desktop). Nenhum código de produto alterado.
- `NOT_RUN`: medição da grade One UI no S25; abertura a frio do chat; TalkBack; texto a 200% no aparelho; `flutter test`; `flutter analyze`; qualquer instalação ou toque de widget.
- Aceite: escolha do dono no chat em 2026-11-14, combinação (teclas no pequeno, linhas no grande; médio em teclas por leitura, D-064).

### F11 — correção dos achados MEDIUM da auditoria (2026-11-13)
- Quatro achados MEDIUM de `docs/reviews/F11.md` corrigidos, cada um com teste escrito antes da correção: (1) `todo.json` legado corrompido vai para quarentena `todo.json.corrupt-<yyyyMMddTHHmmss>` com bytes preservados, cria `todo-v2.json` vazio, registra aviso sem conteúdo e mostra aviso na tela (`todo_legacy_damaged_banner`, chaves `todoLegacyFileDamaged` em pt e en); `todo-v2.json` corrompido continua falhando sem ser zerado; (2) sincronização de alarmes saiu de `_storageLock` e roda depois do rename; (3) sincronização serializada com um run por vez e um run extra que relê a lista mais nova; (4) `time_zone` inválido cai para `America/Sao_Paulo` em `TodoItem.fromJson` e o cálculo não lança mais exceção.
- Ajustes de teste com intenção preservada: `todo_service_test.dart` ("corrupt legacy ...") e `todo_repository_test.dart` ("returns a Result error ...", agora "a damaged legacy file is kept aside ...") trocaram a expectativa de erro pela de quarentena; manteve-se a verificação de que o original e o backup ficam intactos. `tearDown` de três arquivos passou a aguardar a sincronização de alarmes (`TodoService.waitForAlarmSync`) para evitar corrida de arquivo em uso no Windows. Fakes de `MemexRouter` em 30 arquivos ganharam `todoDamagedLegacyFileName` (retorno `Ok(null)`), exigido pela interface.
- `flutter test --no-pub --reporter compact` nos 15 arquivos da área (comando da F11) → **135 aprovados, 0 falhas** (eram 127; +8 testes novos).
- `dart analyze` nos arquivos Dart alterados → 0 erros; 9 diagnósticos, todos em linhas que já existiam (8 infos e o warning `unused_element_parameter` em `todo_screen.dart:415`, `super.key`).
- `flutter build apk --flavor globalDev --debug --no-pub` → `app-globaldev-debug.apk` gerado.
- `NOT_RUN`: validação no S25 (aparelho desconectado; a rodar depois, com o AC-01 e a tela de aviso de quarentena); suíte completa `flutter test`; `flutter analyze` do repositório inteiro; limites conhecidos: a inicialização do `MemexRouter` ainda aguarda a primeira sincronização de alarmes, e a tela aguarda a checagem de alarmes antes de sair do carregamento (só visível com lista vazia).

### F11-06 — aviso de conteúdo (2026-11-13)
- Aviso fixo na captura (legenda abaixo do campo, `ContentNoticeCaption` em `lib/ui/core/widgets/content_notice.dart`, usado em `lib/ui/chat/widgets/agent_chat_dialog.dart`) e linha em Configurações (`lib/ui/settings/widgets/settings_page.dart`, chave `content-notice-settings`). Textos novos em `app_pt.arb` e `app_en.arb`: `contentNoticeCaption` e `contentNoticeSettingsDesc`. `gen-l10n` regenerado. Decisão D-061.
- Ajuste de teste: a linha nova empurrou `link-preview-switch` para fora da área construída da lista; o teste passou de `ensureVisible` para `scrollUntilVisible`, como o vizinho. Nenhum teste foi removido ou enfraquecido.
- `flutter test --no-pub test/ui/core/widgets/content_notice_test.dart test/ui/settings/widgets/settings_page_test.dart test/ui/chat/widgets/agent_chat_dialog_test.dart test/l10n --reporter compact` → **67 aprovados, 0 falhas** (aviso pt e en na captura, pt e en nas Configurações, paridade de chaves ARB, localização e strings fixas).
- `flutter test --no-pub test/l10n test/ui/settings test/ui/chat/widgets test/ui/core --reporter compact` → **310 aprovados, 0 falhas** (vizinhança dos arquivos tocados).
- `dart analyze` nos seis arquivos Dart tocados → 2 infos, pré-existentes em `test/ui/chat/widgets/agent_chat_dialog_test.dart` (linhas 44 e 45, imports que não foram alterados); nenhum problema no código novo.
- S25 Ultra, pacote `app.segundamente.dev` (`flutter build apk --flavor globalDev --debug --no-pub`, `adb install -r`, alarme do AC-01 preservado): legenda sob o campo de captura em uma linha, legível, sem corte nem sobreposição com os botões; linha nas Configurações (ícone, título e descrição, abaixo de Idioma) legível no fundo AMOLED. Capturas inspecionadas pelo orquestrador.
- `NOT_RUN`: leitura por TalkBack; tema claro; fonte ampliada do sistema; suíte completa `flutter test` e `flutter analyze` do repositório.

### F7-03 — fechamento no S25 (2026-11-13)
- Conversa no app `app.segundamente` (release 1.0.47+132), por volta de 22h55–23h00, com o dono falando. **Interromper e falar**: PASS, observado pelo dono (a voz parou e o app voltou a ouvir). **Encerrar**: PASS, observado pelo dono. Nenhum dos dois tem medição de tempo.
- **Permissão negada**: PASS. O dono negou o microfone e o app mostrou o aviso. Adb às 23:02:47: `RECORD_AUDIO: granted=false` (negação permanente) e `Uid mode: RECORD_AUDIO: ignore`. Restaurada às 23:03 (`granted=true`, `foreground`).
- Limitação de evidência: o observador por adb foi preparado, mas a gravação da linha do tempo (estados da tela e `appops`) não foi concluída.
- `NOT_RUN`: revogação no meio da conversa (dispensada pelo dono, D-060); bateria fora do carregador; eco com fone; latência ponta a ponta no app.
- Detalhes em `docs/fases/F7-03-voz-duplex.md`, seção 5c; decisão em D-060.

### F11-01 — modelo e migração do Todo (2026-11-13)
- Novo modelo versionado com UUID, prioridade baixa/normal/alta/urgente, dia e hora separados em `America/Sao_Paulo`, recorrência, subtarefas, origem F9, versão e tombstone. O armazenamento novo é aditivo (`todo-v2.json`); o `todo.json` original fica intacto e é copiado para backup antes de interpretar. Migração só roda quando o v2 não existe.
- Serviço protegido contra chamadas simultâneas entre o app e a integração de relatórios; o teste concorrente reproduziu colisão de rename no Windows antes do `Lock` e passou depois da correção.
- `flutter test --no-pub test/domain/models/todo_item_test.dart test/data/services/todo_service_test.dart test/data/repositories/todo_repository_test.dart test/data/services/session_report_service_test.dart test/integration/memex_router_init_test.dart test/ui/todo/widgets/todo_screen_test.dart` → **66 testes aprovados**. Inclui fixtures sintéticas de migração e regressão do vínculo F9.
- `dart analyze lib/domain/models/todo_item.dart lib/data/services/todo_service.dart lib/data/repositories/todo_repository.dart` → **No issues found**. A análise direcionada mais ampla encontrou apenas um `info` preexistente em `file_system_service.dart:288`.
- `git diff --check` → sem erros.
- `NOT_RUN`: `flutter analyze` completo (ficou sem saída após “Analyzing segundamente...” e foi interrompido); suíte `flutter test --no-pub` completa; validação física. Alarmes no aparelho pertencem à F11-04.

### F11-02 — atalhos e repetição (2026-11-13)
- Implementados atalhos de data/hora configuráveis, alerta padrão de 20 minutos, editor com recorrência diária/semanal/mensal e cálculo em `America/Sao_Paulo`; mensal no dia 31 usa o último dia disponível. A interface mostra a orientação de tarefa sem horário somente enquanto o horário está vazio.
- Clarificação do dono registrada em D-051: ao concluir depois de ciclos vencidos, manter a cadência e pular essas ocorrências; uma tarefa sem horário continua válida até o fim do dia local.
- Ao concluir uma ocorrência, o histórico permanece concluído e a próxima ocorrência ativa é gravada junto, com série, vínculo de origem, prioridade, horário e alerta preservados; checklist reinicia e reabrir/concluir de novo não duplica o sucessor.
- `flutter test --no-pub --reporter compact test/domain/models/todo_shortcut_settings_test.dart test/domain/use_cases/todo_schedule_calculator_test.dart test/utils/user_storage_todo_shortcuts_test.dart test/data/repositories/todo_repository_test.dart test/data/services/settings_registry_todo_test.dart test/ui/todo/widgets/todo_shortcut_settings_page_test.dart test/ui/todo/widgets/todo_screen_test.dart test/data/services/todo_service_test.dart test/integration/memex_router_init_test.dart` → **73 testes aprovados**.
- `dart analyze lib/domain/models/todo_item.dart lib/domain/use_cases/todo_schedule_calculator.dart lib/data/services/todo_service.dart lib/data/repositories/todo_repository.dart` → **No issues found**. `flutter gen-l10n` concluiu; `git diff --check` sem erros.
- `flutter analyze --no-pub` → `NOT_RUN`: permaneceu em “Analyzing segundamente...” sem saída por 60 segundos e foi interrompido.
- `flutter test --no-pub test/ui/settings/widgets/settings_page_test.dart test/ui/settings/widgets/ai_service_setup_page_test.dart` → **FAIL** em fixtures antigas de configurações (FileSystemService não inicializado e interações fora da área visível); os testes isolados da rota e das configurações Todo passaram.
- `NOT_RUN`: suíte Flutter completa; validação física. Alarmes no aparelho pertencem à F11-04.

### F11-03 — telas, busca e lista única (2026-11-13)
- Entregues as abas Hoje, Próximas, Atrasadas e Concluídas sobre a mesma coleção, com busca global incluindo concluídas, filtro de prioridade, subtarefas e estado/data explícitos nos resultados. Itens sem data aparecem em Hoje sob “Sem data”, sem receber prazo. Exclusão usa tombstone com “Desfazer”; o vínculo de origem do relatório continua visível.
- `flutter test --no-pub --reporter expanded test/data/repositories/todo_repository_test.dart test/data/services/todo_service_test.dart test/domain/use_cases/todo_schedule_calculator_test.dart test/ui/todo/view_models/todo_viewmodel_test.dart test/ui/todo/widgets/todo_screen_test.dart test/integration/todo_undo_flow_test.dart` → **62 testes aprovados** antes da correção de inicialização.
- `flutter gen-l10n` → código pt/en regenerado, saída 0. `dart format` nos arquivos Dart alterados → concluído. `git diff --check` → sem erros.
- Reteste pós-F11-03: o AVD x86_64 exigiu ABI x86_64 temporária no filtro local, revertida depois do build. Com ela, a inicialização revelou que `TodoService` acessava `FileSystemService.instance` antes do `init()` assíncrono. O serviço agora resolve o filesystem sob demanda; `test/data/repositories/todo_repository_initialization_test.dart` cobre a regressão.
- `flutter test --no-pub --reporter expanded test/data/repositories/todo_repository_test.dart test/data/repositories/todo_repository_initialization_test.dart test/data/services/todo_service_test.dart test/domain/use_cases/todo_schedule_calculator_test.dart test/ui/todo/view_models/todo_viewmodel_test.dart test/ui/todo/widgets/todo_screen_test.dart test/integration/todo_undo_flow_test.dart` → **63 testes aprovados**.
- `dart analyze lib/data/services/todo_service.dart test/data/repositories/todo_repository_initialization_test.dart` → **No issues found!**
- `flutter run --flavor globalDev --no-pub -d emulator-5554` iniciou o app; `adb shell monkey -p app.segundamente.dev -c android.intent.category.LAUNCHER 1` confirmou reinício a frio e persistência. QA manual passou em criação sem data, edição de prioridade, filtro, busca global com estado/data, conclusão/reabertura, quatro abas, subtarefa criada/concluída, exclusão/desfazer e persistência da tarefa e subtarefa após reinício. Capturas AMOLED foram inspecionadas; a tarefa sintética foi removida.
- QA atualizado em `docs/reviews/F11-todo-referencias/qa-f11-03.md`. `flutter analyze --no-pub` e suíte completa `flutter test --no-pub` → `NOT_RUN`; TalkBack, tema claro, fonte ampliada do sistema, Maestro e validação no S25 → `NOT_RUN`. Alarmes físicos permanecem na F11-04.
- O primeiro APK sem ABI x86 falhou no AVD por incompatibilidade com o filtro arm64 de produto; não é uma falha do APK destinado ao aparelho arm64. A correção de inicialização foi verificada no build x86 temporário; validação física continua pendente para fluxos que a exigem.

### F11-05 — propostas de tarefa pela IA (2026-11-13)
- Chat e captura exibem uma proposta persistida como artefato; comentários de personas guardam o mesmo cartão no comentário. A lista Todo só muda após a confirmação do dono; datas como “sexta” e horários vagos ficam sem resolução automática. O ID da proposta torna a confirmação idempotente e impede duplicação ao reabrir o chat; tombstones continuam visíveis. Mapas de proposta malformados, inclusive com chave YAML não textual, são ignorados sem derrubar a leitura do cartão.
- O editor compartilhado permite revisar título, data, hora, prioridade, subtarefas, repetição e alerta. Foi protegida a carga assíncrona do cartão contra descarte do ViewModel ao fechar o chat.
- `flutter test --no-pub test/domain/models/todo_proposal_test.dart test/domain/models/card_model_test.dart test/data/model/chat_artifact_test.dart test/data/services/todo_service_test.dart test/data/repositories/todo_repository_test.dart test/data/repositories/todo_repository_initialization_test.dart test/data/repositories/card_reply_name_test.dart test/agent/todo_proposal_skill_test.dart test/agent/comment_tool_factory_test.dart test/agent/comment_agent_policy_test.dart test/agent/super_agent_permissions_test.dart test/ui/todo/view_models/todo_viewmodel_test.dart test/ui/todo/view_models/todo_proposal_viewmodel_test.dart test/ui/todo/widgets/todo_screen_test.dart test/ui/todo/widgets/todo_proposal_card_test.dart test/ui/chat/widgets/agent_chat_dialog_test.dart test/integration/todo_undo_flow_test.dart` → **166 testes aprovados**.
- A integração inclui skill → artefato → confirmação → MemexRouter/serviço/armazenamento; nenhum Todo existia antes da confirmação.
- `flutter test --no-pub --reporter compact` → **1.743 aprovados, 2 ignorados, 4 falhas**, todas em `test/ui/settings/widgets/settings_page_test.dart` (toques fora da janela). A execução isolada reproduziu: `link previews start off and the switch is remembered`, `on-device transcription starts off and the switch is remembered`, `the local speech model is downloaded and deleted here, only when on-device transcription is on` e `downloaded model can be deleted while semantic search is off`. São falhas conhecidas, fora dos arquivos alterados; a suíte geral foi executada antes dos dois testes finais de mapas malformados, aprovados no lote de área acima.
- `flutter analyze --no-pub` → **159 issues encontrados** no repositório; não é PASS. `dart analyze lib/ui/todo/view_models/todo_proposal_viewmodel.dart test/ui/todo/view_models/todo_proposal_viewmodel_test.dart test/integration/todo_undo_flow_test.dart test/domain/models/todo_proposal_test.dart test/agent/todo_proposal_skill_test.dart` → `No issues found!`. A análise dirigida mais ampla apontou 15 avisos/infos em linhas legadas de `todo_screen.dart`, `card_model.dart` e `timeline_card_detail_screen.dart`; a análise final dos parsers/modelos/testes encontrou 3 `info` legados em `card_model.dart` e nenhum erro.
- AVD `CoreFlow_API36_Clean`/`emulator-5554`: `flutter run --flavor globalDev --no-pub -d emulator-5554` abriu o app após build x86_64 local temporário (filtro restaurado). Maestro navegou até Todo, confirmou o estado vazio, abriu o editor, verificou “Sem horário” e alerta padrão de 20 min e cancelou sem gravar dados.
- `NOT_RUN`: geração de proposta por modelo real no chat/captura/persona (o AVD mostra modelo de IA não configurado); validação física no S25 (pertence à F11-04); TalkBack; suíte geral aprovada sem as quatro falhas de Configurações.

### F11-04 — alarmes locais do Todo (2026-11-13)
- Implementado o agendamento local exato no Android, com verificação e solicitação das permissões de notificações e alarmes, ações Adiar (10 min), Concluir e Abrir, reagendamento após alterações do Todo e cancelamento de alarmes obsoletos. A F11-04 permanece `IN_PROGRESS` até concluir a matriz física.
- `flutter test --no-pub test/domain/use_cases/todo_alarm_schedule_test.dart test/domain/use_cases/todo_schedule_calculator_test.dart test/domain/models/todo_item_test.dart test/data/services/todo_service_test.dart test/data/repositories/todo_repository_test.dart test/data/repositories/todo_repository_initialization_test.dart test/data/services/session_report_service_test.dart test/data/services/app_action_service_test.dart test/ui/todo/view_models/todo_viewmodel_test.dart test/ui/todo/widgets/todo_screen_test.dart test/integration/todo_undo_flow_test.dart test/integration/memex_router_init_test.dart test/l10n/arb_key_parity_test.dart test/l10n/locale_lookup_test.dart test/l10n/hardcoded_ui_strings_test.dart` → **124 testes aprovados**.
- `flutter build apk --flavor globalDev --debug --no-pub` → **build arm64 concluído**. O build não valida entrega física do alarme.
- `dart analyze` nos arquivos Dart alterados → **4 diagnósticos já existentes**: `todo_screen.dart:409` (parâmetro `key` sem uso), `todo_screen.dart:765` (`value` depreciado) e dois `prefer_const_constructors` em `todo_screen_test.dart`; nenhum diagnóstico nos novos arquivos de agendamento/modelo. `flutter analyze --no-pub` → **159 issues encontrados, exit 1**; não é PASS.
- AVD `emulator-5554` (API 36 x86_64): Maestro abriu Todo e salvou a tarefa sintética `F11 smoke QA alarm` para 14 nov. 2026 às 09:00; a hierarquia de acessibilidade mostrou o item em Próximas. `adb shell cmd appops get app.segundamente.dev SCHEDULE_EXACT_ALARM` → `allow`. `adb shell dumpsys alarm` mostrou `RTC_WAKEUP` para `ScheduledNotificationReceiver`; após excluir a tarefa sintética no app, o dump registrou `alarm_cancelled`. O teste Maestro com correspondência exata do título não passou porque o item expõe título, data e prioridade em um único rótulo; a inspeção da tela confirmou o rótulo completo.
- S25 Ultra (SM-S938B, Android 17 / SDK 37): `adb devices -l` enumerou o aparelho e `emulator-5554`. Foi instalado `globalDev` no pacote separado `app.segundamente.dev`; o pacote estável `app.segundamente` e seus dados não foram alterados. O workspace dev usa o perfil sintético `F11 QA`.
- No primeiro acesso, o Todo mostrou o aviso de alarme exato negado. “Configurar” abriu a tela Android “Alarmes e lembretes”; após autorizar e voltar, o aviso sumiu. `cmd appops get app.segundamente.dev SCHEDULE_EXACT_ALARM` confirmou `allow`.
- Tarefa sintética `F11 S25 smoke abrir`, prazo 13 nov. 2026 às 21:00, alerta padrão de 20 min: `dumpsys alarm` mostrou `RTC_WAKEUP` às 20:40 com `exactAllowReason=permission`; às 20:40 o S25 entregou a notificação com título, corpo e três ações. Tocar em “Abrir” levou à lista Hoje e exibiu a tarefa com prazo correto. Tocar em “Adiar 10 min” criou novo `RTC_WAKEUP` para 20:54:04.
- T15: após `adb reboot`, o user 0 ficou `RUNNING_LOCKED`; depois do desbloqueio, `ScheduledNotificationBootReceiver` recebeu `BOOT_COMPLETED` às 20:48:33, restaurou o alarme exato para 20:54:04 e `dumpsys alarm` registrou `Deliver` às 20:54. A notificação pós-reinício permaneceu ativa com as três ações.
- AVD `emulator-5554` (API 36 x86_64): Maestro criou e excluiu uma tarefa sintética de amanhã às 09:00; `dumpsys alarm` confirmou o agendamento e depois `alarm_cancelled`. A assertion Maestro por título exato não correspondeu ao rótulo combinado de acessibilidade (título/data/prioridade); a inspeção mostrou o rótulo completo.
- Primeira rodada: Concluir, T03, T05 e T16 ficaram `NOT_RUN` (o servidor Maestro morreu ao abrir o painel após o reboot). Fechados na segunda rodada abaixo.

### F11-04 — validação física final no S25 (2026-11-13, 21:22–21:36)
- Feita por `adb -s RQCY10934YV` (uiautomator e toques); Maestro MCP indisponível. Perfil sintético `F11 QA` no pacote `app.segundamente.dev`; o pacote estável não foi tocado.
- Notificação pós-reboot (T15): já entregue às 20:54 (registro acima). Ao expandi-la às 21:23, um toque meu caiu durante a animação do painel e a dispensou (`notification_canceled` motivo 2); nenhuma ação foi executada e a tarefa continuou aberta. Concluir foi testado na notificação seguinte.
- T05: tarefa `F11 S25 smoke abrir` editada no app para 21:55 → `dumpsys alarm` com um único `RTC_WAKEUP` às 21:35; editada para 21:52 → um único pendente às 21:32 (`exactAllowReason=permission`), o das 21:35 não existe mais. Cada gravação registra dois `Add` do mesmo PendingIntent com ~20 ms de diferença; o segundo substitui o primeiro, sem alarme duplicado.
- T03 offline + Doze: app em segundo plano, `cmd connectivity airplane-mode enable` e `cmd wifi set-wifi-enabled disabled` (`Active default network: none`), `dumpsys battery unplug` e `dumpsys deviceidle force-idle` (`deep: IDLE`). Às 21:32:00.049 `notification_enqueue` e `Deliver` do alarme, ainda com Doze `IDLE` e sem rede. Restaurados depois: `deviceidle unforce`, `battery reset`, modo avião desligado e Wi‑Fi ligado (estado conferido).
- Concluir: na notificação das 21:32, expandida pelo botão dela, “Concluir” abriu o app, removeu a notificação e moveu a tarefa para Concluídas; `dumpsys alarm` → 0 alarmes pendentes do app.
- T16: nova tarefa sintética `F11 S25 T16` (hoje 23:30, alerta 23:10) → `RTC_WAKEUP` 23:10. `pm revoke app.segundamente.dev android.permission.POST_NOTIFICATIONS` (`granted=false`); ao abrir o Todo apareceu “As notificações de tarefas estão desativadas. Ative-as para receber avisos.” com “Configurar”, e o alarme foi cancelado (`alarm_cancelled`, 0 pendentes). “Configurar” abriu o diálogo do sistema; “Permitir” restaurou `granted=true`, o aviso sumiu e o alarme das 23:10 foi reagendado. `SCHEDULE_EXACT_ALARM` continuou `allow`.
- Limpeza: as duas tarefas sintéticas foram excluídas pelo app; `alarm_cancelled` registrado, 0 alarmes pendentes, 0 notificações do app e as quatro abas vazias.
- Ambiente: a primeira execução da suíte falhou ao compilar (`timezone-0.11.2` e `flutter_local_notifications` ausentes do cache do pub, fora do repositório). `flutter pub get --enforce-lockfile` restaurou o cache sem alterar arquivos versionados.
- Mesmo comando de 15 arquivos acima, `--reporter expanded` → **124 testes aprovados**.
- `flutter analyze --no-pub` → **159 issues (153 info, 6 warning, 0 error), exit 1**; nenhum em `todo_alarm_service.dart`, `todo_schedule_calculator.dart` ou `main.dart`. Igual à linha de base; não é PASS.
- Correção D-059 (auditoria F11, HIGH): aviso no horário do prazo quando o alerta já passou. 127 testes da área aprovados; no S25, tarefa criada às 22h27 para as 22h35 recebeu `RTC_WAKEUP` às 22:35:00 e foi entregue às 22:35:00.002. Detalhes em `docs/reviews/F11.md`.
- Concluir com o app fechado: o lembrete das 22h04 foi entregue com o processo morto, mas o Não Perturbar do dono (desde 22h00, lista suprimida) o ocultou da bandeja e a atualização do APK o removeu. `NOT_RUN`; será testado na notificação do AC-01.
- `NOT_RUN`: AC-01 na hora real 08h30/08h10 (exige esperar a manhã; o relógio do S25 não foi alterado) e a parte “após sincronização confirmada” do AC-01, que depende da F12; suíte completa `flutter test --no-pub`; TalkBack.

### Modelo de fala em Configurações (2026-11-12)
- O download do modelo local saiu do microfone do chat e foi para Configurações > "Transcrição no aparelho", com progresso e exclusão. Desligado, o áudio vai direto para o ChatGPT. O microfone do chat só dita; sem modelo, ele aponta para Configurações.
- Correção: a extração no fim do download falhava com "object is unsendable", porque o fecho do `Isolate.run` levava o `onProgress`. Agora a extração usa uma função estática.
- Testado no S25 (APK release instalado). A conversa por voz passou em início, 7 turnos, pausa, retomada, segundo plano e tela apagada. Detalhes em [docs/fases/F7-03-voz-duplex.md](docs/fases/F7-03-voz-duplex.md), seção 5b.
- `NOT_RUN`: Interromper e falar, Encerrar, permissão negada/revogada, download do modelo no aparelho.
- Commit: 2026-11-13, junto com a reestruturação dos documentos.

### Expansão Lumen + Todo robusto (2026-11-13)
- Decisões D-050 a D-055, a partir do [questionário](docs/questionario/2026-11-13-lumen-desktop-e-todo.md). O pacote original está em [docs/lumen/](docs/lumen/README.md).
- Documentação reestruturada:
  - o ROADMAP virou índice, com um arquivo por fase em `docs/roadmap/`;
  - os documentos de trabalho foram para `docs/fases/`, as imagens para `docs/imagens/`, os roteiros de teste para `docs/testes/` e os documentos do Memex original para `docs/upstream/`;
  - este STATE foi enxugado e o histórico arquivado em `docs/historico/`.
- Nenhum código de produto mudou na reestruturação; só comentários com caminhos de documentos.

## Como registrar evidência

Adicione uma subseção datada em "Evidências recentes" com o comando, a saída, o aparelho e o que ficou `NOT_RUN`. Quando uma fase fechar ou a seção passar de umas 15 entradas, mova as evidências antigas para um novo arquivo em `docs/historico/` e deixe aqui só o link.

# STATE — ponto de retomada

**Atualizado:** 2026-11-13 · **MVP:** pronto (portão da F5 fechado em 2026-11-05, `docs/reviews/F5.md`: AUDIT RESULT: PASS) · **Última release:** v1.0.47+132 (2026-11-11, GitHub Release privada) · **Fase ativa:** F11 — Todo robusto (IN_PROGRESS), em paralelo à Fase L (Lumen) do fork `playertwo1/coucou`

Este arquivo guarda só o estado atual, a próxima ação e as evidências recentes. O histórico completo de 2026-11-02 a 2026-11-13 está em [docs/historico/STATE-2026-11-02-a-2026-11-13.md](docs/historico/STATE-2026-11-02-a-2026-11-13.md). Fases, critérios e portões estão no [ROADMAP](ROADMAP.md).

## Estado das fases

| Fase | Estado | Observação |
|---|---|---|
| F0, F4, F5, F6 | DONE | Portões fechados |
| F1, F2, F3 | IN_PROGRESS | Critérios do MVP cumpridos; tarefas adicionais abertas |
| F7 | IN_PROGRESS | Só a F7-03 (voz duplex por turnos, D-049); F7-02 adiada (D-041), F7-06 BLOCKED |
| F5V, F9, F10 | PAUSED | D-050; o estado de cada subfase no momento da pausa está no arquivo da fase |
| F8 | BLOCKED | NotebookLM pós-MVP sem previsão; caminho escolhido: via B (D-055) |
| F11 | IN_PROGRESS | F11-01 a F11-05 DONE; portão aguarda AC-01 (08h30/08h10) no S25; F11-06 BLOCKED |
| F12, F13, F14 | BLOCKED | Sync (D-054), Google (D-055), assistente ativo (D-050) |

## Próxima ação

1. **Portão F11:** observar AC-01 no S25 às 08h10 de 2026-11-14 (tarefa sintética `F11 AC-01` das 08h30 já agendada) e testar Concluir com o app fechado na notificação `F11 cold start`, oculta pelo Não Perturbar até 07h00. A auditoria `docs/reviews/F11.md` está `FAIL` por um HIGH: sem aviso quando o horário do alerta já passou. Corrigir depende de decisão do dono.
2. **F11-06:** permanece BLOCKED; D-056 não a desbloqueia.
3. **F7-03:** validar no S25 o que falta: Interromper e falar, Encerrar, permissão negada ou revogada. Depois fechar a subfase.
4. **Em paralelo, no fork:** Fase L (L0: fechar o que está quase pronto; L1: renomear para Lumen com assets próprios). Ver `docs/roadmap/fase-l-lumen.md` em `playertwo1/coucou`.
5. **F12:** permanece bloqueada até a conclusão da F11 e das decisões de sync.

## Pendências do dono

- Criar o projeto Google Cloud em produção sem verificação (F13-01, D-055).
- Escolher o visual do Lumen no protótipo (Fase L1 do fork).
- Testar no S25 os itens da F7-03 acima.
- Observar o AC-01 no S25 às 08h10 (aviso de uma tarefa sintética das 08h30).

## Ambiente (fora do repositório)

- Flutter em `C:\Users\notefael\tools\flutter`, fora do PATH: usar `C:\Users\notefael\tools\flutter\bin\flutter`. `flutter config --jdk-dir` aponta para o JDK 17 em `C:\Users\notefael\AppData\Local\Programs\jdk-17` (o Java 25 padrão quebra o Gradle 8.14).
- O Flutter 3.47 reescreve `analysis_options.yaml` e `android/gradle.properties` ao rodar `pub get`, build ou test: reverter com `git checkout` antes de commitar. Usar `flutter pub get --enforce-lockfile`.
- Aparelho de prova: Samsung Galaxy S25 Ultra (Android 17). Keystore de release local em `android/key-global.properties`, fora do git.

## Linha de base de qualidade

- v1.0.47 (2026-11-11): `flutter test --no-pub --reporter compact` com 1.674 aprovados, 4 ignorados e 0 falhas. A análise completa da época ficou `NOT_RUN`; a execução final da F11-05 encontrou 159 issues, detalhadas abaixo.

## Evidências recentes

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

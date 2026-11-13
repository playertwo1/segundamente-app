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
| F11 | IN_PROGRESS | F11-01 a F11-03 DONE; F11-04 BLOCKED (validação no S25) |
| F12, F13, F14 | BLOCKED | Sync (D-054), Google (D-055), assistente ativo (D-050) |

## Próxima ação

1. **F11-04:** permanece BLOCKED; requer validação de alarmes no Galaxy S25 Ultra antes de iniciar.
2. **F7-03:** validar no S25 o que falta: Interromper e falar, Encerrar, permissão negada ou revogada. Depois fechar a subfase.
3. **Em paralelo, no fork:** Fase L (L0: fechar o que está quase pronto; L1: renomear para Lumen com assets próprios). Ver `docs/roadmap/fase-l-lumen.md` em `playertwo1/coucou`.
4. **F12:** permanece bloqueada até a conclusão da F11 e das decisões de sync.

## Pendências do dono

- Criar o projeto Google Cloud em produção sem verificação (F13-01, D-055).
- Escolher o visual do Lumen no protótipo (Fase L1 do fork).
- Testar no S25 os itens da F7-03 acima.

## Ambiente (fora do repositório)

- Flutter em `C:\Users\notefael\tools\flutter`, fora do PATH: usar `C:\Users\notefael\tools\flutter\bin\flutter`. `flutter config --jdk-dir` aponta para o JDK 17 em `C:\Users\notefael\AppData\Local\Programs\jdk-17` (o Java 25 padrão quebra o Gradle 8.14).
- O Flutter 3.47 reescreve `analysis_options.yaml` e `android/gradle.properties` ao rodar `pub get`, build ou test: reverter com `git checkout` antes de commitar. Usar `flutter pub get --enforce-lockfile`.
- Aparelho de prova: Samsung Galaxy S25 Ultra (Android 17). Keystore de release local em `android/key-global.properties`, fora do git.

## Linha de base de qualidade

- v1.0.47 (2026-11-11): `flutter test --no-pub --reporter compact` com 1.674 aprovados, 4 ignorados e 0 falhas. `flutter analyze` no repositório inteiro: `NOT_RUN` desde então.

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

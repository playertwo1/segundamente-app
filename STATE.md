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
| F11 | IN_PROGRESS | F11-01 DONE; F11-02 READY (D-051, D-052) |
| F12, F13, F14 | BLOCKED | Sync (D-054), Google (D-055), assistente ativo (D-050) |

## Próxima ação

1. **F11-02:** implementar recorrência e atalhos de dia/hora com relógio/fuso verificáveis. Critério em [docs/roadmap/F11-todo-robusto-celular.md](docs/roadmap/F11-todo-robusto-celular.md).
2. **F11-03:** telas Hoje, Próximas, Atrasadas e Concluídas; busca, filtros e testes de widget, após F11-02.
3. **F7-03:** validar no S25 o que falta: Interromper e falar, Encerrar, permissão negada ou revogada. Depois fechar a subfase.
4. **Em paralelo, no fork:** Fase L (L0: fechar o que está quase pronto; L1: renomear para Lumen com assets próprios). Ver `docs/roadmap/fase-l-lumen.md` em `playertwo1/coucou`.
5. **F12:** permanece bloqueada até a conclusão da F11 e das decisões de sync.

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

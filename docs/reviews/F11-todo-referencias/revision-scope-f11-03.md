# Escopo de revisão — F11-03 Todo

- Data: 2026-11-13
- Pedido: implementar F11-03 nas referências visuais aprovadas e no aceite da fase.
- Plataforma e stack: Android, Flutter, MVVM + Provider.
- Status: aplicada
- Esforço: telas e estados afetados; testes de widget e da camada de dados.
- Base/reversão: branch `feat/f11-03-telas-lista-unica`, baseada no merge local `5624b1ac`; retornar a esse commit para desfazer esta subfase.

## Escopo

| Tela / componente | Mudança proposta | Arquivos prováveis |
|---|---|---|
| Lista Todo | Abas Hoje, Próximas, Atrasadas e Concluídas; prioridade, filtros, subtarefas, estados vazio/erro e ação de exclusão com Desfazer | `lib/ui/todo/widgets/todo_screen.dart`, `lib/ui/todo/view_models/todo_viewmodel.dart` |
| Busca Todo | Busca global incluindo concluídas; resultado mostra estado e data | `lib/ui/todo/widgets/todo_screen.dart`, `lib/ui/todo/view_models/todo_viewmodel.dart` |
| Persistência Todo | Restaurar tombstone ao desfazer exclusão, mantendo fluxo Repository → MemexRouter → ViewModel | `lib/data/services/todo_service.dart`, `lib/data/repositories/todo_repository.dart`, `lib/data/repositories/memex_router.dart` |
| Localização e testes | Strings pt/en e regressões de widget, serviço e repositório | `lib/l10n/app_{pt,en}.arb`, `test/ui/todo/`, `test/data/` |

Fora desta lista: alarmes da F11-04, sync, integração Google, confirmação de IA, alterações ao processamento da F9 e mudanças às referências aprovadas.

## Prévia da mudança

- Estado atual: uma lista simples, busca inline, exclusão com diálogo e sem filtros por aba.
- Mudança pretendida: quatro abas literais; uma única coleção Todo; busca independente da aba que inclui concluídas e explicita estado/data; filtro de prioridade; edição e exibição de subtarefas; exclusão imediata reversível pelo snackbar aprovado.
- Resultado esperado: navegar por estado, localizar qualquer tarefa e recuperar uma exclusão sem apagar dados.
- Decisão registrada em D-051: tarefas sem data aparecem em Hoje, numa seção “Sem data”, sem receber um prazo.
- Risco de regressão: texto ampliado e largura de 320 dp exigem validação.
- Captura de linha de base: `NOT_RUN`; o flavor `globalDev` compilou e instalou no emulador, mas a inicialização falhou com `MissingLibraryException` para `libflutter.so`.

## O que permanece aprovado

- `01-listas-v3.png`, `02-edicao-e-repeticao-v2.png`, `03-configuracoes-e-estados-v2.png`.
- `04-layout-320dp.png`, `05-busca-global.png`, `06-exclusao-desfazer.png`.
- Nenhuma dessas imagens será regravada ou substituída.

## Histórico e reversão

| Versão | Data | O que mudou | Artefato | Como reverter |
|---|---|---|---|---|
| v0 | 2026-11-13 | Base F11-02 concluída; sem alteração de código F11-03 | `5624b1ac` | Manter a branch na base |
| v1 | 2026-11-13 | Implementadas as quatro abas, busca global, prioridade, subtarefas, erro/vazio e desfazer; 62 testes direcionados passaram; a inspeção visual ficou bloqueada pela falha de inicialização do emulador | branch `feat/f11-03-telas-lista-unica`; QA em `qa-f11-03.md` | Reverter o commit da subfase |

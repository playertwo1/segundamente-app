# F15-05 — Widget grande com tarefas de hoje

> Subfase da [F15 — Widget e atalhos Android](../roadmap/F15-widget-e-atalhos-android.md). Estado: **REVIEW** (código e testes prontos; aparelho `NOT_RUN`). Visual: linhas no grande (D-064). Escolhas de produto: D-072. Estado atual: [STATE.md](../../STATE.md).

## O que entrega

O tamanho grande do widget "Segunda Mente" (faixa mínima 250×270 dp), no desenho "linhas" da [F15-01](F15-01-maquetes.md):

- **Em cima:** a faixa de Conversar e Falar (F15-03) e a faixa de captura Anotar, Foto e Colar (F15-04).
- **No meio:** até três tarefas de hoje. Cada linha tem um círculo (toque conclui a tarefa), o título (toque abre a lista de tarefas no app) e a hora. Atrasadas vêm primeiro, depois as de hoje por horário.
- **Embaixo:** a tecla **+ tarefa** (pt) / **+ Task** (en).
- Sem tarefas: "Nada para hoje" (pt) / "Nothing for today" (en) no lugar das linhas.

## Quais tarefas aparecem (D-072)

- Só tarefas abertas (não concluídas, não apagadas) **com data**.
- Atrasadas: data anterior a hoje, ou hoje com hora já passada (mesma regra de `TodoScheduleCalculator.statusFor`, fuso America/Sao_Paulo).
- De hoje: data de hoje, com ou sem hora.
- Tarefas futuras e **sem data** não aparecem. Elas continuam na tela de Todo.

## Fluxo de dados

### Snapshot (Dart → nativo)

`TodoWidgetSnapshotService` (`lib/data/services/todo_widget_snapshot_service.dart`) monta um JSON e envia pelo canal `com.memexlab.memex/todo_widget`, método `updateSnapshot`:

```json
{"version":1,"items":[{"id":"…","title":"…","dueDate":"2026-11-14","dueTime":"15:00","status":"today","timeZone":"America/Sao_Paulo"}]}
```

- Campos: `id`, `title`, `dueDate`, `dueTime` (ou `null`), `status` (informativo: `overdue`, `today` ou `upcoming` na hora do envio), `timeZone`. Nenhum outro campo; nenhum texto de conversa.
- Conteúdo: as **10 primeiras** tarefas abertas com data, em ordem de data e hora. Com esse corte, o lado nativo sempre tem as três linhas certas depois da meia-noite: se houver dez atrasadas, as três mais antigas são as que aparecem.
- O nativo guarda o último JSON em `SharedPreferences` privado do app (`todo_widget_snapshot`). Não há arquivo gerenciado, então nenhum caminho novo entrou no `FileSystemService`.

### Quando envia

- **Após cada escrita do Todo:** `TodoService._write` chama `_syncWidgetSnapshot(items)` sem `await`, depois do rename e fora do `_storageLock` (mesma regra dos alarmes). Um canal travado não bloqueia leitura nem escrita. As escritas são enviadas na ordem em que acontecem, então o último envio é sempre a lista mais nova.
- **Na inicialização:** `MemexRouter._ensureInitialized` chama `TodoRepository.refreshWidgetSnapshot` (sem `await`).

### Quando o widget se redesenha

- A cada envio do snapshot (`SegundaMenteWidgetProvider.refreshAll`).
- Broadcasts `DATE_CHANGED`, `TIME_SET` (mudança de hora) e `TIMEZONE_CHANGED`, declarados no receiver do manifesto.
- Alarme inexato (`AlarmManager.set`, sem permissão de alarme exato) no próximo instante em que as linhas podem mudar: meia-noite em America/Sao_Paulo ou a hora de uma tarefa de hoje que ainda não passou. Ao disparar, o widget se redesenha e agenda o próximo instante. Sem widget colocado, o alarme é cancelado.
- As linhas são escolhidas a cada desenho, com a hora atual, então a virada do dia não depende de um envio do Dart.

## Concluir pelo widget

O círculo abre `FloatingChatActivity` com o modo `todo_complete:<id>` (o mesmo caminho da F15-02). Escolha e motivo:

1. **Trampolim, não edição nativa.** A `FloatingChatActivity` é translúcida e não mostra folha. O Dart abre a rota `/floating-todo-complete?id=…`, que chama `FloatingTodoCompleteViewModel.complete` → `MemexRouter.setTodoDone` → `TodoService.setDone` (o caminho normal), e depois `closeFloatingSheet`. O nativo nunca escreve no arquivo do Todo (AGENTS.md).
2. **Processo morto.** O motor compartilhado sobe com o Activity (`SharedFlutterEngine.ensure`), e o `main()` lê o modo pendente (`takePendingLaunch`) e começa na rota de conclusão. Por isso funciona a frio.
3. **Por que não BroadcastReceiver.** Com o processo morto, um receiver não tem motor Dart para chamar; precisaria do mesmo trampolim. Um só caminho é mais simples.
4. Depois da conclusão, o `setDone` escreve o Todo, o snapshot é enviado e o widget se redesenha.
5. Concluir de novo uma tarefa já concluída não muda nada. Id desconhecido: o router devolve erro, o ViewModel registra no log e fecha a folha, sem exceção.

## + tarefa

O toque abre `FloatingChatActivity` com o modo `todo_add` → rota `/floating-todo-add` → `FloatingTodoAddScreen`. A tela usa `TodoViewModel` e o editor que a tela de Todo usa (`showTodoEditorDialog`), por cima da folha. Salvar chama `TodoViewModel.add` → `MemexRouter.addTodo`. Cancelar, toque fora ou voltar só fecha. Nada é gravado sem o Salvar do editor.

## Título

O toque abre `memex://open_todo`: um filtro novo no manifesto (`MainActivity`) e o mapeamento `open_todo` em `AppActionService.actionFromDeepLink`. A ação já existia (`openTodoAction`, usada pelos alarmes); a lista de tarefas abre por `_handleAppAction`. Abrir uma tarefa específica não existe no app hoje, então o título abre a lista.

## Privacidade (D8)

- Só na tela inicial (`widgetCategory="home_screen"`, sem keyguard), como o restante do widget.
- O snapshot fica no `SharedPreferences` privado do app, sem rede e sem log de títulos (o log de envio não traz o JSON).
- Nenhum trecho de conversa entra no widget.

## Arquivos

Dart:
- `lib/data/services/todo_widget_snapshot_service.dart` (novo): `buildSnapshot` puro e `push` pelo canal.
- `lib/data/services/todo_service.dart`: seam `widgetSnapshotSynchronizer`, envio após escrita, `refreshWidgetSnapshot`.
- `lib/data/repositories/todo_repository.dart`, `lib/data/repositories/memex_router.dart`: início e repasse.
- `lib/data/services/app_action_service.dart`: `memex://open_todo`.
- `lib/data/services/floating_chat_service.dart`: `takePendingLaunch` e `openRequests` com `FloatingLaunch`; `takePendingMode` continua como antes.
- `lib/domain/models/floating_chat_mode.dart`: modos `todoAdd`, `todoComplete`; `FloatingLaunch` (modo e id).
- `lib/routing/routes.dart`, `lib/routing/router.dart`, `lib/main.dart`: rotas e início a frio.
- `lib/ui/floating_chat/view_models/floating_todo_complete_viewmodel.dart` (novo).
- `lib/ui/floating_chat/widgets/floating_todo_complete_screen.dart` (novo) e `floating_todo_add_screen.dart` (novo).

Android:
- `widget/SegundaMenteWidgetProvider.kt`: `onReceive` (data e hora), `refreshAll`, alarme do próximo instante.
- `widget/TodoWidgetSnapshot.kt` (novo): armazenamento, `parse`, `rows` (escolha por agora), `nextChangeMillis`.
- `widget/WidgetLayouts.kt`: chave `LARGE_MIN` 250×270 dp no API 31+, altura ≥ 270 no API 26–30, linhas, "+ tarefa", título e círculo.
- `channels/TodoWidgetChannelHandler.kt` (novo), registrado em `ChannelRegistrar`.
- `channels/FloatingChatChannelHandler.kt`: aceita `todo_add` e `todo_complete:<id>`.
- `layout/widget_large.xml`, `layout/widget_task_row.xml`, `drawable/widget_task_circle.xml` (novos).
- `values/strings.xml`, `values-pt/strings.xml`, `values/colors.xml` (`widget_muted`).
- `AndroidManifest.xml`: `memex://open_todo`; broadcasts do receiver.

Testes:
- `test/data/services/todo_widget_snapshot_service_test.dart` (novo): conteúdo, filtros, ordem, corte de 10, virada da meia-noite com relógio fixo, envio pelo canal, falha sem exceção.
- `test/data/services/todo_service_test.dart`: grupo "widget snapshot": escrita completa com envio que nunca volta, ordem dos envios, falha do envio, envio na inicialização.
- `test/data/services/app_action_service_test.dart`: `memex://open_todo`.
- `test/data/services/floating_chat_service_test.dart`: `takePendingLaunch` e `todo_complete:<id>`; a expectativa de `openRequests` agora lê `.mode` do launch (mesmo valor).
- `test/domain/models/floating_chat_mode_test.dart`: modos e `FloatingLaunch`.
- `test/ui/floating_chat/view_models/floating_todo_complete_viewmodel_test.dart` (novo): conclusão uma vez, já concluída, id desconhecido, falha, id vazio.
- `test/ui/floating_chat/widgets/floating_todo_add_screen_test.dart` (novo): editor sobre a folha, salvar, cancelar, texto vazio.
- `test/integration/floating_todo_flow_test.dart` (novo): conclusão a frio, id desconhecido, conclusão com o app aberto, "+ tarefa".
- `test/helpers/floating_todo_fakes.dart` (novo): `FakeTodoRouter` e `todoTask`.

## Riscos

- **Layout nativo sem teste automatizado.** O projeto não tem teste de Android (`android/app/src/test`). Os caminhos de `TodoWidgetSnapshot.rows`, `nextChangeMillis`, `WidgetLayouts` e os broadcasts só se validam no S25.
- **Altura de 270 dp.** É estimativa (D-064); a grade medida no S25 pode mudar o corte. Abaixo dela, o widget mostra o médio.
- **Alarme inexato.** Sob Doze, a virada da meia-noite pode atrasar; as linhas atualizam no próximo desenho. Não há alarme exato, de propósito.
- **Broadcast de data.** `DATE_CHANGED` pode não chegar a receiver de manifesto no Android 8+ (não é exceção de broadcast implícito). A meia-noite pelo alarme cobre; `TIME_SET` e `TIMEZONE_CHANGED` são declarados e confirmados no S25.
- **Concluir a frio.** A janela de trampolim translúcido aparece em branco pelo tempo de boot do Dart, não medido. Sem tela, sem toque.
- **Fechar a frio.** Sem pilha abaixo, `closeFloatingSheet` vai para a tela inicial depois do `close` nativo (o Activity já terminou). Mesmo caminho da F15-02.
- **Snapshot cortado em 10.** Não muda as três linhas: as linhas saem da ordem por data e hora, e o corte mantém as tarefas mais antigas, que são as que aparecem.
- **+ tarefa com erro.** Se o `addTodo` falhar, o rascunho some (o editor da tela de Todo também não guarda rascunho). O erro vai ao ViewModel.
- **Ordem de envios.** Garantida pelo canal (FIFO) e porque o envio é feito antes do primeiro `await`. Não há teste de canal real.
- **Campo `status`.** É informativo. O nativo recalcula a partir de `dueDate`, `dueTime` e `timeZone`.
- **Hora em "dd/MM" e "Hoje".** O formato de data é fixo (`%02d/%02d`), e "Hoje" vem do `strings.xml` do idioma do aparelho.

## Checklist para o validador no S25

Instalar o pacote `globalDev` debug (`app.segundamente.dev`) e seguir:

1. Redimensionar o widget até o grande: aparecem Conversar, Falar, Anotar, Foto, Colar, até três linhas e "+ tarefa", nada cortado. Anotar em qual altura o grande aparece (a grade real).
2. Com duas tarefas de hoje e uma atrasada: a atrasada vem primeiro, depois as de hoje por horário, com hora e data nas linhas.
3. Sem tarefas abertas com data: aparece "Nada para hoje".
4. Tocar no círculo com o app fechado: a tarefa some do widget; abrir o Todo e conferir que ela está concluída.
5. Tocar no círculo com o app aberto em outra tela: a tarefa é concluída; a tela de origem volta.
6. Tocar no título: a lista de tarefas abre (app fechado e aberto).
7. Tocar em "+ tarefa": o editor abre sobre a tela inicial; salvar cria a tarefa (aparece no widget se for de hoje); cancelar não cria nada e volta para a origem.
8. Criar ou editar uma tarefa no app: o widget muda sem reabrir.
9. Mudar a data ou a hora do aparelho: o widget se atualiza sozinho. Não alterar o relógio do aparelho do dono; conferir pelo próximo dia real.
10. Virada do dia: observar o widget na primeira meia-noite depois da instalação; a tarefa de ontem vira atrasada sem tocar em nada.
11. Tela de bloqueio: nenhum título de tarefa aparece.
12. TalkBack: o círculo é anunciado como "Concluir <título>" e o título e a hora são lidos.

Registrar em STATE.md o resultado de cada item. Sem o S25, a subfase segue `REVIEW`.

## Evidência e NOT_RUN

- Testes, análise e build: ver o bloco "F15-05 — widget grande" em [STATE.md](../../STATE.md).
- `NOT_RUN`: tudo no aparelho (checklist de doze itens acima); o próprio widget grande; os broadcasts; o alarme da meia-noite; a abertura a frio do trampolim; TalkBack; texto a 200%.

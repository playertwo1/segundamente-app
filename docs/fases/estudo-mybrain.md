# Estudo — o que a Segunda Mente pode aproveitar do MyBrain

Data: 2026-11-25. Nada aqui está autorizado para implementação: cada item só abre com decisão do dono e entra antes em [IDEIAS-FUTURAS](../roadmap/IDEIAS-FUTURAS.md). A parte que serve ao Lumen está no repositório dele, em `docs/roadmap/parqueado.md` (seção "Ideias do MyBrain").

## O projeto

[`mhss1/MyBrain`](https://github.com/mhss1/MyBrain): app Android em Kotlin Multiplatform e Compose, com tarefas, notas em Markdown, diário com humor, favoritos, calendário, painel do dia, widgets e um assistente com ferramentas (biblioteca Koog) que cria e busca itens. Sync local entre aparelhos na mesma rede (NSD, WebSocket, AES-GCM, zstd, pareamento por QR). Estudado na `main` de 2026-10-03.

## Licença

O MyBrain é GPL-3.0, como a Segunda Mente (fork do Memex). A licença permite reaproveitar código aqui. Na prática quase nada vem direto, porque ele é Kotlin e a Segunda Mente é Flutter/Dart: o reaproveitamento é de ideia e de regra. Se algum trecho for traduzido quase linha a linha (por exemplo uma regra de merge ou um parser), acrescentar no `NOTICE` uma linha creditando o MyBrain (autor `mhss1`, GPL-3.0) e o arquivo de origem. Os ícones dele são da Flaticon, com atribuição obrigatória, e não entram.

## O que já existe na Segunda Mente (não fazer)

| No MyBrain | Na Segunda Mente | Onde |
|---|---|---|
| Limpar lápides depois de 90 dias (`CleanupDeletedEntitiesUseCase.kt`, `TOMBSTONE_RETENTION = 90.days`) | Já poda lápides com 90 dias ou mais | `_isExpiredTombstone` em `lib/data/services/todo_sync_service.dart` |
| Ferramenta que cria tarefa | Melhor: `create_todo_proposal` só cria um cartão de confirmação; nada é gravado sem o dono | `lib/agent/skills/propose_todo/todo_proposal_skill.dart`, `lib/ui/todo/widgets/todo_proposal_card.dart` |
| Data rígida para a IA, com erro se inválida | Melhor: `date_state`/`time_state` com "ambíguo" e frase preservada | mesmo skill |
| Subtarefas, prioridade, repetição, alerta | Já existem no Todo (F11) | `lib/ui/todo/` |
| Diário com humor | Cartão de humor na linha do tempo | template `mood` em `lib/agent/skills/manage_timeline_card/timeline_templates.dart` |
| Favoritos pelo menu compartilhar | Compartilhar já recebe conteúdo; há cartão de link | `share_handler` no `pubspec.yaml`, template `link` |
| Trava biométrica | Já existe | `lib/ui/app_lock/`, `local_auth` |
| Widget do calendário e painel do dia | Widgets e painel rápido (F15) | `docs/roadmap/F15-widget-e-atalhos-android.md` |
| Sync local entre aparelhos | Sync com o Lumen pelo relay com cifra ponta a ponta, merge de 3 vias com conflito por campo (o MyBrain usa "o mais recente ganha") | `docs/lumen/CONTRATO-SYNC.md`, F12 |

## O que pode ser aproveitado

Ordem sugerida, se o dono aprovar: SM-MB1 → SM-MB2 → SM-MB3 → SM-MB4 → SM-MB5.

### SM-MB1 — Propor várias tarefas de uma vez (M)

- **No MyBrain:** `create_multiple_tasks` (`ai/data/.../tools/TaskToolSet.kt`) cria uma lista inteira numa chamada.
- **Na Segunda Mente hoje:** `create_todo_proposal` recebe um item por chamada. "Preciso comprar pão, ligar pro banco e renovar o seguro" depende do modelo chamar a ferramenta três vezes, e cada chamada gera um cartão separado (conferir no S25 como isso aparece hoje).
- **Como seria:** uma ferramenta `create_todo_proposals` (ou a atual aceitando `items: [...]`, máximo 10) gera **um** cartão com a lista. Cada item tem caixa de seleção, edição própria e as mesmas regras de `date_state`/`time_state`; um item com data ambígua fica marcado para revisar sem travar os outros. Botão "Criar selecionadas". Nada é gravado sem o toque. Com um item só, o cartão continua o de hoje.
- **Combinar com o Lumen:** ele tem a mesma limitação (`tasks/proposal.rs`, uma proposta por fala) e a ideia está registrada lá como L-MB3. Definir o formato da lista uma vez para os dois lados.
- **Aceite:** testes do parser com lista, lista vazia, 11 itens (corta em 10 e avisa), item sem título (descarta) e formato antigo de um item (compatível). No S25: ditar três tarefas numa frase, desmarcar uma e criar as outras duas; conferir que as duas sincronizam com o Lumen.

### SM-MB2 — Anexar uma tarefa ou um registro ao chat (M)

- **No MyBrain:** `AttachTaskSheet.kt` e `AttachNoteSheet.kt` (`ai/presentation/.../components/`) deixam escolher uma tarefa ou nota e mandá-la como contexto da mensagem.
- **Na Segunda Mente hoje:** o chat anexa fotos (`lib/ui/chat/view_models/photo_attachments_viewmodel.dart`), mas não itens do próprio app.
- **Como seria:** no menu de anexo do chat, além de foto, "Tarefa" e "Registro da linha do tempo", com busca. O item vai como texto delimitado de dado (título, data, subtarefas ou o corpo do registro), nunca como instrução. Como vai para o provedor remoto, o anexo aparece antes do envio e pode ser removido, cumprindo "envio remoto só com escolha explícita e prévia do conteúdo" (PROJECT.md).
- **Aceite:** teste de que o anexo entra delimitado e que remover o anexo tira o conteúdo do pedido; no S25: "me ajuda a quebrar esta tarefa em passos" com uma tarefa anexada, e a resposta propondo subtarefas pelo cartão (não gravando direto).

### SM-MB3 — Cartão do item real depois da confirmação ou da busca (P)

- **No MyBrain:** `AiToolExecutor.extractResultObject` (`ai/data/.../repository/`) relê no banco o item que a ferramenta criou ou achou e mostra o cartão dele na conversa (`AiResultItemCards.kt`), além do texto do modelo.
- **Na Segunda Mente hoje:** o cartão de proposta existe. Conferir no código e no S25 se, depois de "Confirmar", o cartão mostra a tarefa **relida do banco** (com "Abrir na lista") ou só some/muda de texto. Conferir também se as ferramentas de busca (`lib/agent/built_in_tools/`) mostram algum resultado na tela ou só o texto do modelo.
- **Como seria:** o que estiver faltando nessa conferência: depois de confirmar, o cartão vira um cartão compacto da tarefa salva, lido do banco, com "Abrir"; numa busca com 1 a 3 resultados, mostrar os cartões deles abaixo da resposta. Assim, se o modelo resumir errado, a tela mostra o real.
- **Aceite:** teste de widget do cartão confirmado lendo do repositório; no S25: confirmar uma proposta e editar a tarefa na lista; o cartão do chat reflete a edição ao voltar.

### SM-MB4 — Android AppFunctions (G, depende de decisão de privacidade)

- **No MyBrain:** o módulo `appfunctions` (`MyBrainAppFunctions.kt`) expõe ao sistema `createNote`, `searchNotes`, `getNoteById`, `createTask`, `searchTasks`, `updateTaskCompleted`, `createDiaryEntry`, `searchDiaryEntries`, `createBookmark` e `searchBookmarks`, com anotação `@AppFunction` e descrição no KDoc. Um agente do sistema (o Gemini do Android) passa a chamar essas funções.
- **Para a Segunda Mente:** permitiria "Ok Google, o que tenho na Segunda Mente para hoje?" ou "anota na Segunda Mente…" sem abrir o app.
- **Por que é G e condicional:**
  - É API nativa (`androidx.appfunctions`, Android 16 ou mais recente). Em Flutter exige um módulo Kotlin em `android/` que leia os dados sem a interface Flutter (abrir o banco Drift pelo Kotlin ou subir um motor Flutter sem tela). Conferir antes a versão do Android no S25 Ultra e se o Gemini do aparelho já chama AppFunctions de apps de terceiros.
  - **Privacidade:** a busca entrega tarefas e registros ao Gemini, que é um provedor remoto. Isso contraria "dado local por padrão; envio remoto só com escolha explícita" se não houver um controle próprio. Precisa de decisão D-xxx antes de qualquer código.
  - **Confirmação:** uma função "criar" chamada de fora não tem o cartão da Segunda Mente na frente. A versão aceitável é `proposeTask` abrir o app no cartão de confirmação (nunca gravar direto) e `completeTask` ficar de fora.
- **Versão mínima, se aprovada:** só `searchTodayTasks` (leitura, desligada por padrão, com interruptor nos Ajustes explicando que o resultado vai para o assistente do Google) e `proposeTask` (abre o cartão).
- **Encaixe:** ao lado da ideia "Interface MCP para agentes externos" (mesma questão de permissão para agentes de fora).

### SM-MB5 — Gemini Nano pelo ML Kit como alternativa na F7-02 (avaliar, não implementar)

- **No MyBrain:** `ai/data/.../gemininano/GeminiNanoServiceImpl.kt` usa a ML Kit GenAI Prompt API para rodar o Gemini Nano no aparelho, sem rede.
- **Para a Segunda Mente:** a F7-02 (modelo local, adiada pelo dono em D-041) mediu Gemma pelo LiteRT-LM. O Gemini Nano pelo ML Kit seria um terceiro candidato, sem baixar modelo próprio (o sistema fornece).
- **Pontos a conferir antes:** se o S25 Ultra está na lista de aparelhos da ML Kit GenAI; qualidade em pt-BR no corpus da F9-02 (o mesmo usado com o Gemma); limites de contexto; e licença: a ML Kit é componente proprietário do Google Play services (foi por isso que o MyBrain saiu do F-Droid). Para uso pessoal sem distribuir APK não há problema; se um dia houver distribuição, avaliar a compatibilidade com a GPL antes.
- **Encaixe:** só junto com a reabertura da F7-02; não abre sozinho.

### SM-MB6 — Gráfico de humor do mês (P, baixa prioridade)

- **No MyBrain:** o diário guarda um humor de 1 a 5 por entrada e mostra resumo com gráficos.
- **Na Segunda Mente hoje:** existe o cartão de humor na linha do tempo. Conferir se a tela de Insights já tira um resumo desses cartões.
- **Como seria, se faltar:** um insight "Humor do mês" calculado só no aparelho a partir dos cartões de humor, sem enviar nada ao provedor.

## Rejeitado

- **IA que grava tarefa, nota ou diário direto** (como as ferramentas do MyBrain): contraria o controle do MVP (item 7) e a regra "IA propõe, usuário confirma".
- **Sync local Android ↔ Android do MyBrain:** o sync da Segunda Mente é com o Lumen, pelo contrato próprio, com merge mais seguro. Não há segundo Android para sincronizar.
- **Koog, Koin, Room e a arquitetura MVI:** pilha Kotlin, sem uso no Flutter.
- **Notas e diário como módulos separados:** a Segunda Mente organiza tudo como registros e cartões da linha do tempo; separar contrariaria o modelo de dados atual.

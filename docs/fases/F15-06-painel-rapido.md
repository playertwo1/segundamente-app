# F15-06 — botão "Conversar" no painel rápido

> Subfase da [F15](../roadmap/F15-widget-e-atalhos-android.md). Decisão D9 do [questionário](../questionario/2026-11-14-widget-e-capsula.md). Abertura em código antes da validação da F15-02 no S25: [D-070](../DECISIONS.md).

## O que entrega

Um botão "Conversar" no painel de configurações rápidas do Android (o painel que se abre puxando a barra de status). Tocar nele abre o chat flutuante de dentro de qualquer app, com o teclado aberto (modo `type` da F15-02).

- Rótulo: "Conversar" em pt-BR, "Chat" em en.
- Ícone: balão de conversa monocromático (`drawable/ic_qs_chat.xml`), tingido pelo sistema.
- É uma ação, não um liga/desliga: o estado é sempre `STATE_INACTIVE`.

## Entrega e arquivos

| Arquivo | Mudança |
|---|---|
| `android/app/src/main/kotlin/com/memexlab/memex/ConversarTileService.kt` | Novo. `TileService` que abre a `FloatingChatActivity` com `floating_chat_mode=type`. |
| `android/app/src/main/res/drawable/ic_qs_chat.xml` | Novo. Ícone do balão, 24 dp, cor sólida (o sistema tinge). |
| `android/app/src/main/AndroidManifest.xml` | `<service>` com `BIND_QUICK_SETTINGS_TILE`, filtro `android.service.quicksettings.action.QS_TILE`, ícone e rótulo. |
| `android/app/src/main/res/values/strings.xml`, `values-pt/strings.xml` | `tile_conversar` (Chat / Conversar). |
| `docs/fases/F15-06-painel-rapido.md` | Este documento. |

Sem mudança em Dart. Nenhum teste automatizado novo: o projeto não tem configuração de teste unitário Android, e a lógica nova é um desvio de API (ver abaixo), validado pelo build e pelo S25.

## Tratamento por versão de API

- **Android 14+ (API 34, `UPSIDE_DOWN_CAKE`):** `startActivityAndCollapse(PendingIntent)`, com `PendingIntent.getActivity` em `FLAG_IMMUTABLE | FLAG_UPDATE_CURRENT`.
- **Android 8 a 13 (minSdk 26):** `startActivityAndCollapse(Intent)`, com `@Suppress("DEPRECATION")`.
- O intent leva `FLAG_ACTIVITY_NEW_TASK` e a extra `floating_chat_mode=type`. A `FloatingChatActivity` é `singleTask`: se já estiver aberta, recebe `onNewIntent`, o modo pendente é atualizado e o Dart recebe `open`.

## Comportamento com a tela bloqueada

- `onClick()` checa `isLocked`. Com o aparelho bloqueado, a abertura vai dentro de `unlockAndRun { ... }`: o sistema pede o desbloqueio, e só depois do desbloqueio a folha abre. Se o usuário cancelar o desbloqueio, nada abre.
- A `FloatingChatActivity` não declara `showWhenLocked` nem `turnScreenOn`, então ela não aparece sobre a tela de bloqueio por conta própria.
- Nada do chat aparece na tela de bloqueio: a regra de privacidade da F15 (D-064) continua valendo.

## Riscos

- `startActivityAndCollapse` depende da versão. A ramificação de API 34 é a que mais pode falhar; só o S25 (Android 14 ou superior, One UI) confirma o caminho real.
- Uma `FloatingChatActivity` aberta por outro caminho (atalho do ícone) é reaproveitada pelo `singleTask`; o modo muda para `type`, sem perder a conversa aberta.
- Se o tile aparecer como indisponível, o sistema não chamou `onStartListening`: ver o painel de edição de ajustes rápidos e adicionar o tile por lá.

## Validação no S25 (checklist)

Estado: `NOT_RUN`. Só se valida no aparelho com o pacote `globalDev`.

1. Abrir o painel rápido, editar e adicionar "Conversar". O rótulo aparece em pt-BR no aparelho em português.
2. Tocar em "Conversar" com a tela inicial: a folha abre com o teclado. Ao fechar, volta para a tela inicial.
3. Tocar em "Conversar" dentro de outro app (por exemplo, o navegador): a folha abre sobre ele; o painel recolhe; ao fechar, volta para o app de origem.
4. Com o aparelho bloqueado: o pedido de desbloqueio aparece; após desbloquear, a folha abre. Cancelando o desbloqueio, nada abre e nada aparece na tela de bloqueio.
5. Com o app já aberto em folha (atalho "Falar", por exemplo), tocar em "Conversar": o modo passa a ser de digitação, sem duplicar a folha.
6. Ícone do balão visível e monocromático no painel (claro e escuro).

## Limites

- Só `type` (Conversar). "Falar" pelo painel fica fora desta subfase.
- Não cria um estado ativo: o tile não mostra se o chat está aberto.

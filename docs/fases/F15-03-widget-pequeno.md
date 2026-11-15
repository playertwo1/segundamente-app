# F15-03 — Widget pequeno

> Subfase da [F15 — Widget e atalhos Android](../roadmap/F15-widget-e-atalhos-android.md). Estado: **REVIEW** (código pronto; aparelho `NOT_RUN`). Visual: teclas no pequeno (D-064). Roteamento: mesmo intent do chat flutuante (D-065), registrado em D-068. Estado atual: [STATE.md](../../STATE.md).

## O que entrega

Um widget "Segunda Mente" na tela inicial, redimensionável, com duas teclas numa faixa só, como a maquete B no tamanho pequeno:

- **Conversar:** tecla preenchida em âmbar (`#E99A3D`), texto preto.
- **Falar:** tecla em contorno, texto marfim.
- Fundo preto AMOLED, cantos de 20 dp e fio `#33312E`, como [DESIGN.md](../../DESIGN.md).
- Só na tela inicial (`widgetCategory="home_screen"`, sem keyguard, D8). Sem dado pessoal, sem rede, `updatePeriodMillis="0"`.

Os rótulos reusam `shortcut_chat_type` e `shortcut_chat_talk` (pt: Conversar e Falar; default: Chat e Talk).

## Arquivos

- `android/app/src/main/kotlin/com/memexlab/memex/widget/SegundaMenteWidgetProvider.kt`: `AppWidgetProvider`; `onUpdate` monta as views para cada widget.
- `android/app/src/main/kotlin/com/memexlab/memex/widget/WidgetLayouts.kt`: escolhe o `RemoteViews` por tamanho e liga os toques. Ponto de extensão para F15-04 e F15-05.
- `android/app/src/main/res/layout/widget_small.xml`: a faixa com as duas teclas.
- `android/app/src/main/res/xml/segundamente_widget_info.xml`: `appwidget-provider`.
- `android/app/src/main/res/drawable/widget_background.xml`, `widget_key_primary.xml`, `widget_key_outline.xml`: fundo e teclas.
- `android/app/src/main/res/values/colors.xml`: quatro cores do widget.
- `android/app/src/main/res/values/strings.xml` e `values-pt/strings.xml`: `widget_label` e `widget_description`.
- `android/app/src/main/AndroidManifest.xml`: receiver exportado com `APPWIDGET_UPDATE`, rótulo e meta-data.

Nenhum código Dart mudou. Nenhum `*.g.dart` foi tocado.

## Como o toque chega

Cada tecla tem um `PendingIntent.getActivity` explícito para `FloatingChatActivity`:

- ação `ACTION_VIEW`, extra `floating_chat_mode` = `type` (Conversar) ou `talk` (Falar);
- `FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE`, request codes 1 e 2 (a igualdade de `Intent` ignora extras, então os códigos precisam ser diferentes);
- o alvo é `Intent(context, FloatingChatActivity::class.java)`, então vale o pacote do build (`app.segundamente` ou `app.segundamente.dev`). Os atalhos XML exigem literal por flavor; o widget não precisa.

Daí em diante vale o F15-02: `FloatingChatActivity` recebe o extra, `onNewIntent` cuida do caso de a folha já estar aberta, e o chat abre com teclado (`type`) ou ouvindo (`talk`).

**Desvio do roadmap:** a linha da F15-03 dizia "ações entram pelo `AppActionService`". O F15-02 não usa `AppActionService` para o chat flutuante; usa intents da `FloatingChatActivity`. O widget segue o F15-02 e não cria uma segunda rota. A linha foi atualizada e a escolha está em D-068.

## Tamanhos e como crescer

Hoje todo tamanho renderiza o layout pequeno.

- **Provider:** `minWidth` 200 dp e `minHeight` 60 dp (largura para os dois rótulos em 14 sp, estimativa); `targetCellWidth` 2 e `targetCellHeight` 1 (dica do seletor, como pedido); `resizeMode` horizontal e vertical.
- **Android 12+ (API 31+):** `RemoteViews(Map<SizeF, RemoteViews>)` com a chave `SMALL_MIN` = 200×60 dp. O framework escolhe a entrada de maior chave que cabe. Para F15-04 e F15-05, basta acrescentar entradas ao mapa em `WidgetLayouts.views`.
- **API 26 a 30:** só há um layout. Tamanho diferente exige `onAppWidgetOptionsChanged` no provider, que ainda não existe porque hoje não é preciso. A F15-05 precisa dele.
- **Médio e grande:** não implementados nesta subfase (F15-04 e F15-05).

## Riscos

- **Duas células de largura podem ser estreitas para "Conversar".** A maquete estimou 4×2 (D-064), mas o pedido desta subfase foi 2×1 para o alvo do seletor. O `minWidth` de 200 dp garante os rótulos em 14 sp, então o launcher deve tratar o tamanho mínimo como 3 células. O S25 decide se a dica 2×1 precisa mudar.
- **Altura de 60 dp.** A célula real da One UI no S25 não foi medida (a grade é estimativa em D-064).
- **Preview.** `previewLayout` só aparece no seletor do Android 12+. Em API 26 a 30, o seletor mostra o ícone do app.
- **Sem teste unitário Android.** O projeto não tem `android/app/src/test` nem `androidTest`. Não foi adicionada infraestrutura de teste (pedido da subfase). O comportamento se valida só no S25, pelo checklist abaixo.
- **Abertura a frio.** O toque no widget herda a abertura a frio da folha (F15-02), que ainda não foi medida no S25.
- **TalkBack.** Os botões são `TextView` com `minHeight` 48 dp; o anúncio e a área de toque não foram conferidos.

## Checklist para o validador no S25

Instalar o pacote `globalDev` debug (`app.segundamente.dev`) e seguir:

1. Tela inicial, pressionar em área vazia, Widgets: aparece "Segunda Mente" com a descrição. O preview mostra a faixa com Conversar e Falar.
2. Adicionar o widget à tela inicial: faixa preta com cantos arredondados, Conversar em âmbar, Falar em contorno, nada cortado.
3. Tocar em Conversar: a folha abre com o teclado aberto. Fechar; a tela inicial volta.
4. Tocar em Falar: a folha abre ouvindo. Na primeira vez, o Android pede a permissão de microfone.
5. Redimensionar nas duas direções. Anotar o menor tamanho em que "Conversar" cabe inteiro e quantas células ocupa (grade real).
6. Com o app aberto em outra tela, tocar nas teclas: a folha abre por cima e a tela de origem volta ao fechar (comportamento da F15-02).
7. Bloquear a tela: o widget não aparece na tela de bloqueio.
8. Ativar o TalkBack: Conversar e Falar são anunciados com o nome certo e cada tecla responde ao toque.

Registrar em STATE.md o resultado de cada item. Sem o S25, a subfase segue `REVIEW`.

## Evidência e NOT_RUN

- Build e análise: ver o bloco "F15-03 — widget pequeno" em [STATE.md](../../STATE.md).
- `NOT_RUN`: tudo no aparelho (itens 1 a 8 do checklist); TalkBack; medição da grade real; texto a 200%.

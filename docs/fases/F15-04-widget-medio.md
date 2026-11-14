# F15-04 — Widget médio com captura

> Subfase da [F15 — Widget e atalhos Android](../roadmap/F15-widget-e-atalhos-android.md). Estado: **REVIEW** (código e testes prontos; aparelho `NOT_RUN`). Visual: teclas no pequeno e captura no médio (D-064). Abertura antes do S25 da F15-03: D-067. Estado atual: [STATE.md](../../STATE.md).

## O que entrega

O tamanho médio do widget "Segunda Mente" (faixa mínima 200×120 dp):

- **Em cima:** a faixa do pequeno, Conversar em âmbar e Falar em contorno (F15-03).
- **Embaixo:** a faixa de captura, três teclas em contorno: **Anotar**, **Foto** e **Colar**.

Cada tecla de captura abre uma folha compacta por cima da tela inicial, não o chat. A folha só grava quando o dono toca em **Guardar**:

- **Anotar:** campo de texto com o foco. Guardar envia o texto; Fechar descarta.
- **Foto:** escolhe câmera ou galeria, como os anexos do app. Mostra a prévia e um campo de texto opcional; Guardar envia a foto com o texto.
- **Colar:** lê a área de transferência quando a folha abre e pré-preenche o campo. Se não houver texto, mostra "Nada para colar. Copie um texto e tente de novo." e Guardar fica desligado. Nunca grava sozinho.

Em todas: o aviso da F11-06 (`ContentNoticeCaption`) aparece sob o campo; Fechar, o toque fora e o voltar descartam e voltam para a tela de origem, como a folha de chat.

## Como grava

Guardar chama `FloatingCaptureViewModel.save`, que chama `MemexRouter.sendMessage` com a cena `super_agent_home` e a sessão mais recente, o mesmo caminho do Registrar (`openSuperAgentDialog` → `AgentChatDialog._sendMessage`). A foto segue com o mesmo nome original e o mesmo hash de envio (`recordProcessedHashes`). O registro na linha do tempo é feito pelo super agent, como em qualquer captura do Registrar. Nenhum arquivo é escrito direto (AGENTS.md).

O resultado conta como salvo quando o super agent aceita: o primeiro evento chega sem erro, ou o fluxo termina. Um evento de erro ou falha de stream deixa a folha aberta com "Não deu para guardar agora. Tente de novo."; a corrida continua em segundo plano quando aceita, como uma mensagem enviada do chat.

## Roteamento

1. Toque em Anotar, Foto ou Colar: `FloatingChatActivity` com `floating_chat_mode` = `note`, `photo` ou `paste`. Mesmo alvo e mesmo extra de D-065 e D-066; request codes 3, 4 e 5 separam os `PendingIntent`s.
2. `FloatingChatChannelHandler.setPendingMode` aceita os cinco modos (chat e captura).
3. Dart: `takePendingMode` ou o sinal `open` devolve o modo; `AppRoutes.floatingLocationFor(mode)` escolhe `/floating-chat` (type, talk) ou `/floating-capture` (note, photo, paste).
4. `/floating-capture` cria `FloatingCaptureViewModel(router: context.read<MemexRouter>(), mode)` e mostra `FloatingCaptureScreen`.
5. Fechar: `closeFloatingSheet` (compartilhada com o chat): `close` nativo, depois `pop` ou `go('/')`.

## Tamanhos

- **Android 12+ (API 31+):** `RemoteViews(mapOf(SMALL_MIN to small, MEDIUM_MIN to medium))`, com `SMALL_MIN` 200×60 dp e `MEDIUM_MIN` 200×120 dp.
- **Android 8 a 11 (API 26 a 30):** um layout por `RemoteViews`. O provider escolhe por `OPTION_APPWIDGET_MIN_HEIGHT` (≥ 120 dp = médio) em `onUpdate` e em `onAppWidgetOptionsChanged`.
- O grande (F15-05) entra no mesmo mapa e no mesmo `when`.

## Arquivos

Android:
- `android/app/src/main/res/layout/widget_chat_row.xml`: as teclas Conversar e Falar, compartilhadas pelo pequeno e pelo médio (novo).
- `android/app/src/main/res/layout/widget_capture_row.xml`: as teclas Anotar, Foto e Colar (novo).
- `android/app/src/main/res/layout/widget_medium.xml`: as duas faixas (novo).
- `android/app/src/main/res/layout/widget_small.xml`: passa a incluir `widget_chat_row`; visual igual.
- `android/app/src/main/kotlin/com/memexlab/memex/widget/WidgetLayouts.kt`: mapa de tamanhos, teclas de captura e escolha por altura no API 26–30.
- `android/app/src/main/kotlin/com/memexlab/memex/widget/SegundaMenteWidgetProvider.kt`: `onUpdate` com a altura; `onAppWidgetOptionsChanged`.
- `android/app/src/main/kotlin/com/memexlab/memex/channels/FloatingChatChannelHandler.kt`: aceita `note`, `photo` e `paste`.
- `android/app/src/main/res/values/strings.xml` e `values-pt/strings.xml`: `widget_key_note`, `widget_key_photo`, `widget_key_paste`.
- `android/app/src/main/res/xml/segundamente_widget_info.xml`: comentário atualizado; `previewLayout` continua o pequeno.

Dart:
- `lib/domain/models/floating_chat_mode.dart`: `note`, `photo`, `paste`; `isCapture`.
- `lib/routing/routes.dart`: `floatingCapture`, `floatingLocationFor`.
- `lib/routing/router.dart`: rota de captura; `_floatingSheetPage` compartilhada com a do chat.
- `lib/main.dart`: início a frio e sinal `open` usam `floatingLocationFor`.
- `lib/ui/floating_chat/floating_chat_host.dart`: `closeFloatingSheet`, compartilhada.
- `lib/ui/floating_chat/widgets/floating_chat_screen.dart`: `_close` chama `closeFloatingSheet`.
- `lib/ui/floating_chat/view_models/floating_capture_viewmodel.dart` (novo).
- `lib/ui/floating_chat/widgets/floating_capture_screen.dart` (novo).
- `lib/l10n/app_pt.arb`, `app_en.arb` e os `app_localizations*.dart` regenerados (`gen-l10n`).

Testes:
- `test/domain/models/floating_chat_mode_test.dart` (novo): parse e `isCapture`.
- `test/data/services/floating_chat_service_test.dart`: caso dos modos de captura.
- `test/ui/floating_chat/view_models/floating_capture_viewmodel_test.dart` (novo): Colar, Guardar, erros, foto e hash.
- `test/ui/floating_chat/widgets/floating_capture_screen_test.dart` (novo): cada modo, Guardar único, Fechar, clipboard vazio, aviso, recusa.
- `test/integration/floating_capture_flow_test.dart` (novo): cold start e Colar pelo sinal `open`, com o roteador real e o `MemexRouter` falso.
- `test/helpers/floating_capture_fakes.dart` (novo): `FakeCaptureRouter`.

## Riscos

- **Guardar cria o registro pelo super agent.** O toque em Guardar confirma o texto ou a foto, mas quem escreve a linha do tempo é o agente, como no Registrar. Se o dono quiser uma confirmação a mais (revisar o cartão antes de gravar), é outra decisão.
- **Sessão mais recente.** Como o Registrar, a captura entra na conversa mais recente do super agent. Uma conversa longa e ativa pode demorar a aceitar; a fila do chat não é reproduzida aqui.
- **Câmera dentro da folha translúcida.** A câmera e a galeria abrem outra Activity sobre a folha. O retorno e o estado da folha só se validam no S25.
- **Clipboard.** A leitura acontece quando a folha abre. Android 10+ só libera a leitura com a folha em foco; se a leitura falhar, a mensagem é a mesma de área vazia.
- **Imagem no Android 8 a 11.** A troca de layout por altura depende de o launcher enviar `OPTION_APPWIDGET_MIN_HEIGHT`; não foi medida no S25 (nem em outro aparelho desta faixa).
- **Grade real.** Os 120 dp do médio são estimativa (D-064), não medida.
- **Hash de foto.** Usa o mesmo cálculo do chat (`photo_<nome>_<tamanho>`); não foi comparado com um envio real no S25.
- **Abertura a frio.** Herdada da F15-02 (não medida).
- **TalkBack e texto a 200%.** Não conferidos (`NOT_RUN`).

## Checklist para o validador no S25

Instalar o pacote `globalDev` debug (`app.segundamente.dev`) e seguir:

1. Adicionar o widget à tela inicial e redimensioná-lo até o médio: aparecem as duas faixas, Conversar, Falar, Anotar, Foto e Colar, nada cortado.
2. Tocar em Anotar: a folha abre com o campo focado. Digitar um texto: nada grava. Tocar em Guardar: a folha fecha e a tela inicial volta. Confirmar o registro na linha do tempo depois que o agente processar.
3. Tocar em Anotar, digitar um texto e tocar em Fechar: a folha fecha e nada é gravado (conferir a linha do tempo).
4. Tocar em Colar com um texto copiado em outro app: o campo vem preenchido; nada grava; Guardar grava.
5. Tocar em Colar com a área de transferência vazia: aparece a mensagem de nada para colar, e Guardar fica desligado.
6. Tocar em Foto: escolher câmera (uma foto) e galeria (outra foto). Cada prévia aparece; nada grava até Guardar.
7. Com o app aberto em outra tela, tocar em Foto: a folha abre por cima e a tela de origem volta ao fechar.
8. Em Android 8 a 11 (se houver aparelho): redimensionar e conferir que o layout troca entre pequeno e médio.
9. Ativar o TalkBack: cada tecla de captura é anunciada com o nome certo.

Registrar em STATE.md o resultado de cada item. Sem o S25, a subfase segue `REVIEW`.

## Evidência e NOT_RUN

- Testes, análise e build: ver o bloco "F15-04 — widget médio" em [STATE.md](../../STATE.md).
- `NOT_RUN`: tudo no aparelho (itens 1 a 9 do checklist); medição da grade real; abertura a frio; câmera e galeria dentro da folha; TalkBack; texto a 200%.

# F15-07 — Protótipos da minicápsula

> Subfase da [F15](../roadmap/F15-widget-e-atalhos-android.md). Decisão de forma em D11 do [questionário](../questionario/2026-11-14-widget-e-capsula.md). Abertura em código antes da validação da F15-02 no S25: [D-069](../DECISIONS.md).

**Estado:** IN_PROGRESS. Os dois protótipos existem no build dev e compilam. A comparação no S25 e a escolha do dono estão pendentes. Nada foi medido no aparelho ainda (`NOT_RUN`).

## O que existe

Os dois protótipos vivem só no source set `android/app/src/globalDev/`. Nada entra em `src/main`, no `global` nem no `globalEarly`.

| Peça | Caminho |
|---|---|
| Manifesto dev (permissões e entradas) | `android/app/src/globalDev/AndroidManifest.xml` |
| Medição (tag `F1507`) | `android/app/src/globalDev/kotlin/com/memexlab/memex/dev/CapsuleLog.kt` |
| A: bolha (launcher e postagem) | `.../dev/CapsuleBubble.kt` |
| A: host da bolha (reusa o motor e a rota do chat) | `.../dev/CapsuleBubbleHostActivity.kt` |
| B: launcher de permissão e início | `.../dev/CapsuleOverlay.kt` |
| B: serviço com a bolinha sobre outros apps | `.../dev/CapsuleOverlayService.kt` |

O host da bolha não é o `FloatingChatActivity` porque ele é `final` e fica em `src/main`. O host novo usa o mesmo `SharedFlutterEngine`, o mesmo channel `com.memexlab.memex/floating_chat` e a mesma rota `/floating-chat`. A diferença: o "Fechar" dele encerra a própria Activity (a bolha recolhe), e o "Abrir no app" abre a `MainActivity`.

## Prototype A — bolha oficial do Android

**Como começar no S25**
1. Instalar o APK `globalDev` debug (`app.segundamente.dev`).
2. Abrir o app de lançamento **"Cápsula: bolha"** (gaveta de apps).
3. Deve aparecer uma bolha, já expandida, com a conversa da Segunda Mente. Se a bolha não expandir sozinha, tocar no ícone dela.

**Configurações necessárias**
- Notificações do app ligadas (Configurações > Apps > Segunda Mente Dev > Notificações).
- Bolhas liberadas: no One UI, Configurações > Notificações > Notificações flutuantes (ou "Bolhas") e liberar o app. O caminho exato no S25 ainda não foi conferido; registrar o caminho real na validação.
- Se o aparelho não mostrar bolhas, o lançador abre a tela de notificações do app; ligar lá.

**Como parar**
- Arrastar a bolha até "Fechar" (X) na base, ou tocar em "Fechar" dentro da conversa.
- Ou desligar o canal "Cápsula de teste (bolha)" em Configurações > Notificações do app.

**Limites conhecidos**
- Abrir a bolha encerra a `MainActivity` aberta (mesma regra "um host por vez" do F15-02). Se o app estiver aberto, ele fecha.
- Se o app for aberto depois com a bolha ativa, a bolha continua viva, porque a `MainActivity` não conhece o host novo (ela está em `src/main`). Medir e registrar esse caso.

## Prototype B — sobreposição própria

**Como começar no S25**
1. Abrir o app de lançamento **"Cápsula: sobreposição"**. Na primeira vez, abre a tela "Aparecer sobre outros apps".
2. Ligar "Aparecer sobre outros apps" para "Segunda Mente Dev" e voltar.
3. Abrir "Cápsula: sobreposição" de novo. A bolinha **SM** aparece sobre os outros apps, e uma notificação fixa "Cápsula de sobreposição ativa" aparece com a ação **Parar**.

**Como usar**
- Tocar na bolinha: abre o chat flutuante (modo digitar).
- Arrastar: move a bolinha.
- Segurar por 0,6 s, ou arrastar até a parte de baixo da tela (abaixo de 80% da altura): esconde a bolinha e para o serviço.

**Como parar**
- Ação **Parar** da notificação fixa, ou segurar/arrastar a bolinha até a base.

**Configurações necessárias**
- "Aparecer sobre outros apps" para "Segunda Mente Dev".
- Notificações ligadas (a notificação fixa é a única que avisa que o serviço está vivo).
- Economia de bateria: para o teste de sobrevivência, o app não pode estar em "Otimizado" nem "Restrito" em Configurações > Apps > Segunda Mente Dev > Bateria. Medir nas duas condições e registrar qual foi.

## Critérios de comparação (D11)

Tabela para preencher no S25. Não preencher antes de medir.

| Critério | Bolha oficial (A) | Sobreposição própria (B) |
|---|---|---|
| Abre de qualquer app (tocar no lançador a partir de outro app) | | |
| Minimiza mantendo a conversa (recolher e reabrir sem perder a conversa) | | |
| Sobrevive à economia de bateria (ainda ativa após 15 min com a economia ligada) | | |
| Custo de bateria (`dumpsys batterystats`, 30 min de teste) | | |
| Facilidade de esconder (quantos toques ou gestos para sair da tela) | | |

Regra de decisão: a forma escolhida vai para `docs/DECISIONS.md` com a tabela preenchida. Se um dos dois não atende "abre de qualquer app" ou "sobrevive à economia de bateria", ele sai da disputa.

## Como medir (adb)

Os eventos de medição saem com a tag `F1507` e com o instante em milissegundos (epoch) na mensagem:

```bash
adb logcat -c
adb logcat -v time -s F1507
```

Eventos registrados:
- A: `bubble channel ready`, `bubble posted`, `bubble host created`, `bubble expanded` (onResume do host), `bubble collapsed` (onPause), `bubble host destroyed`.
- B: `overlay permission missing`, `overlay service started`, `overlay shown`, `overlay tapped: opening chat`, `overlay hidden: long press`, `overlay hidden: dragged to bottom`, `overlay service stopped`.

**Abre de qualquer app.** Abrir outro app (ex.: Configurações), ir ao lançador e tocar no ícone. Anotar o horário do toque e o horário do log `bubble posted` ou `overlay shown`. A diferença é a latência do protótipo. O `adb shell am start -n app.segundamente.dev/com.memexlab.memex.dev.CapsuleBubbleLauncherActivity` (ou `...CapsuleOverlayLauncherActivity`) serve só para repetir o teste; a medida oficial é o toque manual.

**Minimiza mantendo a conversa.** Enviar uma mensagem e recolher a bolha (A); reabrir tocando na bolha e ver se a conversa continua. Conferir no log que não houve `bubble host destroyed` entre os dois eventos. No B a folha fecha ao tocar fora e não há como recolher; ao reabrir pela bolinha, a conversa é nova (D2, conversa nova a cada abertura). Registrar isso como resultado: é uma diferença real entre os dois protótipos.

**Sobrevive à economia de bateria.** Ativar a economia de bateria do S25 pelo painel rápido (ou `adb shell cmd power set-mode 1`, se o aparelho aceitar). Esperar 15 min com a tela apagada. Conferir se o processo continua: `adb shell pidof app.segundamente.dev` e, para B, `adb shell dumpsys activity services app.segundamente.dev | grep -i CapsuleOverlay`. Para A, conferir se a bolha ainda aparece ao tocar na notificação. Registrar o horário em que o serviço ou o host morreu, se morreu.

**Custo de bateria.** Antes do teste: `adb shell dumpsys batterystats --reset`. Depois de 30 min de uso normal (não de bateria cheia): `adb shell dumpsys batterystats --charged app.segundamente.dev`. Comparar o consumo do app com e sem o protótipo ativo (30 min de controle sem bolha ou bolinha). Registrar o valor em mAh com o nível inicial da bateria.

**Facilidade de esconder.** Contar os toques ou gestos até a tela ficar limpa (A: arrastar para "Fechar" ou fechar a conversa; B: segurar 0,6 s ou arrastar para a base). Anotar o número e a sensação, e registrar se algo ficou visível depois.

## Verificação feita nesta subfase

- `flutter pub get --enforce-lockfile`: ver a seção de evidência no STATE.md.
- `flutter build apk --flavor globalDev --debug --no-pub`: ver STATE.md.
- Release: confirmar que `android/app/src/main/AndroidManifest.xml` não mudou e que o manifesto mesclado do flavor `global` não tem as permissões nem as entradas dos protótipos (ver STATE.md).

## Riscos

- A bolha depende de a Samsung deixar as bolhas ligadas para o app; sem isso, o protótipo mostra só uma notificação comum.
- A sobreposição exige "Aparecer sobre outros apps", que é permissão sensível. Ela só existe no build dev.
- O host da bolha não é destruído quando a `MainActivity` abre (src/main não conhece o host novo). Resolver na escolha final, se a bolha ficar.
- `onResume`/`onPause` aproximam "expandida"/"recolhida"; a tela pode apagar e disparar `onPause` sem a bolha ter sido recolhida. Confirmar visualmente.
- `specialUse` no Android 14+ exige a propriedade no manifesto (incluída). Sem ela, o serviço não inicia no S25.
- Nenhum teste automatizado: não há setup de teste Android no projeto e o protótipo é descartável. A validação é o S25.

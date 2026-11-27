> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md). Referência do protocolo já implementado na placa: `esp32-s3-amoled-2-16` (`firmware/main/ble_bridge.c` e `docs/roadmap/assistente-de-voz/V7-PONTE-CELULAR.md`).

## F16 — Ponte Bluetooth LE com a placa ESP32-S3 AMOLED

**Estado:** CANCELLED (D-082, 2026-11-27). A placa removeu o Bluetooth e fala MQTT; o que serve daqui (listener de notificações, filtro de apps, modelo de tarefas) segue na [F17 — Placa por MQTT](F17-placa-por-mqtt.md), que também remove o código BLE do app. Antes: IN_PROGRESS — F16-01 a F16-06 com código (Kotlin nativo `Esp32BleManager`, `Esp32NotificationListenerService`, `Esp32BleChannelHandler`; Dart `Esp32BleBridgeService`, `Esp32BoardViewModel`, `Esp32BoardPage` em Configurações → Placa ESP32-S3) e testes automatizados de unidade/widget. Validação no S25 com a placa física: `NOT_RUN`. Observação: o cliente BLE é nativo (MethodChannel `com.memexlab.memex/esp32_ble`), sem `flutter_blue_plus`, para não adicionar dependência.

**Objetivo:** com o celular por perto, o Segunda Mente conversa diretamente com a placa de mesa `SegundaMente-Placa` por Bluetooth LE (GATT) para sincronizar tarefas nos dois sentidos sem duplicar, encaminhar notificações escolhidas do Android para a tela da placa e configurar a placa (Wi-Fi, cidade e personagem) pelo app sem recompilar.

**Limites:**
- Comunicação local via BLE GATT (`Service 6e400001-b5a3-f393-e0a9-e50e24dcca9e`, `RX 6e400002-...` escrita até 1024 bytes, `TX 6e400003-...` leitura/notificação com JSON terminado em `\n`).
- Pareamento obrigatório por código de 6 dígitos exibido na placa, com chave de 32 bytes hex salva no `flutter_secure_storage` (nunca em log) e autenticação por `HMAC-SHA256(key, type)` em todas as mensagens após o pareamento.
- Nenhum token do ChatGPT ou segredo do celular trafega para a placa.
- Leitura de notificações do Android é opcional, exige consentimento explícito e aplica filtro por app antes de enviar.
- Com o celular longe ou o app fechado, a placa continua funcionando sozinha; tarefas pendentes sincronizam ao reconectar.

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F16-01 | Cliente BLE GATT em Flutter (ex.: `flutter_blue_plus`) com permissões Android 12+ (`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`), descoberta de `SegundaMente-Placa` pelo UUID `6e400001-b5a3-f393-e0a9-e50e24dcca9e`, escrita em `RX` (`6e400002`) e leitura/notify em `TX` (`6e400003`) | P0 | F11 | READY | App encontra, conecta, lê status `{"ok":true,"paired":bool}` e recebe respostas notify no S25 |
| F16-02 | Fluxo de pareamento por código de 6 dígitos (`pair_start` → exibe código na placa → `pair_confirm` com `code` → recebe e salva `key` de 32 bytes hex no `flutter_secure_storage`), assinatura `HMAC-SHA256(key, type)` nos comandos e ação de revogar (`revoke`) | P0 | F16-01 | READY | Pareamento bem-sucedido no S25; código errado rejeitado; após `revoke`, placa recusa comandos com `nao_autorizado` |
| F16-03 | Sincronização bidirecional de tarefas (`type: "task_sync"` com `envelopes` no formato `SyncEnvelope` v1: `entity_id`, `payload: {text, done, due_ts}`), deduplicação por `entity_id`, fila offline para quando a placa estiver longe e integração com a outbox da F12 (Lumen) | P0 | F16-02, F11 | READY | Tarefa anotada na placa aparece 1x no app; tarefa criada/concluída no app aparece 1x na placa; replay não duplica |
| F16-04 | Encaminhamento de notificações do Android (`NotificationListenerService` opcional + filtro configurável por app) enviando `type: "notif"` (`app` em `whatsapp`, `call`/`ligacao`, `msg`, `alert`, `calendar`; `title` ≤ 63 bytes; `body` ≤ 159 bytes; `silent`) | P1 | F16-02 | READY | Mensagem de WhatsApp aparece na tela da placa em até 5 s, 3 vezes seguidas; apps fora do filtro não são enviados |
| F16-05 | Tela "Configurar placa" no app enviando `type: "config"` (`ssid`, `pass`, `city`, `char_idx` `0..3` para `Mochi`/`Sprout`/`Peach`/`Nimbus`) para trocar Wi-Fi, cidade do clima e personagem sem recompilar | P1 | F16-02 | READY | Wi-Fi, cidade e personagem da placa alterados pelo app e mantidos após reinício da placa |
| F16-06 | Reconexão resiliente, controle de consumo em segundo plano e validação de coexistência BLE + Wi-Fi na placa (sem `ESP_ERR_NO_MEM` durante perguntas à IA) | P1 | F16-03, F16-04, F16-05 | READY | Placa fora de alcance não trava o app; ao voltar, tarefas pendentes sobem; log da placa sem `ESP_ERR_NO_MEM` |

**Portão F16:** validado no Galaxy S25 Ultra com a placa física `esp32-s3-amoled-2-16`: tarefas nos dois sentidos sem duplicar, WhatsApp chegando em ≤ 5 s (3x seguidas), Wi-Fi/cidade/personagem alterados pelo app, revogação efetiva e zero segredos em logs.

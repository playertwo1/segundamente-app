> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md). Decisão: D-082. Contrato (fonte da verdade): `esp32-s3-amoled-2-16/docs/roadmap/mqtt/PROTOCOLO.md`. Lado da placa: `firmware/main/mqtt_link.c` e `crypto_box.c`. Etapa irmã no PC: L10 do `coucou` (Lumen).

## F17 — Placa ESP32-S3 AMOLED por MQTT

**Estado:** IN_PROGRESS. F17-01 a F17-06 DONE em 2026-11-27 (código e testes; evidências em STATE.md); F17-07 a F17-09 pendentes. A placa já fala MQTT (gravada e com autoteste em 2026-11-27); o broker real depende do dono (conta no HiveMQ Cloud ou EMQX). Substitui a F16 (BLE), que está `CANCELLED` pela D-082.

**Objetivo:** o Segunda Mente sincroniza tarefas com a placa e o Lumen, manda notificações escolhidas do Android para a tela da placa e avisa quando um agente do PC (Claude Code, Codex) precisa de você, deixando responder pelo celular — tudo pelo broker MQTT, em qualquer rede. O código BLE sai do app.

**Limites:**
- **Conexão:** MQTT 3.1.1 com TLS (`mqtts://host:8883`). client_id `celular-<sala>`; LWT `sm/<sala>/presenca/celular` = `0`, retido; `1` retido ao conectar.
- **Cifra:** AES-256-GCM em tudo, menos na presença.
  - Chave = SHA-256 do texto da chave da sala; AAD = bytes UTF-8 de `from` (`celular`); IV aleatório de 12 bytes.
  - Envelope `{"v":1,"from","iv","ct","tag"}` em base64 padrão. Ignorar o próprio `from`; rejeitar envelope sem `from`.
- **Segredos:** URI, usuário, senha, sala e chave só no `SecretStorage` (`flutter_secure_storage`), nunca em log, `SharedPreferences` ou backup.
- **Notificações:** a leitura continua opcional, com consentimento explícito e filtro por app antes de enviar.
- **Segundo plano:** o Android corta a rede de apps em segundo plano. Sincronizar tarefas ao abrir o app e quando chegar notificação a encaminhar basta; não manter conexão permanente nem serviço em primeiro plano só para isso.

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F17-01 | Escolher e adicionar o cliente MQTT (`mqtt_client`, Dart puro com TLS) e o leitor de QR (`mobile_scanner` ou o que o app já usar). AES-GCM com `pointycastle` (já no app). Registrar a escolha em DECISIONS se trouxer dependência nova | P0 | D-082 | DONE | `flutter pub get` e build verdes; dependências listadas |
| F17-02 | `Esp32MqttService`: lê o QR da placa (`{"t":"sm-mqtt","v":1,"uri","u","p","sala","k"}`), valida, guarda no `SecretStorage`, conecta com presença e LWT, reconecta com espera crescente, e expõe estado (conectado, placa online pela `presenca/placa`) | P0 | F17-01 | DONE | Testes de unidade com transporte falso: QR inválido, versão errada, cifra de ida e volta, chave errada e `from` adulterado rejeitados |
| F17-03 | Tarefas: transporte MQTT do `SyncEnvelope` v1 do `TodoSyncService`. Um tópico retido por tarefa (`sm/<sala>/tarefas/<entity_id>`), `updated_at` no topo (muda só com o conteúdo), `origin_role` `mobile`; payload vazio retido quando houver `deletedAt`; assina `tarefas/+` e aplica a regra do maior `updated_at` (empate mantém o local) por `applyRemoteMutationBatch`; ao reconectar, apaga a tarefa já publicada ou recebida sem retida, **com a trava** do protocolo (nada se nenhuma retida chegou, ou se sumiria mais da metade e mais de 3) | P0 | F17-02, F11 | DONE | Testes: tarefa nova publicada, remota aplicada, conflito velho/empate/novo, apagar nos dois sentidos e limpeza com e sem a trava |
| F17-04 | Notificações: manter `Esp32NotificationListenerService.kt` e o filtro de apps; trocar o destino do canal BLE pela publicação cifrada em `sm/<sala>/notif` (`{"app","title","body","silent"}`, título ≤ 63 bytes, corpo ≤ 159 bytes); fila curta de 5 min se estiver sem rede, descartando o que passar disso | P1 | F17-02 | DONE | Teste do serviço com transporte falso: app filtrado não sai, UTF-8 truncado sem quebrar caractere, fila esvazia ao reconectar |
| F17-05 | Tela "Placa ESP32-S3" em Configurações: ler QR (ou colar o código), estado (conectado, placa online), apps permitidos e "Esquecer placa". Saem Wi-Fi, senha, cidade e personagem (D-082) | P1 | F17-02 | DONE | Widget test da tela; textos em pt-BR e en |
| F17-06 | Remover o BLE: `esp32_ble_bridge_service.dart`, `Esp32BleManager.kt`, `Esp32BleChannelHandler.kt` e o registro em `ChannelRegistrar.kt`, as permissões `BLUETOOTH*` do manifest, `kEsp32CharacterNames`, a chave segura `esp32_ble_key_v1` e as preferências `esp32_pending_sync_tasks` (limpas na primeira abertura). Trocar os 10 testes de BLE pelos da F17 | P0 | F17-03, F17-04, F17-05 | DONE | `flutter test` e `flutter analyze` verdes; `aapt dump permissions` sem `BLUETOOTH`; nenhuma referência a `esp32_ble` no código |
| F17-07 | Ponta a ponta no S25 com a placa e o Lumen (broker real do dono) | P0 | F17-06, L10 do Lumen | READY | Notificação de WhatsApp na placa em ≤ 3 s, 3x seguidas, com celular e placa em redes diferentes; tarefa concluída no app aparece concluída na placa e no Lumen; celular desligado durante 3 alterações recebe tudo ao voltar, sem duplicar; broker (MQTTX) sem texto claro nem segredo |
| F17-08 | Alerta de agente no celular (D-083): assinar `sm/<sala>/pc/agentes/pedido` e mostrar notificação "Claude/Codex precisa de você em <projeto>"; com `can_approve`, ações **Aprovar** (opção recomendada pelo agente) e **Negar**; sempre **Deixar no PC**. Publicar a decisão cifrada em `pc/agentes/decisao` (`{"request_id","view_sha256","verdict","ts"}`). Pedido vencido ou já respondido pela placa some da notificação. Opcional na tela da placa: lista curta de agentes ativos de `pc/agentes/status` | P1 | F17-02, L11.5 do Lumen | READY | Teste com transporte falso: pedido mostra notificação, aprovação publica a decisão certa, vencido não mostra ação, pedido limpo some; no S25, pergunta do Claude aprovada pelo celular chega ao terminal |
| F17-09 | Decidir como o alerta chega com o app fechado (o Android corta a rede em segundo plano): (a) só com o app aberto, (b) serviço em primeiro plano enquanto houver pedido, ou (c) push (FCM ou ntfy) disparado pelo Lumen sem conteúdo sensível. Registrar em DECISIONS e implementar a escolhida | P1 | F17-08 | READY | Decisão registrada; com a opção escolhida, alerta chega com o app fechado em ≤ 10 s no S25 (ou limite documentado) |

**Portão F17:** validado no Galaxy S25 Ultra com a placa física e o Lumen.
- Tarefas convergem nos três aparelhos em ≤ 5 s, sem duplicar nem ressuscitar apagadas.
- WhatsApp chega à placa em ≤ 3 s (3x).
- A revogação na placa faz o app pedir o QR novo.
- APK sem permissões de Bluetooth e zero segredos em logs.
- Alerta de agente (F17-08/09): pedido do Claude Code aprovado pelo celular chega ao terminal, e nada é aprovado sem toque.

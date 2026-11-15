# Spec — F12-03: Pareamento por QR, guarda segura e revogação com o Lumen

- **Data:** 2026-11-14
- **Branch prevista:** `feat/f1203-pareamento-lumen`
- **Passo na `PONTE.md`:** Passo 6 (`F12-03`)
- **Referências canônicas:**
  - `docs/lumen/PONTE.md` (Passo 6)
  - `docs/lumen/CONTRATO-SYNC.md` (seções 2, 3 e 4)
  - `docs/RELAY_LINK.md` (§2 no repositório do Lumen)

## Objetivo e Escopo

Permitir que a Segunda Mente (Android) leia o QR de pareamento gerado pelo Lumen (`L6.2`), valide e derive as chaves criptográficas do relay, armazene todas as credenciais com segurança no cofre do aparelho e suporte desvincular/revogar a sala no Worker antes de esquecer as credenciais locais.

### Entra nesta etapa (`F12-03`)
1. Captura do link `coucou://pair?...` por **câmera** (`mobile_scanner`) e **colagem manual** (fallback offline/sem câmera e testes).
2. Parsing e validação estrita de todos os parâmetros do link de pareamento.
3. Derivação HKDF-SHA-256 em Dart puro (`LumenRelayCrypto` usando `package:crypto/crypto.dart`) compatível byte a byte com os vetores do Lumen.
4. Persistência segura exclusiva via `SecretStorage` (`flutter_secure_storage`) atrás de uma interface injetável (`LumenSecretStore`), incluindo `device_id` UUID v4 estável por instalação.
5. Fluxo de revogação remota (`POST /v1/mailbox/<room>/revoke`) com timeout de 5 s e limpeza local resiliente a falhas de rede.
6. Tela `LumenPairingPage` (AMOLED v3 / `AppColors`) com `LumenPairingViewModel`, integrada ao `MemexRouter`, `SettingsPage`, `SettingsRegistry` e `app_pt.arb` / `app_en.arb`.

### Fica fora de escopo (etapa futura)
- Envio, polling, outbox ou cifragem/decifragem de mensagens de sync (`F12-04` / Passo 8).
- Conexão direta LAN TLS (a URL `host`/`port`/`fp`/`token` é validada e preservada apenas para uso futuro).
- Alterações no Worker Cloudflare ou no Lumen desktop.

## Formato do QR e Validação (`LumenPairing`)

O link recebido (com tamanho total `< 2048` caracteres) deve seguir o formato:

```text
coucou://pair?v=1&host=192.0.2.10&port=38443&fp=<64hex>&token=<token>&name=Desktop-Exemplo&relay=wss%3A%2F%2Frelay.example.workers.dev&room=<22>&key=<43>&access=<43>
```

Regras estritas de parsing em `LumenPairing.parseUri(String raw)`:
- **Esquema/host/versão:** `uri.scheme == 'coucou'`, `uri.host == 'pair'`, `v == '1'`.
- **Base64url estrito (sem padding):** alfabeto `[A-Za-z0-9_-]`, sem `=`, `+`, `/` nem espaços, rejeitando bits de preenchimento não zerados no último caractere:
  - `room`: 22 caracteres (decodifica para exatamente 16 bytes).
  - `key` (`K`): 43 caracteres (decodifica para exatamente 32 bytes).
  - `access`: 43 caracteres (decodifica para exatamente 32 bytes).
- **Relay (`relay`):**
  - Obrigatório aceitar `wss://host[:port]` (com `/` final opcional; sem path, query, fragmento, `userinfo`, espaços ou `..`).
  - Aceitar `ws://host[:port]` **somente** quando `host` for loopback (`localhost`, `127.0.0.1` ou `[::1]`).
  - Porta opcional (`1..=65535`); host ASCII válido (`<= 253` chars).
  - Expor `httpBaseUrl`: converte `wss://` -> `https://` e `ws://` -> `http://`, omitindo portas padrão (`443` / `80`) para chamadas REST de revogação.
- **Campos LAN (validados e preservados para LAN TLS futura):**
  - `host`: não vazio após `trim()`.
  - `port`: inteiro válido em `1..=65535`.
  - `fp`: exatamente 64 dígitos hexadecimais (`[0-9a-fA-F]{64}`), normalizado em minúsculas.
  - `token`: 16 a 128 caracteres em `[A-Za-z0-9_-]`.
  - `name`: nome legível não vazio após decode/trim.
- **Redação:** `LumenPairing.toString()` nunca imprime `key`, `access` nem `token` (substituídos por `[REDACTED]`).

## Criptografia (`LumenRelayCrypto`)

Implementação em Dart puro sobre `Hmac` e `sha256` (`package:crypto/crypto.dart`, já presente no `pubspec.yaml`), seguindo RFC 5869 HKDF-SHA-256 com `salt = []` (expandindo para `okm` de 32 bytes com prefixo de contexto `"coucou-relay/v1"`):

| Chave derivada | `info` | Tamanho | Uso |
|---|---|---|---|
| `K_join` | `"coucou-relay/v1 join"` | 32 bytes | `joinProof` em base64url sem padding (43 chars) para header `X-Lumen-Join` |
| `K_mailbox` | `"coucou-relay/v1 mailbox"` | 32 bytes | Derivada e testada nesta etapa; reservada para a cifra `coucou-mailbox/v1` no Passo 8 |
| `K_auth` | `"coucou-relay/v1 auth"` | 32 bytes | Derivada e testada nesta etapa; reservada para uso futuro do canal autenticado |

A implementação deve validar RFC 5869 (incluindo salt não vazio no helper genérico `hkdfSha256`) e as derivações do contrato usando uma cópia sintética dos vetores oficiais (`test/fixtures/lumen_relay_test_vectors.json`, espelhando `android/relay/test-vectors-mailbox.json` do Lumen).

## Guarda Segura (`LumenSecretStore`) e `device_id`

- O acesso ao `SecretStorage` (`flutter_secure_storage`) é encapsulado por uma interface `LumenSecretStore` (`read`, `write`, `delete`) para permitir fakes in-memory em testes unitários e de widget.
- **Chaves armazenadas exclusivamente em `SecretStorage`:**
  - Registro serializado (JSON) do pareamento ativo (`lumen_pairing_v1`) contendo todos os campos validados de `LumenPairing` e timestamp de pareamento (`pairedAtIso`).
  - Identificador estável da instalação (`lumen_device_id`), gerado uma única vez via `const Uuid().v4()` se ainda não existir.
- **Invariantes de segurança e ciclo de vida:**
  - **Nada em `SharedPreferences`:** evita que segredos de pareamento ou `device_id` vazem ou sejam clonados no backup `.memex` entre dispositivos.
  - **Estabilidade do `device_id`:** desvincular ou re-parear apaga apenas o registro de pareamento (`lumen_pairing_v1`), preservando `lumen_device_id` (somente `UserStorage.clearAllData()`, na exclusão de conta, chama `SecretStorage.deleteAll()`).
  - **Zero vazamento em logs:** nenhuma mensagem de erro, exceção ou `debugPrint` pode incluir URI completa com `key`/`access`/`token`, `joinProof` ou segredos brutos.

## Revogação e Re-pareamento (`LumenPairingService`)

1. **Desvincular (`unlink()`):**
   - Se houver pareamento ativo, derivar `joinProof` a partir de `key` via `LumenRelayCrypto`.
   - Enviar `POST <httpBaseUrl>/v1/mailbox/<room>/revoke` com timeout de **5 segundos** e headers:
     - `Authorization: Bearer <access>`
     - `X-Lumen-Join: <joinProof>`
   - Respostas HTTP `200` ou `410` (sala já expirada/revogada) confirmam revogação remota.
   - Erro de rede, timeout ou outro status HTTP **não** impedem apagar as credenciais locais (`lumen_pairing_v1`); o método informa ao caller se a revogação remota foi confirmada ou se apenas os dados locais foram limpos.
2. **Troca de sala ao escanear/colar novo QR (`pairFromUri(String raw)`):**
   - Validar o novo URI **antes** de alterar qualquer estado existente (QR inválido não apaga o pareamento atual).
   - Se já existir um pareamento salvo para **outro `room`** (`current.room != next.room`), tentar revogar a sala antiga (`POST .../revoke` com timeout de 5 s, best-effort sem bloquear o novo vínculo em caso de erro de rede) antes de gravar o novo pareamento.
   - Garantir que `device_id` exista no `LumenSecretStore` antes de concluir o pareamento.

## Interface e Navegação (`F12-03`)

- **Camadas MVVM:**
  - `MemexRouter` expõe métodos assíncronos via `runResult` / `runResultVoid`: `getLumenPairingState()`, `pairWithLumen(String rawUri)`, `unlinkLumen()` (ou `LumenPairingStatus` contendo `pairing` opcional e `deviceId` resumido).
  - `LumenPairingViewModel` (`ChangeNotifier`) consome `MemexRouter`, controla `isLoading`, `isRevoking`, mensagens de erro localizadas/mapeadas e status da última operação.
  - `LumenPairingPage` segue a paleta AMOLED v3 (`AppColors.background`, `AppColors.surface`, `AppColors.divider`, `AppColors.primary`, `AppColors.textPrimary`/`Secondary`, `AppColors.success`, `AppColors.danger`).
- **Estados visíveis na `LumenPairingPage`:**
  - **Não pareado:** aviso de estado `"Não pareado"` (via `app_pt.arb`/`app_en.arb`), breve explicação e ações **Escanear QR** e **Colar link**.
  - **Pareado:** estado `"Pareado com <name>"`, host do relay (ex.: `relay.example.workers.dev`), prefixo não sensível do `device_id` (ex.: primeiros 8 chars, sem nenhum segredo/chave), além das ações **Parear de novo** (permite ler/colar novo QR revogando o anterior se mudar de sala) e **Desvincular** (com diálogo de confirmação).
  - **Leitor QR + Fallback:** modal/tela embutida com `MobileScanner` (e callback/builder injetável para testes de widget) e diálogo/bottom sheet para **Colar link**, validando entrada antes de fechar ou exibindo erro claro sem perder o estado atual.
- **Descoberta em Configurações:**
  - Entrada dedicada em `SettingsPage` posicionada **após `showInsightTextTitle`** (junto a `Backup & Restore`) para não quebrar a asserção inicial de viewport em `test/ui/settings/widgets/settings_page_test.dart`.
  - Registro correspondente em `SettingsRegistry` (`_settingsPageItems`) com `UserStorage.l10n` e `parentPathGetter` apontando para Configurações.
  - Strings adicionadas em `lib/l10n/app_pt.arb` e `lib/l10n/app_en.arb` e acessadas via `UserStorage.l10n`.

## Critérios de Teste e Aceite

1. **Testes unitários de modelo e validação (`test/domain/models/lumen_pairing_test.dart`):**
   - URI válido completo (`wss://` e loopback `ws://`), extração de `httpBaseUrl` (omitindo `:443`/`:80`, mantendo portas customizadas).
   - Rejeição de esquema/host/versão inválidos, tamanho `>= 2048`, `ws://` não-loopback, `relay` com path/query/userinfo, `room`/`key`/`access` com tamanho errado, padding `=` ou bits finais inválidos, `port` fora de `1..=65535`, `fp` != 64 hex, `token` inválido, `name`/`host` vazios e `toString()` redigido.
2. **Testes unitários de criptografia (`test/data/services/lumen_relay_crypto_test.dart`):**
   - Verificação exata contra `test/fixtures/lumen_relay_test_vectors.json` (`rfc5869_a1`, `K_join` / `joinProof`, `K_mailbox`, `K_auth`).
3. **Testes unitários do serviço (`test/data/services/lumen_pairing_service_test.dart`):**
   - `LumenSecretStore` in-memory + `http.Client` mockado (`package:http/testing.dart` `MockClient`).
   - Geração única e preservação do `device_id` entre pareamentos e desvínculos; ausência de escrita em `SharedPreferences`.
   - Revogação enviando `POST <httpBaseUrl>/v1/mailbox/<room>/revoke` com `Authorization: Bearer <access>` e `X-Lumen-Join: <joinProof>` e timeout; `200`/`410` confirmando revogação; erro de rede/500 ainda limpando estado local.
   - Re-pareamento com sala diferente revogando a sala antiga antes de persistir a nova; QR inválido mantendo a sala antiga intacta.
4. **Testes de widget e localização (`test/ui/lumen/lumen_pairing_page_test.dart` + suítes existentes):**
   - Renderização dos estados `Não pareado` e `Pareado com <name>` (exibindo host do relay e nenhum segredo na árvore de widgets).
   - Fluxo de colar link válido/inválido, scan mockado via callback injetável e confirmação de desvincular.
   - `flutter analyze`, `python3 scripts/check_arb_key_parity.py`, `arb_key_parity_test.dart`, `hardcoded_ui_strings_test.dart` e `settings_page_test.dart` passando após `flutter gen-l10n`.

# Plano de Implementação — F12-03: Pareamento por QR, guarda segura e revogação com o Lumen

- **Spec de referência:** `docs/superpowers/specs/2026-11-14-f1203-pareamento-qr-revogacao.md`
- **Passo na `PONTE.md`:** Passo 6 (`F12-03`)
- **Branch prevista:** `feat/f1203-pareamento-lumen`

## Pré-condição (antes de editar qualquer código)

1. Confirmar aprovação explícita desta spec e deste plano pelo dono.
2. Verificar `main` limpa e criar a branch de trabalho:
   ```powershell
   git -C C:\Users\notefael\projetos\segundamente status --short --branch
   git -C C:\Users\notefael\projetos\segundamente checkout -b feat/f1203-pareamento-lumen
   ```
3. **Regra do repositório:** testes unitários e de widget novos entram no mesmo commit da implementação; dados sempre sintéticos; nenhuma credencial ou `device_id` em `SharedPreferences`.

## Passo 1 — Dependência (`pubspec.yaml`) e fixture de vetores

- **Arquivos:** `pubspec.yaml`, `test/fixtures/lumen_relay_test_vectors.json`
- **O que fazer:**
  - Adicionar `mobile_scanner` em `pubspec.yaml` (respeitando `sdk: ">=3.6.0 <4.0.0"`, `minSdk = 26` e permissões `CAMERA`/`INTERNET` já presentes no `AndroidManifest.xml`). Note-se que `crypto`, `uuid`, `http` e `flutter_secure_storage` já estão instalados.
  - Rodar `C:\Users\notefael\tools\flutter\bin\flutter pub get`.
  - Criar `test/fixtures/lumen_relay_test_vectors.json` com os vetores sintéticos do contrato (`rfc5869_a1`, `inputs.key`, `inputs.room`, `derived.kAuth`, `derived.kJoin`, `kMailbox` de `android/relay/test-vectors-mailbox.json` do Lumen).

## Passo 2 — Modelo de domínio e validação (`domain`)

- **Arquivos:**
  - `lib/domain/models/lumen_pairing.dart`
  - `test/domain/models/lumen_pairing_test.dart`
- **O que fazer:**
  - Criar `LumenPairing` (imutável, com `toJson`/`fromJson` para o cofre seguro e `toString()` redigindo `key`, `access` e `token`) + classe de erro de validação dedicada (`LumenPairingParseException`).
  - Implementar `LumenPairing.parseUri(String raw)` validando: comprimento `< 2048`, `coucou://pair`, `v == '1'`, `relay` (`wss://host[:port]` ou `ws://` loopback, sem path/query/userinfo) e `httpBaseUrl`, `room` (22 chars base64url / 16 B), `key` (43 chars base64url / 32 B), `access` (43 chars base64url / 32 B), `host`, `port` (`1..=65535`), `fp` (64 hex normalizado em lowercase), `token` (16..=128 `[A-Za-z0-9_-]`) e `name`.
  - Implementar utilitário de base64url estrito sem padding (alfabeto URL-safe e checagem de bits finais zerados).
  - Escrever `test/domain/models/lumen_pairing_test.dart` cobrindo casos válidos, conversão `httpBaseUrl`, todas as rejeições de campos/formato e redação em `toString()`.

## Passo 3 — Derivação criptográfica (`data/services` — HKDF)

- **Arquivos:**
  - `lib/data/services/lumen_relay_crypto.dart`
  - `test/data/services/lumen_relay_crypto_test.dart`
- **O que fazer:**
  - Implementar `LumenRelayCrypto` em Dart puro usando `Hmac` e `sha256` (`package:crypto/crypto.dart`):
    - `hkdfSha256({required Uint8List ikm, required Uint8List salt, required Uint8List info, required int length})` (RFC 5869 Extract + Expand).
    - `deriveKeys(Uint8List masterKey)` retornando `kJoin`, `joinProof` (43 chars base64url sem padding), `kMailbox` (32 B) e `kAuth` (32 B) com `salt = []` e `info` `"coucou-relay/v1 join"`, `"coucou-relay/v1 mailbox"`, `"coucou-relay/v1 auth"`.
  - Escrever `test/data/services/lumen_relay_crypto_test.dart` carregando `test/fixtures/lumen_relay_test_vectors.json` e validando `rfc5869_a1`, `kJoin`, `joinProof`, `kMailbox` e `kAuth` byte a byte.

## Passo 4 — Guarda segura e serviço de pareamento/revogação (`data/services`)

- **Arquivos:**
  - `lib/data/services/lumen_pairing_service.dart`
  - `test/data/services/lumen_pairing_service_test.dart`
- **O que fazer:**
  - Definir a abstração `LumenSecretStore` (`read`, `write`, `delete`) e a implementação padrão `SecureLumenSecretStore` delegando a `SecretStorage` (`lib/utils/secret_storage.dart`).
  - Implementar `LumenPairingService({LumenSecretStore? secretStore, http.Client? httpClient, String Function()? deviceIdGenerator, Duration revokeTimeout = const Duration(seconds: 5)})`:
    - `loadStatus()` -> retorna `LumenPairingStatus(pairing: LumenPairing?, deviceId: String?)` (cria ou preserva `lumen_device_id` via `const Uuid().v4()` no pareamento).
    - `pairFromUri(String raw)` -> valida antes de qualquer escrita; se já existir pareamento ativo com `room != next.room`, tenta revogar a sala antiga no relay (timeout 5 s, best-effort); garante `lumen_device_id` persistido e salva `lumen_pairing_v1` em `LumenSecretStore`.
    - `unlink()` -> se houver pareamento ativo, envia `POST <httpBaseUrl>/v1/mailbox/<room>/revoke` com `Authorization: Bearer <access>`, `X-Lumen-Join: <joinProof>` e timeout de 5 s; `200`/`410` marcam `remoteRevoked: true`, erro de rede/timeout retorna `remoteRevoked: false` e **sempre** remove `lumen_pairing_v1`, mantendo `lumen_device_id`.
  - Escrever `test/data/services/lumen_pairing_service_test.dart` usando `LumenSecretStore` in-memory e `MockClient` (`package:http/testing.dart`) cobrindo: geração/persistência do `device_id`, revogação `200`/`410`/erro de rede/timeout, troca de sala revogando a antiga, e rejeição de QR inválido preservando o estado anterior.

## Passo 5 — Facade `MemexRouter` e verificação de DI (`data/repositories` e `config`)

- **Arquivos:**
  - `lib/data/repositories/memex_router.dart`
  - Verificação em `lib/config/dependencies.dart` (somente se necessário; manter apenas `Provider<MemexRouter>`)
  - Checagem de fakes `implements MemexRouter` (`test/helpers/duplex_voice_fakes.dart`, `test/ui/lazy_secondary_loads_test.dart`)
- **O que fazer:**
  - Instanciar/reter `LumenPairingService` como campo privado em `MemexRouter` (com suporte opcional a delegação/injeção se necessário, sem registrar singletons globais extras em `lib/config/dependencies.dart`).
  - Expor em `MemexRouter` métodos com `runResult` / `runResultVoid`: `getLumenPairingStatus()`, `pairWithLumen(String rawUri)`, `unlinkLumen()`.
  - Confirmar se `test/helpers/duplex_voice_fakes.dart` (`FakeChatRouter`) e `test/ui/lazy_secondary_loads_test.dart` (`_FakeRouter`) compilam sem erros com os novos métodos (possuindo `noSuchMethod` ou adicionando stubs caso algum falte).

## Passo 6 — Strings de localização (`l10n`)

- **Arquivos:**
  - `lib/l10n/app_pt.arb`
  - `lib/l10n/app_en.arb`
- **O que fazer:**
  - Adicionar chaves com prefixo consistente (ex.: `lumenPairingTitle`, `lumenPairingSubtitle`, `lumenPairingStatusUnpaired`, `lumenPairingStatusPaired`, `lumenPairingRelayLabel`, `lumenPairingDeviceIdLabel`, `lumenPairingScanQr`, `lumenPairingPasteLink`, `lumenPairingUnlink`, `lumenPairingRepair`, `lumenPairingPasteDialogTitle`, `lumenPairingPasteHint`, `lumenPairingConfirm`, `lumenPairingUnlinkConfirmTitle`, `lumenPairingUnlinkConfirmBody`, mensagens de sucesso/aviso local/erro de validação).
  - Rodar `C:\Users\notefael\tools\flutter\bin\flutter gen-l10n` e `python3 scripts/check_arb_key_parity.py`.

## Passo 7 — ViewModel e Tela (`ui/lumen`)

- **Arquivos:**
  - `lib/ui/lumen/view_models/lumen_pairing_viewmodel.dart`
  - `lib/ui/lumen/widgets/lumen_pairing_page.dart`
  - `test/ui/lumen/lumen_pairing_page_test.dart`
- **O que fazer:**
  - `LumenPairingViewModel extends ChangeNotifier`: recebe `required MemexRouter router`, carrega `LumenPairingStatus`, expõe `pairFromRawLink(String)` e `unlink()`, trata `Result` (`Ok`/`Error`) e mapeia erros sem expor segredos.
  - `LumenPairingPage`: usa `AppColors` (AMOLED v3), `UserStorage.l10n` e `ListenableBuilder`. Exibe claramente estado **Não pareado** vs **Pareado com `<name>`**, host do relay, prefixo resumido do `device_id` (opcional e sem segredos), botões **Escanear QR** (abre modal/tela com `MobileScanner`, com builder/handler injetável para testes e proteção contra leitura duplicada), **Colar link** (diálogo com campo de texto e validação) e **Desvincular / Parear de novo** (com diálogo de confirmação ao desvincular e aviso amigável caso a revogação remota tenha falhado por rede).
  - Escrever `test/ui/lumen/lumen_pairing_page_test.dart` verificando estados pareado/não pareado, colagem válida e inválida, callback simulado de scanner e confirmação de desvincular (garantindo ausência de `key`/`access`/`token` na árvore renderizada).

## Passo 8 — Entrada em Configurações e Registry (`settings`)

- **Arquivos:**
  - `lib/ui/settings/widgets/settings_page.dart`
  - `lib/data/services/settings_registry.dart`
  - (Opcional/recomendado) caso em `test/ui/settings/widgets/settings_page_test.dart` ou teste dedicado de navegação para `LumenPairingPage`
- **O que fazer:**
  - Em `settings_page.dart`, adicionar a linha de entrada do **Lumen** **após `showInsightTextTitle`** (junto ao bloco de `Backup & Restore`) abrindo `LumenPairingPage(viewModel: LumenPairingViewModel(router: MemexRouter()))`, preservando a asserção inicial de viewport em `settings_page_test.dart`.
  - Em `settings_registry.dart`, registrar `settings.lumen_pairing` dentro de `_settingsPageItems` com `UserStorage.l10n`, `NavigationTarget` para `LumenPairingPage` e `parentPathGetter: () => [UserStorage.l10n.personalCenter, UserStorage.l10n.settings]`.

## Verificação Final (obrigatória no mesmo commit)

Executar na raiz `C:\Users\notefael\projetos\segundamente` após finalizar código e testes:

```powershell
C:\Users\notefael\tools\flutter\bin\flutter gen-l10n
python3 scripts/check_arb_key_parity.py
C:\Users\notefael\tools\flutter\bin\flutter test --no-pub `
  test/domain/models/lumen_pairing_test.dart `
  test/data/services/lumen_relay_crypto_test.dart `
  test/data/services/lumen_pairing_service_test.dart `
  test/ui/lumen/lumen_pairing_page_test.dart `
  test/l10n/arb_key_parity_test.dart `
  test/l10n/hardcoded_ui_strings_test.dart `
  test/ui/settings/widgets/settings_page_test.dart `
  test/data/services/settings_registry_todo_test.dart
C:\Users\notefael\tools\flutter\bin\flutter analyze
```

### Limpeza antes do commit (`Flutter 3.47` quirk)

O SDK `flutter` local pode reescrever `analysis_options.yaml` e `android/gradle.properties` durante `pub get`, `test` ou `analyze`. Antes de commitar, sempre conferir `git status` e restaurá-los:

```powershell
git -C C:\Users\notefael\projetos\segundamente checkout -- analysis_options.yaml android/gradle.properties
git -C C:\Users\notefael\projetos\segundamente status --short --branch
```

### Notas observadas na base antes da implementação
- `STATE.md` registra um fallback esperado de `EncryptedSharedPreferences` no S25 em cold start; o wrapper `LumenSecretStore` deve capturar/propagandar falhas de leitura/escrita sem derrubar a tela.
- A validação final em aparelho real (S25) com QR gerado pelo Lumen desktop fica vinculada ao fechamento conjunto dos Passos 5 e 6 na `PONTE.md`.

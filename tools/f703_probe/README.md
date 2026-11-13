# f703_probe — sonda descartável da F7-03 (voz duplex)

App separado do Segunda Mente (`app.segundamente.f703_probe`), no método da F6-10. Mede no S25 o que o
`docs/fases/F7-01-viabilidade.md` mandou medir antes de liberar a tela de voz: eco, interrupção, latência,
bateria e aquecimento.

**Privacidade:** só usa uma frase sintética fixa. Nenhum áudio é gravado em arquivo; saem apenas contagens,
níveis em dBFS e tempos, na tela e no logcat (linhas `F703 {...}`). O microfone só abre ao tocar num teste,
com a faixa "MICROFONE LIGADO" visível, e fecha ao terminar, ao tocar em "Parar" ou ao sair do app.
Não muda nenhuma configuração do aparelho.

## Rodar

Ambiente silencioso, volume de mídia em ~50%, aparelho fora do carregador, tela ligada.

```bash
cd tools/f703_probe
flutter pub get
flutter build apk --debug
adb -s <serial> install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s <serial> logcat -c
```

| Teste | O que fazer | O que sai |
|---|---|---|
| 1. Eco | Ficar em silêncio (~1 min). Roda 4 configurações de microfone. | `disparos_durante_fala` (ideal: 0), níveis, `ms_ate_inicio_da_voz` |
| 2. Interrupção | Dizer "espera" ~3 s depois de a voz começar, 5 vezes. | `ms_entre_detectar_e_calar`; `detectado_ms_apos_pedir_fala` muito baixo = eco, não você |
| 3. Resistência | Ficar em silêncio por 5 min. | `disparos_falsos`, `falas` |

Bateria e temperatura (antes e depois do teste 3):

```bash
adb -s <serial> shell dumpsys battery | grep -E "level|temperature"   # temperature em décimos de °C
adb -s <serial> shell dumpsys thermalservice | grep -iE "skin|battery" | head
```

Resultados:

```bash
adb -s <serial> logcat -d -s flutter | grep "F703 " > ../../docs/medicoes/f7-03/s25.jsonl
adb -s <serial> uninstall app.segundamente.f703_probe
```

Registre os números em `docs/fases/F7-03-voz-duplex.md` (seção "Medição no S25"). A configuração `voz_aec` é a que o
app usa (`DuplexVoiceService.micConfig`); se outra ganhar, troque lá e nos limiares do detector.

Estado: executada no S25 em 2026-11-11 e desinstalada. Resultado em `docs/fases/F7-03-voz-duplex.md` (seção 5) e `docs/medicoes/f7-03/s25.jsonl`. Depois do primeiro teste de eco, os testes 2 e 3 passaram a usar `voz_aec_saida_chamada`.

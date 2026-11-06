# F5-03 — Medições

**Data:** 2026-11-02. Fixture sintético, nesta máquina. Não é o TXT do Samsung e não é o S25. A F5-03 fica `IN_PROGRESS`. Nenhum código de desempenho foi alterado: os números não mostraram fila nem estouro.

## Comando

`flutter test --reporter expanded test/domain/models/f5_measurements_test.dart` (no mesmo processo que o teste de log).

Saída:

```text
F5-03 parse_ms=15 segments=1500
F5-03 export_ms=25 items=100
00:00 +3: All tests passed!
```

O `+3` inclui os dois testes de log. O teto do teste é 5000 ms. Os tempos medidos não substituem esse teto.

## O que foi medido

`TranscriptImport.parse` em 1500 pares relógio + `frase N`, um a cada 2 segundos, cobrindo 50 minutos. Texto ASCII. Resultado: 1500 segmentos, `timestampsFound`, 15 ms.

`exportSessionReportBytes` de um relatório de reunião com 100 decisões `não confirmado`, nos três formatos, 25 ms. A data de exportação do teste é `2026-11-02 15:04`.

## O que não foi medido

`ChatSessionStorage.listSessionMetadata` não entrou no teste. Esse método chama a migração e a varredura do YAML antigo. Lista de histórico: `NOT_RUN`. Aparelho: `NOT_RUN`.

## Medição no S25 (2026-11-05)

**Aparelho:** Galaxy S25 Ultra, Android 17, APK `globalDev` **debug** (JIT; o build de produção tende a ser mais rápido e usar menos memória, não medido). **Entrada:** importação real do Gravador Samsung `txt_1793924759989`, 53 min 20 s, 625 linhas, 14 participantes, 52 KB de texto normalizado (100 KB no original). Havia um agente de insights trabalhando em segundo plano durante a medida.

**Método:** gravação de tela (`screenrecord`, ~60 qps) durante cada toque; tempo = do primeiro quadro que muda (resposta ao toque) até o último quadro que muda (tela estável, incluindo animações e indicadores de carregamento). Memória: `dumpsys meminfo` (TOTAL PSS). Script fora do repositório (`measure.py` no rascunho da sessão).

| Ação | Tempo até tela estável |
|---|---:|
| Abrir Histórico de chat (lista com 7+ sessões) | 291 ms |
| Abrir o relatório da sessão de 53 min | 166 ms |
| Gerar rascunho local (sem modelo) | 91 ms (log: `Drafted session report txt_1793924759989`) |
| Exportar PDF até a folha de compartilhamento | 425 ms |
| Exportar DOCX | 167 ms |
| Exportar Markdown | 164 ms |

Memória do processo (TOTAL PSS): 770 MB em repouso na linha do tempo, 732 MB após o rascunho, 713 MB após as três exportações. Não houve crescimento com as ações medidas.

**Não medido:** "Gerar com o modelo" sobre esta sessão. É reunião real com terceiros, e o PROJECT.md proíbe enviar conteúdo confidencial de terceiros ao provedor sem autorização; o tempo dessa etapa depende da rede e do provedor. A extração com modelo já foi validada em reunião sintética no S25 (F3-02).

**Conclusão:** nenhuma ação passou de meio segundo no build de depuração; nada a corrigir. A memória alta (~0,7 GB) é do build de depuração com agentes ativos; medir no build de produção fica como acompanhamento, sem bloquear o MVP.


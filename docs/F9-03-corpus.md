# F9-03 — corpus F9-02 contra o modelo (2026-11-06)

**Estado: `DONE` em 2026-11-07, fechada pelo dono.** O resultado que vale é a seção "Série refeita depois da fusão follow-up/tarefa" no fim; as seções anteriores são o histórico das medições.

Dados fictícios. Prompt real do app (`reportExtractionSystemPrompt`), resposta conferida pelo mesmo código de validação do relatório. Scripts: `docs/medicoes/f9-03/corpus.dart` e `rodar.py`.

**Como rodou:** pelo Codex CLI do PC (modelo `gpt-6-luna`, esforço baixo), não pelo cliente do app. O Codex acrescenta instruções próprias, então é uma estimativa do prompt, não a prova do caminho do app. Os 5 PDFs entraram como o texto esperado de cada página, com `p.N`; a leitura do PDF pelo modelo só foi provada no S25 com o `c36`.

## Resultado (tipo de relatório "Livre", 39 casos com texto)
| Medida | Resultado |
|---|---|
| Respostas válidas (JSON, tipo permitido, citação literal) | 38/39 |
| Tarefas esperadas que apareceram como tarefa | 13/20 |
| Tarefas a mais (falsas) | 1 |
| Itens de PDF com a página certa | 5/5 |

- 1ª rodada, tipo "Reunião": 34/39 válidas, 16/20 tarefas, 2 falsas, página 3/4. Quatro das cinco recusas eram do tipo "Reunião", que não aceita ideia/dúvida; não é erro do modelo.
- A diferença entre as duas rodadas (16 e 13 tarefas de 20) mostra que o resultado varia de uma chamada para outra. Um número só não é medida firme.
- Erros típicos: tarefa classificada como decisão (`c02`), resumo (`c17`, `c19`, `c22`, `c23`) ou follow-up (`c26`); `c40` (prazo repetido em duas páginas) voltou sem itens, `c27` e `c09` sem tarefa esperada.
- O modelo nunca devolveu responsável ou prazo (o prompt proíbe), então a coluna "responsável/prazo" do corpus não foi medida.

## O que não vale ainda
- Não é o caminho do app; rodar o corpus pelo app no S25 continua `NOT_RUN` (o dono pediu o teste pelo chat).
- Uma rodada de cada; sem repetição para medir a variação.
- Não decidi se 13/20 é suficiente. Como todo item sai "Não confirmado", a falha é omitir tarefa, não inventar (1 falsa).

## Critério de aceitação e protocolo pelo app (proposto em 2026-11-06; aprovado pelo dono em 2026-11-07, sem alterações)

**Critério proposto** (por tipo de relatório, sobre ≥5 rodadas completas do corpus, mesmo modelo e mesma configuração do app):
- tarefas esperadas encontradas: mediana ≥ 17/20 (85%) e nenhuma rodada abaixo de 14/20 (70%);
- tarefas falsas: ≤ 1 por rodada;
- respostas válidas: ≥ 95% (descontando recusas legítimas de tipo, como ideia em "Reunião");
- página de evidência certa nos 5 PDFs em todas as rodadas.

As rodadas do PC (13/20 e 16/20) ficariam abaixo da mediana pedida; os limites são minha proposta, não decisão do dono.

**Protocolo:** cada caso vira uma sessão sintética no app (texto de `corpus.json`; PDFs de `test/fixtures/f9/`), o relatório é gerado pelo botão do app e a confirmação de envio é aceita na tela. Conferir o resultado contra `esperado`. 39 casos × 5 rodadas ≈ 195 chamadas ao provedor, mais ~39 sessões sintéticas novas no S25 (sem apagar nada). Piloto: 1 caso antes da série.

**Piloto (2026-11-06, S25, caminho real do app, 1 caso, tipo "Livre", dono autorizou só o piloto):** importei `f9_c36.pdf` (aviso "Enviar o PDF para ler?" → Enviar PDF) e gerei "com o modelo" (aviso "Este texto sai do telefone" → Enviar agora). Resultado: 2 itens, ambos com evidência `p.2`, todos "Não confirmado": o resumo "Ficou decidido que o orçamento será revisado." e a tarefa "Paulo envia a versão final até 20/09." Tarefa esperada 1/1, falsas 0, página certa. Uma amostra de 1 caso não mede nada; só prova que o fluxo funciona de ponta a ponta no aparelho. Cria uma sessão sintética nova no S25 (ver RISCOS-F9 item 10).

**Série completa: `NOT_RUN`.** Aceitar a tela de confirmação envia texto sintético ao provedor configurado e grava sessões novas no aparelho; a série (≈195 chamadas, ≈39 sessões) exige autorização explícita do dono, ainda não dada. Nenhum dado foi enviado por CLI, script ou rota fora do app nesta retomada.

## Tentativa de automação (2026-11-06, limite de 10 min no aparelho)

Importei 3 casos TXT (c01, c03, c09) pelo histórico do app e parei no limite de tempo; **nenhuma rodada foi gerada nem pontuada**. Aprendido para a próxima vez:
- TXT importado fica na lista do histórico (botão "Abrir relatório" no item mais recente); só o PDF abre o relatório sozinho.
- O diretório da sessão em `SessionReports/` só aparece depois da primeira geração: detectar a sessão pelo diff de `ls` **depois** de "Gerar com o modelo", não depois da importação.
- Toque de importação (`Enviar agora`), seletor (`f9corpus` → arquivo) e leitura por `run-as` funcionam. Helper: `docs/medicoes/f9-03/ui_s25.py`. Driver corrigido (offline, sem teste no aparelho) em `docs/medicoes/f9-03/rodar_app.py`; reaproveita c09, c03 e c01 já importados.
- Sessões TXT criadas em excesso por tentativas repetidas: 3 (uma por caso). Casos já importados não precisam ser importados de novo.

## Primeira medição pelo app (2026-11-06, S25, tipo "Livre", 9 casos × 2 rodadas)

Janela de ~10 min no aparelho, sem uso paralelo. Driver `docs/medicoes/f9-03/rodar_app.py`; dados brutos em `docs/medicoes/f9-03/app_rodadas.jsonl`. Cada geração passou pelo botão do app e pela confirmação "Enviar agora"; resultado lido de `report.json` por `run-as` (só das sessões criadas por mim). Mesma regra de contagem do `corpus.dart` (tarefas encontradas = mínimo entre tarefas geradas e esperadas).

| Medida | Rodada 1 | Rodada 2 |
|---|---|---|
| Tarefas esperadas encontradas (c01–c09) | 6/7 | 6/7 |
| Tarefas falsas | 0 | 0 |
| Respostas sem resposta/erro | 0/9 | 0/9 |

- Falha repetida nas 2 rodadas: **c03** (nota "renovar o seguro do carro", sem relógio) voltou como item que não é tarefa.
- c07, c08, c09 (sem tarefa esperada) não geraram tarefa falsa.
- Não vale para o critério: são só 9 dos 39 casos, 2 das 5 rodadas, e só texto (nenhum PDF). A coluna `paginas_ok` do jsonl só testa se o campo de relógio é não vazio; **não é medida de página certa** e não deve ser usada.
- Resultado estável entre as 2 rodadas nestes casos (mesmos acertos), diferente da variação vista no PC; amostra pequena demais para concluir.
- Sessões novas no S25: 6 (c02, c04, c05, c06, c07, c08), mais as 3 já documentadas (c01, c03, c09); todas com relatório Livre gerado e nenhum item confirmado.
- Falta para o critério: c10–c40 (inclui os 5 PDFs) e as rodadas 3–5. Estimativa pelo tempo medido (~45 s por caso com 2 rodadas): cerca de 25–30 min para o restante em blocos.

## Janela de 2026-11-07 (S25, ~9 min, dono liberou o aparelho)
- Pelo app, 2 rodadas cada: c10, c11 e c12 (nenhuma tarefa esperada nesses casos): 0 falsas, 0 respostas inválidas, 1 item por rodada. Com os 9 casos anteriores, são 12/39 casos medidos; total de tarefas esperadas medidas continua 7 (6 achadas, 0 falsas).
- c13 em diante não rodou: a importação pelo seletor de arquivos não achou `f9c_c13.txt` (o seletor abriu na gaveta "Abrir de" e a lista precisa de rolagem, que o driver não faz). Nenhum resultado foi inventado; esses casos seguem `NOT_RUN`.
- Ajuste pendente no driver (`rodar_app.py`/`ui_s25.py`): rolar a lista do seletor antes de falhar. Cada janela deve rodar poucos casos e conferir a tela entre eles.
- O critério aprovado exige ≥5 rodadas completas; faltam 27 casos e 3 rodadas. A auditoria continua `FAIL`; F9-03 segue `IN_PROGRESS`.

## Segunda janela de 2026-11-07 (S25)
- Corrigido o driver: o seletor rola até achar o arquivo; o caminho até o "Histórico de chat" passa pelo menu lateral (rolando a gaveta); os botões "Voltar" e "Importar transcrição" são achados pelo nome, não por coordenada fixa (o layout mudou desde a primeira medição).
- Pelo app, c13 (2 rodadas): nenhuma tarefa esperada, 0 falsas, 1 item por rodada, páginas ok. Com isso são 13/39 casos medidos.
- c14 a c25 não rodaram: depois do primeiro caso o driver ainda tocava o botão Voltar por coordenada antiga e ficou preso na tela do relatório. A correção para isso foi escrita no fim da janela e **não foi testada**. Nada foi medido nesses casos (`NOT_RUN`).
- A janela estourou os 10 minutos combinados por causa da depuração; parei sem rodar mais nada.

## Terceira janela de 2026-11-07 (S25) — causa achada e corrigida
- **Causa real das falhas em cascata:** o aparelho tinha girado para retrato (rotação automática ligada), e o driver foi escrito com as coordenadas da tela em paisagem. Em retrato o relatório não abria como esperado. O driver agora só funciona em paisagem; para a janela forcei paisagem (`accelerometer_rotation=0`, `user_rotation=1`) e **restaurei** `accelerometer_rotation=1`, `user_rotation=0` ao terminar.
- Pelo app, 2 rodadas cada: c14, c15, c16 (nenhuma tarefa esperada): 0 falsas. c17 (1 tarefa esperada): achada nas 2 rodadas, 0 falsas. Em c14 (tipo nota, sem horário) `paginas_ok` deu falso nas duas rodadas, esperado porque a nota não tem marca de tempo; não foi tratado como erro.
- Acumulado pelo app: 17/39 casos, 8 tarefas esperadas medidas, 7 achadas, 0 falsas, 2 rodadas por caso. O critério pede ≥5 rodadas completas dos 39 casos: seguem faltando 22 casos e 3 rodadas.
- Próximo: c18 em diante (`rodar_app.py <seg> 2 c18,c19,...`), com a tela forçada em paisagem no início da janela.

## Série completa pelo app no S25 (2026-11-07) — resultado contra o critério aprovado
Dados: `docs/medicoes/f9-03/app_rodadas.jsonl`. Tipo de relatório "Livre", modelo e configuração do app, 5 rodadas de cada caso (rodada = n-ésima geração do caso; os casos c01–c17 tiveram 2 rodadas na primeira sessão e 3 depois, em importações novas). Tela forçada em paisagem durante a série e restaurada no fim.

| Rodada | Tarefas esperadas achadas | Tarefas falsas | Respostas válidas |
|---|---|---|---|
| 1 | 17/20 | 1 | 39/40 |
| 2 | 18/20 | 3 | 39/40 |
| 3 | 17/20 | 2 | 38/39 |
| 4 | 18/20 | 2 | 38/39 |
| 5 | 16/20 | 3 | 38/39 |

- A resposta inválida é sempre o `c39` (PDF digitalizado, sem texto selecionável): recusa esperada, não erro do modelo.
- **Lacuna:** o `c07` ficou com 2 de 5 rodadas. A importação dele pelo seletor de arquivos abre o diálogo "Abrir com" do Android e o driver não passa; ele não espera tarefa, então só poderia acrescentar tarefas falsas.
- **Contra o critério aprovado:**
  - mediana de tarefas achadas ≥ 17/20: **atende** (17);
  - nenhuma rodada abaixo de 14/20: **atende** (mínimo 16);
  - respostas válidas ≥ 95%: **atende** (38/39 a 39/40 por rodada, descontando o `c39`);
  - tarefas falsas ≤ 1 por rodada: **NÃO atende** (1, 3, 2, 2, 3; quatro de cinco rodadas acima).
- **Veredito: o critério não é atendido.** F9-03 continua `IN_PROGRESS` e a auditoria `FAIL`, agora por medida firme, não por falta de medição.
- De onde vêm as falsas: `c34` (follow-up em conversa, 4 de 5 rodadas) e `c35` (follow-up em nota, 5 de 5) saem como tarefa em vez de follow-up; `c19` (duplicata, 2 rodadas). São o modelo tratando "voltar com o preço" / "perguntar ao Rui" como tarefa. Não alterei o critério para absorver isso.
- De onde vêm as perdidas: `c40` (mesma data em duas páginas de PDF, 5/5), `c03` (nota própria, 4/5), `c26` (intervalo vago "semana que vem", 4/5), `c23` (dono ausente, 1/5).
- Próximo passo possível (decisão do dono): ajustar o prompt do relatório para follow-up vs tarefa e repetir a série, ou aceitar e documentar o limite. Nenhum ajuste de prompt foi feito.
- **Efeito colateral a declarar:** ao tentar contornar o `c07`, o diálogo "Abrir com" abriu o app com o texto do caso e eu toquei "Enviar agora" na confirmação do próprio app; o texto fictício foi para o chat da Segunda Mente (não para a importação) e gerou um cartão "Nota de teste fictícia F9". Só dado fictício, mas o cartão e a conversa ficaram no aparelho, somados aos artefatos sintéticos que já aguardam sua autorização de limpeza. Nada foi apagado.

## Série refeita depois da fusão follow-up/tarefa (2026-11-07, D-043)
- **O que mudou:** o tipo follow-up deixou de existir para o modelo (só `task`; "perguntar, checar ou voltar depois" é tarefa) e o corpus passou a esperar tarefa em `c34` e `c35`. Isso muda a definição, então **não é prova de que o modelo melhorou**; a série anterior (`app_rodadas_antes_fusao.jsonl`) fica como registro. Mudei o corpus depois de ver o resultado: o motivo é de produto (dono: as duas ideias se confundem), registrado em D-043.
- **Como rodou:** APK `globalDev` debug novo instalado com `adb install -r`, caminho real do app no S25, tipo "Livre", 40 casos × 5 rodadas completas (inclui o `c07`, que antes ficou com 2), tela em paisagem forçada e restaurada no fim. Dados: `docs/medicoes/f9-03/app_rodadas.jsonl`.

| Rodada | Tarefas esperadas achadas | Falsas | Respostas válidas |
|---|---|---|---|
| 1 | 21/22 | 1 | 39/40 |
| 2 | 20/22 | 1 | 39/40 |
| 3 | 20/22 | 0 | 39/40 |
| 4 | 21/22 | 1 | 39/40 |
| 5 | 21/22 | 1 | 39/40 |

- **Contra o critério aprovado** (o critério foi escrito para 20 tarefas; com 22 uso as mesmas porcentagens: mediana ≥ 85% = 18,7 e mínimo ≥ 70% = 15,4):
  - mediana de tarefas achadas: 21/22 = 95% → **atende**;
  - nenhuma rodada abaixo do mínimo: pior 20/22 = 91% → **atende**;
  - tarefas falsas ≤ 1 por rodada: 1, 1, 0, 1, 1 → **atende**;
  - respostas válidas ≥ 95%: 39/40 = 97,5% por rodada; a única recusa é o `c39` (PDF digitalizado, esperada) → **atende**.
- **Resultado: o critério de aceitação da F9-03 é atendido** nesta série. F9-03 continua `IN_PROGRESS` no ROADMAP: fechar a subfase é decisão do dono, e a auditoria geral da F9 não foi refeita.
- **O que ainda erra:** `c40` (mesma data em duas páginas de PDF) perdeu a tarefa nas 5 rodadas; `c03` e `c05` em 1 rodada cada; falsas em `c19` (duplicata, 3 rodadas no total) e `c38` (1).
- **Driver:** o seletor de arquivos reabre dentro da pasta, então o passo "tocar em f9corpus" deixou de ser obrigatório; linhas coladas nas bordas da tela não são mais tocadas. `c24` precisou de reaproveitamento de sessão depois de uma falha do driver (não afeta os dados).

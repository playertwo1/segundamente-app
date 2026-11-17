> Arquivado de [DECISIONS](../../DECISIONS.md) em 2026-11-17. Registro histórico; não editar.

# Decisões arquivadas

Critério: decisões `SUPERSEDED`, ou decisões de processo cujo efeito já se esgotou (abrir, ordenar ou fechar uma fase ou subfase que já terminou). Decisões de comportamento do produto continuam em `docs/DECISIONS.md`.

| ID | Data | Assunto | Estado |
|---|---|---|---|
| D-003 | 2026-11-02 | Fases F0–F5 (MVP) e F6–F8 (futuro bloqueado) | ACCEPTED |
| D-009 | 2026-11-02 | Até o S25 Ultra estar conectado, o emulador é o aparelho de prova da F0 | ACCEPTED |
| D-010 | 2026-11-02 | A F6 pode começar com os portões da F0 à F5 ainda abertos | ACCEPTED |
| D-013 | 2026-11-03 | Gemini por OAuth desbloqueado via daily-cloudcode-pa SSE stream | SUPERSEDED |
| D-019 | 2026-11-03 | Priorizar a implementação visual F5-04 antes das demais pendências, sem fechar o portão F4 | SUPERSEDED |
| D-021 | 2026-11-03 | Fazer o redesign visual em fase própria após o fechamento da fase F5 atual | SUPERSEDED |
| D-022 | 2026-11-03 | Iniciar a fase F5V agora, em paralelo ao fechamento da F5 | ACCEPTED |
| D-031 | 2026-11-05 | Abrir só a pesquisa F7-01 (sem código) antes do portão F5 | ACCEPTED |
| D-040 | 2026-11-06 | Fechar a F6 sem auditoria própria; abrir a F7-02 (medição do modelo local no S25) | ACCEPTED |
| D-047 | 2026-11-11 | F7-03 (voz duplex) aberta sem o modelo local; entrada desligada até a medição no S25 | ACCEPTED |
| D-048 | 2026-11-11 | Voz duplex ligada no chat com o eco medido no S25, aceito pelo dono | SUPERSEDED por D-049 |
| D-056 | 2026-11-13 | Manter F11-04 pendente do S25 e avançar F11-05 | ACCEPTED |

## D-009 — Emulador até o S25
- Contexto: a F0-02 pedia execução no Galaxy S25 Ultra. Em 2026-11-02 o dono pediu para usar só o emulador por enquanto.
- Decisão e motivo: enquanto o S25 não estiver conectado, `emulator-5554` é o aparelho de prova das subfases da F0. A execução no S25 fica `NOT_RUN`. Os critérios de aceite do MVP continuam no S25. A fase F0 não se declara concluída sem essa execução, ou sem uma decisão nova.
- Descartado: parar a F0 até o telefone aparecer.

## D-010 — Abrir a F6 antes do MVP
- Contexto: D-003 deixa a F6 bloqueada até o MVP. Em 2026-11-02 o dono pediu para avançar depois dos commits da F4 e da F5.
- Decisão e motivo: a F6 pode começar. O MVP não fecha. D-003 continua valendo para o que é o MVP e para manter a F7 e a F8 bloqueadas. Busca semântica, tópicos e o "por quê" não entram sem um modelo. A busca deste passo é texto local nos relatórios.
- Descartado: marcar o MVP como pronto para desbloquear a fase.


## D-013 — Gemini por OAuth (SUPERSEDED por D-020 e commit aa91a48)
- Contexto: Inicialmente `loadCodeAssist` devolvia `UNSUPPORTED_CLIENT` para o client_id do Gemini CLI e exigia projeto GCP standard-tier.
- Decisão e atualização (2026-11-03): Desbloqueado com sucesso usando o endpoint de streaming SSE `https://daily-cloudcode-pa.googleapis.com` com `:streamGenerateContent?alt=sse`. As credenciais de OAuth foram ofuscadas no código fonte (`String.fromCharCodes`) para permitir commit/push sem acionar regras de segredos em texto plano do GitHub Push Protection. Validado no Galaxy S25 Ultra em texto (872ms) e stream (910ms).

## D-019 — Próxima prioridade: redesign móvel
- Estado: `SUPERSEDED` por D-021 após o dono esclarecer que o redesign deve ocorrer numa fase própria, depois da fase atual.
- Decisão anterior: iniciar a implementação em F5-04 foi registrado, mas não executado.

## D-021 — Redesign visual após a fase atual
- Estado: `SUPERSEDED` por D-022.
- Contexto: o dono esclareceu em 2026-11-03 que o redesign da versão nova deve ocorrer depois de concluir a fase atual, não como a próxima tarefa dentro dela.
- Decisão: manter o fechamento de F5 como foco atual e inserir F5V — Redesign visual da versão nova imediatamente depois de F5 e antes de F6. F5-04 cobre a direção aprovada e documentada; a implementação das telas fica em F5V.
- Limite: F5V só começa depois de F5. Esta ordem não fecha nem remove critérios dos portões F0–F5 e não desbloqueia F7/F8 por si só.

## D-022 — F5V começa agora
- Contexto: em 2026-11-03, depois do commit `b513d72` (cofre do Android para tokens e chaves), o dono pediu para iniciar a fase visual imediatamente.
- Decisão: a F5V passa a `IN_PROGRESS` e é a fase de trabalho atual. A F5 continua aberta em paralelo: o que falta nela depende do S25 (7 critérios, migração do cofre no aparelho, medições).
- Limite: a ordem muda, os portões não. F5V não fecha a F4 nem a F5, e o MVP só fica pronto com o portão da F5. F7/F8 continuam bloqueadas.

## D-031 — Abrir a pesquisa F7-01 (2026-11-05)
- Contexto: o dono pediu avançar para a F7, que está `BLOCKED` até o fechamento da F5 (D-003). Mesmo precedente da D-010 para a F6.
- Decisão: abrir somente F7-01 (pesquisa e decisão de escopo). F7-02 a F7-06 seguem `BLOCKED`; nenhum código, provedor, serviço de PC ou permissão de microfone é autorizado. A F5 continua aberta e o MVP não muda.
- Evidência: `docs/fases/F7-01-viabilidade.md` (termos da Anthropic e da OpenAI, licenças, autenticação, sistemas e limites de dados, com nível de evidência por linha).

## D-034 — F8 e F9 só em pesquisa e documento; F7-02 em plano (2026-11-05)
- Contexto: o dono pediu "veja do F7, F8 e F9 o que possa fazer sem o celular e faça". O roadmap exige decisão registrada para abrir fase `BLOCKED` (mesmo precedente de D-010 e D-031).
- Decisão: abrir somente trabalho de pesquisa e de documento, sem código, dependência, permissão ou download de modelo: F8-01 (viabilidade do NotebookLM), F9-01 (mapeamento e perguntas), F9-02 (corpus de 40 casos em dados) e um plano de medição para F7-02. As demais subfases seguem `BLOCKED`.
- Limites: nenhuma recomendação dos documentos está aceita; as decisões do dono estão listadas em `docs/fases/F8-01-viabilidade.md` (seção 5) e `docs/fases/F9-01-mapeamento.md` (seção 3). O que depende do S25 continua `NOT_RUN`. A F5 segue aberta e o MVP não muda.
- Evidência: `docs/fases/F8-01-viabilidade.md`, `docs/fases/F9-01-mapeamento.md`, `docs/fases/F9-02-corpus.md` e `docs/medicoes/f9-02/`, `docs/fases/F7-02-plano-de-medicao.md`.

## D-040 — Fechar a F6 e abrir a F7-02 (2026-11-06)
- Contexto: os 12 itens da F6 estão `DONE` com prova no S25 (F6-01 fechada hoje). O texto do portão F6 não exige auditoria própria, ao contrário da F5. O dono pediu: "feche o f06 e avance para o f07". A F7 estava `BLOCKED`; só a F7-01 (pesquisa) tinha sido aberta (D-031) e a F7-02 tinha plano (D-034).
- Decisão: F6 `DONE` sem auditoria dedicada; limites declarados continuam valendo (corte 0,42 provisório, índice só em memória, tempos e bateria não medidos). F7: abrir somente a F7-02 (sonda de modelo local no S25, método da F6-10, app separado em `tools/`). F7-03 e F7-06 seguem `BLOCKED`; F7-04 e F7-05 seguem `CANCELLED`.
- Limites: nenhum modelo é baixado antes de o dono confirmar o download do Gemma 3 1B (~529 MB) e liberar o S25 por cerca de uma hora. O Gemma nunca vai empacotado no APK nem no repositório (Termos de Uso exigem repassar as restrições a quem recebe os pesos; risco de conflito com a GPL-3.0). Resumo dos Termos lido em 2026-11-06, não é parecer jurídico.
- Evidência: `ROADMAP.md`, `docs/fases/F7-02-plano-de-medicao.md`.

## D-046 — Atualizador Android para releases do repositório privado (2026-11-10) — SUPERSEDED por D-067
- Contexto: o dono pediu uma opção nas Configurações para procurar e baixar atualizações do repositório GitHub do fork.
- Decisão: reutilizar o atualizador existente e apontá-lo ao `origin` privado (`playertwo1/segundamente-app`). Stable e Early no Android podem buscar o APK do mesmo flavor; Dev fica indisponível. Para acessar releases privadas, a pessoa configura um token fine-grained limitado ao repositório, com `Contents: read`, salvo pelo `SecretStorage` no cofre do aparelho; o token não é incluído no código, nas preferências ou no backup. A checagem automática só roda se o token estiver salvo e a preferência estiver ativa; download e instalador continuam sujeitos às opções existentes.
- Limite: é necessário configurar o token em cada instalação e publicar uma release com APK do flavor compatível. Testes Flutter, análise, geração de localizações e validação no S25: `NOT_RUN` neste ambiente, que não tem Flutter/Dart disponível.

## D-047 — Abrir a F7-03 (voz duplex) sem o modelo local (2026-11-11)
- Contexto: o dono pediu "trabalhe no F7-03", autorizando a investigação e o protótipo de áudio do F7-01, sem reabrir a F7-02 nem ignorar a dependência. O ROADMAP marcava F7-03 `BLOCKED` até a F7-02, adiada por D-041. D-032 tinha deixado a voz duplex "em aberto, sem decisão".
- Constatação: a dependência da F7-02 não é técnica. A conversa por voz usa a transcrição já existente (Parakeet local ou nuvem), o modelo de chat já configurado e a voz do sistema Android; nenhuma parte exige um LLM no aparelho. A F7-02 só acrescentaria a opção de resposta sem nuvem.
- Decisão: F7-03 passa a `IN_PROGRESS` pelo caminho independente. F7-02 continua `BLOCKED` (D-041 intacta) e F7-06 continua `BLOCKED`. Nenhuma dependência nova: a voz usa um canal nativo sobre o `TextToSpeech` do Android; `flutter_tts` e TTS por modelo foram descartados.
- Limites: o S25 não estava conectado em 2026-11-11, então eco, interrupção, latência, bateria e aquecimento estão `NOT_RUN`. Por isso a entrada da tela no chat fica desligada (`AppConfig.enableDuplexVoice = false`) e a F7-03 não pode ser `DONE`. O turno falado vai ao chat em modo somente leitura. O texto da conversa entra no histórico; o áudio nunca é gravado.
- Falta ao dono: rodar `tools/f703_probe` no S25 e, com os números, decidir ligar a entrada (ou exigir fone / trocar a interrupção por toque se o eco não for controlável).
- Evidência: `docs/fases/F7-03-voz-duplex.md`, STATE.md.

## D-048 — Ligar a voz duplex com o eco como está (2026-11-11)
- Contexto: a sonda no S25 mostrou que, com a voz no alto-falante, o detector dispara com a própria resposta (2 disparos por fala de ~13 s na configuração do app; `docs/fases/F7-03-voz-duplex.md` seção 5). Foram oferecidas três saídas: interrupção por toque, falar por cima só com fone, modo "telefone".
- Decisão do dono: "deixe com eco mesmo, está aceitável para mim". Nenhuma das três saídas é adotada; a configuração de microfone e os limiares ficam como estão e `AppConfig.enableDuplexVoice` passa a `true`.
- Consequência conhecida e aceita: no alto-falante a resposta pode ser cortada pela própria voz do app, e o trecho de eco pode ser transcrito e enviado ao modelo como se fosse um turno do usuário (em modo somente leitura; entra no histórico do chat e gasta chamadas do modelo) até o usuário pausar ou encerrar. Com fone o efeito deve sumir, mas isso não foi medido.
- Limites: a tela e o canal `TtsChannelHandler` ainda não foram executados no aparelho (`NOT_RUN`); a F7-03 segue `IN_PROGRESS`. Reavaliar se o corte da resposta incomodar no uso: a alternativa mais barata continua sendo fechar o microfone enquanto o app fala.
- Evidência: `docs/medicoes/f7-03/s25.jsonl`, STATE.md.

## D-056 — Ordem de execução da F11 enquanto alarmes aguardam o S25 (2026-11-13)
- Contexto: o dono pediu para deixar a F11-04 pendente até haver acesso ao Galaxy S25 Ultra e avançar para a próxima subfase. A F11-04 exige evidência física de alarmes exatos em Doze, offline, após reinício e com economia de bateria.
- Decisão: manter a F11-04 `BLOCKED` e abrir a F11-05 agora. A F11-05 depende da F11-03, já concluída, e segue as regras de confirmação de IA aceitas em D-051. Esta decisão não dispensa nem simula qualquer teste físico da F11-04 e não desbloqueia outras subfases.

## D-058 — Retomar F11-04 com o S25 conectado (2026-11-13)
- Contexto: D-056 manteve a F11-04 bloqueada até haver acesso ao Galaxy S25 Ultra. O dono confirmou que o aparelho está conectado e pediu para continuar.
- Decisão: abrir a F11-04 para implementação e validação física no S25. A F11-06 continua `BLOCKED`; esta decisão não a desbloqueia.

## D-060 — Fechamento da F7-03 sem o teste de revogação durante a conversa (2026-11-13)
- Decisão do dono: não testar a revogação da permissão de microfone no meio da conversa, por não ter utilidade real. Esse caso fica `NOT_RUN` e não bloqueia o fechamento.
- A F7-03 fecha com Interromper e falar, Encerrar e permissão negada observados no S25 em 2026-11-13 (`docs/fases/F7-03-voz-duplex.md`, seção 5c). Bateria fora do carregador, eco com fone e latência ponta a ponta seguem fora desta decisão, como pela ordem de trabalho da D-050.

## D-063 — Abrir a F15-01 (maquetes) antes do portão da F11 (2026-11-14)
- Contexto: o dono pediu para trabalhar a F15 hoje, antes de fechar o portão da F11. O AC-01 no S25 (alarme às 08h10, tarefa sintética às 08h30) segue pendente em STATE.md. D-062 exige o portão da F11 para começar a fase.
- Decisão:
  - Abrir só a **F15-01** (maquetes do widget e do chat flutuante), documentada em `docs/fases/F15-01-maquetes.md`, com o HTML em `docs/fases/f15-01/maquetes.html`. Estado: REVIEW.
  - Nenhum código de produto da F15 começa antes da escolha do dono entre as opções A (linhas), B (teclas) ou a combinação (teclas no pequeno e linhas no grande).
  - A escolha do dono é a evidência de aceite da F15-01. Sem ela, a F15-01 não vira DONE.
  - O portão da F11 não é dispensado. F15-02 a F15-07 seguem BLOCKED até o portão da F11, como D-062 prevê.
- Limite: o estado da fase não muda para além da F15-01; a estimativa de células é só estimativa, até medir a grade One UI no S25.

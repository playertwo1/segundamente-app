# Estudo — o que a Segunda Mente pode aproveitar do Speakr e do Leon

Data: 2026-11-25. Nada aqui está autorizado para implementação: cada item só abre com decisão do dono e passa antes por [IDEIAS-FUTURAS](../roadmap/IDEIAS-FUTURAS.md). A parte que serve ao Lumen está no repositório dele, em `docs/roadmap/parqueado.md` (seções "Ideias do Speakr" e "Ideias do Leon"). O estudo anterior, do MyBrain, está em [estudo-mybrain.md](estudo-mybrain.md).

---

## Parte 1 — Speakr

### O projeto

[`murtaza-nasir/speakr`](https://github.com/murtaza-nasir/speakr): app web auto-hospedado em Python (Flask), estudado na `master` de 2026-11-24. Grava microfone e som do sistema, recebe arquivos, transcreve com vários motores (WhisperX, OpenAI, Mistral e outros), separa falantes, resume com prompts por pasta ou etiqueta, extrai eventos, conversa sobre uma gravação e pesquisa a biblioteca inteira com um agente que cita a fonte de cada afirmação.

### Licença

AGPL-3.0. A GPL-3.0 da Segunda Mente permite combinar com código AGPL-3.0 (seção 13 das duas licenças), mas a parte vinda do Speakr continua AGPL, com a obrigação extra de oferecer o código a quem usa pela rede. Como a Segunda Mente não é um serviço de rede, na prática pesa pouco. Mesmo assim, o código dele é Python e o daqui é Dart: o reaproveitamento é de ideia. Se algum trecho for traduzido quase linha a linha, registrar no `NOTICE` (Speakr, autor `murtaza-nasir`, AGPL-3.0, arquivo de origem). O CLA do Speakr só vale para quem contribui com ele.

### O que já existe na Segunda Mente (não fazer)

| No Speakr | Na Segunda Mente | Onde |
|---|---|---|
| Conferir se o trecho citado existe no segmento | Já confere nos relatórios: item com segmento desconhecido ou trecho que não está no segmento é descartado | `lib/domain/models/session_report.dart` (`_sourceExcerpt`) |
| Correção de nomes e jargão | Glossário e correção da transcrição depois do reconhecimento | `lib/data/services/glossary_service.dart`, `transcript_correction_service.dart` |
| Importar transcrição com horários | Importa TXT do Gravador Samsung com timestamps | `transcript_import_service.dart` |
| Exportar resumo e relatório | PDF, DOCX e Markdown | `session_report_export_service.dart` |
| Compartilhar do celular para o app | `share_handler` | `pubspec.yaml` |
| Separação de falantes | Já é ideia futura ("Separação de falantes/voiceprint") | IDEIAS-FUTURAS |

### O que pode ser aproveitado

Ordem sugerida, se o dono aprovar: SM-SP1 → SM-SP2 → SM-SP3 → SM-SP4 → SM-SP5 → SM-SP6 → SM-SP7.

#### SM-SP1 — Palavras do glossário no reconhecimento, não só na correção (P)

- **No Speakr:** vocabulário próprio e hotwords puxam o reconhecimento para nomes, siglas e jargão, configuráveis no geral, por pasta ou etiqueta, ou na hora de gravar.
- **Na Segunda Mente hoje:** o glossário corrige o texto **depois** (`transcript_correction_service.dart`). A transcrição pelo modelo remoto usa um prompt fixo, "Transcribe the spoken audio exactly." (`speech_transcription_service.dart`), sem os termos do glossário. O motor local é sherpa-onnx (`pubspec.yaml`).
- **Como seria:**
  - **Remoto:** acrescentar ao prompt da transcrição uma linha com os termos do glossário (por exemplo os 50 mais usados, com limite de tamanho). O áudio já vai ao provedor; os termos são do próprio dono.
  - **Local:** conferir se o modelo do sherpa-onnx usado aceita hotwords (para modelos transdutores há lista de hotwords com `modified_beam_search`). Se aceitar, passar os termos; se não, registrar N/A.
- **Aceite:** 10 gravações sintéticas com nomes e siglas do glossário, contagem de acertos antes e depois, nos dois caminhos.

#### SM-SP2 — Citação verificada também nas respostas do chat (M)

- **No Speakr:** `src/services/citations.py`. O texto vai ao modelo com marcadores de segmento (`[S12 12:34 Dana]`); o modelo cita `[S12 "palavras exatas"]`; o app normaliza e confere se a citação está no segmento. Verificada, vira um chip numerado que abre a gravação **no ponto exato**; não verificada, fica marcada. Funciona também com a resposta chegando aos pedaços. No modo "Inquire" o agente busca, lista e lê várias gravações e cita cada posição.
- **Na Segunda Mente hoje:** os relatórios já verificam trechos. Conferir o que o chat faz quando o agente usa as ferramentas de busca (`lib/agent/built_in_tools/search_event_logs_tool.dart`, `related_sessions_tool.dart`): se a resposta cita de onde tirou cada coisa e se dá para tocar e abrir o registro.
- **Como seria:** reaproveitar a mesma conferência dos relatórios no chat. Cada registro lido pelo agente entra com id e segmentos numerados; a resposta mostra chips `[1]`, `[2]` que abrem o registro no segmento citado; citação não encontrada aparece como "não verificada".
- **Aceite:** testes do parser (citação exata, com espaços e maiúsculas diferentes, segmento inexistente, marcador cortado no streaming). No S25: perguntar algo que está em dois registros e tocar nos dois chips.

#### SM-SP3 — Escolher o que o agente pode ler (P a M)

- **No Speakr:** no modo agente, "você decide o que ele pode ler": transcrições sempre; resumos e notas privadas só se o dono permitir.
- **Na Segunda Mente hoje:** a regra do projeto é "envio remoto só com escolha explícita e prévia do conteúdo" (PROJECT.md, item 7 do MVP). Conferir se o agente do chat respeita um escopo por tipo de dado ou lê tudo que as ferramentas alcançam.
- **Como seria:** um controle nos Ajustes do chat (e um atalho na própria conversa) com o que entra: registros, relatórios, memórias, comentários das personas. Desligado = a ferramenta nem devolve aquele tipo. O padrão é decisão do dono.
- **Aceite:** teste de que a ferramenta de busca não devolve o tipo desligado; no S25, desligar "memórias" e conferir que a resposta não usa nenhuma.

#### SM-SP4 — Aviso de envio sem criptografia para base URL própria (P)

- **No Speakr:** `src/config/outbound_warnings.py` avisa, uma linha por serviço, quando um endereço `http://` aponta para outra máquina (redes privadas incluídas, porque o conteúdo ainda atravessa a rede). Não avisa para `localhost`, `127.0.0.0/8` e `::1`. O aviso nunca mostra caminho, consulta, usuário ou chave.
- **Na Segunda Mente hoje:** o registro de modelos aceita base URL personalizada (PROJECT.md, item 3 do MVP; `lib/data/services/model_list_service.dart`). Um `http://` para outra máquina mandaria conversas e áudio em texto aberto, sem aviso.
- **Como seria:** ao salvar ou testar um provedor com `http://` e host que não seja local, mostrar um aviso no próprio formulário ("o conteúdo vai sem criptografia para este endereço") e pedir confirmação. Nada muda para `https`.
- **Aceite:** testes da regra de host local (localhost, `127.0.0.1`, `::1`, `10.x`, `192.168.x`, nome com ponto) e do aviso no formulário.

#### SM-SP5 — Tocar o áudio a partir da linha da transcrição (M, depende da biblioteca de áudios)

- **No Speakr:** tocar uma linha da transcrição pula o áudio para aquele momento; durante a reprodução a linha atual fica destacada; os chips das citações também começam a tocar no ponto citado.
- **Na Segunda Mente hoje:** os registros guardam segmentos com horários; a biblioteca agregada de áudios foi autorizada pelo D-081. Conferir se o registro mantém o arquivo de áudio original ligado à transcrição.
- **Como seria:** quando o registro tiver áudio, cada segmento vira tocável (pula o player para o horário) e o segmento atual é destacado durante a reprodução. Sem áudio, nada muda.
- **Aceite:** teste de widget do salto para o horário; no S25, uma gravação de 10 minutos tocando a partir do 3º segmento.

#### SM-SP6 — Prazo de guarda do áudio (P a M, com a biblioteca de áudios)

- **No Speakr:** políticas de retenção apagam a gravação depois de N dias, com proteção por gravação e etiquetas que impedem a limpeza.
- **Para a Segunda Mente:** áudio ocupa muito espaço e é o dado mais sensível (voz de terceiros). A ideia é apagar só o **áudio** depois de N dias (escolhido pelo dono, desligado por padrão), mantendo transcrição, relatório e itens derivados, com "manter sempre" por registro.
- **Cuidado:** apagar é irreversível. A spec precisa de aviso antes da primeira limpeza, lista do que será apagado e interação com o backup do Drive (o áudio apagado sai também do próximo backup?).
- **Aceite:** testes com relógio fixo (áudio de 31 dias some com prazo de 30; protegido fica; transcrição sempre fica).

#### SM-SP7 — Relatório com formato + foco combinados (P)

- **No Speakr:** etiquetas com prompt próprio se empilham: primeiro as de formato ("Receita", "Notas de aula"), depois as de foco ("Sem glúten", "Biologia"). A ordem importa.
- **Na Segunda Mente hoje:** o relatório tem tipo selecionável e opção personalizada (PROJECT.md, item 4 do MVP).
- **Como seria:** permitir escolher um tipo de formato e, opcionalmente, um foco salvo (por exemplo "Reunião" + "Só decisões e prazos"), com o prompt final montado nessa ordem e visível antes de gerar.
- **Aceite:** teste do prompt montado e no S25 um relatório com e sem foco.

### Rejeitado (Speakr)

- **Servidor multiusuário, SSO, grupos, compartilhamento interno e links públicos, API REST, webhooks, cotas por usuário e registro de auditoria de admin:** app pessoal de uma pessoa.
- **Separação de falantes e perfis de voz com WhisperX:** precisa de servidor com GPU; no celular não roda. Continua na ideia futura que já existe; se um dia vier, provavelmente pelo PC.
- **Modo anônimo (processar sem salvar):** não resolve a regra de conteúdo confidencial, porque o conteúdo ainda vai ao provedor; a regra daqui é não mandar sem autorização.
- **Pasta vigiada que importa áudio sozinha:** o caminho do celular é o compartilhar; uma pasta vigiada no PC seria assunto da ponte Notetaker do Lumen.

---

## Parte 2 — Leon

### O projeto

[`leon-ai/leon`](https://github.com/leon-ai/leon): assistente pessoal em Node.js/TypeScript (com partes em Python), na reescrita 2.0 (branch `develop`, estudada em 2026-11-25/26). O mapa da arquitetura está em `core/context/ARCHITECTURE.md`. Partes estudadas: laço do agente (`server/src/core/llm-manager/llm-duties/react-llm-duty/`), memória (`server/src/core/memory-manager/`), assistente proativo "Pulse" (`server/src/core/pulse-manager/pulse-manager.ts`) e experiências (`server/src/core/experience-manager/`).

### Licença

MIT ("Copyright (c) 2019-present, Louis Grenard"). Código MIT pode entrar numa obra GPL-3.0, desde que o aviso de copyright vá junto (no `NOTICE` e na tela de licenças). Como o código é TypeScript, o reaproveitamento aqui é de regra e de ideia. Nome, logotipo e personagem do Leon não entram.

### O que já existe na Segunda Mente (não fazer)

| No Leon | Na Segunda Mente | Onde |
|---|---|---|
| Assistente que puxa a conversa, com horário de silêncio | F14: resumo de manhã e de tarde, cobrança de tarefas paradas, sugestões das personas com limite diário, espaçamento de 2 h e silêncio | `docs/roadmap/F14-assistente-ativo.md`, `lib/domain/use_cases/persona_suggestion_governor.dart` |
| Memória que filtra ruído | Agente de memória com política "negar por padrão" (só grava atributos duráveis) | `lib/agent/memory_agent/memory_agent.dart` |
| Compactar contexto longo | Compressores de contexto do super agente e das personas | `lib/agent/memory/*_context_compressor.dart` |
| Interface gerada pelo modelo | UI dinâmica por templates e biblioteca de padrões | `lib/agent/skills/dynamic_timeline_ui/` |

### O que pode ser aproveitado

Ordem sugerida, se o dono aprovar: SM-LE1 (encaixa na validação da F14) → SM-LE2 → SM-LE3 → SM-LE4.

#### SM-LE1 — Regras do Pulse na iniciativa das personas (P a M)

- **No Leon (`pulse-manager.ts`):**
  - no máximo **um** assunto por rodada; cada assunto tem id estável, e o que já foi relatado não se repete;
  - pesquisa só com ferramentas de **leitura** (memória, conversas, contexto, busca); depois, uma decisão separada entre ficar quieto, guardar ou entregar;
  - espera 2 minutos depois de uma conversa ativa antes de agir (`ACTIVE_CONVERSATION_GRACE_MS`);
  - recusa do dono aumenta o silêncio sobre aquele assunto: 1 dia, depois 7, depois 30 (`PULSE_DECLINE_COOLDOWN_MS`); assunto concluído espera 12 h, falha espera 3 h;
  - agenda limitada (até 6 assuntos pendentes), acompanhamento por no máximo 30 dias;
  - quando uma conversa posterior do dono resolve o assunto, ele é arquivado com referência a essa conversa.
- **Na Segunda Mente hoje:** `PersonaSuggestionGovernor` tem limite diário, espaçamento de 2 h e silêncio. Não guarda **qual** sugestão foi recusada, então a mesma ideia pode voltar no dia seguinte, e não há espera depois de uma conversa ativa.
- **Como seria:** dar a cada sugestão uma chave de assunto (por exemplo id da tarefa + tipo de sugestão). Recusar ("agora não", dispensar o cartão) sobe o silêncio daquele assunto para 1, 7 e 30 dias; aceitar ou concluir a tarefa arquiva o assunto. Não sugerir nos 2 minutos seguintes a uma conversa. O limite diário e o horário de silêncio continuam valendo por cima.
- **Aceite:** testes com relógio fixo no `PersonaSuggestionGovernor` (ou numa classe nova ao lado): recusa 1 → nada por 24 h; recusa 2 → nada por 7 dias; tarefa concluída → assunto arquivado; conversa há 1 minuto → nada. No S25: recusar a mesma sugestão e conferir que ela não volta no dia seguinte.

#### SM-LE2 — Correção de memória que não deixa o velho vencer o novo (M)

- **No Leon:** a extração em segundo plano compara cada fato novo com um conjunto limitado de registros relevantes e reconcilia: uma correção atualiza o registro, e uma substituição mais velha que o registro atual é **rejeitada**. A extração junta até 3 turnos por conversa; quando o dono pede explicitamente para lembrar, a gravação termina antes da resposta.
- **Na Segunda Mente hoje:** o agente de memória só acrescenta (`append_memories`), com a política de negar por padrão. Conferir o que acontece quando um fato muda (o dono mudou de cidade, de cargo, de preferência): os dois ficam e o modelo escolhe?
- **Como seria:** antes de acrescentar, buscar as memórias parecidas (pelo índice que já existe) e oferecer ao agente `update_memory` além de `append_memories`, com a data de cada memória; uma atualização com data anterior à da memória atual é recusada. Toda mudança fica com histórico (o dono vê o antes e o depois).
- **Aceite:** testes com memórias sintéticas: fato novo substitui o antigo; fato antigo reimportado não substitui o novo; o histórico guarda as duas versões.

#### SM-LE3 — Perfil do dono num documento legível e editável (M)

- **No Leon:** `OWNER.md` é o perfil canônico do dono, curado a partir das conversas relevantes; o resto da memória é a lembrança mais ampla. O dono pode ler e corrigir esse arquivo.
- **Na Segunda Mente hoje:** as memórias existem como registros; conferir se há uma tela que mostra "o que o app sabe de mim" num texto só.
- **Como seria:** uma página "Meu perfil" (Markdown) gerada a partir das memórias duráveis, editável pelo dono; a edição vira a fonte da verdade para o agente. Combina com a regra "nada escondido".
- **Aceite:** editar uma linha no S25 e ver o agente usar a versão editada na conversa seguinte.

#### SM-LE4 — Pausa para perguntar sem perder o que já foi feito (P a M)

- **No Leon:** quando falta informação, o laço pausa guardando plano, observações e estado; a resposta do dono retoma a mesma tarefa sem refazer passos.
- **Na Segunda Mente hoje:** conferir como o super agente lida com uma pergunta no meio de uma tarefa com várias ferramentas (por exemplo montar um relatório e perguntar qual tipo).
- **Como seria:** uma ferramenta `ask_owner` que encerra o turno como "aguardando resposta" e guarda as observações; a próxima mensagem retoma o mesmo plano.
- **Aceite:** teste com modelo falso que pergunta no passo 2 e termina depois da resposta sem repetir o passo 1.

### Rejeitado (Leon)

- **Telemetria:** o Leon vem com `telemetry_enabled: true` no `config.sample.yml`. A Segunda Mente não coleta nada.
- **Experiências aprendidas sozinhas** (procedimentos salvos como `SKILL.md` depois de cada turno): grava comportamento sem aprovação do dono.
- **Shell, computer use (Cua), navegador (Browser Use) e Satellite:** são do lado do PC; no ecossistema daqui isso é papel do Lumen, que já recusou ou escolheu outro caminho.
- **Interface gerada em HTML/JavaScript (Aurora):** a Segunda Mente já gera UI por templates (`dynamic_timeline_ui`), que é mais seguro; não trocar.
- **Modelo local escolhido pela memória disponível (llmfit, llama.cpp):** a questão do modelo local está na F7-02 (adiada, D-041).
- **Humor do assistente influenciado pelo clima ("Vibes") e diário interno do assistente:** exige serviço de clima e não ajuda nas tarefas do dono; as personas já têm personalidade própria.

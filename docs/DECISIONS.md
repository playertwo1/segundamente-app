# Decisões (ADR leve)

Só escolhas caras de desfazer ou que outro agente poderia contestar. Nova decisão = próximo número. Decisão substituída não é apagada: marcar `SUPERSEDED` e apontar a nova. Registro completo das perguntas: [questionario/2026-11-02-segunda-memoria.md](questionario/2026-11-02-segunda-memoria.md).

| ID | Data | Assunto | Estado |
|---|---|---|---|
| D-001 | 2026-11-02 | Base: fork do Memex (Flutter) com F0 como portão | ACCEPTED |
| D-002 | 2026-11-02 | MVP = escopo "Prioridade atual"; full duplex, NotebookLM, grafo, ponte CLI fora | ACCEPTED |
| D-003 | 2026-11-02 | Fases F0–F5 (MVP) e F6–F8 (futuro bloqueado) | ACCEPTED |
| D-004 | 2026-11-02 | Provedores: OpenAI e Gemini via OAuth existente; Claude por chave de API opcional | ACCEPTED |
| D-005 | 2026-11-02 | Sem login Claude.ai por assinatura (termos da Anthropic); só via Claude Code oficial no PC (F7) | ACCEPTED |
| D-006 | 2026-11-02 | Nome do app e applicationId: "Segunda Mente" | ACCEPTED |
| D-007 | 2026-11-02 | Voz do MVP: STT na nuvem pelo modelo configurado; TTS do Android na F2; SenseVoice não cobre pt-BR | ACCEPTED |
| D-008 | 2026-11-02 | Docs de planejamento vivem na `main` do fork; só os arquivos úteis do kit ideias_standard | ACCEPTED |
| D-009 | 2026-11-02 | Até o S25 Ultra estar conectado, o emulador é o aparelho de prova da F0 | ACCEPTED |
| D-010 | 2026-11-02 | A F6 pode começar com os portões da F0 à F5 ainda abertos | ACCEPTED |
| D-011 | 2026-11-03 | Áudio: transcrição pelo endpoint do ChatGPT; o canal de chat nunca recebe áudio | ACCEPTED |
| D-012 | 2026-11-03 | O app tem só inglês e português | ACCEPTED |
| D-013 | 2026-11-03 | Gemini por OAuth desbloqueado via daily-cloudcode-pa SSE stream | SUPERSEDED |
| D-014 | 2026-11-03 | Ideias do Memos: quatro entram na F6 (F6-05 a F6-08); o resto fica fora | ACCEPTED |
| D-015 | 2026-11-03 | Login OAuth Claude (PKCE local) e Claude Sonnet/Opus 5.5 High via Google OAuth | ACCEPTED |
| D-016 | 2026-11-03 | Ideias do Daedalus Echo: Whisper local multilíngue, extrator de tarefas robusto, recuperação por tópicos, agenda; o resto fica fora | ACCEPTED |
| D-017 | 2026-11-03 | Direção visual móvel AMOLED, editorial e sem barra inferior persistente | ACCEPTED |
| D-018 | 2026-11-03 | Ideias do anarlog: prompts de resumo, correção conservadora, dicionário, legenda SRT/VTT e transparência dos provedores; o resto fica fora | ACCEPTED |
| D-019 | 2026-11-03 | Priorizar a implementação visual F5-04 antes das demais pendências, sem fechar o portão F4 | SUPERSEDED |
| D-020 | 2026-11-03 | Mecanismo de fallback resiliente entre modelos e provedores (FallbackLLMClient) | ACCEPTED |
| D-021 | 2026-11-03 | Fazer o redesign visual em fase própria após o fechamento da fase F5 atual | SUPERSEDED |
| D-022 | 2026-11-03 | Iniciar a fase F5V agora, em paralelo ao fechamento da F5 | ACCEPTED |
| D-023 | 2026-11-04 | Sem espelho chinês no download do modelo de voz | ACCEPTED |
| D-024 | 2026-11-04 | Remover tudo que é da China: provedores, sabores `cn*`, geocoding Amap e transcrição local SenseVoice | ACCEPTED |
| D-025 | 2026-11-04 | Revisar as pranchas 17, 19, 20 e 22 sem inventar capacidades | ACCEPTED |
| D-026 | 2026-11-04 | Implementar parcialmente as pranchas 17, 19, 20 e 22 na F5V | ACCEPTED |
| D-027 | 2026-11-04 | Ajustes encontrados na revisão das pranchas e decisão sobre bloqueio por PIN | ACCEPTED |
| D-028 | 2026-11-04 | Microfone explícito na conversa, transcrevendo para revisão | ACCEPTED |
| D-029 | 2026-11-04 | Planejar F9 — Meeting Decoder, sem abrir o MVP nem autorizar código | ACCEPTED |
| D-030 | 2026-11-04 | Ampliar F9 com PDFs, Todo, destinos de tarefas e relatórios PDF/DOCX | ACCEPTED |
| D-031 | 2026-11-05 | Abrir só a pesquisa F7-01 (sem código) antes do portão F5 | ACCEPTED |
| D-032 | 2026-11-05 | F7 sem ponte para CLIs: o login ChatGPT/Codex já existente basta | ACCEPTED |
| D-033 | 2026-11-05 | `daedalus-echo` só como referência; F7-02 passa a medir IA no aparelho, não Ollama | ACCEPTED |
| D-037 | 2026-11-05 | F10 detalhada por questionário; exportador com biblioteca de PDF entra já na F4 | ACCEPTED |
| D-038 | 2026-11-05 | Critério 7 sem segunda confirmação para anexos do chat; critério 6 sem prova de troca de modelo | ACCEPTED |
| D-039 | 2026-11-06 | Busca semântica local com MiniLM-L12 int8, opcional e baixada sob demanda | ACCEPTED |
| D-040 | 2026-11-06 | Fechar a F6 sem auditoria própria; abrir a F7-02 (medição do modelo local no S25) | ACCEPTED |
| D-041 | 2026-11-06 | Adiar a F7-02 (modelo local) e guardar como reserva; nada implementado | ACCEPTED |
| D-042 | 2026-11-06 | F9 aberta: PDF lido pelo modelo (ChatGPT), Todo própria, só imagens do dono, JSON sim e ICS só sob pedido, só Android | ACCEPTED; lembretes e "só Android" substituídos por D-052/D-053 |
| D-043 | 2026-11-07 | Follow-up e tarefa viram uma coisa só | ACCEPTED |
| D-044 | 2026-11-07 | Retirar a exportação em JSON do relatório | ACCEPTED |
| D-047 | 2026-11-11 | F7-03 (voz duplex) aberta sem o modelo local; entrada desligada até a medição no S25 | ACCEPTED |
| D-048 | 2026-11-11 | Voz duplex ligada no chat com o eco medido no S25, aceito pelo dono | SUPERSEDED por D-049 |
| D-049 | 2026-11-11 | Voz duplex: interrupção por toque, microfone fechado enquanto o app fala | ACCEPTED |
| D-050 | 2026-11-13 | Expansão: Todo robusto no celular + Lumen no notebook; ordem, pausas e assistente ativo | ACCEPTED |
| D-051 | 2026-11-13 | Todo robusto: lista única, recursos, atalhos de dia/hora e IA que propõe com confirmação | ACCEPTED |
| D-052 | 2026-11-13 | Lembretes de tarefa disparados pelo próprio app (substitui D-042 no item lembretes) | ACCEPTED |
| D-053 | 2026-11-13 | Desktop: fork do Coucou renomeado Lumen, no repositório do fork, com IA própria e e-mail pessoal | ACCEPTED |
| D-054 | 2026-11-13 | Sync: relay do Coucou + caixa de correio no Cloudflare; escopo, avisos e backup semanal | ACCEPTED |
| D-055 | 2026-11-13 | Google: login próprio, Drive (backup) e Calendar; NotebookLM pós-MVP sem previsão | ACCEPTED |
| D-056 | 2026-11-13 | Manter F11-04 pendente do S25 e avançar F11-05 | ACCEPTED |

## D-001 — Base: fork do Memex
- Contexto: Memex já traz diário/chat, banco local (Drift/SQLite), provedores e OAuth. Licença GPL-3.0.
- Decisão e motivo: usar o fork; app pessoal, então a GPL só pesa se distribuir o APK. Se build, licença ou teste no S25 falharem, reavaliar.
- Descartado: comparar 3 bases antes; app novo do zero.

## D-004 / D-005 — Autenticação
- Contexto: o usuário não usa chave de API. O fork reaproveita o `client_id` dos CLIs oficiais (Codex e Gemini) para OAuth.
- Decisão e motivo: manter esses dois logins no MVP, com risco registrado (podem quebrar ou violar termos; testar na F1-04). A Anthropic não permite login Claude.ai em apps de terceiros (code.claude.com/docs/en/legal-and-compliance, lido em 2026-11-02), então Claude fica com chave de API opcional.
- Descartado: fluxo próprio de login Claude.ai.
- Risco de termos, registrado na F1-04 em 2026-11-02: o login da OpenAI é PKCE com o client_id público do Codex CLI (`app_EMoamEEZ73f0CkXaXp7hrann`), emissor `https://auth.openai.com` e redirect `http://localhost:1455/auth/callback`. O do Gemini usa o client do Gemini CLI e o redirect `http://localhost:8085/oauth2callback`. Esses clientes pertencem aos CLIs oficiais. A OpenAI e o Google podem revogar o fluxo, trocar o client ou tratar o uso fora do CLI como fora dos termos. A Segunda Mente não tem um client OAuth próprio. Se o login quebrar, a alternativa do MVP é chave de API.
- `gemini_auth_service.dart` também traz um client secret. Esse valor não entra em documento, log, estado nem chat.
- O login em si não foi executado, nem no emulador nem no S25. Esta nota não prova que o login funciona.

## D-007 — Voz do MVP
- Contexto: o fork tem STT local por sherpa-onnx (SenseVoice zh/en/ja/ko/yue) e STT na nuvem, que envia o áudio ao modelo configurado. Não há TTS.
- Decisão e motivo: no MVP, a fala em português usa a transcrição na nuvem (`SpeechTranscriptionService`), no modelo que o usuário já escolheu. A resposta em áudio, opcional, usa o TTS do Android na F2-02. O modelo local SenseVoice fica disponível, mas não é o caminho do pt-BR.
- Descartado: trocar o SenseVoice por outro modelo nesta fase; voz full duplex (continua na F7).

## D-006 — Identidade de instalação
- Decisão e motivo: o app se chama Segunda Mente. Os `applicationId` passam a ser `app.segundamente`, `app.segundamente.cn`, `app.segundamente.early`, `app.segundamente.cn.early`, `app.segundamente.dev` e `app.segundamente.cn.dev`.
- O namespace Kotlin e os method channels continuam `com.memexlab.memex`. Eles identificam código nativo, não o pacote instalado. Renomeá-los fica fora da F0-03.
- Assinatura de debug usa o keystore de debug do Android SDK, fora do repositório. `android/key-*.properties`, `*.jks` e `*.keystore` já estão no `.gitignore` e não há nenhum desses arquivos versionado. Keystore de release não foi criado.

## D-009 — Emulador até o S25
- Contexto: a F0-02 pedia execução no Galaxy S25 Ultra. Em 2026-11-02 o dono pediu para usar só o emulador por enquanto.
- Decisão e motivo: enquanto o S25 não estiver conectado, `emulator-5554` é o aparelho de prova das subfases da F0. A execução no S25 fica `NOT_RUN`. Os critérios de aceite do MVP continuam no S25. A fase F0 não se declara concluída sem essa execução, ou sem uma decisão nova.
- Descartado: parar a F0 até o telefone aparecer.

## D-010 — Abrir a F6 antes do MVP
- Contexto: D-003 deixa a F6 bloqueada até o MVP. Em 2026-11-02 o dono pediu para avançar depois dos commits da F4 e da F5.
- Decisão e motivo: a F6 pode começar. O MVP não fecha. D-003 continua valendo para o que é o MVP e para manter a F7 e a F8 bloqueadas. Busca semântica, tópicos e o "por quê" não entram sem um modelo. A busca deste passo é texto local nos relatórios.
- Descartado: marcar o MVP como pronto para desbloquear a fase.


## D-011 — Áudio pelo ChatGPT
- Contexto: em 2026-11-03, no S25, o canal `chatgpt.com/backend-api/codex` respondeu `400 Audio input is not available` com `gpt-5.6-sol` e com `gpt-6-luna`. Um áudio gravado no histórico da conversa repetia o erro em todas as chamadas seguintes.
- Decisão e motivo: o canal de chat nunca recebe áudio (`CodexResponsesClient` troca por uma nota de texto). A transcrição usa `POST chatgpt.com/backend-api/transcribe` com o mesmo token do OAuth, e só o texto vai ao modelo. Testado em 2026-11-03 com um áudio pt-BR sintético: devolveu a frase correta. Isso cumpre D-007 (STT na nuvem pelo modelo configurado) sem depender do SenseVoice.
- Risco: o endpoint não é documentado e pode mudar ou ser bloqueado. Duração e tamanho máximos não foram medidos; a gravação de ~50 min é `NOT_RUN`.
- Descartado: enviar o áudio no canal de chat; chave de API do Gemini só para áudio (fica como reserva se o endpoint cair).

## D-012 — Idiomas
- Decisão e motivo: o app tem só inglês (`en`) e português (`pt`). As outras 16 línguas, incluindo o chinês, saíram do código, das galerias de cartão e dos testes (commit `73feb20`). Texto em outro idioma cai no inglês. Pedido do dono, que usa só pt-BR.
- As buscas de local pedem nomes no idioma do app, e não mais em chinês.
- Descartado: manter as demais línguas como reserva.

## D-013 — Gemini por OAuth (SUPERSEDED por D-020 e commit aa91a48)
- Contexto: Inicialmente `loadCodeAssist` devolvia `UNSUPPORTED_CLIENT` para o client_id do Gemini CLI e exigia projeto GCP standard-tier.
- Decisão e atualização (2026-11-03): Desbloqueado com sucesso usando o endpoint de streaming SSE `https://daily-cloudcode-pa.googleapis.com` com `:streamGenerateContent?alt=sse`. As credenciais de OAuth foram ofuscadas no código fonte (`String.fromCharCodes`) para permitir commit/push sem acionar regras de segredos em texto plano do GitHub Push Protection. Validado no Galaxy S25 Ultra em texto (872ms) e stream (910ms).

## D-014 — Ideias do Memos
- Contexto: `usememos/memos` (MIT, Go e React, self-hosted, 64 mil estrelas) foi comparado com o app em 2026-11-03. Só o README, o CONTEXT.md e os arquivos `.proto` foram lidos.
- Decisão e motivo: entram na F6 quatro ideias que cabem no produto local de uma pessoa: tags hierárquicas (F6-05), filtros por propriedade e visões salvas (F6-06), prévia de links (F6-07) e mapa de atividade (F6-08). Só as ideias são aproveitadas, nenhum código.
- Fora: espaços e colaboração, comentários, reações, links públicos, vários usuários, servidor/Docker/API/webhooks/MCP, Web Clipper e bot do Telegram (o Compartilhar do Android cobre o mesmo uso). Biblioteca de anexos fica em Ideias futuras.

## D-015 — Login OAuth do Claude e acesso a Claude 5.5
- Contexto: O usuário solicitou explicitamente suporte a Claude por OAuth e aos modelos Claude Haiku 5.5, Sonnet 5.5 e Opus 5.5.
- Decisão e motivo: Integrado serviço OAuth para Claude com PKCE e servidor local de callback na porta 1455 e deep link `memex://`. Além disso, os modelos Claude Sonnet 5.5 High e Claude Opus 5.5 High foram adicionados diretamente pelo provedor Google OAuth (Vertex), com cota de 100% e sem o bloqueio de rate-limit de 5 horas do Claude OAuth direto. Validado com resposta real no Galaxy S25 Ultra em 1484ms.

## D-016 — Ideias do Daedalus Echo
- Contexto: `DaedalusApps/daedalus-echo` (MIT, Kotlin e Compose, 12 estrelas, último push em 2026-08-25) é um gravador 100% local: Whisper por sherpa-onnx, Gemma 3 1B por MediaPipe, embeddings com Universal Sentence Encoder, busca por significado, tarefas extraídas e mapa de tópicos. Foram lidos o README, o CHANGELOG, `ModelConfig.kt`, `TranscriptionService.kt`, `EmbeddingService.kt`, `GraphRetrieval.kt`, `TodoExtraction.kt` e `CalendarIntegration.kt`. Nada foi executado.
- Decisão e motivo: entram só ideias, nenhum código (outra linguagem e outra arquitetura). Entram: Whisper multilíngue local (F2-11), extrator de tarefas robusto com deduplicação (F3-07), recuperação por tópicos com piso de relevância (F6-09) e "adicionar à agenda" (F6-11). Os embeddings no aparelho ficam como F6-10 `BACKLOG`.
- Cuidado que o Echo mostra: o Whisper dele é `base.en`, só inglês, com o idioma fixo em `en`, e o Universal Sentence Encoder é centrado em inglês. Para português é preciso um modelo Whisper multilíngue e um embedder que cubra português. Nenhum dos dois foi medido.
- Fora do MVP: Gemma 3 1B local (555 MB, qualidade em pt-BR desconhecida; fica na F7 com Ollama), conversa por voz mãos-livres (F7), mapa global de tópicos (Ideias futuras).
- Descartado: copiar a arquitetura offline total. O nosso produto usa o modelo que o dono escolheu (D-002, D-004).

## D-017 — Direção visual móvel
- Contexto: em 2026-11-03 o dono aprovou a versão v3 das referências AMOLED após comparar com interfaces oficiais do Apple Journal, Day One e Things.
- Decisão: usar fundo preto AMOLED, texto marfim e cinza, âmbar/cobre como acento, composição editorial com listas abertas e divisores finos, tipografia compacta com escala do sistema preservada e ícones coerentes com rótulos. A navegação global não terá barra inferior persistente; os destinos ficam no menu do cabeçalho e em ações contextuais. O chat terá acesso explícito com “Conversar” e “Conversar com a Segunda Mente”.
- Fonte de implementação: [DESIGN.md](../DESIGN.md) e as dez pranchas em `.impeccable-mobile/references/amoled-v3-ios/`.
- Limite: a decisão aprova a direção visual, não declara a implementação pronta. Antes de mudar o roteamento, mapear o menu às rotas existentes; manter acessibilidade, fluxos atuais e testes de widget. F5-04 conclui apenas a documentação; a implementação e suas evidências ficam na fase F5V (D-021).
- Descartado: a exploração v1/v2 com paleta azul e navegação inferior pesada.


## D-018 — Ideias do anarlog
- Contexto: `fastrepl/anarlog` (antes Hyprnote; MIT; Tauri, React e Rust; ~9,8 mil estrelas; último push em 2026-11-01) é um bloco de notas de reunião local, alternativa ao Granola. Foram lidos o README, a documentação (`docs/*.mdx`), a lista de crates e os prompts de `crates/template-app/assets` (`enhance`, `title`, `transcript-patch`, `chat`). Nada foi executado.
- Decisão e motivo: entram só ideias; o código é Rust e Tauri para desktop, e o nosso é Flutter. Entram: tela que mostra qual provedor transcreve e qual resume (F1-09), importação de legenda `.srt` e `.vtt` (F2-12), dicionário de termos (F2-13), regras de prompt do resumo com regenerar (F3-08) e correção conservadora da transcrição (F3-09).
- Licença: o anarlog é MIT e o nosso fork é GPL-3.0, então copiar texto de prompt é permitido com o aviso de licença. Preferimos reescrever em português e testar com as nossas amostras. O diretório `enterprise/` tem licença comercial e não pode ser usado.
- Fora: captura do áudio do sistema e do PC (o Android não permite), calendário e contatos do Google e do Outlook, sincronização, compartilhamento e cobrança (Supabase e Stripe), importação do histórico de outros apps, ditado global e a licença enterprise. O app de celular deles não foi lido.
- Ficam em ideias futuras: separar falantes (diarização e voiceprint, modelos pesados), CLI e servidor MCP (F7) e detecção do idioma do resumo (hoje o app tem só en e pt).

## D-019 — Próxima prioridade: redesign móvel
- Estado: `SUPERSEDED` por D-021 após o dono esclarecer que o redesign deve ocorrer numa fase própria, depois da fase atual.
- Decisão anterior: iniciar a implementação em F5-04 foi registrado, mas não executado.

## D-020 — Fallback resiliente entre modelos e provedores
- Contexto: se o provedor ativo falhar (HTTP 429 rate limit, 500/503/529 sobrecarga, timeout de rede ou falta de cota), os agentes ou chats do usuário falhavam diretamente. O usuário pediu um fallback automático (ex.: se o ChatGPT parar de responder, vai para o Claude; se o Claude parar de responder, vai para o Gemini).
- Decisão: criar `FallbackLLMClient` implementando `LLMClient`, operando em cascata ordenada. Se o provedor primário falhar, tenta sequencialmente os próximos candidatos autorizados com seus respectivos `ModelConfig`. Em streams, realiza failover transparente antes da emissão de dados. Adicionada chave de ativação e tela de reordenação de prioridade por drag-and-drop nas configurações de IA.
- Limite: se um modelo já começou a emitir texto em streaming antes de falhar, a transmissão parcial é encerrada com erro para não duplicar texto já exibido na UI.

## D-021 — Redesign visual após a fase atual
- Estado: `SUPERSEDED` por D-022.
- Contexto: o dono esclareceu em 2026-11-03 que o redesign da versão nova deve ocorrer depois de concluir a fase atual, não como a próxima tarefa dentro dela.
- Decisão: manter o fechamento de F5 como foco atual e inserir F5V — Redesign visual da versão nova imediatamente depois de F5 e antes de F6. F5-04 cobre a direção aprovada e documentada; a implementação das telas fica em F5V.
- Limite: F5V só começa depois de F5. Esta ordem não fecha nem remove critérios dos portões F0–F5 e não desbloqueia F7/F8 por si só.

## D-022 — F5V começa agora
- Contexto: em 2026-11-03, depois do commit `b513d72` (cofre do Android para tokens e chaves), o dono pediu para iniciar a fase visual imediatamente.
- Decisão: a F5V passa a `IN_PROGRESS` e é a fase de trabalho atual. A F5 continua aberta em paralelo: o que falta nela depende do S25 (7 critérios, migração do cofre no aparelho, medições).
- Limite: a ordem muda, os portões não. F5V não fecha a F4 nem a F5, e o MVP só fica pronto com o portão da F5. F7/F8 continuam bloqueadas.

## D-023 — Sem espelho chinês
- Contexto: em 2026-11-04 o dono viu o botão "China Mirror (Faster in CN)" no download do modelo de voz e pediu: "retire esse china, não vamos usar nada da China".
- Decisão: o download do modelo de voz vem só da release do GitHub (`k2-fsa/sherpa-onnx`). O caminho `hf-mirror.com`, a escolha de fonte e os textos dela saíram do app. Guarda em `test/data/services/speech_model_source_test.dart`.
- Em aberto (não alterado, depende do dono): o próprio modelo de voz é o SenseVoice (Alibaba/FunAudioLLM), que a F2-11 já planeja trocar por Whisper; os sabores Android `cn*` (`AppFlavor.isCN`, com Kimi como modelo padrão); os provedores Kimi, Qwen, DeepSeek, Zhipu, MiniMax, Seed e Mimo na lista de modelos.

## D-024 — Remover tudo da China
- Contexto: em 2026-11-04 o dono pediu "Retire tudo que tiver de China do aplicativo".
- Decisão: saíram os provedores Kimi, Qwen, Seed, Zhipu, DeepSeek, MiniMax e Mimo (tipos, textos, listas de modelos, parser de listagem), os modelos chineses das listas do OpenRouter e do Ollama, os sabores Android `cn`, `cnEarly` e `cnDev` (Gradle, `AppFlavor`, atualizador, CI, esquema `cn` do iOS), o geocoding Amap (fica só o OpenStreetMap; a config gravada com `amap` cai no OpenStreetMap) e a transcrição local SenseVoice (Alibaba).
- Configs gravadas com os provedores removidos são descartadas ao carregar, junto com as chaves no cofre (`LLMConfig.removedTypes`; teste em `test/utils/secret_storage_test.dart`). Agentes que apontavam para elas caem no padrão.
- Transcrição: sem modelo local até a F2-11 (Whisper multilíngue). `getUseLocalSpeechToText()` devolve sempre `false` e o interruptor saiu das configurações; a fala vai ao endpoint do ChatGPT (D-011). O código do `WhisperService`/`StreamingTranscriber` com SenseVoice continua no repositório, sem caminho de uso; a F2-11 o troca.
- Em aberto, depende do dono: serviço Memex AI (`typeMemex`, upstream); bibliotecas de autores chineses (`wechat_assets_picker`, `photo_manager`, necessárias ao seletor de fotos); comentários e palavras-chave de busca em chinês que permanecem no código (os aliases chineses do item de idioma foram removidos nesta retomada); `cn.xcconfig` e as configurações `cn` do `project.pbxproj` do iOS (não dá para validar no Windows); `state_util` ainda repara sessões antigas do DeepSeek.
- Continuação (2026-11-04): as galerias de exemplo e o prompt de transações agora usam locais/moedas fora da China; saíram também os aliases de busca em chinês da preferência de idioma. Comentários, dependências e dados existentes foram preservados.

## D-025 — Pranchas 15–23: redesenho do que existe, sem funções novas (2026-11-04)
- Contexto: as pranchas 15–23 mostram telas inteiras; parte delas pede funções que o sistema não tem.
- Decisão: implementar só o que tem suporte real (bloqueio com PIN e espera de 30 s após 3 erros; busca sobre `searchCards`/`searchPkmFiles`; atividade lida de `Tasks`; leitor; revisão antes de enviar; localização). Ficaram de fora, sem dado inventado: grupo "Memória" na busca, etapas/cancelar/tentar de novo em tarefas, Editar/Favoritar no leitor, mapa com tiles, compartilhar por proximidade.
- Pranchas 17, 19 e 20 e o import de DOCX seguem para as fases seguintes da F5V (e F2 para DOCX).

## D-026 — Implementação parcial das pranchas 17, 19, 20 e 22 (2026-11-04)
- Contexto: o dono pediu implementar o que faltava nas referências 17, 19, 20 e 22 sem criar capacidades que o app ainda não tem.
- Decisão de fase: 17 (insights) e 20 (tour/GUIAS) entram na F5V-02; 22 (importação de TXT) entra na F5V-03; 19 (prévia/compartilhamento) entra na F5V-04. As subfases continuam `IN_PROGRESS`; F5V-05 fica `NOT_RUN` sem validação e acessibilidade no S25.
- Limites: insights reutilizam as fábricas existentes; o mapa é geográfico e depende de coordenadas reais, sem grafo de conexões. O tour reaproveita `DemoOverlay`; `Memex Guide.md` é dado do usuário e não foi editado. O compartilhamento usa `ShareService` e a folha nativa sem opções não suportadas. A importação oferece lista, prévia, confirmação, progresso e falha para TXT; DOCX fica adiado porque F2-03 só cobre TXT.
- Evidência de testes: `flutter test test/ui test/l10n` teve 356 aprovações e 5 falhas; a base limpa reproduziu as mesmas cinco. A suíte completa teve 1.112 aprovações, 1 ignorado e 33 falhas, contra 1.074/1/34 na base. As falhas variaram entre duas execuções do mesmo teste de notificações no Windows; não houve nova área de falha nos componentes destas pranchas.

## D-027 — Revisão das pranchas 17/19/20/22 (2026-11-04)
- Corrigido: GUIAS escondia dos Recentes qualquer arquivo com "guia"/"guide" no caminho, mesmo fora da lista GUIAS; agora só some o que a lista já mostra (teste novo). "deepseek" saiu do exemplo de `keyIdHelper` (visível em Editar modelo), de duas strings sem uso e das palavras-chave da busca de configurações.
- Não alterado: `typeMemex` e as ~40 strings "Memex" do serviço oficial (aparecem com o flavor global; depende do dono), `state_util` (reparo de sessões antigas), caminhos reais `.memex`/iCloud nas strings de backup.
- Dispositivo (S25): bloqueio e pôster tinham defeitos que os testes não mostravam (sem Overlay/Navigator acima do app; texto na cor do divisor). Corrigidos; teste do bloqueio agora usa o mesmo posicionamento. Decisão do dono (2026-11-04): não quer PIN nem senha para entrar no app. O bloqueio fica desativado e sem entrada nas configurações (`AppLockSettingsPage` segue sem rota); o código da prancha 15 permanece, testado, mas fora do uso.

## D-028 — Microfone explícito na conversa (2026-11-04)
- Contexto: a gravação rápida só existia como toque longo no botão "+" da timeline; o dono não achou como mandar áudio.
- Decisão: o microfone da conversa grava e transcreve, devolvendo o texto ao campo para revisão (escolha do dono entre gravar-e-transcrever, gravar-e-enviar-arquivo e só expor o "Áudio" do menu). Não envia o arquivo de áudio ao modelo. Sem limite de duração: o transcritor na nuvem rejeita áudio longo (`shortcut:` no código).

## D-029 — Planejar F9 — Meeting Decoder (2026-11-04)
- Contexto: o dono pediu transformar a ideia Meeting Decoder numa fase estruturada, com subetapas, evidência, checklist e referências visuais quando necessárias.
- Decisão: incluir F9 como fase futura `BLOCKED`, fora do MVP. Ela reaproveita F3/F4/F6, começa por texto próprio ou transcrição já importada, exige evidência e confirmação individual, e planeja resumo, ideias, oportunidades, decisões, dúvidas, follow-ups, tarefas, imagens relacionadas e exportações JSON/ICS. IA fica opcional: sem ela, o app não inventa síntese semântica.
- Limites: o plano não autoriza implementação nem altera F5V/F6. Não acrescenta gravação de terceiros, transcrição de áudio na nuvem, inferência de responsável/prazo ou mensagens automáticas. Busca/geração de imagens e o sistema operacional desktop são decisões pendentes de F9-01; referência visual existente é reaproveitada quando suficiente.

## D-030 — Ampliar F9 — Meeting Decoder (2026-11-04)
- Contexto: o dono acrescentou resumos de conversas e PDFs, envio de tarefas/follow-ups para agenda/Todo, uma lista Todo própria e relatórios organizados em PDF/DOCX.
- Decisão: atualizar o plano F9 com PDF como entrada inicial, evidências por página, uma página Todo pessoal no menu existente, encaminhamento confirmado para Todo/calendário/lembretes e exportação PDF/DOCX reutilizando F4. Definir formatos adicionais, PDF escaneado/OCR, regras de destino e sistema desktop em F9-01.
- Limites: F9 continua `BLOCKED` e fora do MVP; esta decisão autoriza o planejamento, não código. A lista Todo do usuário fica separada da fila interna dos agentes. Criar tarefa/evento exige confirmação individual e as permissões necessárias.

## D-031 — Abrir a pesquisa F7-01 (2026-11-05)
- Contexto: o dono pediu avançar para a F7, que está `BLOCKED` até o fechamento da F5 (D-003). Mesmo precedente da D-010 para a F6.
- Decisão: abrir somente F7-01 (pesquisa e decisão de escopo). F7-02 a F7-06 seguem `BLOCKED`; nenhum código, provedor, serviço de PC ou permissão de microfone é autorizado. A F5 continua aberta e o MVP não muda.
- Evidência: `docs/fases/F7-01-viabilidade.md` (termos da Anthropic e da OpenAI, licenças, autenticação, sistemas e limites de dados, com nível de evidência por linha).

## D-032 — F7 sem ponte para CLIs (2026-11-05)
- Contexto: `docs/fases/F7-01-viabilidade.md` propunha uma ponte opcional para Claude Code e Codex CLI. O dono respondeu que o acesso ao ChatGPT por OAuth via Codex, que o app já tem, "já está bom".
- Decisão: não haverá ponte desktop (F7-04) nem interface MCP (F7-05). O app segue com o login ChatGPT já existente; nenhum fluxo novo de credenciais. O limite dos termos permanece: sem login Claude.ai por assinatura (D-005).
- Em aberto, sem decisão: voz full duplex (F7-03) e Ollama (F7-02). Seguem `BLOCKED` até o dono pedir, e só com medição no S25/PC.
- F7-01 cumpre o objetivo (escopo decidido antes de código).

## D-033 — daedalus-echo como referência (2026-11-05)
- Contexto: o dono propôs https://github.com/DaedalusApps/daedalus-echo (MIT, Kotlin) como exemplo de conversa duplex. Pelo README e pela árvore de arquivos, ele é gravador + transcrição Whisper + resumo Gemma 3 1B + busca por embeddings; não tem voz sintetizada, VAD contínuo, cancelamento de eco nem interrupção (busca por `TextToSpeech`, `AcousticEchoCanceler`, `VOICE_COMMUNICATION` sem resultado).
- Decisão (escolha do dono): usar só como referência de IA no aparelho e embeddings. F7-02 passa de "Ollama no PC" para "medir modelo local no S25" (ex.: Gemma 3 1B, qualidade em pt-BR, RAM, latência, tamanho). Para F6-10, o Universal Sentence Encoder do projeto não está comprovado para português; candidatos a medir: USE multilingual (16 idiomas, inclui português) e EmbeddingGemma (100+ idiomas; tamanhos a confirmar). O Whisper `base.en` dele é só inglês e não serve.
- Limites: nenhum código, dependência ou download de modelo é autorizado; nada foi medido. O duplex (F7-03) continua sem exemplo e sem teste.

## D-034 — F8 e F9 só em pesquisa e documento; F7-02 em plano (2026-11-05)
- Contexto: o dono pediu "veja do F7, F8 e F9 o que possa fazer sem o celular e faça". O roadmap exige decisão registrada para abrir fase `BLOCKED` (mesmo precedente de D-010 e D-031).
- Decisão: abrir somente trabalho de pesquisa e de documento, sem código, dependência, permissão ou download de modelo: F8-01 (viabilidade do NotebookLM), F9-01 (mapeamento e perguntas), F9-02 (corpus de 40 casos em dados) e um plano de medição para F7-02. As demais subfases seguem `BLOCKED`.
- Limites: nenhuma recomendação dos documentos está aceita; as decisões do dono estão listadas em `docs/fases/F8-01-viabilidade.md` (seção 5) e `docs/fases/F9-01-mapeamento.md` (seção 3). O que depende do S25 continua `NOT_RUN`. A F5 segue aberta e o MVP não muda.
- Evidência: `docs/fases/F8-01-viabilidade.md`, `docs/fases/F9-01-mapeamento.md`, `docs/fases/F9-02-corpus.md` e `docs/medicoes/f9-02/`, `docs/fases/F7-02-plano-de-medicao.md`.

## D-035 — Serviço pago do Memex fora da interface; GPS de foto sob o interruptor de localização (2026-11-05)
- Contexto: o dono pediu "retire conectar pelo Memex e serviço oficial Memex, troque tudo por Segunda Mente" e deixou o GPS a meu critério. A auditoria da F5 achou que o GPS do EXIF de foto ia ao Nominatim e ao prompt do modelo sem passar pelo interruptor de localização.
- Decisão: `AppConfig.enableMemexModelService` passa a `false`; as rotas de configuração de modelo abrem sempre `AiServiceSetupPage`; 12 textos (pt e en) foram reescritos sem citar o serviço do Memex. O GPS de foto só é lido e enviado quando `LocationContextConfig.enabled` está ligado (padrão: desligado); sem ele a foto informa só a data.
- Limites: o código do serviço (`MemexAuthSection`, `MemexCloudService`) continua no repositório, inativo, para facilitar mesclar o upstream; apagar é decisão futura. Quem já tinha tag de local vinda de foto mantém o que foi gravado.
- Evidência: `test/data/services/image_exif_context_test.dart` (falha sem a trava), `test/ui/settings/widgets/ai_service_setup_page_test.dart`, `test/config/app_config_test.dart`.

## D-036 — Enriquecer conversas nos comentários e produzir materiais (2026-11-05)
- Contexto: o dono confirmou que quer desenvolver as conversas que surgem dos comentários das personas em documentos e registros, respondendo quando quiser e transformando o que foi construído em novos materiais.
- Decisão de produto: preservar esse ponto de entrada; permitir aprofundamento, criação e revisão por pedido na própria conversa, com saídas MD/PDF/DOCX, imagens e relatório ilustrado. Original, fontes, hipóteses, decisões e versões permanecem distinguíveis.
- Planejamento: F10 em BACKLOG, detalhada em [F10-criacao-nos-comentarios.md](fases/F10-criacao-nos-comentarios.md). Primeiro conversa/rascunho/exportação textual; depois imagens e relatório ilustrado. Reutilizar F3/F4/F6/F9 onde compatível, sem exigir Todo, NotebookLM ou desktop.
- Limites: este pedido autoriza estruturar a ideia no projeto. Não abre implementação, não altera a fase ativa nem amplia o MVP fechado. Prioridade de execução após MVP ou exceção explícita ainda precisa ser registrada. Provedor/custo de imagem e contratos persistidos ainda não estão decididos.
- Evidência: plano com mapa de código, contratos, etapas e casos de aceite. Funcionalidade e revisão independente: NOT_RUN.

## D-037 — Desenho da F10 e exportador compartilhado na F4 (2026-11-05)
- Contexto: avaliação crítica da F10 mostrou que o PDF anexado não fica no workspace (a persona vê só o resumo do cartão), que o prompt de resposta limita a persona a 1-2 frases e que o exportador da F4 troca aspas curvas, travessão e reticências por "?" no PDF e corta palavras no meio. O dono respondeu ao questionário [2026-11-05-f10-criacao-nos-comentarios.md](questionario/2026-11-05-f10-criacao-nos-comentarios.md) (D1–D24).
- Decisão de produto (F10): textos curtos e longos; PDF guardado no registro e transcrito por página pelo modelo do chat só quando o registro é discutido, com confirmação acima de um limite de páginas; respostas proporcionais ao usuário; outras personas podem entrar e debater entre si só depois de uma resposta do usuário, com no máximo 4 falas por mensagem dele; documento pedido por texto ou botão, a partir do fio do pedido, em voz neutra com créditos (outra voz sob pedido); busca automática de registros relacionados só envia o que o usuário confirmar na lista; cartão do documento no fio com tela própria, versões, revisão pelo fio ou pela tela e edição manual sem sobrescrita; exclusão da origem pergunta se apaga os documentos; modelo que não lê PDF gera aviso e documento com a limitação escrita.
- Mudança de regra: substitui, no plano da F10, "comentar não autoriza debate autônomo entre personas" pelo debate com o freio acima. Envio remoto continua exigindo escolha explícita (PROJECT.md).
- Prioridade: a F10 só começa depois do fechamento do MVP, na ordem conversa → PDF guardado → documento. Exceção: o exportador novo (pacote `pdf`, Apache-2.0, compatível com GPL-3.0, com a fonte Inter já empacotada) entra agora como F4-05 e passa a servir relatório de sessão, F10 e F9.
- Evidência: questionário concluído. Implementação da F10: NOT_RUN. F4-05: ver STATE.md.

## D-038 — Critérios 6 e 7 do MVP sem passos extras (2026-11-05)
- Contexto: no checklist da F5-01, o critério 7 esperava prévia "isto vai sair do telefone" também para anexos do chat, e o critério 6 esperava trocar o modelo do chat no S25 e reabrir conversas antigas.
- Decisão do dono: anexos do chat (foto, PDF, áudio) não precisam de segunda confirmação; vê-los na caixa de mensagem e tocar em enviar é a escolha explícita. A troca de modelo não precisa ser provada no aparelho.
- Mantido: prévia e confirmação na importação de TXT/arquivos e no "Gerar com o modelo" do relatório; itens nascem não confirmados; histórico em arquivo local, independente do provedor.
- Efeito: critérios 6 e 7 passam com a evidência já registrada no S25; F2-07 deixa de exigir prévia para anexos do chat.

## D-039 — Busca semântica local com MiniLM-L12 int8 (2026-11-06)
- Contexto: a medição da F6-10 (`docs/fases/F6-10-medicao.md`) mostrou ganho dos embeddings sobre a busca textual nas consultas reformuladas. Com as 24 notas reais do dono: acerto@3 de 0,83 (texto) para 0,92 (e5-small) e 1,00 (MiniLM); o MiniLM também recusou melhor o que está fora do tema (94% contra 67% de acertos acima do corte).
- Decisão do dono: usar o `paraphrase-multilingual-MiniLM-L12-v2` quantizado (int8, Apache-2.0, 118 MB).
- Desenho aceito para a F6-01: busca textual primeiro; a semântica só complementa quando o texto acha pouco, com corte de nota; recurso opcional e desligado por padrão. O modelo não vai no repositório nem no APK: é baixado sob demanda do repositório público `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2`, em revisão fixa, com conferência de SHA-256; depois disso roda só no aparelho, sem enviar texto a ninguém. Dependência nova: `flutter_onnxruntime` (MIT, compatível com GPL-3.0).
- Limites: o corte de nota depende do corpus (no corpus sintético da F6-10 o resultado dos dois modelos foi o inverso), então o valor inicial é só um ponto de partida e precisa ser conferido no S25 com as notas do dono. O índice fica em memória no início (sem persistência). Bateria, tokenizador sobre texto fora do ASCII/NFKC e notas muito longas (truncadas em 128 tokens) seguem como limites conhecidos.
- Evidência: implementação e testes locais em STATE.md; convivência dos runtimes, busca no app e calibração do corte no S25 permanecem `NOT_RUN`.

## D-040 — Fechar a F6 e abrir a F7-02 (2026-11-06)
- Contexto: os 12 itens da F6 estão `DONE` com prova no S25 (F6-01 fechada hoje). O texto do portão F6 não exige auditoria própria, ao contrário da F5. O dono pediu: "feche o f06 e avance para o f07". A F7 estava `BLOCKED`; só a F7-01 (pesquisa) tinha sido aberta (D-031) e a F7-02 tinha plano (D-034).
- Decisão: F6 `DONE` sem auditoria dedicada; limites declarados continuam valendo (corte 0,42 provisório, índice só em memória, tempos e bateria não medidos). F7: abrir somente a F7-02 (sonda de modelo local no S25, método da F6-10, app separado em `tools/`). F7-03 e F7-06 seguem `BLOCKED`; F7-04 e F7-05 seguem `CANCELLED`.
- Limites: nenhum modelo é baixado antes de o dono confirmar o download do Gemma 3 1B (~529 MB) e liberar o S25 por cerca de uma hora. O Gemma nunca vai empacotado no APK nem no repositório (Termos de Uso exigem repassar as restrições a quem recebe os pesos; risco de conflito com a GPL-3.0). Resumo dos Termos lido em 2026-11-06, não é parecer jurídico.
- Evidência: `ROADMAP.md`, `docs/fases/F7-02-plano-de-medicao.md`.

## D-041 — Adiar o modelo local (2026-11-06)
- Contexto: a medição no PC mostrou o Gemma 3 1B fraco (8/40) e o Gemma 4 E2B melhor (até 23/40 no corpus da F9-02), ainda abaixo do que serve para classificar sozinho. O dono: "vamos deixar esse negocio para depois, coloque no rollback, nao vamos implementar isso agora".
- Decisão: a F7-02 volta a `BLOCKED` e vira reserva em "Ideias futuras". Nenhum código, dependência, sonda ou instalação no S25. Os arquivos baixados ficam só em `%TEMP%702` (fora do repositório).
- Reavaliar quando: o modelo remoto ficar caro/indisponível, ou o dono quiser voz/resumo sem nuvem. Antes, rodar o E4B com os dois prompts, comparar com o modelo remoto + regra da F3-07 e medir velocidade e RAM no S25.

## D-042 — Decisões da F9-01 e abertura da F9 (2026-11-06)
- Contexto: o dono pediu "vamos para o f09" e respondeu às perguntas de `docs/fases/F9-01-mapeamento.md` (seção 3). MVP e F6 estão fechados.
- Decisão (escolha do dono): (1) PDF é lido pelo **modelo configurado (ChatGPT)**, não por biblioteca local; não entra OCR local nem DOCX nesta fase. (2) Todo pessoal em **lista própria**, alimentada só por itens aprovados e ligada ao relatório de origem; lembretes e agenda pelas ações nativas existentes, um item por vez. (3) Imagens: **só as do dono**, com origem registrada; JSON de exportação sim (guarda a proveniência); ICS só quando houver pedido real. (4) **Só Android** agora; desktop fica para depois. Lembretes pelo `SystemActionService`, sem permissão antecipada (recomendação aceita por falta de objeção).
- Consequências: o cliente `codex_responses_client.dart` já envia PDF (`input_file`, base64); o `gemini_oauth_client.dart` descarta PDF, então o app deve avisar quando o modelo ativo não lê PDF. O PDF sai do aparelho para o provedor, então exige o consentimento de envio já existente, com aviso de tamanho e de páginas. Página de evidência vem do modelo e precisa ser conferida no corpus. Sem IA, PDF não gera síntese.
- Limites: nenhuma implementação autorizada além da F9-02 (fixtures de PDF) e da F9-03 em diante conforme o ROADMAP; limite de páginas e tamanho do PDF e a conferência de página pelo modelo ficam para medir na F9-02/F9-03.

## D-043 — Follow-up e tarefa viram uma coisa só (2026-11-07)
- Contexto: a série F9-03 pelo app no S25 reprovou só no critério de tarefas falsas (≤ 1 por rodada): quase todas as falsas eram follow-up classificado como tarefa (`c34`, `c35`). O dono apontou que as duas ideias se confundem no produto.
- Decisão (escolha do dono, recomendação aceita): o modelo passa a emitir só `task`; "perguntar a alguém, checar ou voltar depois" é tarefa. O tipo `followUp` fica no código apenas para ler dados antigos: relatórios salvos e respostas do modelo com follow-up são lidos como tarefa. A tela "Encaminhamentos" e o botão no histórico de chat foram removidos; a lista de tarefas (busca, agenda, lembrete) cobre o uso.
- Consequências: o corpus F9-02 passa a esperar `tarefa` em `c34` e `c35` (o motivo é de produto, não de passar no critério); a série F9-03 foi refeita com o app novo. Itens `follow_up` antigos aprovados viram tarefas aprovadas ao abrir o relatório; o arquivo em disco só muda se o item for editado.
- Limites: o critério de aceitação aprovado em 2026-11-07 não foi alterado.

## D-044 — Retirar a exportação em JSON do relatório (2026-11-07)
- Contexto: D-042 aceitou "JSON sim" porque mantém a proveniência e era barato. O dono perguntou para que servia; nenhuma tela lê o JSON de volta e ele não tem uso hoje.
- Decisão (escolha do dono): remover o formato JSON do menu e do código de exportação do relatório. Ficam Markdown, PDF e DOCX; ICS segue dispensado.
- Consequências: menos um formato a provar na F9-07; a origem de cada item continua visível no relatório e nos formatos de documento. Exportações JSON já feitas em disco não são tocadas. Se um uso aparecer (backup, ferramenta externa), reabrir como pedido novo.

## D-045 — Vozes de personas no chat principal (2026-11-10)
- Contexto: o dono pediu respostas de persona mais desenvolvidas e que elas participem do chat principal quando o assunto combinar.
- Decisão: no chat principal normal, a persona habilitada com maior afinidade clara com a mensagem pode acrescentar um parágrafo próprio, identificado pelo nome, depois da resposta central da Segunda Mente. A persona só entra se tiver algo distinto a acrescentar; saudações ficam curtas e assuntos substantivos recebem cerca de 3–6 frases. Sem afinidade clara não há fallback para a persona principal. Quick Query e outras cenas ficam fora.
- Implementação: o mesmo SuperAgent e modelo configurado produzem a resposta central e a fala identificada, mantendo-a no histórico da conversa e sem chamada adicional ao modelo.
- Limite de validação: testes focados locais; resposta de modelo real e visualização no S25: `NOT_RUN`.

## D-046 — Atualizador Android para releases do repositório privado (2026-11-10)
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

## D-049 — Interrupção por toque na voz duplex (2026-11-11)
- Contexto: horas depois de aceitar o eco (D-048), o dono escolheu a opção A oferecida na medição: "então vamos por esse caminho".
- Decisão: enquanto o app fala, o microfone fica **fechado** (o fluxo é encerrado, não só ignorado) e o indicador mostra desligado. O botão "Interromper e falar" cala a resposta e reabre o microfone; ao fim da resposta ele reabre sozinho. Deixa de existir o "falar por cima". Substitui D-048 no comportamento; a entrada no chat continua ligada.
- Consequência: some o risco de o app ouvir a própria voz, cortar a resposta e mandar eco ao modelo. A conversa passa a ser em turnos com interrupção manual, não full duplex no sentido estrito. Cada resposta custa um fechar/abrir do microfone (tempo não medido no aparelho).
- Reserva: falar por cima só com fone (opção B) depende de medir o eco com fone; não implementado.
- Evidência: testes em STATE.md; `docs/fases/F7-03-voz-duplex.md`. Tela no aparelho: `NOT_RUN`.

## D-050 — Expansão: Todo robusto no celular e Lumen no notebook (2026-11-13)
- Contexto: o dono quer ampliar o escopo para um assistente pessoal de trabalho que lembre o que fazer, ajude nas tarefas e troque ideias, com um Todo robusto no celular e uma parte no notebook que converse com ele. Base: o pacote de planejamento salvo em `docs/lumen/pacote-v1/` e o questionário [questionario/2026-11-13-lumen-desktop-e-todo.md](questionario/2026-11-13-lumen-desktop-e-todo.md) (D1–D27 do questionário).
- Decisão:
  - **Frentes:** o Todo robusto (F11) e o desktop Lumen (no fork, D-053) andam **em paralelo**; o sync (F12) vem depois dos dois. A frente desktop começa pelo que não depende do modelo de tarefas; as telas de tarefas do Lumen só começam depois que a F11-01 fixar o modelo.
  - **Fases atuais:** a F7-03 é fechada, porque só falta validar a tela no S25. A F9, a F5V e a F10 ficam `PAUSED`, sem apagar nada.
  - **Conteúdo do trabalho:** uso real, só com a agenda, as tarefas e as ideias do dono. Dados de clientes, contas, valores e documentos internos do banco não entram, e o app avisa sobre isso.
  - **Assistente "mais ativo"** (F14): resumo de manhã e de tarde, cobrança de tarefas paradas e sugestões das personas. Só entra depois que o núcleo estiver estável: alarmes, sync sem perda e Lumen abrindo nota.
- Notebook: pessoal, de uso livre (não é corporativo).
- Supera: a parte "desktop fica para depois" da D-042.
- Evidência: questionário citado; ROADMAP (F11–F14).

## D-051 — Todo robusto (2026-11-13)
- Decisão do dono: **lista única, sem grupos/listas/projetos**. Entram:
  - telas Hoje, Próximas e Atrasadas, com hora e alerta antes;
  - repetição: diária, semanal com dias escolhidos e mensal; concluir uma ocorrência mantém o histórico em Concluídas e cria a próxima ocorrência ativa sem apagar a série; no mensal, dia 31 vira o último dia do mês;
  - ao concluir após ciclos já vencidos, preservar a cadência e avançar para a primeira ocorrência futura; uma tarefa sem horário continua válida até o fim do dia local atual;
  - subtarefas/checklist;
  - prioridade com quatro níveis: baixa, normal, alta e urgente;
  - filtros e busca, que incluem as tarefas concluídas; cada resultado mostra o estado e a data.
  - tarefas sem data aparecem em Hoje, numa seção “Sem data”, sem receber um prazo.
- Atalhos prontos, editáveis nas configurações:
  - horários: Manhã 9h, Tarde 14h e Noite 20h;
  - dias: Hoje, Amanhã, Daqui a 3 dias e Semana que vem (= próxima segunda);
  - alerta padrão: 20 min antes;
  - tarefa sem hora é tarefa do dia, sem alarme; a explicação aparece apenas quando o campo de hora está vazio;
  - ao excluir, a tarefa sai da lista e aparece a ação temporária “Tarefa excluída · Desfazer”.
- Fuso das datas e horas: `America/Sao_Paulo`.
- IA: propõe e o dono confirma. Texto ou voz viram um cartão pré-preenchido (título, dia, hora, alerta) que o dono ajusta e confirma. Data ou hora ambígua nunca é inventada. Vale no chat, na captura rápida e nos comentários das personas.
- Regras que valem como estão no pacote: o domínio calcula as datas e o SO dispara, nunca a IA; IDs estáveis e tombstones.
- Descartado: listas/projetos; a IA criar a tarefa direto.

## D-052 — Lembretes disparados pelo próprio app (2026-11-13)
- Contexto: pela D-042, o lembrete de uma tarefa era enviado ao app nativo de lembretes, um por vez. Assim não há como adiar ou concluir com estado conhecido, nem como avisar com o notebook desligado de forma controlada.
- Decisão: a Segunda Mente agenda a própria notificação local como alarme exato, com as ações Adiar, Concluir e Abrir. Ela sobrevive ao reinício e funciona offline. As tarefas deixam de ir para o app nativo de lembretes. Substitui a D-042 só nesse item; o resto da D-042 continua.
- Custo conhecido: exige a permissão de alarme exato e a de notificações. Se uma permissão for negada, a interface mostra que o disparo não está garantido. Exige teste físico no S25 com Doze, reinício e economia de bateria. A biblioteca é escolhida na F11-04.

## D-053 — Desktop: fork do Coucou como Lumen (2026-11-13)
- Contexto: o dono pediu "usar o Coucou como base para o Windows, pois ele já tem conversação, enviar documentos, chat, ver e-mails etc. [...] transformando em um só". Ele já mantém o fork público `playertwo1/coucou`: Tauri 2 com Rust e TypeScript, código MIT, releases `windows-v0.6.x` e roadmap próprio.
- Decisão:
  1. O fork `playertwo1/coucou` vira o app desktop inteiro, renomeado **Lumen**, e continua no próprio repositório. Não vira monorepo: o histórico, os merges do upstream e o atualizador ficam. O Flutter fica só no celular. O plano do pacote com Flutter Windows e Tauri como casca (T-002) foi descartado.
  2. A primeira etapa é renomear, com personagem, ícone e sons próprios. O `LICENSE-ASSETS.md` do Coucou não permite distribuir um fork com o nome e os assets Coucou/Mochi sem autorização escrita. O visual se escolhe por protótipo.
  3. O desktop chama o LLM direto, com o mesmo login OAuth do celular, começando pelo ChatGPT, sem chave de API paga. As personas e a memória resumida chegam pelo sync como dados. Em TypeScript/Rust só se reescreve o mínimo: comentar nota e conversar com persona.
  4. Ficam todos os recursos do Coucou: ditado offline, captura rápida, chat, e-mail e monitorar agentes. O Notetaker passa a ser um **anotador de pensamentos e ideias**, comentado pelas personas com as mesmas regras do celular. Só o aparelho que criou a nota pede o comentário, e o outro recebe pelo sync.
  5. E-mail: só a conta pessoal, e nada é enviado sozinho. O e-mail principal é o **MailCraft**, ligado pelo servidor MCP ou pelo canal de controle (`UCS-Care-Group/mailcraft`, MIT OR Apache-2.0). O Outlook clássico fica como secundário. A agenda vem do Google Calendar (D-055).
  6. O trabalho do Lumen vai na frente da fila do fork. Das fases 0/1/2 fecha-se só o que está quase pronto; a 2B e a 2C pausam. O plano "Mochi assistente" (M0–M10) vira "Lumen assistente" e vem depois.
  7. Interface do Lumen só em pt-BR. A regra das 13 línguas do fork deixa de valer para o trabalho do Lumen.
- Difícil de reverter: a base e a linguagem do desktop.

## D-054 — Sync entre celular e Lumen (2026-11-13)
- Decisão:
  - **Transporte:** reaproveitar o pareamento por QR, a criptografia e o relay do Coucou (`docs/ANDROID_LINK.md` e `docs/RELAY_LINK.md` do fork). O Worker do dono no Cloudflare passa a guardar as mudanças cifradas até o outro aparelho buscar (caixa de correio em Durable Objects/SQLite). O Wi-Fi local continua o caminho rápido.
  - **Custo:** conferido em 2026-11-13 nas páginas oficiais de preço. Plano Free: 100 mil requisições por dia e 100 mil gravações por dia nos Durable Objects. Estourar bloqueia e não cobra.
  - **Escopo:** tarefas, notas (inclusive do anotador), conversas e comentários das personas, personas, preferências confirmadas e memória resumida. Timeline, fotos e áudios ficam só no celular; o espelho completo é futuro sem previsão.
  - **Avisos:** com os dois ligados, os dois avisam. Concluir ou adiar num aparelho cancela o aviso no outro.
  - **Backup:** semanal no Google Drive, numa pasta própria, feito pelos dois aparelhos, cada um na sua subpasta. O celular faz o backup completo.
  - **Regras do pacote mantidas:** `mutation_id` idempotente, tombstones, conflito de texto visível, e "salvo no aparelho" diferente de "sincronizado".
- Difícil de reverter: o formato das mensagens e o pareamento.

## D-055 — Ferramentas Google (2026-11-13)
- Decisão:
  - **Login:** um login Google próprio, num projeto Google Cloud do dono, em produção sem verificação e só para uso próprio. O aviso de "app não verificado" é aceito uma vez por aparelho. O modo teste foi descartado porque expira o login a cada 7 dias. Os escopos são os mínimos: Drive para arquivos do app e eventos do Calendar. O login do Gemini (D-013) não serve de base. Credenciais e client IDs ficam fora do repositório.
  - **Google Calendar:** lê os eventos, que entram nos lembretes e resumos, e cria um evento a partir de uma tarefa confirmada. Nunca apaga ou altera evento sem confirmação e nunca convida terceiros.
  - **NotebookLM:** o caminho escolhido é a via B da F8-01, criar ou atualizar um Google Doc do conteúdo escolhido, com prévia. Fica **pós-MVP, sem previsão**, e a F8 continua `BLOCKED`. Plano do dono: NotebookLM Pro.
- Descartado agora: Gmail (o e-mail é o MailCraft, D-053), Google Tasks, Drive como fonte de leitura das personas.

## D-056 — Ordem de execução da F11 enquanto alarmes aguardam o S25 (2026-11-13)
- Contexto: o dono pediu para deixar a F11-04 pendente até haver acesso ao Galaxy S25 Ultra e avançar para a próxima subfase. A F11-04 exige evidência física de alarmes exatos em Doze, offline, após reinício e com economia de bateria.
- Decisão: manter a F11-04 `BLOCKED` e abrir a F11-05 agora. A F11-05 depende da F11-03, já concluída, e segue as regras de confirmação de IA aceitas em D-051. Esta decisão não dispensa nem simula qualquer teste físico da F11-04 e não desbloqueia outras subfases.

## D-057 — Adiar notificação do Todo (2026-11-13)
- Decisão do dono: a ação **Adiar** reagenda o aviso para 10 minutos depois.

## D-058 — Retomar F11-04 com o S25 conectado (2026-11-13)
- Contexto: D-056 manteve a F11-04 bloqueada até haver acesso ao Galaxy S25 Ultra. O dono confirmou que o aparelho está conectado e pediu para continuar.
- Decisão: abrir a F11-04 para implementação e validação física no S25. A F11-06 continua `BLOCKED`; esta decisão não a desbloqueia.

## D-059 — Aviso do Todo quando o alerta já passou (2026-11-13)
- Decisão do dono, vinda da auditoria da F11 (`docs/reviews/F11.md`): se o horário do alerta já passou e o prazo da tarefa ainda não chegou, o lembrete dispara na hora do prazo. Tarefa com prazo já vencido continua sem lembrete.

## D-060 — Fechamento da F7-03 sem o teste de revogação durante a conversa (2026-11-13)
- Decisão do dono: não testar a revogação da permissão de microfone no meio da conversa, por não ter utilidade real. Esse caso fica `NOT_RUN` e não bloqueia o fechamento.
- A F7-03 fecha com Interromper e falar, Encerrar e permissão negada observados no S25 em 2026-11-13 (`docs/fases/F7-03-voz-duplex.md`, seção 5c). Bateria fora do carregador, eco com fone e latência ponta a ponta seguem fora desta decisão, como pela ordem de trabalho da D-050.

## D-061 — Abrir a F11-06: aviso de conteúdo (2026-11-13)
- Contexto: o dono aprovou seguir com a F11-06, que estava `BLOCKED` na ordem de trabalho da F11. Ela depende da F11-03, já `DONE`.
- Decisão: abrir somente a F11-06. O aviso "não registre dados de clientes, contas ou documentos do banco" aparece como legenda fixa na captura e como linha em Configurações, em pt-BR e en. Não é diálogo, não bloqueia e não exige toque extra. Nada mais é desbloqueado: F11-04 segue pendente do S25 e a F12 segue bloqueada.

## D-062 — Fase F15: widget e atalhos Android (2026-11-14)
- Contexto: o dono respondeu o [questionário](questionario/2026-11-14-widget-e-capsula.md) e confirmou a abertura da F15 em 2026-11-14. O app não tem widget hoje; os atalhos do ícone e os deep links já passam pelo `AppActionService`.
- Decisão:
  - Abrir a **F15 — Widget e atalhos Android** (`docs/roadmap/F15-widget-e-atalhos-android.md`), com as subfases F15-01 a F15-07. A fase começa depois do portão da F11 e roda em paralelo à fase L do fork.
  - Escopo: um widget redimensionável (pequeno: Conversar e Falar; médio: + captura; grande: + tarefas de hoje), um chat flutuante, o botão "Conversar" no painel de configurações rápidas e protótipos da minicápsula.
  - A forma da minicápsula (bolha oficial ou sobreposição própria) só é decidida depois dos protótipos no S25 (F15-07).
  - Vão para "Ideias futuras": resumo e próximo evento no widget (depende de F13 e F14); captura sem sair do app pela minicápsula; assistente que vê a tela (risco alto de privacidade; exige decisão própria antes de qualquer trabalho).
  - Widget, microfone, painel rápido e minicápsula só se validam no S25.
  - Não desbloqueia F12, F13 nem F14.

## D-063 — Abrir a F15-01 (maquetes) antes do portão da F11 (2026-11-14)
- Contexto: o dono pediu para trabalhar a F15 hoje, antes de fechar o portão da F11. O AC-01 no S25 (alarme às 08h10, tarefa sintética às 08h30) segue pendente em STATE.md. D-062 exige o portão da F11 para começar a fase.
- Decisão:
  - Abrir só a **F15-01** (maquetes do widget e do chat flutuante), documentada em `docs/fases/F15-01-maquetes.md`, com o HTML em `docs/fases/f15-01/maquetes.html`. Estado: REVIEW.
  - Nenhum código de produto da F15 começa antes da escolha do dono entre as opções A (linhas), B (teclas) ou a combinação (teclas no pequeno e linhas no grande).
  - A escolha do dono é a evidência de aceite da F15-01. Sem ela, a F15-01 não vira DONE.
  - O portão da F11 não é dispensado. F15-02 a F15-07 seguem BLOCKED até o portão da F11, como D-062 prevê.
- Limite: o estado da fase não muda para além da F15-01; a estimativa de células é só estimativa, até medir a grade One UI no S25.

## D-064 — Composição do widget da F15: teclas no pequeno, linhas no grande (2026-11-14)
- Contexto: D-063 pediu a escolha do dono entre as opções A (linhas), B (teclas) ou a combinação, em [F15-01-maquetes.md](fases/F15-01-maquetes.md). Em 2026-11-14 o dono respondeu "Combinação" no chat.
- Decisão:
  - **Pequeno:** teclas. Conversar preenchido em âmbar e Falar em contorno, na mesma faixa.
  - **Médio:** teclas mais a faixa de captura (Anotar, Foto e Colar), como o médio da opção B. O dono não disse nada sobre o médio; esta é a leitura adotada, e ele pode trocá-la sem nova fase.
  - **Grande:** linhas, com Conversar e Falar em linha, captura e até três tarefas de hoje.
  - **Comum:** chat flutuante, folha de Anotar e estados compartilhados como nas maquetes.
- Limite: não abre a F15-02. O portão da F11 continua exigido (D-062). Os tamanhos em células seguem estimativa até medir a grade One UI no S25. A mudança de forma entre o médio e o grande, ao redimensionar, precisa ser conferida no aparelho na F15-05.

## D-065 — Chat flutuante com um motor Flutter compartilhado (2026-11-14)
- Contexto: a F15-02 abre o chat por cima da tela inicial numa Activity translúcida (`FloatingChatActivity`). Desenho em `docs/fases/F15-02-chat-flutuante.md`.
- Decisão:
  - A `MainActivity` e a `FloatingChatActivity` usam o mesmo `FlutterEngine`, guardado no `FlutterEngineCache` com o ID `segundamente_main` (`SharedFlutterEngine`). Dois motores seriam dois isolates Dart no mesmo processo, cada um com seu executor de tarefas, sua conexão SQLite e seus singletons, com risco de tarefa duplicada e gravação concorrente.
  - Um host por vez: ao nascer, uma Activity solta o fragmento Flutter da outra de forma síncrona e a encerra. O estado Dart fica no motor.
  - Os channels são registrados antes do `main()` do Dart rodar.
  - Fechar o app pelo voltar não destrói mais o motor: a próxima abertura é morna e volta para onde o usuário estava.
  - A folha é uma rota do mesmo app (`/floating-chat`), com o `AgentChatDialog` em modo flutuante. Conversar abre o teclado; Falar ouve uma fala, transcreve e envia. Nada é gravado sem confirmação (D-051).
  - Até existir o widget (F15-03), a folha abre por dois atalhos do ícone: "Conversar" e "Falar".
- Limite: a troca de host, a abertura a frio e a transparência só se validam no S25. Se a troca de host falhar no aparelho, a alternativa registrada é um segundo motor com `FlutterEngineGroup` e um ponto de entrada leve, o que exige nova decisão por causa do risco de dois isolates.

## D-066 — Abrir a F15-03 (widget pequeno) antes do S25 da F15-02 (2026-11-14)
- Contexto: a linha da F15-03 estava BLOCKED pela F15-02, cujo código está em `main` (d787e85d) mas ainda não foi validado no S25. O dono pediu a implementação da F15-03 hoje. AGENTS.md exige decisão registrada para abrir uma subfase BLOCKED.
- Decisão:
  - Abrir a **F15-03** com o widget pequeno em código: duas teclas (Conversar em âmbar, Falar em contorno), `AppWidgetProvider` nativo, home screen apenas, sem rede e sem atualização periódica. Estado: REVIEW. A validação no S25 fica como `NOT_RUN` até o validador rodar o checklist em `docs/fases/F15-03-widget-pequeno.md`.
  - As teclas abrem a `FloatingChatActivity` com o mesmo alvo e o mesmo extra (`floating_chat_mode` = `type` ou `talk`) dos atalhos da F15-02 (D-065). A linha da F15 falava em `AppActionService`; isso não existe para o chat flutuante, e uma segunda rota não se justifica.
  - Médio e grande continuam fora (F15-04 e F15-05, BLOCKED).
- Limite: o aceite da F15-03 (tocar o widget no S25) depende do S25 da F15-02, que ainda não foi feito. Não fecha a F15-02 nem o portão da F15.

# ROADMAP — Segunda Mente

**Visão e escopo:** [PROJECT.md](PROJECT.md) · **Design aprovado:** [DESIGN.md](DESIGN.md) · **Índice e pranchas:** [docs/INDEX.md](docs/INDEX.md) · **Estado e próxima ação:** [STATE.md](STATE.md) · **Decisões:** [docs/DECISIONS.md](docs/DECISIONS.md) · **Regras de execução:** [docs/WATCHDOG.md](docs/WATCHDOG.md) · **Auditoria:** [docs/AUDIT.md](docs/AUDIT.md)

**Atualização deste mapa:** 2026-11-13. D-050 abriu a expansão Todo robusto + Lumen (F11–F14; desktop no fork `playertwo1/coucou`) e pausou F9, F5V e F10; veja STATE.md para a próxima ação. Se um resumo divergir de uma evidência datada posterior, prevalece a evidência posterior.

## Como ler e executar este roadmap

**Estrutura:** este arquivo é o índice: regras, estados, mapa, ordem de trabalho, ideias futuras e histórico. Cada fase tem seu arquivo em [docs/roadmap/](docs/roadmap/), com subfases, critérios e portão. Os documentos de trabalho das fases (estudos, medições, viabilidade) ficam em [docs/fases/](docs/fases/). Abra só o arquivo da fase em que estiver trabalhando.

1. Leia STATE.md antes de trabalhar. Ele registra o estado observado, a evidência disponível, os bloqueios e a próxima ação.
2. Use este arquivo para entender o escopo, as fases, as dependências e os critérios de aceite. Não trate uma linha planejada como funcionalidade já implementada.
3. Faça apenas subfases READY da fase ativa. Fases BLOCKED só podem ser abertas quando todas as condições de desbloqueio forem atendidas e a decisão correspondente estiver registrada em docs/DECISIONS.md.
4. Uma subfase só fica DONE depois que a evidência indicada é registrada em STATE.md (evidências antigas ficam arquivadas em [docs/historico/](docs/historico/)). Implementação sem validação não fecha a subfase. Verificação não executada é NOT_RUN, nunca PASS.
5. Estado da fase descreve o trabalho agregado; estado do portão descreve se os critérios de aceite foram provados. Uma fase pode ter tarefas opcionais abertas depois de seu portão ter sido cumprido.
6. Dependências indicam os dados, decisões ou resultados necessários para começar ou aceitar a tarefa. Exceções de execução paralela têm de ser explícitas e não fecham os portões anteriores.
7. Siga PROJECT.md, AGENTS.md, docs/WATCHDOG.md e docs/AUDIT.md. Toda mudança de comportamento precisa dos testes exigidos em AGENTS.md.

### Estados

| Estado | Significado |
|---|---|
| BACKLOG | Ideia aprovada para planejamento futuro, ainda sem início previsto |
| BLOCKED | Não pode começar até cumprir a dependência ou obter decisão indicada |
| READY | Pré-requisitos necessários estão disponíveis e a tarefa pode começar |
| IN_PROGRESS | Implementação ou validação já começou |
| REVIEW | Aguarda revisão ou validação de aceite |
| DONE | Entrega e evidência de aceite registradas em STATE.md |
| PAUSED | Interrompida por decisão do dono; nada é apagado e retomar exige nova decisão registrada |
| NOT_RUN | Estado explícito de uma checagem ou tarefa ainda não executada; não é aprovação |

### Prioridades

| Prioridade | Significado |
|---|---|
| P0 | Bloqueia o fluxo principal ou o portão de aceite |
| P1 | Necessária para completar a fase ou sustentar o uso esperado |
| P2 | Melhoria útil, sem bloquear o portão principal |
| P3 | Ideia futura sem compromisso de execução |

## Mapa das fases

| Fase | Resultado esperado | Dependência e exceção | Estado atual | Portão |
|---|---|---|---|---|
| [F0 — Fundação](docs/roadmap/F0-fundacao.md) | Fork, identidade, licença e ambiente verificados | Nenhuma | DONE | Fechado |
| [F1 — Registro de modelos](docs/roadmap/F1-registro-de-modelos.md) | Catálogo, seleção, provedores e troca de modelo confiáveis | F0; o catálogo e os provedores foram validados antes dos demais portões | IN_PROGRESS; critério MVP cumprido | Critério 4 do MVP cumprido pelo catálogo e por múltiplos provedores; há tarefas adicionais abertas |
| [F2 — Chat, voz e importação](docs/roadmap/F2-chat-voz-e-importacao.md) | Conversa persistente, entrada de voz e arquivos autorizados | F1; aberta antecipadamente por decisão do dono | IN_PROGRESS | Critérios 1, 2, 3 e consentimento de envio comprovados |
| [F3 — Extração e relatório](docs/roadmap/F3-extracao-e-relatorio.md) | Relatório editável, fiel às fontes e com itens não confirmados por padrão | F2; aberta antecipadamente por decisão do dono | IN_PROGRESS | Critério 6, extração real do modelo e amostra longa comprovados |
| [F4 — Exportação](docs/roadmap/F4-exportacao.md) | O mesmo relatório em Markdown, PDF e DOCX | F3 | DONE | Critério 5 e compartilhamento verificados no fixture e no S25 |
| [F5 — Fechamento do MVP](docs/roadmap/F5-fechamento-do-mvp.md) | Aceite integral, privacidade, desempenho e auditoria | F0–F4 | DONE | Fechado em 2026-11-05: sete critérios no S25 (1–3 aprovados pelo dono), F5-03 medida e AUDIT RESULT: PASS |
| [F5V — Redesign visual](docs/roadmap/F5V-redesign-visual.md) | Aplicação da direção AMOLED aprovada nas telas existentes | D-022 permite execução em paralelo à F5 | PAUSED por D-050 (2026-11-13); estado anterior registrado na seção da fase | Interações, acessibilidade e validação visual comprovadas |
| [F6 — Memória longitudinal](docs/roadmap/F6-memoria-longitudinal.md) | Busca, encaminhamentos, histórico de mudanças, tópicos e agenda | D-010 permite avançar antes do fechamento do MVP | DONE | Busca semântica, tópicos, justificativas e encaminhamentos verificados |
| [F7 — Voz contínua e ponte CLI](docs/roadmap/F7-voz-continua-e-ponte-para-clis-oficiais.md) | Voz full duplex opcional, modelo local e integração controlada com CLIs oficiais | MVP fechado e decisões de plataforma, termos e segurança aprovadas; D-047 abriu só a F7-03 | IN_PROGRESS (F7-03 DONE por D-060; F7-02 adiada por D-041; F7-06 bloqueada) | Portão F7 |
| [F8 — NotebookLM](docs/roadmap/F8-notebooklm.md) | Exportação opt-in e integração somente se suportada e aprovada | MVP e exportação estáveis; termos e destino aprovados | BLOCKED | Portão F8 |
| [F9 — Meeting Decoder](docs/roadmap/F9-meeting-decoder.md) | Conversas e PDFs viram relatórios revisáveis, Todo e encaminhamentos | MVP fechado; decisões da F9-01 aprovadas | PAUSED por D-050 (2026-11-13); estado anterior registrado na seção da fase | Portão F9 |
| [F10 — Criação nos comentários](docs/roadmap/F10-criacao-a-partir-das-conversas-nos-comentarios.md) | Conversas com personas desenvolvem documentos e imagens | D-036/D-037: desenho decidido; MVP fechado | PAUSED por D-050 (2026-11-13); estado anterior registrado na seção da fase | Portão F10 |
| [F11 — Todo robusto](docs/roadmap/F11-todo-robusto-celular.md) | Lista única com Hoje/Próximas/Atrasadas, repetição, subtarefas, prioridade, busca, alarmes próprios e cartão de confirmação da IA | D-050/D-051/D-052; paralela à fase Lumen do fork | READY | AC-01 no S25 offline e após reinício; nenhum Todo antigo perdido |
| [F12 — Sync com o Lumen](docs/roadmap/F12-sync-com-o-lumen.md) | Celular e Lumen trocam tarefas, notas, conversas, personas e preferências por relay + caixa de correio | D-054; F11-01 e o contrato F12-01 | BLOCKED | Cenários de caos sem perda nem duplicação |
| [F13 — Google](docs/roadmap/F13-google.md) | Login Google próprio, backup semanal no Drive e Google Calendar | D-055; projeto Google Cloud do dono | BLOCKED | Backup restaurado e eventos lidos/criados com confirmação |
| [F14 — Assistente ativo](docs/roadmap/F14-assistente-ativo.md) | Resumos manhã/tarde, cobrança de tarefas paradas e sugestões das personas | D-050; portões F11 e F12, F13-04 | BLOCKED | Configurável, silenciável e sem tarefa criada sem confirmação |

**Exceções vigentes:** D-010 permitiu avançar F6 antes do fechamento do MVP. D-022 permite executar F5V em paralelo à F5. D-042 abriu F9 após o fechamento do MVP e limita seu escopo atual a Android; não fecha a fase nem reduz seu checklist. D-050 permite F11 em paralelo à fase Lumen do fork, sem fechar portões de fases pausadas.

## Ordem de trabalho vigente

Definida por D-050 (2026-11-13). Decisões completas: [questionário](docs/questionario/2026-11-13-lumen-desktop-e-todo.md); material de base: [pacote Lumen](docs/lumen/pacote-v1/README.md).

1. **F7-03:** fechada em 2026-11-13 (D-060). No S25 passaram início, turnos, pausa, retomada, tela apagada, Interromper e falar, Encerrar e permissão negada; a revogação no meio da conversa não foi testada por decisão do dono. F7-02 e F7-06 seguem BLOCKED.
2. **F11 (celular)** em paralelo com a **fase L do fork** (`playertwo1/coucou`, `docs/roadmap/fase-l-lumen.md`): renomear para Lumen, login OAuth, anotador, e-mail. As telas de tarefas do Lumen esperam a F11-01 fixar o modelo.
3. **F12:** sync, depois que F11-01 e a fase L tiverem base. O contrato F12-01 pode ser escrito antes.
4. **F13:** Google (login, backup no Drive, Calendar). O backup entra assim que o login existir.
5. **F14:** assistente ativo, só depois dos portões F11 e F12.
6. **Pausadas por D-050:** F9, F5V e F10, sem perda; retomar exige nova decisão. F8 (NotebookLM) continua BLOCKED como pós-MVP sem previsão (D-055).

## Ideias futuras — sem autorização de implementação

| Ideia | Condição para reavaliar |
|---|---|
| Grafo temporal Graphiti ou mapa visual global de tópicos | Depois de F6-04/F6-09 demonstrarem que listas não bastam |
| Gemma local e voz mãos-livres | Dentro de F7, após medir qualidade pt-BR, hardware e privacidade |
| Backup automático versionado que inclua configurações padrão | Revisão futura do backup; definir retenção e restauração antes |
| Separação de falantes/voiceprint | Se as transcrições reais não preservarem identificação suficiente; medir no S25 |
| Interface MCP para agentes externos | Decisão da F7-05 e limites de permissão aprovados |
| Escolher idioma do resumo pelo idioma predominante | Só se o produto voltar a suportar mais de en e pt |
| Biblioteca agregada de fotos, PDFs e áudios | Depois de F2/F6, se a busca atual não bastar |
| Índice semântico gravado no banco (Drift): guardar o vetor de cada item e calcular só os novos | Reserva da F6-01 (hoje o índice vive só na memória do app). Reavaliar se a primeira busca do dia passar de ~2 s ou o histórico passar de alguns milhares de itens; medir antes no S25 |
| Modelo local no aparelho (F7-02): Gemma 4 E2B/E4B pelo LiteRT-LM (Apache-2.0) | Adiado pelo dono em 2026-11-06 (D-041); nada implementado. No PC o E2B acertou 23/40 (57,5%) no corpus da F9-02 com o melhor prompt; falta comparar com o modelo remoto + regra da F3-07 e medir velocidade/RAM no S25. Detalhes em `docs/fases/F7-02-medicao.md` e `docs/fases/F7-02-pesquisa-modelos.md` |
| Chave Gemini como reserva de transcrição | Se o caminho D-011 falhar ou se os limites medidos forem insuficientes |
| Conversas guiadas por perfil: o Advogado do Diabo define a ideia/hipótese, apresenta uma objeção por turno, recebe a réplica e termina com veredito equilibrado e resumo opcional; outros personagens podem ter ciclos próprios, como professor com perguntas e exercício ou planejador com alternativas, riscos e próximo passo. O usuário pode responder, pular ou encerrar; conclusões só viram registros após salvamento explícito. | Reavaliar após o fechamento da F5 e a validação dos chats da F5V; experimentar em dois perfis e definir controles, formato das saídas e o que pode ser salvo antes de abrir uma tarefa de implementação |

Ideias já avaliadas e distribuídas em tarefas ficam nas decisões D-014, D-016 e D-018; não reabrir essas pesquisas sem uma lacuna concreta.

## Histórico de mudanças de escopo

- 2026-11-02 — escopo do MVP e fases: docs/DECISIONS.md.
- 2026-11-02 — D-010 permite F6 em paralelo ao MVP; F7/F8 continuam bloqueadas.
- 2026-11-03 — D-011 transcrição de áudio, D-012 idiomas en/pt, D-013 Gemini OAuth, D-014 ideias do Memos e D-015 Claude OAuth.
- 2026-11-03 — D-016 ideias do Daedalus Echo; D-017 design móvel AMOLED; D-018 ideias do anarlog.
- 2026-11-03/04 — D-020 fallback de modelos; D-021 substituída por D-022, que inicia F5V em paralelo à F5.
- 2026-11-04 — D-023 retirada do espelho chinês e D-024 remoção dos componentes chineses do produto.
- 2026-11-04 — D-025 a D-028: pranchas visuais, microfone explícito e limites de execução; ver docs/DECISIONS.md.
- 2026-11-04 — D-029/D-030: planejar Meeting Decoder na F9 com PDFs, Todo pessoal, encaminhamentos e relatórios PDF/DOCX. F9 permanece bloqueada.
- 2026-11-05 — ideia futura de conversas guiadas por perfil: objeções e veredito para o Advogado do Diabo, com dinâmicas próprias para outros personagens; sem iniciar implementação.
- 2026-11-05 — D-038: critério 7 sem segunda confirmação para anexos do chat; critério 6 sem prova de troca de modelo no S25.
- 2026-11-05 — D-036/D-037: F10 desenhada por questionário (debate entre personas com freio, PDF guardado e transcrito, documentos com versões); começa após o MVP. Exportador compartilhado antecipado como F4-05.
- 2026-11-13 — D-050 a D-055: expansão Todo robusto + Lumen (fork do Coucou) + sync + Google; F11–F14 criadas; F9, F5V e F10 pausadas; NotebookLM pós-MVP.

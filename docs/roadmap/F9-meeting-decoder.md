> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F9 — Meeting Decoder

**Estado:** PAUSED por D-050 (2026-11-13). Antes: IN_PROGRESS desde 2026-11-06 (D-042: decisões da F9-01 aceitas; só Android; PDF lido pelo modelo ChatGPT). Fora do MVP.

**Objetivo:** transformar uma conversa, nota própria, transcrição importada ou PDF suportado em um relatório visualmente organizado com resumo, decisões, ideias possíveis, oportunidades, dúvidas, tarefas e follow-ups. Cada sugestão deve apontar para um trecho, relógio ou página. O usuário revisa, edita, confirma ou descarta cada item. A fase inclui Todo pessoal e encaminhamento escolhido para agenda/lembretes.

**Reuso obrigatório:** aproveitar os relatórios, evidências e confirmação da F3; Markdown/PDF/DOCX da F4; busca e encaminhamentos da F6; ações nativas existentes em SystemActionService quando compatíveis. TaskCard não é uma Todo agregada. AsyncTaskListPage é fila interna de agentes e não pode ser reaproveitada como lista pessoal.

**Limites:** PDF com texto selecionável é a entrada inicial prevista. F9-01 decide OCR, outros formatos e suporte “etc.”. Não gravar terceiros silenciosamente, não transcrever conversa corporativa na nuvem sem escolha, não inferir responsável/data, não enviar mensagens e não encaminhar item sem confirmação individual. IA é opcional; sem IA não inventar síntese semântica. Imagens externas exigem origem, licença, proveniência e consentimento. A prioridade de F9 em relação a F7/F8 será decidida após o MVP.

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F9-01 | Mapear F3/F4/F6, SystemActionService, TaskCard e destinos; decidir PDF/OCR/outros formatos, Todo/agenda/lembretes, imagens, IA e sistema desktop | P0 | F5 fechado; F3-02/04/05, F4-01/02/03, F6-02/11 | DONE | Matriz requisito → recurso existente/lacuna, fluxo de dados e decisões aceitas antes do código; fila de agentes separada da Todo |
| F9-02 | Criar corpus de 40 exemplos fictícios e fixtures de PDF com saída esperada e fontes | P0 | F9-01 | DONE | Casos positivos/negativos cobrem tarefa clara, hipótese, fato passado, duplicata, dono ausente, data ambígua, PDF selecionável e evidência por página; sem dados pessoais reais |
| F9-03 | Gerar relatório editorial organizado e incluir imagens relacionadas quando houver fonte aprovada, reutilizando categorias existentes e provedor autorizado | P0 | F3-01 a F3-05, F9-02 | DONE | Imagens próprias registram mensagem/horário; a leitura do relatório filtra caminhos fora dos assets do usuário; UI e exportações explicam que são referências visuais e informam quando nenhuma imagem relacionada existe; JSON marca illustrative_only e omite o caminho local. Testes de serviço, widget e exportação passam. Qualidade: série completa pelo app no S25 (D-043, 40 casos × 5 rodadas): tarefas 21/22, 20/22, 20/22, 21/22, 21/22; falsas 1,1,0,1,1; válidas 39/40 (única recusa esperada: PDF digitalizado). Critério aprovado atendido; limite conhecido: `c40` (mesma data em duas páginas de PDF) perdido nas 5 rodadas. Fechada pelo dono em 2026-11-07; F9 segue aberta. |
| F9-04 | Revisar cada sugestão individualmente: editar, confirmar, descartar e resolver ambiguidade/duplicata | P0 | F9-03 | DONE | S25 pediu confirmação para `sexta` e aprovou após "Confirmar assim"; testes cobrem edição, descarte, bloqueio na Todo e duplicata visível sem remoção automática. |
| F9-05 | Definir origem das imagens e produzir prancha de referência para relatório e Todo antes da UI | P1 | F9-01 | DONE | D-042 limita imagens do relatório a imagens próprias, com proveniência; `04-report-followups.png` já existia antes da UI da F9, está em `docs/INDEX.md` e o README registra prancha sintética e fontes de inspiração sem capturas copiadas. |
| F9-06 | Criar página Todo pessoal no menu existente, com itens aprovados, estado, prazo, busca e vínculo à fonte; encaminhar sob escolha para calendário/lembrete | P0 | F9-04, F6-02, F6-11 | DONE | S25: item de teste aparece, busca sem acento e estado vazio funcionam, concluir/reabrir restaura o estado, fonte abre o relatório; lembrete pede confirmação e cria horário local. Permissão já concedida no aparelho; negação coberta por widget. Sem tarefas de agentes na lista. |
| F9-07 | Exportar relatório organizado em Markdown/PDF/DOCX (JSON retirado, ICS dispensado) | P1 | F9-03 a F9-06, F4-01 a F4-04 | DONE | Exporta em Markdown/PDF/DOCX (JSON retirado em 2026-11-07 a pedido do dono: sem uso e sem leitura de volta); Markdown/PDF/DOCX incluem imagem própria, origem e aviso ilustrativo, e informam o estado sem imagem. Testes focados e suíte completa (1471 passaram, 2 pulados), build Android e abertura do app no S25 passam. Em 2026-11-07 o S25 gerou Markdown, PDF e DOCX de um relatório sintético; os bytes foram conferidos no PC (acentos, estrutura, fontes embutidas, PDF renderizado). Falta ver os arquivos num leitor do aparelho e um caso com imagem no aparelho (imagem só coberta por teste unitário); nenhum destino externo foi escolhido. Em 2026-11-07 o dono abriu PDF e DOCX no aparelho (pasta Download/SegundaMente) e aprovou; o caso com imagem tem só teste unitário (ressalva aceita). ICS dispensado por D-042. |
| F9-08 | Entregar os fluxos local-first no Android | P1 | F9-01, F9-05 a F9-07 | DONE | Build e fluxos de captura, revisão, Todo, exclusão e exportação validados no Android; desktop fica adiado por D-042; sem sincronização externa implícita. Provas no S25 (2026-11-07, APK `globaldev` debug): importação de transcrição sintética e abertura do relatório; revisão (F9-04) e Todo (F9-06) já provadas; exportação MD/PDF/DOCX aprovada pelo dono em Download/SegundaMente (F9-07); exclusão da conversa apaga relatório, conversa, texto original importado e cache de compartilhamento (conferido em disco), tarefas ficam por desenho. Cópia em Downloads só no toque de exportar; nada sai do aparelho sem o dono escolher um destino |
| F9-09 | Fechar qualidade, privacidade, acessibilidade e auditoria da fase | P0 | F9-02 a F9-08 | IN_PROGRESS | Checklist abaixo concluído; provas em STATE.md; auditoria em docs/AUDIT.md sem bloqueios. Em 2026-11-07: `docs/reviews/F9-2026-11-07.md` com AUDIT RESULT PASS técnico (sem CRITICAL/HIGH), suíte 1524 passam, build e S25 ok; falta a passada de acessibilidade (TalkBack `NOT_RUN`, adiada pelo dono) e o dono aceitar o checklist |

### Checklist de aceite da F9

- [ ] Cada tipo de entrada aprovado em F9-01 gera relatório organizado com resumo, decisões, ideias, oportunidades, dúvidas, follow-ups e tarefas aplicáveis.
- [ ] Cada item indica trecho e relógio ou número da página correspondente.
- [ ] IA desligada não produz síntese semântica inventada; IA ligada usa modelo configurado e consentimento de envio.
- [ ] Hipótese não se transforma em decisão/tarefa; pessoa e prazo ausentes ficam como não informados.
- [ ] Confiança é explicada em linguagem compreensível e aparece junto da evidência.
- [ ] Relatórios incluem imagens relacionadas quando houver origem segura e autorizada; cada imagem mostra sua proveniência e não é apresentada como fato da conversa.
- [ ] Prazo como “quinta” sem semana definida fica pendente até confirmação explícita.
- [ ] Cada sugestão pode ser editada, confirmada ou descartada sem alterar o texto original.
- [ ] Ação descartada não chega a Todo, agenda ou lembrete; cada encaminhamento exige confirmação individual.
- [ ] Todo mostra itens abertos/concluídos, permite busca/conclusão/reabertura e mantém vínculo à fonte.
- [ ] A lista Todo não mostra filas nem tarefas internas dos agentes.
- [ ] Possíveis duplicatas são sinalizadas; nada é removido automaticamente.
- [ ] Exclusão permanente remove relatório e derivados associados, sem deixar cópia inesperada.
- [ ] Markdown, PDF e DOCX preservam estrutura, acentos, fontes e imagens; JSON mantém proveniência; ICS respeita America/Sao_Paulo.
- [ ] Imagens externas só entram após escolha/consentimento e têm origem e licença registradas; sem fonte aprovada, o relatório informa que não há imagem relacionada disponível.
- [ ] Android passa pelo fluxo local-first e pela revisão de acessibilidade; desktop permanece adiado por D-042.
- [ ] Os 40 exemplos e PDFs sintéticos cobrem positivos, falsos positivos, ambiguidades e evidência; testes unitários, de widget e integração cobrem extração, revisão, destinos, armazenamento, exclusão e exportação.

**Portão F9:** MVP fechado; decisões F9-01 aceitas; todos os itens confirmados seguem pelo fluxo revisável; exclusão, exportação e acessibilidade comprovadas; auditoria sem bloqueios. O que não foi executado continua NOT_RUN em STATE.md.

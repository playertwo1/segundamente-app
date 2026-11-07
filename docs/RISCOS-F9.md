# Riscos e validações pendentes da F9

Atualizado em 2026-11-06. A qualidade de extração continua sendo um bloqueio alto para fechar a fase. Os riscos técnicos de persistência e proveniência listados abaixo foram corrigidos e testados; os dados sintéticos que já estão no S25 foram preservados.

## Corrigidos nesta retomada

| # | Risco original | Correção e evidência |
|---|---|---|
| 1 | Gravação direta ou corrupção de Todo podia perder a lista | Todo grava em arquivo temporário e renomeia; JSON inválido é preservado com sufixo corrupto e a lista retorna vazia. Testes de serviço. |
| 2 | Excluir sessão apagava tarefas concluídas | Tarefas abertas da fonte são removidas; concluídas são mantidas sem vínculo para a sessão. Testes de serviço. |
| 3 | Tarefa aprovada editada deixava a cópia Todo parecer atual | Edição marca a cópia como desatualizada e a UI informa isso. Testes de serviço e widget. |
| 4 | Data sem ano parecia exata | isAmbiguousDue usa parseExplicitDue; datas sem ano pedem confirmação. Testes de domínio e widget. |
| 5 | Suíte inteira não executada | flutter test --reporter compact passou: 1471; 2 skips esperados — tokenizer F6-10 não baixado nesta máquina e teste OpenAI sem OPENAI_BASE_URL/OPENAI_API_KEY. |
| 11 | Caminhos de imagem persistidos no relatório eram aceitos sem validar a origem | SessionReportService.load filtra caminhos que não pertencem aos assets de imagem do usuário. Teste injeta um caminho externo e confirma que ele é omitido. |
| 12 | Relatório sem imagem não explicava a ausência; imagem podia parecer evidência | UI e Markdown/PDF/DOCX mostram estado sem imagem; imagens próprias registram mensagem/horário e recebem aviso de referência visual. JSON marca illustrative_only e omite relative_path. Testes de UI, serviço e exportação. |
| 13 | Caixas de seleção do relatório e da Todo não tinham rótulo para leitor de tela | Corrigido: rótulo = texto do item. Testes `androidTapTargetGuideline`, `labeledTapTargetGuideline` e fonte 2× passam em ambas as telas. TalkBack real no S25: `NOT_RUN`, adiado pelo dono em 2026-11-06 (não fazer por enquanto; o checklist da F9-09 segue sem essa prova). |

## Riscos ainda abertos

| # | Risco | Efeito | Estado / próxima prova |
|---|---|---|---|
| 6 | Em PDF, a citação vem da transcrição feita pelo modelo, não do PDF original | Erro de cópia do modelo pode parecer citação literal | ABERTO — revisar a página original antes de confirmar o item; a página fica visível junto da fonte. |
| 7 | O modelo pode omitir uma tarefa do relatório | O que não aparece não pode ser revisado | MITIGADO — MÉDIO (2026-11-07, D-043). Série completa pelo app no S25, 40 casos × 5 rodadas: tarefas 21/22, 20/22, 20/22, 21/22, 21/22, falsas 1,1,0,1,1, válidas 39/40; critério aprovado atendido após fundir follow-up e tarefa (mudança de definição, não de modelo). Resta o `c40` (mesma data em duas páginas de PDF, perdido 5/5) e variação entre rodadas. Ver docs/F9-03-corpus.md. |
| 8 | Toast de lembrete criado não apareceu na captura anterior | Mensagem de sucesso não foi confirmada visualmente | ABERTO — o evento e o horário local foram conferidos e o evento de teste foi apagado; capturar o toast em uma validação futura. |
| 9 | Lembrete no iOS (Permission.reminders) não foi testado | Comportamento no iPhone desconhecido | ADIADO por D-042: esta fase cobre Android. Reavaliar se iOS voltar ao escopo. |
| 10 | Artefatos sintéticos antigos permanecem no S25: sessão pdf_1793979183587 uma segunda sessão do mesmo `f9_c36.pdf` criada no piloto de 2026-11-06 (relatório Livre gerado), nove sessões TXT de teste do corpus (c01–c09, com relatório Livre gerado, nada confirmado), a pasta `/sdcard/Download/f9corpus` com 40 arquivos sintéticos, arquivos f9_c36.pdf/f9_c39.pdf, uma Todo de teste, mensagens de chat e relatorio.json | Dados de teste continuam no aparelho | AGUARDA autorização do dono para limpeza. Não remover durante validação. |

## Provado no S25 em 2026-11-06

- Lista de tarefas mostra o item com a fonte `p.2`.
- Busca `versao` sem acento encontra o item; `zzzz` mostra o estado vazio.
- Concluir/reabrir alterna o estado e foi restaurado para aberto; tocar na fonte abre o relatório.
- Editar o prazo para `2026-12-20 14:30` faz aparecerem os botões de calendário e de lembrete.
- O botão de lembrete pede confirmação ("Nada é criado antes de você confirmar").
- Ao confirmar, o evento foi criado no calendário para 14:30 do horário local (dtstart conferido). O evento de teste foi apagado em seguida.

## Exportação PDF vista no S25 (2026-11-06, retomada 2)

- Sessão sintética `pdf_1793979183587`: botão PDF abre a folha de compartilhamento com `relatorio.pdf`. Nenhum contato nem app foi escolhido.
- Visualização local: Imprimir → destino "Salvar como PDF" mostra o PDF em 1 página A4 (título, data, Decisões/Tarefas com fonte e `p.2`, seção "Imagens relacionadas: Nenhuma imagem relacionada disponível"). Cancelado sem salvar; nada gravado em Downloads.
- Observação (LOW): o rótulo "Relógio: p.2" também aparece para páginas de PDF; "Relógio" não é o termo certo para página.
- Ainda `NOT_RUN`: DOCX e Markdown no aparelho, e PDF com imagem de verdade (precisa de foto sintética anexada a uma sessão nova).

## APK após a retomada (2026-11-06)

- APK globalDev debug compilado com sucesso e instalado por ADB usando `adb install -r`, preservando os dados do app.
- Maestro abriu app.segundamente.dev com clearState=false e chegou à tela principal no S25 Ultra (RQCY10934YV). Esta foi uma verificação de abertura; o fluxo de relatório e a renderização visual das exportações não foram repetidos após a instalação.
- Nenhuma sessão, arquivo, mensagem, Todo ou exportação de teste foi apagada nesta retomada.

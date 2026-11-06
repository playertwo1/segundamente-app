# Riscos abertos da F9 (para resolver depois)

Registrados em 2026-11-06. Nenhum bloqueia o uso; todos têm correção planejada.

| # | Risco | Efeito | Correção planejada |
|---|-------|--------|--------------------|
| 1 | `Todo/todo.json` é gravado direto e lido sem tolerância | Queda no meio da gravação ou arquivo corrompido pode travar a lista inteira | Gravar em arquivo temporário e renomear; ao ler, ignorar o arquivo inválido sem bloquear a tela |
| 2 | Apagar uma sessão remove também os itens já concluídos da lista | Histórico de tarefas feitas some junto | Decidir: manter os concluídos (sem o link da fonte) ou avisar antes de apagar |
| 3 | Editar uma tarefa aprovada no relatório não atualiza a cópia na lista | Lista e relatório podem divergir | Pedir nova confirmação ao editar, ou marcar a cópia como desatualizada |
| 4 | `_exactDue` aceita `21/11` (sem ano) como data exata, mas calendário e lembrete exigem o ano | Item sem pergunta de data ambígua, porém sem botão de calendário | Alinhar `_exactDue` com `parseExplicitDue` |
| 5 | Suíte completa de testes não foi rodada nesta etapa | Falhas fora das telas mexidas passam despercebidas | Rodar `flutter test`; corrigir ou justificar: `unigram_tokenizer_test` (precisa de `tokenizer.json` apagado a pedido) e 2 falhas antigas em `file_operation_service_grep_test` |
| 6 | Em PDF, a citação vem da transcrição feita pelo modelo, não do PDF | Erro de cópia do modelo pode virar "citação literal" | Não tem correção total; documentar e manter a página visível para conferência |
| 7 | O modelo pode omitir uma tarefa do relatório | Tarefa que não aparece não é revisada | Documentar; o relatório mostra a transcrição para conferência manual |
| 8 | Aviso de lembrete criado: o toast não apareceu no print do S25 (tirado 2 s depois) | Não confirmado visualmente | Repetir com captura imediata, ou trocar por mensagem fixa na tela |
| 9 | Lembrete no iOS (`Permission.reminders`) nunca foi testado | Pode falhar no iPhone | Fora do alvo atual (Android); testar se o iOS voltar a ser usado |
| 10 | Lixo de teste no S25: sessão `pdf_1793979183587`, `f9_c36.pdf`, `f9_c39.pdf`, item "Enviar a versão final." e a mensagem de teste no chat | Dados fictícios no aparelho | Limpar com o ok do dono |

## Provado no S25 em 2026-11-06

- Lista de tarefas mostra o item com a fonte `p.2`.
- Editar o prazo para `2026-12-20 14:30` faz aparecerem os botões de calendário e de lembrete.
- O botão de lembrete pede confirmação ("Nada é criado antes de você confirmar").
- Ao confirmar, o evento foi criado no calendário para 14:30 do horário local (dtstart conferido). O evento de teste foi apagado em seguida.

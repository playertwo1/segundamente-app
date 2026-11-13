# MVP 1.0 | Escopo fechado proposto
O MVP é um **produto completo mínimo**, não apenas uma demonstração do personagem.

## P0 obrigatório (deve existir no piloto)
1. **App Segunda Mente para Windows** com notas, chat, histórico, personas e exportação; adaptação responsiva a teclado/mouse.
2. **Lumen no Windows**: janela/personagem compacto, iniciar/minimizar com o sistema, atalho configurável, captura rápida em texto e voz, abrir app completo contextualizado, indicadores claros de escuta/erro/sincronização.
3. **Todo robusto nativo**: criar/editar/excluir/concluir/reabrir, listas, subtarefas, prioridade, categorias, filtros Hoje/Próximas/Atrasadas, vencimento e hora, alertas relativos/absolutos, adiamento e recorrência básica (diária/semanal/mensal) com fuso horário.
4. **Notificações independentes**: alarme local persistente no Android e Windows; o Android avisa sem notebook e sem rede após o agendamento. Testes com Doze/reinício/permissões.
5. **Vínculo inteligente**: nota->tarefa; tarefa->nota; personas comentam anotação; o usuário confirma extrações de compromissos e datas ambíguas.
6. **Sincronização confiável**: IDs estáveis, outbox, tombstones, conflitos detectáveis, retries, pareamento/auth, status por dispositivo, armazenamento de alterações no servidor para dispositivos desconectados. *Decisão de tecnologia a validar em F0.*
7. **Memória e aprendizado mínimos**: reutilizar memória longitudinal da Segunda Mente, registrar preferências confirmadas e histórico auditável, sem inferir hábitos silenciosamente.
8. **Documentos**: preservar PDF, DOCX e Markdown do app e seu vínculo à origem, incluindo experiência Windows.
9. **Privacidade/testes**: dados sintéticos; compatibilidade GPL/MIT; backup/restauração e suíte E2E.

## P1 desejável dentro do ciclo se P0 estiver estável
- Múltiplos alertas para um mesmo compromisso e opção de padrão por categoria.
- Briefing de início do dia configurável localmente.
- Notificação Windows com abrir nota/adiar/concluir; sons discretos e escolha de voz.
- Pesquisa por tags sem acento, filtros e ordenação melhores.

## Fora do MVP, deliberadamente
- Integração com Samsung Reminder, serviços de e-mail e Microsoft Outlook.
- Importação automática do Outlook/Google Calendar, envio de mensagens/e-mails, ações Windows remotas.
- Lembretes por localização, geofencing, foco e produtividade preditiva.
- Agentes autônomos que executam ações no computador; auto-despacho de personas sem limites.
- Ambientes múltiplos Trabalho/Pessoal; no MVP apenas Trabalho, com arquitetura evitando acoplamentos irreversíveis.
- Treinamento/fine-tuning de LLM, análises comportamentais opacas, inferência de contexto corporativo sensível.

## Definição de pronto (DoD)
A função só é considerada pronta com comportamento validado em Android físico, Windows físico, testes automatizados de domínio e sincronização, migração reversível ou backup, texto de interface em pt-BR, acessibilidade mínima, registro de logs sem segredos e documentação atualizada. Se não testada, marcar NOT_RUN, jamais PASS.

## Critérios de aceite obrigatórios
AC-01 reunião marcada às 08h30, aviso 20 min antes às 08h10 (America/Sao_Paulo) no celular com PC desligado, após sincronização confirmada.
AC-02 editar tarefa offline em Android e reconectar: sem perda nem duplicação; eventual conflito é exposto.
AC-03 criar nota pelo Lumen, clicar personagem e abrir a nota na interface completa.
AC-04 persona preexistente comenta nota em Windows, usuário responde em Android e o comentário não se duplica.
AC-05 tarefa gerada de comentário exige confirmação antes de virar definitiva.
AC-06 exportar documentação resultante para DOCX e PDF a partir da interface completa.
AC-07 recorrência sobre transição de mês/fuso não dispara duas vezes e próxima ocorrência correta.
AC-08 notebook fechado, Android recebe alerta local; notebook aberto, Windows apresenta alerta próprio.
AC-09 restaurar dados após cópia/backup preserva vínculos entre notas, tarefas, personas e comentários.
AC-10 nenhuma credencial trafega em log; dispositivo pode ser revogado.

## Política de priorização
Não adicionar features P1 enquanto AC-01, AC-02, AC-03 e AC-04 estiverem instáveis. O nome Lumen e a aparência do personagem não são prioridade maior que integridade de dados.

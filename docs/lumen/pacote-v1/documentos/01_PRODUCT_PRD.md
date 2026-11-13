# PRD | Segunda Mente + Lumen
**Estado:** PROPOSTA v1 | **Público do MVP:** uso de trabalho, individual, Android + Windows.

## Problema
Notas dispersas e tarefas esquecidas: uma IA conversa sobre ideias, mas sem gestão confiável de execução e notificação o trabalho continua fragmentado. No desktop, abrir telas completas interrompe o fluxo. No celular, é preciso receber alertas mesmo sem notebook.

## Proposta de valor
Uma anotaçao vira memória contextual, conversa com personas existentes, tarefas executáveis, compromissos, notificações e documentos. Um só contexto atravessa interfaces.

## Nomes e papéis
- **Segunda Mente:** aplicativo completo em Flutter, com módulos de notas, tarefas, memória, personas, conversa e documentos; disponível em Android e Windows.
- **Lumen:** presença compacta do próprio produto no Windows, baseada em conceitos e tecnologias reaproveitáveis do Coucou. Clique no personagem abre Segunda Mente em tela cheia, no contexto atual.
- **Não criar:** aplicativo Lumen com memória própria; Umi; renomeação da Segunda Mente; conexão obrigatória com Samsung Reminder.

## Personas, componente central
A anotação criada no Windows ou Android pode ser analisada e comentada pelas **mesmas personas já configuradas na Segunda Mente**, sob suas regras existentes. Comentários, respostas, referências e documentos derivados fazem parte da mesma conversa. Sincronizar não deve gerar comentários novamente. Nenhuma persona nova será criada automaticamente.

## Casos principais
### UC-01 | Lembrete natural
Usuário diz pelo Lumen: “Amanhã, reunião com Juliana às 8h30; me lembre 20 minutos antes.” O sistema extrai a proposta estruturada (data local, hora, alerta 08h10), pede confirmação se necessário e registra a tarefa/compromisso com fonte original. O agendador do SO dispara o alerta, não o modelo de IA.
### UC-02 | Celular sem PC
Uma tarefa sincronizada permanece no Android, com agendamento local persistente. Mesmo notebook desligado e sem internet, notificação deve ocorrer no celular, sujeito às permissões e restrições do sistema operacional. A interface evidencia se a sincronização ainda está pendente.
### UC-03 | Ideia + persona + documento
Criar nota pelo Lumen; abrir interface completa com um clique; comentar com personas existentes; editar ações sugeridas; gerar DOCX/PDF/MD; continuar a mesma discussão no Android.
### UC-04 | Todo robusto
Lista Hoje, Próximos, Atrasados e Concluídos; prioridades, categorias, projetos/listas, checklist, repetição, adiar, reagendar, conclusão, busca, filtros e referência à nota de origem.
### UC-05 | Aprendizado compartilhado
O usuário confirma uma preferência (por exemplo, antecedência de alerta de 20 minutos). O sistema registra valor, origem, confiança, confirmação e histórico. O Lumen e a Segunda Mente passam a respeitá-la, com editar/apagar. Não é treinamento contínuo do LLM.

## Requisitos funcionais
FR-01 registrar notas por teclado e ditado; FR-02 converter nota em tarefa mediante confirmação; FR-03 tarefas manuais completas; FR-04 alertas múltiplos com antecipação; FR-05 recorrência diária/semanal/mensal; FR-06 agendamento Android offline; FR-07 alertas Windows quando dispositivo ligado; FR-08 comentários vinculados por personas existentes; FR-09 navegação contextual do Lumen ao app; FR-10 sincronização multi-dispositivo, inclusive com dispositivos desconectados; FR-11 histórico, rastreio de fonte e revisões; FR-12 exportação existente PDF/DOCX/MD; FR-13 preferências aprendidas com confirmação; FR-14 pesquisa e filtros; FR-15 backup/restauração; FR-16 notificações adiáveis/reagendáveis.

## Requisitos não funcionais
NFR-01 local-first e funcionamento offline; NFR-02 sem duplicidade sob reenvio; NFR-03 idempotência de comandos; NFR-04 TLS + autenticação + revogação de dispositivo; NFR-05 acessibilidade e contraste; NFR-06 interface Windows sem CPU excessiva no repouso; NFR-07 nenhum dado bancário real em provedores externos sem autorização institucional; NFR-08 LGPD/minimização; NFR-09 documentação e testes; NFR-10 sincronização com status claro e possibilidade de resolução de conflitos.

## Restrições
- Preservar o app Flutter, dados atuais e as personas existentes.
- Prototipar Tauri/Rust do Coucou, sem presumir que o código será incorporado diretamente.
- O protocolo relay do Coucou serve como **referência de transporte**, não como sincronização de estado implementada.
- Não pressupor que Android permite execução arbitrária no segundo plano: usar notificações nativas e políticas de bateria; validar no Galaxy S25 Ultra real.
- Uso profissional piloto: contas e dados sintéticos, sem contato com sistemas corporativos reais.

## Sucesso do piloto
Fluxo completo sem perda; alerta às 08h10 para reunião 08h30; criação/conclusão em ambos os aparelhos; persona única e comentários visíveis no Windows/Android; PDF/DOCX exportável; funcionamento sem notebook; status de sync honesto.

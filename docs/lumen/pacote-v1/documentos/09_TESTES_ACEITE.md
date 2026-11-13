# Matriz de testes e aceite
## Equipamentos-alvo iniciais
Android real: Galaxy S25 Ultra; Windows 11 real: notebook Samsung ou desktop. Emuladores são apoio, não substitutos para notificações de segundo plano e reprodução de áudio.

## Testes P0 de negócio
T01 reunião 13/11/2026 08h30, lembrete -20 min: avisar em 08h10 no Android depois que o dispositivo recebeu/salvou evento; PC desligado.
T02 PC sem internet e Android com internet: evento criado no PC aparece como PENDENTE até conectividade; não mostrar falso sucesso remoto.
T03 Android offline: novo evento salvo e agenda local; receber aviso offline, sem PC.
T04 recorrência diária/semanal/mensal: completar uma ocorrência sem apagar próximas.
T05 lembrete reagendado: cancelar notificação anterior e programar nova.
T06 mesmo evento entregue duas vezes pela rede: um só registro/aviso por ocorrência.
T07 edição simultânea em Android e Windows: conflito preservado e resolvível.
T08 exclusão offline seguida de sync: tarefa não ressuscita.
T09 nota criada no Lumen, clique abre detalhe da mesma nota na Segunda Mente.
T10 persona existente comenta no desktop e comentário aparece no Android; sincronização não recria mensagem.
T11 proposta da IA sem data ou com 'sexta': solicitar confirmação adequada, não registrar lembrete errado.
T12 backup+restore preserva nota->tarefa->persona->documento.
T13 DOCX/PDF/Markdown funcionam no Windows e Android com acentuação.
T14 PC reiniciado: Lumen inicia, não duplica instância, mantém atalhos, sem microfone aberto ao iniciar.
T15 celular reiniciado: notificações futuras reconstituídas segundo limites Android.
T16 permissão Android de notificações negada: UI alerta impossibilidade de garantir disparo.
T17 relógio fuso diferente/teste DST: cálculo correto e informação visível.
T18 dispositivo revogado: sem acesso a novas informações.
T19 transferência de anexos falha parcialmente: retomar, sem corrupção.
T20 apagamento de preferência aprendida: não volta após sync.

## Testes não funcionais
- Startup/perf: medir CPU/RAM em repouso e após uso real; orçamento definido a partir da F0.
- A11y: TalkBack, teclado, contraste, foco, redução de movimento.
- Segurança: logs sem segredos, abuso de IPC, refresh de token, vazamento entre workspaces.
- Compatibilidade Windows de plugins e modelo offline de transcrição.
- Regressão Android existente, F9/F10 e dados legados.

## Gate de liberação
Todas T01–T12 aprovadas em físico; T13–T20 aprovadas ou explicitamente bloqueadas com correção; nenhuma perda/duplicação P0; todo `NOT_RUN` visível e impede alegar pronto. Bug crítico mantém release bloqueado.

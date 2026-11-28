# Assistente Ativo: publicar avisos na central de notificações do Android

**Relato do Rafael:** os avisos do Assistente Ativo aparecem na lista de **Tarefas**, mas não como notificações normais no celular. A lista deve continuar funcionando; o aviso precisa também aparecer na bandeja do Android, inclusive com o app em segundo plano. Não é pedido de push remoto. Base revisada: main `4d1e70d` (1.0.21), sem reprodução física neste rascunho.

## Onde começar

- [F14 Assistente Ativo](../roadmap/F14-assistente-ativo.md): resumos da manhã/tarde, tarefas paradas e sugestões das personas. [ActiveAssistantService.buildState](../../lib/data/services/active_assistant_service.dart#L175) monta os dados para a interface; isso, por si só, não publica um aviso Android. Trace cada categoria até a publicação para identificar se falta agendamento/entrega ou se permissão/canal está bloqueado.
- O [PR #2](https://github.com/playertwo1/segundamente-app/pull/2), já mesclado, corrigiu o reagendamento da **conversa espontânea** de persona. O [PersonaMessageNotifier](../../lib/data/services/persona_message_notifier.dart) tem canal próprio e suprime avisos com app em primeiro plano. Não trate esse caminho como cobertura do F14 nem duplique uma conversa que já notifica. Não altere a decisão D-085, que diz respeito a alertas dos agentes **do PC** via Lumen/ESP32, nem o fluxo das notificações encaminhadas à placa.

## Comportamento pedido

1. **Além da lista**, publicar notificação local Android quando estiver devido um resumo habilitado (manhã/tarde), houver tarefa parada elegível para aviso ou chegar sugestão de persona que passe pelas regras do Assistente Ativo. Não inventar conteúdo nem publicar aviso vazio. Uma sugestão continua exigindo confirmação antes de virar tarefa.
2. Entregar sem precisar abrir Tarefas ou reabrir o app. Usar o agendamento local que funcionar com o ciclo de vida Android e os serviços existentes. Respeitar fuso, horário de silêncio, horários e categorias habilitadas, adiamento por tarefa e limites de sugestões. Não disparar em lote avisos vencidos após reinício. Não prometer horário exato em Doze nem exigir acesso a alarme exato para uma publicação imediata.
3. Criar ou reaproveitar um canal claramente identificado como **Assistente Ativo**, sem mudar lembretes manuais. Tratar a permissão de notificação e o canal silenciado: explicar no app como habilitar, sem repetir prompts ou reativar preferências. Mesmo com bloqueio, manter o registro interno. Evitar conteúdo pessoal na tela bloqueada por padrão.
4. O toque abre o resumo, a tarefa ou a sugestão correspondente dentro do app, em partida fria ou com app aberto. Se o item não existir mais, abra o Assistente Ativo e explique. Deduplicar por evento lógico (por exemplo, data/período para os resumos), inclusive em repetição do worker/reinício, sem deduplicar eventos distintos.

## Aceite e evidência

- Com relógio/dados/sistema de notificação controlados, testar as três categorias, permissão/canal bloqueados, silêncio, horários, categoria desligada, adiamento, deduplicação e que a lista permanece intacta. Não usar conta ou provedor de IA real para validar.
- Em Android, fora do silêncio e com permissões concedidas, produzir um evento elegível com o app em segundo plano e a tela bloqueada; conferir a bandeja do sistema e o toque com abertura fria e quente. Testar também um lembrete manual para confirmar que não regrediu. Fechar pela tela de recentes não é a mesma coisa que usar “Forçar parada”. Distinguir teste do worker, publicação e visualização física; se o S25 Ultra não estiver disponível, registrar `NOT_RUN` para o aparelho.
- Informar comandos, resultados, atraso observado e limitações. Este rascunho só documenta o pedido; sem merge ou release.

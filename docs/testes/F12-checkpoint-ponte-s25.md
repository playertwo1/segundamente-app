# Roteiro — Checkpoint da Ponte (F12-03 a F12-05) no S25 + notebook

Pacote: `app.segundamente.dev` (perfil sintético). Lumen `0.7.3` no notebook. Todas as tarefas usam o prefixo `PONTE` e são apagadas no fim.
Observação pelo adb: `dumpsys alarm` (alarmes), `logcat` (sync) e `uiautomator` (tela).

| # | Caso | Passo | Esperado | Resultado |
|---|---|---|---|---|
| 1 | F12-03 pareamento | Lumen: Configurações → Celular Android → QR. Celular: Configurações → Pareamento com o Lumen → Escanear QR | "Pareado com …" nos dois lados | PASS pelo link (13:2x, "Pareado com BOOKFAEL", relay e LAN salvos). FAIL na câmera: 2 tentativas sem decodificar (fechadas por Voltar) |
| 2 | Checkpoint: entrega | PC cria `PONTE 1` para hoje, prazo em +30 min (alerta 20 min). Celular: Todo → Sincronizar agora | Chega **uma** vez; `RTC_WAKEUP` em +10 min | PASS: chegou na consulta ao abrir (13:30), uma vez; `RTC_WAKEUP` 13:40:00 `exactAllowReason=permission` |
| 3 | T06 replay | Sincronizar agora mais 2 vezes; reabrir o app | Continua uma só `PONTE 1`, um só alarme | PASS: 3 syncs (último 13:31), uma `PONTE 1`, 1 alarme |
| 4 | Celular → PC | Celular cria `PONTE 2` e sincroniza | Aparece no Lumen uma vez | PASS: sync 13:41, visto uma vez no Lumen pelo dono |
| 5 | Checkpoint: alarme | Esperar o horário do alerta de `PONTE 1` | Notificação no S25 e toast no Windows (AC-08) | PASS: S25 (`Deliver` 13:40:00.000 e `NOTIFICATION_INTERRUPTION` `todo_reminders`) e toast no Windows, visto pelo dono |
| 6 | AC-08 / T05 cancelamento | PC conclui `PONTE 1`; celular sincroniza | Alarme e notificação de `PONTE 1` cancelados no S25 | PASS no S25: sync 13:44; alarme pendente removido; `notification_cancel` id 1741488228 reason 8 (APP_CANCEL) às 13:44:47.721; 0 notificações ativas |
| 7 | T05 adiar | Celular adia `PONTE 1` (Adiar 10 min) e sincroniza; PC consulta | Toast antigo some no PC; novo horário nos dois | PASS com `PONTE 5` (prazo 14:58, editado no celular): aviso às 14:38:00 nos dois; Adiar 10 min no S25 → `snoozed_until` 14:50:21, alarme reagendado 14:50:21; sync 14:40:51; no Lumen o toast sumiu e a tarefa ficou adiada até 14:50 (dono) |
| 8 | AC-02 edição offline | Celular em modo avião edita o título de uma tarefa; volta a rede e sincroniza | Título novo no PC, sem duplicar; conflito aparece se o PC também editou | PASS: offline (`airplane_mode_on=1`, sem rede) `PONTE 2` → `PONTE 2 editada` v3, tela "Salvo no aparelho · erro ao sincronizar"; após religar, sync 14:05:18 com outbox 0 e `last_error` nulo; Lumen mostra `PONTE 2 editada` uma vez (dono) |
| 9 | T08 exclusão offline | Celular em modo avião exclui `PONTE 3`; volta a rede e sincroniza; PC consulta de novo | Some nos dois e não volta | PASS: tombstone 13:51:21 offline; sumiu no Lumen e não voltou após novo sync do PC (dono); sync do celular às 14:10 manteve o tombstone |
| 10 | Workmanager | `dumpsys jobscheduler` mostra o trabalho de 1 h; forçar a execução com o app fechado | Consulta roda em segundo plano | PASS: `lumen_todo_periodic_sync` registrado (WorkManager, job 68). Forçar com `cmd jobscheduler run -f` não executa trabalho periódico antes do período ("ENQUEUED; not doing any work"). Execução natural às 14:28:52 com o app fora da tela (`Worker result SUCCESS`): `PONTE 5`, criada no Lumen com o app fechado, entrou no `todo-v2.json` |
| 11 | T18 revogação | Lumen: Configurações → Celular Android → Mostrar código de pareamento → Parear de novo (revoga a sala). PC cria `PONTE 7`. Celular sincroniza | Celular vê a sala revogada, mostra que não sincroniza mais e `PONTE 7` não chega | PASS: log do Lumen `14:52:04 phone link: new pairing code, phones disconnected`, sem `revoke skipped`; sync do celular às 14:53 → `revoked: true`, tela "Salvo no aparelho · pareamento revogado", `PONTE 7` ausente do `todo-v2.json`. Tentativa anterior (`PONTE 6`) não valeu: o Lumen só desligou e religou o vínculo (`phone link: stopped`), sem revogar, e a `PONTE 6` chegou normalmente |
| 12 | Limpeza | Excluir todas as `PONTE *` | 0 alarmes e 0 notificações do app | PASS (feita antes do passo 11): `PONTE 1`–`5` com tombstone, sync 14:45:31 com outbox 0, sumiram no Lumen (dono); 0 alarmes e 0 notificações ativas do app |

## Resultado (2026-11-15, 13:20–14:53)

Checkpoint da Ponte **PASS** no Galaxy S25 Ultra (`app.segundamente.dev` 1.0.50, build da `main` `a6cf1300`) e no notebook (Lumen 0.7.3): tarefa do PC chega uma vez na primeira consulta, o alarme toca nos dois, e concluir ou adiar num lado cancela o aviso no outro depois da consulta. F12-03 (pareamento e T18), F12-04 (T06, AC-02, T08 e WorkManager) e F12-05 (AC-08 e T05) com evidência física. Pendências que não bloqueiam: leitura do QR pela câmera e os achados abaixo.

## Achados da rodada de 2026-11-15

1. **Lumen: QR pequeno demais.** O leitor do S25 não decodificou o QR em 2 tentativas. Aumentar o QR para ocupar boa parte da tela (no repositório do Lumen).
2. **SM: tela de pareamento presa em "Carregando".** Ao reentrar na tela na mesma sessão, depois de abrir o leitor, `load()` não retornou; reiniciar o app resolveu. Causa não confirmada (suspeita: chamada ao `FlutterSecureStorage` que não volta; o S25 registra `Could not decrypt key` na inicialização).
3. **SM: prévia da área de transferência grava texto copiado no log** (`app_flutter/logs`, ~100 caracteres). Pegou o início do link de pareamento. Não deve registrar conteúdo.
4. **Lumen: editar o horário da `PONTE 5` no PC não salvou** (o horário não mudou). A mesma edição feita no celular chegou ao Lumen normalmente.
5. **SM: sem rede, o rótulo diz "erro ao sincronizar"** em vez de indicar offline/pendente. Logo após religar a rede, o "Sincronizar agora" ficou ~1 min sem resposta visível (rótulo parado em "2 pendentes · 13:49") e o sync concluiu às 14:05; a causa não aparece porque `TodoViewModel` engole exceções sem log.
6. **SM: o sync não registra nada no log.** Sem linha de início, fim ou erro, a evidência depende só da tela e do `dumpsys`.

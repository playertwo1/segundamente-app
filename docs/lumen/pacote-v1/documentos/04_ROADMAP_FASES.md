# Roadmap estruturado | Fases e subfases
*Ordem de dependência, não promessa de duração. Todo gate exige evidência verificável no repositório.*

## F0 | Auditoria, fronteiras e protótipo de risco
- F0.1 congelar baseline, fazer inventário de branch, versões, testes e migrações; preservar F9/F10 em curso.
- F0.2 examinar `TodoService`, `todo.json`, modelos atuais e fluxos de lembretes; testar exportação de dados.
- F0.3 matriz de suporte Windows dos plugins Flutter; criar build vazia Windows; isolar APIs Android.
- F0.4 criar PoC Coucou Tauri: janela flutuante, hotkey e abertura contextual de uma rota Flutter.
- F0.5 escolher estratégia de conexão do Lumen ao app (IPC/API local autenticada) e de distribuição única.
- F0.6 definir transporte + persistência de sincronização; medir risco de cloud/segurança/licenças.
**Gate:** build mínima Windows + Lumen abre tela Flutter + nota de dados sem corrupção; ADR de sync; plano de migração assinado.

## F1 | Modelo unificado e migração do Todo
- F1.1 entidades Note, Task, Reminder, Checklist, PersonaComment, Attachment, Preference.
- F1.2 identificadores estáveis, versionamento, migração de `todo.json`, vínculo à fonte.
- F1.3 comandos idempotentes criar/editar/concluir/reabrir/excluir, tombstone e auditoria.
- F1.4 regras de recorrência, prazo, adiar e timezone; testes determinísticos de relógio.
**Gate:** nenhum Todo anterior perdido; recorrência correta; testes de unidade de domínio.

## F2 | UX de tarefas e lembretes no Android
- F2.1 telas Hoje/Próximas/Atrasadas/Listas/Concluídas, busca e prioridade.
- F2.2 captura texto/voz, criação manual, checklist e categorias.
- F2.3 alertas locais via scheduler nativo; permissões, canais, Doze, boot, horário de verão, timezone.
- F2.4 ação de notificação: abrir, adiar, concluir; estados idempotentes.
- F2.5 vínculo anotação->lembrete com confirmação explícita.
**Gate:** AC-01 funciona no aparelho físico offline e após reinício.

## F3 | Segunda Mente completa no Windows
- F3.1 layouts desktop, navegação teclado/mouse, janela redimensionável e tema escuro.
- F3.2 histórico de notas/conversas, indexação, anexos e exportação PDF/DOCX.
- F3.3 tornar mecanismo das personas invocável pela UI Windows, preservando configurações.
- F3.4 tarefas Windows e agendamento local de notificações.
- F3.5 testes de arquivos, permissão e atualização/instalador Windows.
**Gate:** nota+persona+DOCX de ponta a ponta na UI Windows.

## F4 | Lumen na área de trabalho
- F4.1 extrair componentes de janela flutuante do Coucou; atribuições MIT e identidade independente.
- F4.2 atalho global; ativação de microfone; ditado local com fallback e indicação do estado.
- F4.3 criar nota/tarefa em canal autenticado; abrir tela Flutter no contexto exato.
- F4.4 iniciar/minimizar com o sistema, tray, pausar notificações e consumo mínimo.
- F4.5 não duplicar memória, chat, cache autoritativo nem motor de personas.
**Gate:** criação por voz->persistência na Segunda Mente->abertura contextual em um clique.

## F5 | Sincronização e continuidade
- F5.1 pareamento autorizado, autenticação e revogação de dispositivo.
- F5.2 outbox local, servidor de alterações persistente (necessário com PC desligado), replay idempotente, delta-sync.
- F5.3 conflitos por campo/entidade, tombstones, anexos e atualização do status visível.
- F5.4 lembrar localmente em cada SO depois que evento foi recebido; evitar disparos por efeito de sync.
- F5.5 testes de caos: offline, reconexão, edição simultânea, troca de rede, relógio errado.
**Gate:** AC-02, AC-04, AC-08 e AC-09 aprovados, sem perdas em cenários de caos.

## F6 | Aprendizado e proatividade controlados
- F6.1 memórias e preferências explícitas compartilhadas; CRUD, fonte, revisão, remover.
- F6.2 extração de compromissos com confirmação e sem prazo inventado.
- F6.3 comentários das personas com deduplicação e histórico, sem disparo automático por replicação.
- F6.4 briefing leve opcional e notificação contextual sem dados não verificados.
**Gate:** usuário aprova/corrige uma preferência e ela vale nas duas interfaces; compromissos permanecem corretos.

## F7 | Hardening, release e piloto
- F7.1 suíte integral Android/Windows com cenários de LGPD e licença.
- F7.2 revisão UX, TalkBack, teclado, contraste, modos de acessibilidade.
- F7.3 instalação/atualização, backup e rollback testados.
- F7.4 15 a 30 cenários sintéticos de trabalho, relatório de bugs, gates de regressão.
- F7.5 empacotar uma instalação Windows contendo Lumen + Segunda Mente, sem duas configurações.
**Gate:** AC-01 a AC-10 com evidências e P0 = 0.

## Pós-MVP
PM1 e-mail/calendário opt-in; PM2 automações Windows e localizações; PM3 inteligência de padrões; PM4 separação pessoal/trabalho.

## Paralelismo permitido
F1 e protótipo F3 podem avançar em branches isolados após F0. F4 começa após contrato de abertura contextual. F5 começa cedo como protótipo mas não desbloqueia release sem F1 estável. Não executar migração de armazenamento e UI sem testes de fixtures.

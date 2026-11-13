> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F5 — Fechamento do MVP

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F5-01 | Executar e registrar os sete critérios de aceite em fluxo ponta a ponta no S25 Ultra | P0 | F1–F4 | DONE | Checklist completo em docs/fases/F5-01-checklist.md, com resultado e evidência de cada critério |
| F5-02 | Revisar consentimento, dados enviados, armazenamento de chaves/tokens e logs | P0 | F1–F4 | DONE | Migração do cofre no S25 ainda NOT_RUN; revisar também exceções OAuth ainda registradas; relatório em docs/fases/F5-02-privacidade.md |
| F5-03 | Medir sessão longa, geração/exportação e lista de histórico; corrigir regressões relevantes | P1 | F2–F4 | DONE | Medições reproduzíveis no dispositivo com entrada, tempo e memória; números de fixture não substituem medida real; registrar em docs/fases/F5-03-medicoes.md |
| F5-04 | Definir e documentar direção visual móvel AMOLED | P2 | D-017 | DONE | DESIGN.md, D-017 e dez pranchas aprovadas em docs/INDEX.md |
| F5-05 | Fazer auditoria final e conferir atribuições GPL | P0 | F5-01, F5-02, F5-03 | DONE | docs/reviews/F5.md sem CRITICAL/HIGH aberto e resultado da auditoria registrado |

**Portão F5 = MVP pronto.** Os sete critérios abaixo precisam de prova, assim como privacidade, desempenho e auditoria. Portão FECHADO em 2026-11-05: docs/reviews/F5.md registra AUDIT RESULT: PASS. Os critérios 1, 2 e 3 foram executados e aprovados pelo dono no S25. O MVP está pronto; F5V e F6 seguem abertas. Com o MVP fechado, F7, F8, F9 e F10 podem ser priorizadas pelo dono.

### Sete critérios de aceite do MVP

1. Conversar por texto e falar com o app em turnos; resposta em áudio é opcional.
2. Compartilhar um TXT real do Samsung e produzir relatório rastreável a trechos e relógios.
3. Analisar uma foto em ao menos um provedor com visão e avisar quando o provedor escolhido não oferece essa capacidade.
4. Selecionar modelo por ID ou por catálogo atualizado sem instalar outro APK.
5. Exportar o mesmo relatório em PDF, DOCX e Markdown com acentuação correta.
6. Editar e confirmar decisões, ideias, tarefas e follow-ups, sem alterar a fonte original; manter histórico ao trocar o modelo (a troca de modelo não precisa de prova no S25, D-038: o histórico é arquivo local independente do provedor).
7. Mostrar o que será enviado, pedir escolha explícita antes do envio remoto e exigir confirmação humana antes de tornar decisão ou tarefa definitiva. No chat, ver os anexos na caixa de mensagem e tocar em enviar é a escolha explícita (D-038).

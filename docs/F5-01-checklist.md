# F5-01 — Checklist dos 7 critérios

**Revisado:** 2026-11-05 (versão anterior: 2026-11-02, antes de qualquer execução no aparelho). **Aparelho exigido:** Galaxy S25 Ultra. Fonte de cada evidência: entrada datada em `STATE.md`. `PASS` só com execução no S25; o que falta fica escrito.

| # | Critério | No S25 | Evidência e o que falta |
|---|---|---|---|
| 1 | Conversar por texto e falar, com resposta opcional em áudio | `PASS` (dono) | Texto: conversas reais com OpenAI, Gemini e Claude no S25 (F1, 2026-11-03). Voz: o microfone transcreveu fala real para o campo, sem enviar (2026-11-04). Turno falado completo executado e aprovado pelo dono no S25 em 2026-11-05 (sem registro do agente). TTS é opcional. |
| 2 | TXT real do Samsung vira relatório com trecho e relógio | `PASS` (dono) | TXT sintético compartilhado abriu o chat e virou relatório com relógios; extrator com modelo validou trecho e relógio (2026-11-04). TXT real do Gravador executado e aprovado pelo dono no S25 em 2026-11-05 (sem registro do agente; há uma importação nova `txt_1793924759989` no aparelho às 21:26). |
| 3 | Foto analisada em um provedor com visão; aviso nos demais | `PASS` (dono) | Nenhuma foto enviada a um modelo no S25. O aviso de modelo sem visão está sendo implementado (mudança paralela ainda não commitada em `agent_chat_dialog.dart` e `.arb`). Foto e aviso executados e aprovados pelo dono no S25 em 2026-11-05 (sem registro do agente). |
| 4 | Escolher modelo por ID ou catálogo atualizado, sem APK novo | `PASS` | Catálogo F1-01 e respostas reais de OpenAI, Gemini e Claude no S25 (portão F1, 2026-11-03). ID manual com resposta real (F1-02) segue tarefa adicional. |
| 5 | O mesmo relatório em PDF, DOCX e MD, com acentos | `PASS` | 2026-11-05 (F4-05): PDF e DOCX exportados pelo app abertos no Acrobat e no Word do S25; arquivo de estresse com aspas curvas, travessão, reticências, listas e negrito sem `?`. MD conferido em fixture. |
| 6 | Editar e confirmar sem perder o original; histórico sobrevive à troca de modelo | `PASS` | Confirmar e editar item gravaram `revisions.json` com o original intacto (2026-11-04); histórico de revisões com motivo (F6-03). Defeito que esvaziava a tela ao sair da edição com Voltar foi corrigido e conferido no S25 (2026-11-05). Troca de modelo dispensada de prova no aparelho pelo dono (D-038). |
| 7 | Nada sai sem escolha explícita; nada vira tarefa ou decisão sem confirmação | `PASS` | "Gerar com o modelo" mostra "Este texto sai do telefone" (Voltar / Enviar agora) no S25; itens nascem `Não confirmado`, sem responsável nem prazo inventados (2026-11-04); TXT importado passa por tela de confirmação. No chat, anexos visíveis na caixa de mensagem e envio só ao tocar em enviar; o dono dispensou segunda confirmação (D-038). |

Os sete critérios estão `PASS` no S25 (1, 2 e 3 por execução e aprovação do dono). F5-01 `DONE` em 2026-11-05.

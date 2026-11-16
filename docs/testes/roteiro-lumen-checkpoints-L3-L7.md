# Roteiro — checkpoints reais do Lumen (L3 a L7)

Pré-requisito já verificado em 2026-11-15: suíte sintética do Lumen verde (`npx tsc --noEmit`, `npm test` 721/0, `cargo test --lib` 743/0/9 ignorados, `npm run build`). Este roteiro cobre só a validação **real**, que hoje está `NOT_RUN`.

Regra: cada passo com resultado `PASS`, `FAIL` ou `NOT_RUN`. Anotar a hora. Não colar links de pareamento, chaves ou tokens em lugar nenhum.

## Parte A — Notebook (Lumen)

### L3 — Anotador e personas (ditado real)
| # | Passo | Esperado |
|---|---|---|
| A3.1 | Lumen aberto. Ditar uma nota pelo atalho de anotador (`notes_start`, modo voz, só microfone) | Nota criada; sem gravação de áudio do sistema |
| A3.2 | Ditar uma ideia (`notes_idea`) | Segunda nota criada |
| A3.3 | Esperar o comentário de persona | Exatamente **um** comentário por persona sorteada, sem duplicar ao reabrir a nota |
| A3.4 | Fechar e reabrir o Lumen; abrir a nota | Comentário continua lá, não é gerado de novo |

### L4 — Tarefas por voz com aviso no horário
| # | Passo | Esperado |
|---|---|---|
| A4.1 | Ctrl+Alt+K e ditar "Lumen teste L4 em dez minutos" | Cartão de confirmação; **nada gravado** antes de clicar Confirmar |
| A4.2 | Ambiguidade: ditar "Lumen teste sexta de manhã" | Cartão pede data/hora explícita; não grava sozinho |
| A4.3 | Confirmar a tarefa com horário em +10 min e pré-alerta padrão | Tarefa em **Hoje**, com prioridade normal |
| A4.4 | Esperar o horário | Toast nativo do Windows com ações Adiar, Concluir, Abrir |
| A4.5 | Clicar **Adiar** | Toast some; tarefa mostra adiada +10 min |
| A4.6 | Esperar de novo e clicar **Concluir** | Tarefa vai para **Concluídas**; sem novo aviso |
| A4.7 | Apagar a tarefa de teste | Some; registrar |

### L5 — E-mail (MailCraft real)
Pré-requisito: `mailcraft-cli` instalado e conta de teste **sua** conectada. Não usar caixa de cliente.
| # | Passo | Esperado |
|---|---|---|
| A5.1 | Hub → E-mail → resumir a caixa de entrada | Resumo gerado; nenhuma mensagem enviada |
| A5.2 | Pedir rascunho de resposta a um e-mail de teste | Rascunho salvo na pasta de rascunhos; **nada enviado** (conferir na caixa de Enviados) |
| A5.3 | Tentar acionar envio (se a interface oferecer) | Bloqueado; registrar a mensagem |

### L7 — Google: backup e Calendar (com confirmação)
Pré-requisito: conta Google do dono conectada em Configurações → Integrações.
| # | Passo | Esperado |
|---|---|---|
| A7.1 | Acionar backup agora | Pasta `Segunda Mente/Lumen-PC` no Drive com `lumen-backup-latest.json` |
| A7.2 | Conferir o hash SHA-256 do arquivo no Drive contra o registrado pelo app | Confere; sem segredos no arquivo |
| A7.3 | Restaurar o backup | Pede confirmação dupla; cria snapshot em `BackupRestoreSafety/pre-restore.json`; depois da restauração, tarefas e notas recarregam |
| A7.4 | Criar evento a partir de uma tarefa com data explícita | Pede confirmação dupla; evento criado no Calendar **sem convidados** |
| A7.5 | Conferir o evento no Calendar | Sem convidados; nenhum evento existente editado ou removido |
| A7.6 | Limpeza | Apagar o evento de teste e o arquivo de backup de teste no Drive |

## Parte B — S25 Ultra (Segunda Mente ↔ Lumen, L6)

Pré-requisito: o S25 está **revogado** desde o T18 de 2026-11-15. Parear de novo antes de tudo.

| # | Passo | Esperado |
|---|---|---|
| B6.0 | Lumen: Configurações → Celular Android → **Parear de novo** → escanear o QR com o S25 (ou colar o link pelo botão de colar) | "Pareado com …" nos dois lados |
| B6.1 | S25: Todo → Sincronizar agora | Sincroniza; log `Todo sync (...) -> synced` |
| B6.2 | **Desligar o S25** (ou Wi-Fi e dados desligados e modo avião) | Sem rede no celular |
| B6.3 | Lumen: criar tarefa `PONTE L6 <hora>` com horário em +10 min | Salva no PC; "Salvo neste PC" |
| B6.4 | Ligar o S25 e abrir a Segunda Mente | Sincroniza na abertura; tarefa aparece **uma vez** |
| B6.5 | Conferir o alarme do S25 | Dispara no horário; notificação única |
| B6.6 | Concluir no Lumen; sincronizar o S25 | Alarme e notificação cancelados no S25 |
| B6.7 | Limpeza | Apagar as tarefas `PONTE L6` nos dois lados; 0 alarmes ativos |

## Parte C — Resultados

Preencher ao executar, com `PASS`, `FAIL` ou `NOT_RUN` por passo e a hora. Não registrar conteúdo pessoal nem dados de clientes.

### Rodada de 2026-11-15 (noite), relatada pelo dono

| Bloco | Resultado |
|---|---|
| L3 (A3.1–A3.4) | PASS |
| L4 (A4.1–A4.7) | PASS |
| L5 (A5.1) | **FAIL** às 21:23: "Falha ao resumir caixa. Servidor MCP encerrou a saída inesperadamente." A5.2 e A5.3 `NOT_RUN`. Refeito depois da correção abaixo: A5.1 e A5.2 **PASS** |
| L6 (B6.0–B6.7) | PASS |
| L7 (A7.1–A7.6) | PASS |

Causa do FAIL da L5 (diagnóstico por reprodução local, sem ler conteúdo de e-mail): o comando MCP salvo no Lumen (`%APPDATA%\Coucou\mail\backend.json`) é `mailcraft-cli.exe mcp --file`, sem o caminho da caixa. O CLI responde `error: mcp: --file needs a value` e sai; o Lumen descarta o stderr e só mostra o fechamento da saída. Com o caminho, `status`, `list_folders` e `list_messages` respondem normalmente (modo headless, só leitura). Para salvar rascunho, o MailCraft precisa estar aberto com `--control 7991` (grava `control-key.local-7991`); sem isso, o modo conectado responde `no control key`.

Correção e nova rodada (2026-11-15, 22:10–22:30):
- Lumen: `backend.json` trocado para `mode: control`, porta 7991, `mcpCommand` vazio (backup em `backend.json.bak-20261115`); Lumen reiniciado.
- MailCraft reaberto com `--control 7991` (porta `127.0.0.1:7991` em LISTEN, `control-key.local-7991` criado). A primeira abertura morreu junto com o terminal da ferramenta e o Lumen caiu no modo só leitura ("MailCraft conectado só para leitura local"); a segunda, num processo à parte, ficou de pé.
- A5.1 resumo da caixa: **PASS** (dono). A5.2 rascunho: **PASS** (dono). A5.3 tentativa de envio: `NOT_RUN` (envio bloqueado em código e coberto por teste).
- Código: branch `fix/mailcraft-mcp-erro` do Lumen (`5635bac`) passa a recusar `--file`/`--connect` sem valor com mensagem clara e a mostrar o fim do stderr quando o servidor MCP sai; `cargo test --lib` 745 aprovados, 0 falhas, 9 ignorados.
- Limite: o `--control 7991` vale só para esta abertura do MailCraft; abrir pelo atalho normal volta a deixar o rascunho só leitura.

Pendências conhecidas que podem bater nestes testes: QR pequeno demais para a câmera do S25 (achado aberto no Lumen); edição de horário que não salva (achado aberto no Lumen).

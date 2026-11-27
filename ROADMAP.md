# ROADMAP — Segunda Mente

Índice das fases. Cada fase tem o próprio documento, com subfases, critérios e portão: as abertas ficam em [docs/roadmap/](docs/roadmap/) e as concluídas em [docs/arquivadas/roadmap/](docs/arquivadas/roadmap/). Abra só o arquivo da fase em que estiver trabalhando.

**Leia também:** [STATE.md](STATE.md) (estado e próxima ação) · [docs/DECISIONS.md](docs/DECISIONS.md) (decisões) · [docs/WATCHDOG.md](docs/WATCHDOG.md) (regras, estados e prioridades) · [PROJECT.md](PROJECT.md) (escopo)

**Atualizado:** 2026-11-17. Se este resumo divergir do arquivo da fase ou de uma evidência posterior em STATE.md, valem o arquivo da fase e a evidência.

## Ordem de trabalho

1. **F14 e F15:** validar no Galaxy S25 Ultra o que já tem código (assistente ativo, chat flutuante, widgets, painel rápido, bolha).
2. **F12:** sync com o Lumen. Depois do checkpoint da ponte, segue a tabela da fase.
3. **F13:** Google, quando o dono criar o projeto Google Cloud.
4. **Pausadas por D-050:** F5V, F9 e F10, sem perda; retomar exige nova decisão. F8 segue BLOCKED.

O lado desktop (Lumen) tem roadmap próprio no repositório `playertwo1/coucou`.

## Fases abertas

| Fase | O que faz | Estado |
|---|---|---|
| [F1 — Registro de modelos](docs/roadmap/F1-registro-de-modelos.md) | Catálogo de modelos, provedores e troca de modelo | IN_PROGRESS: critério do MVP cumprido, 4 subfases extras abertas |
| [F2 — Chat, voz e importação](docs/roadmap/F2-chat-voz-e-importacao.md) | Conversa persistente, voz e arquivos importados com consentimento | IN_PROGRESS: critérios do MVP cumpridos, 8 subfases extras abertas |
| [F3 — Extração e relatório](docs/roadmap/F3-extracao-e-relatorio.md) | Relatório editável e fiel às fontes, com itens não confirmados por padrão | IN_PROGRESS: critério do MVP cumprido, 3 subfases extras abertas |
| [F5V — Redesign visual](docs/roadmap/F5V-redesign-visual.md) | Direção AMOLED aplicada nas telas existentes | PAUSED (D-050) |
| [F7 — Voz contínua e ponte CLI](docs/roadmap/F7-voz-continua-e-ponte-para-clis-oficiais.md) | Voz full duplex, modelo local e integração com CLIs oficiais | IN_PROGRESS: F7-03 DONE; F7-02 adiada (D-041); F7-06 BLOCKED |
| [F8 — NotebookLM](docs/roadmap/F8-notebooklm.md) | Exportar conteúdo escolhido para o NotebookLM via Google Doc | BLOCKED: pós-MVP sem previsão (D-055) |
| [F9 — Meeting Decoder](docs/roadmap/F9-meeting-decoder.md) | Conversas e PDFs viram relatórios revisáveis, tarefas e encaminhamentos | PAUSED (D-050) |
| [F10 — Criação nos comentários](docs/roadmap/F10-criacao-a-partir-das-conversas-nos-comentarios.md) | Conversas com personas desenvolvem documentos e imagens | PAUSED (D-050) |
| [F12 — Sync com o Lumen](docs/roadmap/F12-sync-com-o-lumen.md) | Celular e Lumen trocam tarefas, notas, conversas e personas por relay e caixa de correio | IN_PROGRESS (D-066): F12-02 a F12-05 DONE |
| [F13 — Google](docs/roadmap/F13-google.md) | Login Google, backup semanal no Drive e Google Calendar | BLOCKED: falta o projeto Google Cloud do dono (D-055) |
| [F14 — Assistente ativo](docs/roadmap/F14-assistente-ativo.md) | Resumos de manhã e de tarde, cobrança de tarefas paradas e sugestões das personas | REVIEW (D-074): código pronto, S25 NOT_RUN |
| [F15 — Widget e atalhos Android](docs/roadmap/F15-widget-e-atalhos-android.md) | Widget redimensionável, chat flutuante, painel rápido e minicápsula | F15-01 DONE; F15-02 a F15-07 com código, S25 NOT_RUN |
| [F16 — Ponte Bluetooth LE com a placa ESP32-S3 AMOLED](docs/roadmap/F16-ponte-placa-esp32.md) | Pareamento PIN 6 dígitos, sync bidirecional de tarefas, notificações e config da placa via BLE GATT | IN_PROGRESS: F16-01 a F16-06 com código e testes; S25 NOT_RUN |

Ideias aprovadas para pensar depois, sem autorização de implementação: [docs/roadmap/IDEIAS-FUTURAS.md](docs/roadmap/IDEIAS-FUTURAS.md).

## Fases concluídas (arquivadas)

| Fase | O que fez | Fechada em |
|---|---|---|
| [F0 — Fundação](docs/arquivadas/roadmap/F0-fundacao.md) | Fork do Memex, identidade, licença e ambiente | 2026-11-03 |
| [F4 — Exportação](docs/arquivadas/roadmap/F4-exportacao.md) | O mesmo relatório em Markdown, PDF e DOCX, com compartilhamento | 2026-11-04 |
| [F5 — Fechamento do MVP](docs/arquivadas/roadmap/F5-fechamento-do-mvp.md) | Aceite dos sete critérios no S25, privacidade, desempenho e auditoria | 2026-11-05 |
| [F6 — Memória longitudinal](docs/arquivadas/roadmap/F6-memoria-longitudinal.md) | Busca semântica, tópicos, histórico de mudanças e encaminhamentos | 2026-11-06 |
| [F11 — Todo robusto](docs/arquivadas/roadmap/F11-todo-robusto-celular.md) | Lista única com Hoje/Próximas/Atrasadas, repetição, subtarefas, alarmes e confirmação da IA | 2026-11-14 |

Histórico das mudanças de escopo do roadmap: [docs/arquivadas/roadmap/historico-de-escopo.md](docs/arquivadas/roadmap/historico-de-escopo.md).

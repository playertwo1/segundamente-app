> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F7 — Voz contínua e ponte para CLIs oficiais

**Objetivo:** avaliar voz mãos-livres com interrupção natural, inferência local opcional e encaminhamento explícito para Claude Code/Codex CLI oficiais no desktop. Esta fase não autoriza captura contínua silenciosa nem uso de credenciais fora dos fluxos oficiais.

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F7-01 | Comparar viabilidade, sistemas desktop, licenças, termos, autenticação e limites de dados; decidir escopo antes de código | P0 | F5 fechado (D-031 abriu só esta linha) | DONE | Matriz de opções, riscos e decisão aceita em docs/DECISIONS.md |
| F7-02 | Medir modelo local no S25 (D-033; antes Ollama) para qualidade em pt-BR, requisitos de hardware e privacidade | P1 | F7-01 | BLOCKED | Tabela de qualidade, latência, RAM/VRAM, tamanho e plataforma; modelo escolhido ou caminho descartado com motivo |
| F7-03 | Implementar voz full duplex opcional com controle explícito, interrupção, pausa, cancelar e estado de microfone visível | P0 | F7-01; F7-02 dispensada por D-047 (não é dependência técnica) | IN_PROGRESS (código e testes prontos; sonda medida no S25 em 2026-11-11; interrupção por toque com microfone fechado enquanto o app fala, D-049; entrada ligada; tela no aparelho `NOT_RUN`) | Testes de início, interrupção, cancelamento, erro, permissão e liberação do microfone; nenhuma gravação sem ação visível; eco, latência, bateria e aquecimento medidos no S25 (`docs/fases/F7-03-voz-duplex.md`) |
| F7-04 | Criar ponte desktop opcional para Claude Code e Codex CLI oficiais, com escopo e prévia de cada solicitação | P0 | F7-01 | CANCELLED | Teste com cada CLI instalada; destino/comando visíveis, confirmação antes de enviar ou executar, cancelamento sem efeito e falha sem perda de contexto |
| F7-05 | Decidir se uma interface MCP é necessária e, se aprovada, restringir ferramentas e permissões | P2 | F7-01, F7-04 | CANCELLED | Decisão explícita; se implementada, teste de acesso somente aos recursos autorizados e ausência de escrita em Quick Query |
| F7-06 | Validar privacidade, acessibilidade, segurança, termos e funcionamento nos sistemas escolhidos | P0 | F7-02 a F7-05 | BLOCKED | Auditoria sem bloqueios, resultados de testes e execução real registrados em STATE.md |

**Portão F7:** requisitos de plataforma e termos decididos; voz e ponte funcionam nos sistemas aprovados; toda captura e todo encaminhamento são iniciados pelo usuário; testes e auditoria sem bloqueios. A ponte não pode contornar autenticação nem termos do fornecedor.

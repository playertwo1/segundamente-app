> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F1 — Registro de modelos

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F1-01 | Catálogo de modelos por provedor, com versão/cache e estado recomendado, acessível ou não testado | P0 | F0 | DONE | Testes unitários e tela de seleção; status não afirma disponibilidade sem prova |
| F1-02 | Permitir ID de modelo e base URL personalizados | P1 | F1-01 | IN_PROGRESS | ID fora da lista selecionado e respondendo em chamada real |
| F1-03 | Teste de conexão e matriz de texto, streaming, JSON, visão e áudio | P0 | F1-01 | DONE | Respostas reais de OpenAI, Gemini e Claude registradas no S25; capacidades descritas sem extrapolar os testes |
| F1-04 | Validar OAuth OpenAI/Gemini e documentar riscos de termos | P1 | F0-05 | DONE | Login de ambos no S25; endpoint e ressalvas registrados |
| F1-05 | Validar Claude por chave de API e endpoint compatível/local, se disponíveis | P2 | F1-02 | NOT_RUN | Uma resposta real por configuração; indisponibilidade deve ser registrada como NOT_RUN |
| F1-06 | Trocar provedor/modelo sem perder o histórico | P0 | F1-01 | DONE | Conteúdo da conversa permanece após troca |
| F1-07 | Manter os IDs gpt-6-luna, gpt-6.1-sol e gpt-6.1-terra selecionáveis no OAuth OpenAI | P1 | F1-03 | IN_PROGRESS | Chamada real de cada ID; erro claro para ID indisponível e opção manual por F1-02 |
| F1-08 | OAuth Claude e modelos Claude previstos em D-015 | P1 | F1-04 | DONE | Login PKCE e respostas reais registradas em STATE.md |
| F1-09 | Mostrar, nas configurações, qual provedor/modelo transcreve e qual resume/conversa, além dos dados enviados | P1 | F1-03, F2-09 | IN_PROGRESS | Widget test e validação S25 para OAuth, chave de API e modelo local; endpoint de transcrição claramente identificado |
| F1-10 | Failover configurável entre provedores, com ordem visível e reordenável | P1 | F1-03, F1-04 | DONE | Testes do FallbackLLMClient e prioridade drag-and-drop registrados |

**Portão F1:** cumprido segundo STATE.md. O critério 4 do MVP aceita seleção por catálogo atualizado ou por ID; F1-01 e respostas de múltiplos provedores provam a opção por catálogo. F1-02, F1-05 e F1-07 permanecem tarefas adicionais e não invalidam esse portão.

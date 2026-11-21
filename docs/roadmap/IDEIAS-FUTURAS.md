> Parte do [ROADMAP](../../ROADMAP.md). Ideias aprovadas para pensar depois; nenhuma está autorizada para implementação.

# Ideias futuras

| Ideia | Condição para reavaliar |
|---|---|
| Grafo temporal Graphiti ou mapa visual global de tópicos | Depois de F6-04/F6-09 demonstrarem que listas não bastam |
| Gemma local e voz mãos-livres | Dentro de F7, após medir qualidade pt-BR, hardware e privacidade |
| Backup automático versionado que inclua configurações padrão | Revisão futura do backup; definir retenção e restauração antes |
| Separação de falantes/voiceprint | Se as transcrições reais não preservarem identificação suficiente; medir no S25 |
| Interface MCP para agentes externos | Decisão da F7-05 e limites de permissão aprovados |
| Escolher idioma do resumo pelo idioma predominante | Só se o produto voltar a suportar mais de en e pt |
| Biblioteca agregada de fotos, PDFs e áudios | Autorizada por D-081 (2026-11-21) |
| Índice semântico gravado no banco (Drift): guardar o vetor de cada item e calcular só os novos | Reserva da F6-01 (hoje o índice vive só na memória do app). Reavaliar se a primeira busca do dia passar de ~2 s ou o histórico passar de alguns milhares de itens; medir antes no S25 |
| Modelo local no aparelho (F7-02): Gemma 4 E2B/E4B pelo LiteRT-LM (Apache-2.0) | Adiado pelo dono em 2026-11-06 (D-041); nada implementado. No PC o E2B acertou 23/40 (57,5%) no corpus da F9-02 com o melhor prompt; falta comparar com o modelo remoto + regra da F3-07 e medir velocidade/RAM no S25. Detalhes em `docs/fases/F7-02-medicao.md` e `docs/fases/F7-02-pesquisa-modelos.md` |
| Chave Gemini como reserva de transcrição | Se o caminho D-011 falhar ou se os limites medidos forem insuficientes |
| Conversas guiadas por perfil: o Advogado do Diabo define a ideia/hipótese, apresenta uma objeção por turno, recebe a réplica e termina com veredito equilibrado e resumo opcional; outros personagens podem ter ciclos próprios, como professor com perguntas e exercício ou planejador com alternativas, riscos e próximo passo. O usuário pode responder, pular ou encerrar; conclusões só viram registros após salvamento explícito. | Reavaliar após o fechamento da F5 e a validação dos chats da F5V; experimentar em dois perfis e definir controles, formato das saídas e o que pode ser salvo antes de abrir uma tarefa de implementação |
| Resumo e próximo evento no widget Android (D-062) | Depois que F13 (Calendar) e F14 (assistente ativo) tiverem dados |
| Captura sem sair do app pela minicápsula: anotar ou mandar print ou trecho para a linha do tempo (D-062) | Depois que a F15-07 medir a bolha no S25 e a F15-02 estiver validada no S25 |
| Assistente que vê a tela, por leitura de acessibilidade (D-062) | Exige decisão própria antes de qualquer trabalho: risco alto de privacidade, pois lê e-mails e mensagens de terceiros |

Ideias já avaliadas e distribuídas em tarefas ficam nas decisões D-014, D-016 e D-018; não reabrir essas pesquisas sem uma lacuna concreta.

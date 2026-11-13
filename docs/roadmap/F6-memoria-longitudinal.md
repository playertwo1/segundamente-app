> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F6 — Memória longitudinal

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F6-01 | Buscar sessões e itens entre registros, começando por texto e avançando para semântica | P0 | D-010, F3 | DONE | Busca textual + MiniLM int8 local no S25: ONNX alinhado ao sherpa (1.24.3), download verificado, busca em Encaminhamentos e `find_related_sessions` no chat validados; corte 0,42 provisório, calibrar com o uso|
| F6-02 | Listar encaminhamentos aprovados sem incluir sugestões pendentes ou tarefas internas dos agentes | P0 | F3-05 | DONE | Painel no S25 exibe apenas item confirmado; validar estado vazio, busca e acesso pelo fluxo normal |
| F6-03 | Mostrar o que mudou e preservar histórico de versões e motivo | P0 | F3-06 | DONE | Alteração cria revisão com motivo explícito ou 'não informado'; exclusão remove derivados e preserva original; testes cobrem ReportRevision, SessionReportService, revisions.json, FollowUpsView e SessionReportView |
| F6-04 | Criar tópicos/projetos como entidade própria e relacioná-los a sessões | P1 | F6-01 | DONE | Modelo, migração, UI e persistência no S25; renomear, excluir com diálogo e desvínculo automático na exclusão de sessão |
| F6-05 | Organizar tags hierárquicas como area/projeto, com árvore e contagens | P1 | D-014 | DONE | Pai soma filhos; tag simples fica na raiz; tocar filtra; testes e prova visual no S25 |
| F6-06 | Combinar filtros de propriedade e salvar visões locais | P1 | F6-01 | DONE | Filtros combinam por E; persistência, renomear/apagar e propriedades derivadas (@prop:link, @prop:code, @prop:open_task) validadas no S25 |
| F6-07 | Mostrar prévia opcional de URL, desligada por padrão | P2 | F5-02 | DONE | Somente HTTP/HTTPS; recusa localhost e IPs privados; handshake TLS corrigido para HTTPS no S25; prévia real renderizada |
| F6-08 | Mostrar intensidade de atividade por dia no calendário mensal | P2 | D-014 | DONE | Cinco níveis: 0, 1, 2, 3–4, 5+; contraste e leitura de hoje/seleção permanecem corretos |
| F6-09 | Recuperar sessões relacionadas a perguntas com sementes, tópico e limite de relevância | P1 | F6-01, F6-04 | DONE | Sementes de texto e irmãs por tópico validadas no S25; SuperAgent chama find_related_sessions x1 sem pesquisa pesada e responde sobre a sessão irmã |
| F6-10 | Medir embeddings locais multilíngues para busca em português antes de decidir implementação | P2 | F6-09 | DONE | Comparação textual/semântica em pt-BR, medição de tamanho, tempo e memória no S25 e comparação local com 24 cartões; decisão D-039 documentada |
| F6-11 | Oferecer “Adicionar à agenda” em encaminhamento aprovado com data explícita | P2 | F6-02 | DONE | ACTION_INSERT abre calendário com título e descrição pré-preenchidos; validado no S25 com vencimento 20/11/2026 |
| F6-12 | Gerar Insights de Conhecimento automaticamente depois que um registro é salvo, em lote, sem depender do chat | P1 | F6-09, F5V-02 | DONE | Registro salvo enfileira uma análise agrupada e sem repetição; sem evidência entre registros não grava insight nem cartão de resumo; resumo de insight não dispara nova análise; no S25, com modelo real, o insight aparece com `related_facts` e a tela atualiza |

**Definições de F6-05 a F6-08:**

- **F6-05:** a barra / define níveis, por exemplo trabalho/reuniao. A contagem do nó inclui os cartões de seus descendentes. Não renomear/mover tags em lote nem adicionar integração P.A.R.A. sem decisão.
- **F6-06:** propriedades derivadas incluem presença de link, tarefa, tarefa aberta e código. Filtro pode combinar texto, tag e data. Visão salva contém nome e filtro em arquivo local; sem linguagem de consulta aberta e sem sincronização.
- **F6-07:** busca de metadados com cache, limite de tamanho/tempo e sem cabeçalhos/cookies do usuário. A proteção contra requisição a endereços privados é obrigatória antes de ligar a função.
- **F6-08:** usar a contagem existente de cartões por dia. Não acrescentar visão anual nem sequência/streak nesta tarefa.

**Definições adicionais:**

- **F6-09:** a busca textual escolhe as sementes primeiro; com a F6-01 ligada, a busca semântica pode acrescentar itens acima do corte quando o texto encontra menos de 3. Sessões com tópicos em comum vêm depois por relevância e data, dentro do orçamento de caracteres. Sem sementes, nenhuma sessão é retornada.
- **F6-10:** avanço autorizado pela medição em pt-BR e pela decisão D-039; bateria/calor prolongados ficam como limites registrados, sem bloquear a comparação definida para esta tarefa.
- **F6-11:** abrir o aplicativo de calendário Android com os campos preenchidos via ACTION_INSERT. Não ler a agenda, não sincronizar e não salvar automaticamente.

**Portão F6:** busca semântica, tópico/projeto como entidade própria, histórico com motivo, painel de encaminhamentos e integração de agenda conforme escopo. F6 foi aberta sob D-010 enquanto F0–F5 estavam abertas. Estado em 2026-11-06: o MVP foi fechado (F5 com `AUDIT RESULT: PASS`). Tópico/projeto como entidade própria (F6-04), histórico com motivo da revisão (F6-03), visões salvas (F6-06), prévia de link (F6-07), sessões relacionadas no chat (F6-09) e "adicionar à agenda" (F6-11) estão `DONE` com prova no S25. F6-02, F6-05, F6-08 e F6-12 ficaram `DONE` em 2026-11-05 com prova no S25. F6-10 está `DONE` com as medições e D-039; F6-01 ficou `DONE` em 2026-11-06 com prova no S25 (ONNX alinhado ao sherpa, busca em Encaminhamentos e `find_related_sessions` no chat); corte 0,42 provisório e índice só em memória estão declarados como limites. Os 12 itens estão `DONE`; portão fechado em 2026-11-06 (D-040), sem auditoria própria como a da F5.

### Ordem das tarefas adicionais F1/F2/F3/F6

1. Provar pendências no S25: F2-09, F2-10, F2-03 e F1-07, em paralelo à F5 quando o aparelho estiver disponível.
2. Implementar F1-09, F3-08 e F3-07 em sequência conforme dependências e prioridade do uso diário.
3. Depois: F2-13, F2-11 e F2-12, respeitando os respectivos estados e dependências.
4. F6: F6-11, F6-08, F6-05, F6-09 e F6-06; F6-04 precisa existir antes da expansão por tópico em F6-09.
5. F3-09, F6-10 e F6-07 só avançam após cumprir seus critérios de medição, segurança ou dependência. F1-05 também depende de chave/endpoint disponível.

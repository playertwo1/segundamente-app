> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F3 — Extração e relatório

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F3-01 | Esquema versionado de sessão, segmentos, itens e fontes, independente do provedor | P0 | F2 | DONE | Migração e testes; o esquema atual não possui entidade Topic |
| F3-02 | Extrair JSON validado com resumo, ideias, oportunidades, decisões, tarefas, follow-ups e dúvidas | P0 | F3-01 | IN_PROGRESS | S25 validou saída de modelo em reunião sintética; falta amostra real de 53 min e avaliação da cobertura/comportamento em sessão longa |
| F3-03 | Tipos de relatório: livre, reunião, brainstorm, diário, estudo e título personalizado | P1 | F3-02 | DONE | Testes demonstram seções e título por tipo |
| F3-04 | Vincular cada item ao segmento/relógio de origem e permitir abrir a fonte | P0 | F3-02 | DONE | Fixture de teste abre o segmento e relógio corretos; original permanece acessível |
| F3-05 | Deixar sugestões não confirmadas até decisão humana; não inventar responsável ou prazo | P0 | F3-02 | DONE | Fixture prova estado inicial pendente e valores “não identificado”/“não informado” |
| F3-06 | Editar, confirmar, descartar, buscar e excluir relatório e derivados sem alterar o original | P1 | F3-05 | DONE | Fixtures provam edição, estados, busca e exclusão com original preservado |
| F3-07 | Reduzir falsos positivos e duplicatas na extração de tarefas | P1 | F3-02 | IN_PROGRESS | Casos positivos/negativos pt-BR; narração, opinião e fato passado não viram tarefa; duplicata não entra duas vezes |
| F3-08 | Regras de resumo em português, preservação das notas do usuário e regeneração sem apagar a versão anterior | P1 | F3-02 | IN_PROGRESS | Teste por regra e validação no S25; título vazio não vira relatório em branco |
| F3-09 | Correção conservadora da transcrição em arquivo separado, sem reescrever nem traduzir o original | P2 | F2-04, F3-08 | DONE | Só substituições autorizadas de palavras/trechos existentes; teste recusa índices/operações inválidos e compara original byte a byte |

**Estado específico de F3-02:** em 2026-11-04, a tela do relatório enviou a reunião sintética ao modelo após confirmação explícita e recebeu resumo, decisão, tarefa e ideia como itens não confirmados. A validação recusou evidência inventada; responsável, prazo e status enviados pelo modelo não foram aceitos. Testes de serviço, parsing, prompt e diálogo foram registrados. A amostra real de 53 min continua NOT_RUN. O limite atual é 60000 caracteres em uma chamada; acima dele o fluxo usa o rascunho local, sem divisão por tempo.

**Regras da extração de tarefas (F3-07):** extrair somente compromissos claros; ignorar narração, opinião, fatos passados e comentários sobre o app. Limitar a quantidade/tamanho segundo a implementação validada. Deduplicar sem confundir ações diferentes, como “ligar para o pai” e “ligar para a mãe e o pai”. Resposta inválida nunca gera nota vazia. Nenhum item vira tarefa definitiva sem confirmação.

**Regras do resumo (F3-08):** preservar detalhes concretos e marcas do usuário; não iniciar com texto genérico; separar conteúdo anterior e conteúdo da sessão quando aplicável; próximos passos só incluem responsável e prazo ditos explicitamente; devolver conteúdo no formato pedido sem comentário extra. Regenerar conserva o relatório anterior até o usuário aceitar o novo.

**Portão F3:** os critérios do relatório do MVP e a extração com modelo foram demonstrados em reunião sintética no S25. Falta processar uma amostra real de aproximadamente 53 min e comprovar que pontos relevantes e relógios não se perdem. O portão permanece aberto.

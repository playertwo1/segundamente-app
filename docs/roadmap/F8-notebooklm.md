> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F8 — NotebookLM

**Estado:** BLOCKED, pós-MVP sem previsão (D-055, 2026-11-13). Caminho já escolhido: via B (criar/atualizar Google Doc do conteúdo escolhido, com prévia), usando o login Google da F13. Plano do dono: NotebookLM Pro.

**Objetivo:** permitir levar material selecionado ao NotebookLM por um fluxo opt-in, começando por uma exportação controlada para Google Docs. Não presumir que API, importação direta ou integração comunitária sejam suportadas.

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F8-01 | Verificar capacidades atuais, requisitos, termos, autenticação e fluxo suportado pelo NotebookLM | P0 | F5 fechado, F4 estável | IN_PROGRESS | Pesquisa em fontes oficiais e decisão de escopo registrada, incluindo dados que deixam o aparelho |
| F8-02 | Exportar apenas conteúdo selecionado para Google Docs, com destino e conteúdo visíveis antes de autorizar | P0 | F8-01 | BLOCKED | Documento criado na conta escolhida; cancelar não cria/exporta; origem e conteúdo conferidos |
| F8-03 | Avaliar conector comunitário opt-in, licença, segurança, manutenção e compatibilidade | P1 | F8-01, F8-02 | BLOCKED | Avaliação registrada; integrar somente após aprovação e sem tornar caminho comunitário requisito do MVP |
| F8-04 | Avaliar eventual API empresarial apenas se existir caso de uso e benefício comprovados | P2 | F8-01 | BLOCKED | API, custo, termos e necessidade verificados em fonte oficial; decisão aceita antes de qualquer integração |
| F8-05 | Validar consentimento, revogação, segurança, exportação e comportamento quando o serviço está indisponível | P0 | F8-02; F8-03/F8-04 se aprovados | BLOCKED | Testes e revisão demonstram operação opt-in, cancelamento e ausência de upload/sincronização automática |

**Ordem prevista:** Via A, Google Docs; Via B, conector comunitário somente se aprovado; Via C, API empresarial somente se existir e justificar. Cada via depende da conclusão da anterior ou de uma decisão documentada para descartá-la.

**Portão F8:** apenas capacidades confirmadas e autorizadas foram integradas; o usuário escolhe conteúdo, conta e destino; nenhuma sincronização bidirecional ou envio automático ocorre.

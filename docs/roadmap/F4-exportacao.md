> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F4 — Exportação

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F4-01 | Exportar Markdown com título, data, seções, itens e fontes | P0 | F3 | DONE | Fixture gerado e conferido |
| F4-02 | Exportar PDF legível com acentos pt-BR e hierarquia de títulos | P0 | F4-01 | DONE | PDF aberto no Adobe Acrobat do S25; acentos e hierarquia conferidos; exportação mantém fontes e relógios do relatório |
| F4-03 | Exportar DOCX legível e editável | P0 | F4-01 | DONE | DOCX aberto no Word do S25; acentos, títulos e conteúdo exportado conferidos |
| F4-04 | Compartilhar ou salvar relatório inteiro/selecionado sem enviar a serviço remoto sem consentimento | P1 | F4-01 | DONE | Teste comprova exportação de seleção; folha nativa Android abriu para PDF e DOCX no S25 sem envio automático |
| F4-05 | Exportador compartilhado: PDF por biblioteca (`pdf`) com fonte embutida, quebra por palavra, listas e negrito; DOCX com listas e negrito; serve relatório de sessão, F10 e F9 (D-037) | P1 | F4-02, F4-03 | DONE | Aspas curvas, travessão e reticências sem "?"; nenhuma palavra cortada; testes de exportação passando; PDF no Acrobat e DOCX no Word do S25 conferidos em 2026-11-05 |

**Portão F4:** cumprido em 2026-11-04. Markdown foi conferido no fixture; o PDF foi aberto no Acrobat e o DOCX no Word do S25, ambos com acentos e títulos corretos. O teste de exportação também cobre relatório completo e seleção de itens. A integração externa escolhida pelo usuário continua sujeita ao consentimento normal do sistema.

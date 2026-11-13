> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F13 — Google

**Estado:** BLOCKED até o dono criar o projeto Google Cloud (D-055).

**Objetivo:** um login Google próprio do app (produção sem verificação, uso pessoal), usado para backup semanal no Drive e para o Google Calendar, no celular e no Lumen.

**Limites:** escopos mínimos; credenciais e client IDs fora do repositório; login do Gemini (D-013) não é base. Calendar: nunca apagar/alterar evento sem confirmação, nunca convidar terceiros. NotebookLM fica na F8 (pós-MVP).

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F13-01 | Guia e criação do projeto Google Cloud pelo dono (tela de consentimento em produção, escopos) | P0 | D-055 | BLOCKED | Projeto criado; IDs guardados fora do repositório |
| F13-02 | Login e logout Google no celular, com revogação | P0 | F13-01 | BLOCKED | Login no S25; token no cofre do aparelho; teste de serviço |
| F13-03 | Backup semanal completo no Drive (pasta própria, subpasta por aparelho) e restauração | P0 | F13-02 | BLOCKED | Restaurar preserva nota→tarefa→persona→comentário (AC-09, T12) |
| F13-04 | Calendar: ler eventos para lembretes/resumos e criar evento a partir de tarefa confirmada | P1 | F13-02, F11-03 | BLOCKED | Evento lido e criado no S25; cancelar não cria nada |
| F13-05 | Mesmo login, backup e Calendar no Lumen | P1 | F13-02; fase L do fork | BLOCKED | Evidência registrada no roadmap do fork |

**Portão F13:** backup restaurado com sucesso e Calendar funcionando nos dois aparelhos.

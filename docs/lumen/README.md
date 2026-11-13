# Lumen + Segunda Mente

- `pacote-v1/`: pacote de planejamento original, copiado sem alterações de `Downloads/sefgundamentedesktop/Segunda_Mente_Lumen` em 2026-11-13. O DOCX tem o mesmo conteúdo dos `.md`.
- Decisões que valem: [questionário de 2026-11-13](../questionario/2026-11-13-lumen-desktop-e-todo.md) e D-050 a D-055 em [DECISIONS.md](../DECISIONS.md).

Onde o pacote diverge das decisões, valem as decisões. As principais diferenças são estas:
- O desktop não é Flutter Windows com Tauri como casca. É o fork `playertwo1/coucou` renomeado Lumen (D-053).
- O Todo é uma lista única, sem listas ou projetos (D-051).
- O sync usa o relay do Coucou com uma caixa de correio no Cloudflare do dono (D-054).
- Os dados do trabalho entram, mas só agenda, tarefas e ideias, sem dados de clientes. O pacote previa só dados fictícios (D-050).
- Entra o e-mail pessoal pelo MailCraft (D-053). O Google Calendar entra no lugar do calendário externo pós-MVP (D-055).

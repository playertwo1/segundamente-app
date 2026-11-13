# Segunda Mente — instruções para o Claude Code

O arquivo canônico é o [AGENTS.md](AGENTS.md). Ele vale para todos os agentes e prevalece sobre este. Leia-o inteiro antes de editar:

@AGENTS.md

## Lembretes rápidos
- Ordem de leitura: `STATE.md`, depois `ROADMAP.md`, depois o arquivo da fase em `docs/roadmap/`, depois `docs/DECISIONS.md`.
- Mudança de comportamento exige teste no mesmo commit: unitário para lógica, widget para UI e de integração para fluxos que cruzam camadas.
- O que não foi executado é `NOT_RUN`. Fluxos de notificação, áudio e permissão são validados no S25.
- Push só para `origin` (`playertwo1/segundamente-app`, privado). Nunca para `upstream`.
- O lado desktop (Lumen) vive em outro repositório: `playertwo1/coucou`.

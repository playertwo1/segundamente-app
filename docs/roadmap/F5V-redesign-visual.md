> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F5V — Redesign visual

**Estado:** PAUSED por D-050 (2026-11-13); as linhas abaixo guardam o estado de cada subfase no momento da pausa.

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F5V-01 | Aplicar tokens AMOLED e navegação superior sem barra inferior persistente | P1 | D-017, D-022 | DONE | Testes de widget e capturas no AVD; navegação superior e ausência da barra inferior conferidas; validação global no S25 fica em F5V-05 |
| F5V-02 | Aplicar direção visual à timeline, cartões, conhecimento, insights e memórias | P1 | F5V-01 | IN_PROGRESS | Estados principais e famílias de cartão cobertos por testes; comparação com pranchas; discrepâncias registradas |
| F5V-03 | Atualizar entrada, conversa, anexos, importação TXT e acesso explícito a Conversar | P1 | F5V-01 | IN_PROGRESS | Fluxos de abrir, revisar, cancelar, importar e erro cobertos por teste e evidência visual |
| F5V-04 | Atualizar calendário, detalhes, compartilhar, relatórios, configurações, modelos, agentes e backup | P1 | F5V-01 | IN_PROGRESS | Testes de interação e capturas das famílias de tela; sem remoção de funções suportadas |
| F5V-05 | Revisar estados vazios/erro, escala, contraste, leitor de tela e aparelho | P1 | F5V-02, F5V-03, F5V-04 | NOT_RUN | Checklist de acessibilidade, capturas comparadas e validação final no S25 registradas |

**Direção aprovada:** DESIGN.md e as pranchas em docs/INDEX.md. Usar temas/componentes existentes e mapear rotas antes de alterar navegação. Mudança de interação precisa de teste de widget conforme AGENTS.md. F5V não fecha F0–F5.

**Distribuição das pranchas:** 12/13, 14 e 17 em F5V-02; 20 também em F5V-02; 22 em F5V-03; 19 em F5V-04. A 17 usa fábricas de insight existentes; mapas só mostram coordenadas disponíveis, sem inventar grafo. A 20 reaproveita o tour e não edita Memex Guide.md. A 19 usa ShareService e folha nativa. A 22 mantém a importação em TXT; DOCX fica fora por F2-03. O bloqueio por PIN da prancha 15 permanece desativado conforme D-027.

> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F0 — Fundação

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F0-01 | Configurar upstream memex-lab/memex, branch de trabalho e commit base | P0 | — | DONE | Remotes e hash base registrados em STATE.md |
| F0-02 | Build limpo e execução no emulador e no Galaxy S25 Ultra | P0 | F0-01 | DONE | App aberto nos dois ambientes; build, instalação e testes registrados |
| F0-03 | Identidade Segunda Mente, applicationId próprio, ícone provisório e assinatura fora do repositório | P0 | F0-02 | DONE | APK app.segundamente.dev instalado ao lado do original |
| F0-04 | Revisar licença GPL-3.0, dependências e atribuições | P1 | F0-01 | DONE | Tabela de licenças em docs/fases/F0-04-licencas.md |
| F0-05 | Mapear componentes reutilizáveis: provedores, OAuth, voz, anexos, Drift e exportação | P1 | F0-02 | DONE | Nota em docs/fases/F0-05-modulos.md e decisão D-007 |
| F0-06 | Documentar e executar atualização segura do upstream | P2 | F0-01 | DONE | Procedimento em docs/fases/F0-06-upstream.md e merge registrado |

**Portão F0:** F0-01 a F0-06 estão DONE. Execução no Galaxy S25 Ultra (SM-S938B, Android 17) confirmada em 2026-11-03; captura em docs/imagens/s25_screenshot.png. Portão fechado.

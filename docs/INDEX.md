# Índice de documentação — Segunda Mente

Mapa de toda a documentação. Agentes: comecem pelo [AGENTS.md](../AGENTS.md).

## Retomada e governança

| Documento | Para quê |
|---|---|
| [STATE.md](../STATE.md) | Estado atual, próxima ação, pendências e evidências recentes |
| [ROADMAP.md](../ROADMAP.md) | Índice das fases e ordem de trabalho |
| [roadmap/](roadmap/) | Um arquivo por fase aberta, com subfases, critérios e portão, e as [ideias futuras](roadmap/IDEIAS-FUTURAS.md) |
| [DECISIONS.md](DECISIONS.md) | Decisões aceitas (D-001 em diante) |
| [PROJECT.md](../PROJECT.md) | Visão, escopo e restrições do produto |
| [WATCHDOG.md](WATCHDOG.md) · [AUDIT.md](AUDIT.md) | Regras de execução e auditoria antes de fechar fase |
| [arquivadas/](arquivadas/) | Fases concluídas e seus documentos de trabalho, STATE e decisões antigos, planos da F12 |

## Expansão Lumen + Todo robusto (2026-11-13)

- [Questionário com as decisões](questionario/2026-11-13-lumen-desktop-e-todo.md) (D-050 a D-055)
- [Pacote de planejamento original](lumen/README.md): proposta de 2026-11-12; onde divergir, valem as decisões
- Fases: [F11 Todo](arquivadas/roadmap/F11-todo-robusto-celular.md) · [F12 Sync](roadmap/F12-sync-com-o-lumen.md) · [F13 Google](roadmap/F13-google.md) · [F14 Assistente ativo](roadmap/F14-assistente-ativo.md) · [F15 Widget](roadmap/F15-widget-e-atalhos-android.md)
- Lado desktop: `docs/roadmap/fase-l-lumen.md` no repositório `playertwo1/coucou`
- [Prompts para o Codex](prompts/codex-segundamente-lumen.md): um para cada repositório

## Questionários

- [2026-11-02 — Segunda memória (escopo inicial)](questionario/2026-11-02-segunda-memoria.md)
- [2026-11-05 — F10, criação nos comentários](questionario/2026-11-05-f10-criacao-nos-comentarios.md)
- [2026-11-06 — F10-05, imagens](questionario/2026-11-06-f10-05-imagens.md)
- [2026-11-13 — Lumen desktop e Todo](questionario/2026-11-13-lumen-desktop-e-todo.md)

## Testes, releases e revisões

- Roteiros no aparelho: [teste no S25 de 2026-11-04](testes/TESTE-NO-S25-2026-11-04.md) · [prompt para o Antigravity](testes/PROMPT-ANTIGRAVITY-S25.md)
- [Notas de release](releases/) · [Revisões e auditorias](reviews/) · [Dados de medição](medicoes/)

## Referência herdada do Memex

[upstream/](upstream/) guarda os documentos do projeto original: arquitetura de agentes, avaliação, revisão de PR e READMEs em chinês. Servem de referência e podem citar código que não existe mais no fork.

## Design móvel

- [Direção visual aprovada](../DESIGN.md)
- [README e cobertura das referências v3](../.impeccable-mobile/references/amoled-v3-ios/README.md)
- [Relatório de QA das referências](../.impeccable-mobile/QA-REPORT.md)

### Pranchas aprovadas

| Referência | Arquivo |
|---|---|
| Linha do tempo e conhecimento | [imagem](../.impeccable-mobile/references/amoled-v3-ios/01-timeline-knowledge.png) |
| Insights e memórias | [imagem](../.impeccable-mobile/references/amoled-v3-ios/02-insights-memory.png) |
| Conversa e revisão de envio | [imagem](../.impeccable-mobile/references/amoled-v3-ios/03-chat-review.png) |
| Relatório e encaminhamentos | [imagem](../.impeccable-mobile/references/amoled-v3-ios/04-report-followups.png) |
| Configurações e modelos | [imagem](../.impeccable-mobile/references/amoled-v3-ios/05-settings-models.png) |
| Configuração inicial e permissões | [imagem](../.impeccable-mobile/references/amoled-v3-ios/06-setup-permissions.png) |
| Calendário e detalhe | [imagem](../.impeccable-mobile/references/amoled-v3-ios/07-calendar-detail.png) |
| Agentes e backup | [imagem](../.impeccable-mobile/references/amoled-v3-ios/08-agents-backup.png) |
| Menu, acesso ao chat e ícones | [imagem](../.impeccable-mobile/references/amoled-v3-ios/09-navigation-chat-icons.png) |
| Estados vazios e erro | [imagem](../.impeccable-mobile/references/amoled-v3-ios/10-primary-states.png) |
| Captura rápida, anexos e gravação | [imagem](../.impeccable-mobile/references/amoled-v3-ios/11-capture-quick-record.png) |
| Tipos de registro da timeline (1) | [imagem](../.impeccable-mobile/references/amoled-v3-ios/12-timeline-card-types.png) |
| Tipos de registro (2) e detalhe de métrica | [imagem](../.impeccable-mobile/references/amoled-v3-ios/13-timeline-card-types-2.png) |
| Companheiro, perfil e central de ações | [imagem](../.impeccable-mobile/references/amoled-v3-ios/14-companion-profile-states.png) |
| Bloqueio biométrico e por PIN | [imagem](../.impeccable-mobile/references/amoled-v3-ios/15-app-lock.png) |
| Busca global e resultados | [imagem](../.impeccable-mobile/references/amoled-v3-ios/16-global-search.png) |
| Variações de insight | [imagem](../.impeccable-mobile/references/amoled-v3-ios/17-insight-variants.png) |
| Atividade dos agentes | [imagem](../.impeccable-mobile/references/amoled-v3-ios/18-agent-activity.png) |
| Pôster e compartilhamento | [imagem](../.impeccable-mobile/references/amoled-v3-ios/19-share-poster.png) |
| Tour de boas-vindas e guia | [imagem](../.impeccable-mobile/references/amoled-v3-ios/20-welcome-tour.png) |
| Leitor de arquivo de Conhecimento | [imagem](../.impeccable-mobile/references/amoled-v3-ios/21-knowledge-reader.png) |
| Importação DOCX/TXT | [imagem](../.impeccable-mobile/references/amoled-v3-ios/22-import-data.png) |
| Contexto de localização (OpenStreetMap) | [imagem](../.impeccable-mobile/references/amoled-v3-ios/23-location-context.png) |

### Implementação das pranchas 17, 19, 20 e 22

| Prancha | Subfase | Componentes existentes | Limite aplicado |
|---|---|---|---|
| 17 — Variações de insight | F5V-02 | `insight_screen.dart`, `insight_detail_page.dart`, `NativeWidgetFactory` e `insight_cards/` | Gráficos, mapas geográficos com coordenadas, timeline e narrativa. Não há grafo de conexões disponível. |
| 20 — Tour e GUIAS | F5V-02 | `demo_overlay.dart`, `KnowledgeBaseViewModel` e `KnowledgeBaseScreen` | Tour em três passos; o guia existente é apenas listado e renomeado na interface, sem alterar `Memex Guide.md`. |
| 22 — Importação | F5V-03 | `TranscriptFileImportButton`, `TranscriptImportService` e rota de atividade existente | Lista, prévia, confirmação, progresso e falha para TXT. DOCX adiado porque a F2-03 só autoriza TXT. |
| 19 — Compartilhamento | F5V-04 | `SharePreviewDialog`, `SharePosterDecorator` e `ShareService` | Prévia e folha nativa; sem data, edição de texto ou compartilhamento por proximidade. |

### Referência principal de navegação

![Tela inicial, menu superior, chat e família de ícones](../.impeccable-mobile/references/amoled-v3-ios/09-navigation-chat-icons.png)

## Documentos de trabalho das fases ([fases/](fases/))

- [Checklist dos sete critérios F5-01](arquivadas/fases/F5-01-checklist.md)
- [Privacidade F5-02](arquivadas/fases/F5-02-privacidade.md)
- [Viabilidade F8-01 (NotebookLM)](fases/F8-01-viabilidade.md)
- [Mapeamento F9-01](fases/F9-01-mapeamento.md)
- [Corpus F9-02](fases/F9-02-corpus.md)
- [Plano de medição F7-02](fases/F7-02-plano-de-medicao.md)
- [F7-03 — voz duplex: implementação, limites e medição pendente](fases/F7-03-voz-duplex.md)
- [Plano de medição F2-11](fases/F2-11-plano-de-medicao.md)
- [Medições F5-03](arquivadas/fases/F5-03-medicoes.md)
- [Revisão F5](reviews/F5.md)
- [Revisão F9](reviews/F9-2026-11-06.md)
- [Captura do S25 Ultra](imagens/s25_screenshot.png)
- `docs/fases/EXTRACAO-DOCUMENTOS.md`: regras de leitura para atas e documentos, com fontes e o que foi aplicado nos prompts.

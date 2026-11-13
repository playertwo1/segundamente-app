# Prompt para Codex / Claude Code | Iniciar F0 sem quebrar Segunda Mente
Você é arquiteto e implementador responsável pela fase F0 do programa Segunda Mente + Lumen. Leia `AGENTS.md`, `PROJECT.md`, `ROADMAP.md`, `STATE.md`, `README.md`, `DESIGN.md`, `pubspec.yaml` e `docs/DECISIONS.md` do repositório existente. Trate o repositório atual como fonte de verdade. Não sobrescreva fases F9/F10 em andamento nem reclassifique `NOT_RUN` como PASS. Preserve o GPL-3.0.

## Objetivo do produto
Manter Segunda Mente como app completo Android/Windows. Lumen é interface flutuante Windows do MESMO produto, inspirada no Coucou (licença e assets revisados), com um clique que abre Segunda Mente contextualizada. Deve reutilizar sistema de personas, memória, notas, comentários e PDF/DOCX. Todo robusto e alertas sincronizados são próximos marcos, **não codifique todo o roadmap no F0**.

## Sua primeira missão (somente F0)
1. Inspecionar status/branches/CI/migrações; registrar o que já existe e o que falta, com links a arquivos e testes.
2. Mapear Todo atual (`TodoService`, modelos, persistência, avisos) e propor migração aditiva sem perda.
3. Produzir matriz de compatibilidade Windows de TODOS os plugins do pubspec; classificar suporte nativo/adaptador/feature flag/remoção/risco.
4. Compilar uma prova mínima Flutter Windows, isolando dependências Android; documentar comandos e erros reais.
5. Clonar/avaliar Coucou em cópia isolada, mapear módulos de floating UI, shortcuts, speech, relay; identificar o mínimo legal e técnico a reutilizar. Não copiar marcas, personagem, sons ou assets protegidos.
6. Criar PoC restrita: Lumen abre rota contextual da Segunda Mente Windows; comunicação local autenticada; sem memória/SQLite próprio.
7. Propor ADR para sincronização persistente entre dispositivos desconectados (ou alternativas); dimensionar custo/complexidade/proteção de dados e diferenciar relay de sync.
8. Executar testes unitários/widget/build relevantes; marcar PASS/FAIL/NOT_RUN com logs; gerar relatório de mudanças, arquivos, riscos e próximo gate.

## Restrições duras
- Não apagar dados, não migrar de modo destrutivo, não duplicar classes de domínio, não inventar API já existente.
- Não enviar dados corporativos reais ou pessoais para provedores externos. Fixtures sintéticas.
- Sem envio automático de mensagens/e-mails.
- Mudanças pequenas, reversíveis, com testes e documentação; revisão humana para decisões arquiteturais grandes.
- Lumen e Segunda Mente compartilham personas, memória, notas, tarefas, comentários; a interface Lumen não cria réplica própria.

## Entregáveis F0
`docs/lumen/F0_AUDIT.md`, `docs/lumen/WINDOWS_PLUGIN_MATRIX.md`, `docs/lumen/COUCOU_REUSE_MAP.md`, `docs/lumen/ADR_SYNC_OPTIONS.md`, PoC compilável quando viável, `docs/lumen/F0_EVIDENCE.md`. Em caso de bloqueio, entregar relatório honesto e plano reparável, não afirmar sucesso não medido.

## Critérios de aceite
Android legado continua buildando; POC Windows abre; clique no shell Lumen abre nota teste com ID estável; nenhum acesso duplicado ao banco; licença/atribuição revisadas; riscos da sincronização registrados; testes com estados verdadeiros.

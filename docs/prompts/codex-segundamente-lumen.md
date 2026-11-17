# Prompts para o Codex — Segunda Mente e Lumen

Dois prompts prontos para colar, um por repositório. Rode **uma sessão do Codex por repositório**, em paralelo se quiser. Os dois compartilham o bloco "Regras comuns", que já está dentro de cada um.

---

## Prompt 1 — Segunda Mente (app Android, Flutter)

Pasta: `C:\Users\notefael\projetos\segundamente` · Repositório: `playertwo1/segundamente-app` (privado)

```text
Você é o engenheiro responsável pela Segunda Mente, um app Flutter/Android local-first com IA, memória e personas. Ela está virando um assistente pessoal de trabalho com Todo robusto e um lado desktop (Lumen), que fica em outro repositório.

ANTES DE QUALQUER CÓDIGO, leia nesta ordem:
1. AGENTS.md (guia canônico: regras, arquitetura, testes, git)
2. STATE.md (estado atual e próxima ação)
3. ROADMAP.md e, depois, só o arquivo da fase em docs/roadmap/
4. docs/DECISIONS.md: as decisões D-050 a D-055 definem a expansão. O questionário completo está em docs/questionario/2026-11-13-lumen-desktop-e-todo.md.

SUA MISSÃO NESTA SESSÃO: fase F11 — Todo robusto (docs/arquivadas/roadmap/F11-todo-robusto-celular.md).
Ordem: F11-01 → F11-02 → F11-03. Pare depois da F11-03 e reporte.
- F11-01: modelo de tarefa com ID estável, prioridade, dia/hora com fuso (America/Sao_Paulo), "sem hora = tarefa do dia, sem alarme", regra de repetição, subtarefas, vínculo de origem, versão e tombstone. Migração ADITIVA do todo.json atual (lib/data/services/todo_service.dart) para o novo armazenamento, com backup antes e migração idempotente. A F9 (pausada) grava no Todo via SessionReportService/MemexRouter: preserve os itens dela e o vínculo com o relatório. Antes de escrever código, proponha em 10 linhas o desenho (tabelas Drift ou arquivo, interfaces) e siga o padrão do repositório (Repository → MemexRouter → ViewModel; Result<T>).
- F11-02: repetição diária, semanal (dias escolhidos) e mensal, e atalhos de dia (Hoje, Amanhã, Daqui a 3 dias, Semana que vem = próxima segunda) e de hora (9h, 14h, 20h; alerta padrão de 20 min), editáveis nas configurações. Testes com relógio fixo: troca de mês, fuso e concluir uma ocorrência sem apagar a série.
- F11-03: telas Hoje, Próximas, Atrasadas e Concluídas; lista ÚNICA, sem listas ou projetos; prioridade, subtarefas, filtros e busca, que inclui as concluídas. Siga DESIGN.md (AMOLED). Testes de widget para criar, editar, concluir, reabrir, excluir, buscar e filtrar, e para os estados vazio e erro. Strings em app_en.arb e app_pt.arb.
NÃO faça agora: F11-04 (alarmes; exige teste físico no S25), F12 (sync), F13 (Google), F14. Não retome F9, F5V nem F10, que estão pausadas.

REGRAS COMUNS:
- Uma subfase por vez, numa branch própria (feat/f11-01-modelo-tarefa etc.), com commit em pt-BR no estilo Conventional Commits. Integre na main com merge só depois dos testes. Push só para origin. Nunca para upstream.
- Mudança de comportamento leva teste no mesmo commit, conforme AGENTS.md. Rode os testes da área e, quando der, flutter analyze. O Flutter fica fora do PATH: C:\Users\notefael\tools\flutter\bin\flutter. Ele reescreve analysis_options.yaml e android/gradle.properties: reverta com git checkout antes de commitar.
- O que não foi executado é NOT_RUN, nunca PASS. Subfase só vira DONE com evidência registrada em STATE.md (seção "Evidências recentes"): comando, saída resumida e o que ficou NOT_RUN. Atualize também o estado da subfase no arquivo da fase.
- Sem segredos, tokens ou dados pessoais no repositório. Fixtures sintéticas. A IA propõe e o usuário confirma: nenhuma tarefa ou data vira definitiva sem confirmação.
- Não apague dados nem migre de forma destrutiva. Não invente API: leia o código antes.
- Pare e pergunte quando precisar de uma decisão de produto que não está em docs/DECISIONS.md, ou quando algo exigir o aparelho físico.

RELATÓRIO FINAL: o que mudou (arquivos), testes com o resultado, o que ficou NOT_RUN, riscos e a próxima subfase sugerida.
```

---

## Prompt 2 — Lumen (fork do Coucou, Windows, Tauri)

Pasta: `C:\Users\notefael\projetos\coucou` · Repositório: `playertwo1/coucou` (**público**)

```text
Você é o engenheiro responsável pelo fork playertwo1/coucou. É o app Windows do Coucou (Tauri 2: Rust em windows/src-tauri, TypeScript em windows/src), que está virando o LUMEN, o lado desktop da Segunda Mente (app Android num repositório privado separado).

ANTES DE QUALQUER CÓDIGO, leia nesta ordem:
1. AGENTS.md (raiz): regras do fork, mapa, validação, git e releases
2. docs/STATE-FORK.md: estado atual, trabalho fora da main e próxima ação
3. docs/ROADMAP-FORK.md (índice e regras de execução) e, depois, docs/roadmap/fase-l-lumen.md
4. CLAUDE.md: mapa do código e regras herdadas do original

SUA MISSÃO NESTA SESSÃO: Fase L, etapas L0 e L1.
- L0: leia docs/roadmap/fase-0-validacao.md, fase-1-recursos-mac.md e fase-2-melhorias-windows.md. Liste o que só falta validar manualmente ou está a uma etapa do fim. Feche só o que puder ser fechado com evidência real ou sintética permitida. Marque o resto, e as fases 2B e 2C, como "Pausada (D-053)", sem apagar nada. Registre a lista no arquivo da Fase L e atualize docs/STATE-FORK.md.
- L1.1: prepare um protótipo com 2–3 opções originais de personagem, ícone e paleta de sons para o Lumen. Nada derivado do Mochi nem dos assets do Coucou (LICENSE-ASSETS.md). Apresente as opções e PARE: o dono escolhe.
- Depois da escolha, L1.2/L1.3: novo nome, identifier e plano de migração de settings, hooks, permissões e atualizador (veja docs/roadmap/fase-3-identidade.md), com teste de upgrade antes de qualquer release.
NÃO faça agora: L4 (tarefas; espera a F11-01 da Segunda Mente fixar o modelo), L6 (sync; espera o contrato F12-01), L7 (Google). Não mexa nas worktrees codex/windows-git-pill e codex/windows-permission-notifications-eval, nem nas alterações locais não commitadas do app sintético, sem pedido do dono.

REGRAS COMUNS:
- Antes de cada subfase de código: árvore limpa, git fetch upstream e git merge upstream/main (conflitos num commit próprio). Uma subfase por vez, numa branch ou worktree própria, com commit em pt-BR. Merge na main depois dos testes. Push só para origin. Nunca para upstream.
- Validação: em windows/, npx tsc --noEmit, npm test e npm run build; em windows/src-tauri, cargo test --lib. O sintético não substitui a validação real. O que não foi executado é NOT_RUN.
- Spec curta em docs/superpowers/specs/ e plano em docs/superpowers/plans/ antes de código com UX ou comportamento novo.
- REPOSITÓRIO PÚBLICO: nada de dados pessoais do dono, conteúdo do trabalho dele, caminhos pessoais, tokens ou dados de clientes em código, docs, fixtures ou logs.
- Frases novas da Fase L só em pt-BR. O What's new das releases continua validado pelo CI até a L1 ajustar isso.
- Sem telemetria. Nada de e-mail, mensagem ou aprovação sem clique explícito. A IA propõe e o usuário confirma.
- Releases windows-vX.Y.Z seguem a autorização e o checklist do ROADMAP-FORK. Nenhuma release depois da L1 usa o nome ou os assets do Coucou.
- Pare e pergunte quando precisar de uma decisão do dono (como a escolha do visual) ou de validação no aparelho.

RELATÓRIO FINAL: o que mudou, os comandos de validação com o resultado, o que ficou NOT_RUN, as decisões que esperam o dono e a próxima etapa.
```

---

## Como os dois se encontram

| Momento | Segunda Mente | Lumen |
|---|---|---|
| Agora | F11-01 a F11-03 | L0, L1 |
| Depois da F11-01 | F12-01: contrato de sync em `docs/lumen/CONTRATO-SYNC.md` | L4: tarefas no Lumen, seguindo o modelo da F11-01 |
| Com o contrato pronto | F12-02 a F12-07 | L6: caixa de correio no relay e pareamento |
| Com o projeto Google Cloud criado pelo dono | F13 | L7 |

Method: design review only (detector not applicable, native platform)

# Crítica Impeccable — referências F11 (terceira passada)

**Target:** o conjunto em [REFERENCIAS.md](REFERENCIAS.md), agora com seis imagens estáticas. Revisão visual do conceito Android, não da implementação.

## Design Health Score

| # | Heurística | Nota / 4 | Observação |
|---|---|---:|---|
| 1 | Visibilidade do estado | 3 | Busca, conclusão recorrente e estado temporário de exclusão estão representados. |
| 2 | Correspondência com o mundo real | 3 | Datas, horário opcional e ações estão rotulados em linguagem direta. |
| 3 | Controle e liberdade | 3 | “Desfazer” permite recuperar a tarefa excluída; reabrir e editar também aparecem no conjunto. |
| 4 | Consistência e padrões | 3 | Prioridades têm nomes consistentes e a exclusão usa ação temporária sem diálogo. |
| 5 | Prevenção de erros | 3 | Sem horário, regra mensal e layout semanal reduzem erros previsíveis. |
| 6 | Reconhecimento em vez de memorização | 4 | Busca global, status/data e rótulos explícitos aparecem nos exemplos. |
| 7 | Flexibilidade e eficiência | 3 | Há atalhos configuráveis, filtros, busca e recuperação rápida após excluir. |
| 8 | Estética e minimalismo | 3 | O conjunto conserva AMOLED puro, linhas abertas e acento âmbar contido. |
| 9 | Recuperação de erro | 3 | Erro de migração oferece nova tentativa; exclusão oferece “Desfazer”. |
| 10 | Ajuda e documentação | 2 | Dicas de horário e recorrência estão junto aos controles; ajuda contextual não é demonstrada. |
| **Total** |  | **30/40 — bom** | Nenhum achado prioritário visual permanece nas referências. |

## Veredito

As referências agora cobrem as quatro abas, editor e repetição, configurações, filtro, estados vazio/erro, largura estreita, busca entre estados e exclusão reversível. A composição mantém a direção aprovada em `DESIGN.md` e comunica o fluxo escolhido sem acrescentar um diálogo interruptivo.

## O que funciona

- A exclusão remove a linha e oferece a ação temporária “Tarefa excluída · Desfazer” acima da navegação de sistema.
- Os demais ajustes continuam visíveis: prioridade “Normal”, busca global com status e data, dica condicional de horário, série recorrente preservada e dias semanais em duas linhas.
- A tela de 320 dp separa busca e filtro, mantendo os quatro rótulos de aba visíveis.

## Problemas prioritários

Nenhum achado prioritário novo nas imagens revisadas.

## Alertas por perfil

- **Casey, uso móvel:** busca, filtro e desfazer têm áreas amplas nas referências; altura e duração do snackbar precisam ser verificadas no aparelho.
- **Sam, acessibilidade:** estados têm rótulos e marcações além da cor; TalkBack, foco e alvos medidos dependem dos widgets reais.
- **Riley, teste de limites:** a série recorrente concluída mantém a próxima instância visível, e a exclusão pode ser desfeita; o comportamento real precisa de teste.

## Observações menores

- A referência de configurações mostra alerta padrão de 20 minutos, mas não representa agendamento de alarmes. A implementação de alarmes permanece fora do escopo visual/código desta sessão (F11-04).
- Temporização do snackbar, restauração do tombstone, semântica e escalas de texto não são validadas em imagens estáticas.

## Decisões do dono

- Busca mostra o estado e a data dos resultados.
- A dica de tarefa sem horário aparece somente quando o campo estiver vazio.
- Excluir usa mensagem temporária “Tarefa excluída · Desfazer”, conforme resposta do dono em 2026-11-13.

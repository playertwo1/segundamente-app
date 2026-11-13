Method: design review only (detector not applicable, native platform)

# Crítica Impeccable — referências do Todo F11

**Escopo:** três pranchas conceituais estáticas para a lista, edição/repetição e configurações/estados do Todo. Avaliadas contra `DESIGN.md`, D-017, o escopo F11 e as escolhas confirmadas para quatro prioridades, recorrência mensal no último dia do mês e conclusão de ocorrência recorrente preservada enquanto a próxima permanece ativa.

**Limite:** esta é uma revisão visual das referências, não da implementação Flutter. Texto e datas nas imagens são ilustrativos. Não valida comportamento, acessibilidade em aparelho, contraste medido ou navegação real.

## Pranchas avaliadas

1. [Listas Hoje, Próximas, Atrasadas e Concluídas](01-listas.png)
2. [Editor, data/hora e recorrência](02-edicao-e-repeticao.png)
3. [Configurações, filtro e estados vazio/erro](03-configuracoes-e-estados.png)

## Design Health Score

| # | Heurística | Nota / 4 | Observação |
|---|---|---:|---|
| 1 | Visibilidade do estado | 2 | Aba atual e tarefas concluídas aparecem; falta mostrar a próxima ocorrência de uma série recorrente. |
| 2 | Correspondência com o mundo real | 3 | Datas e ações são familiares; “Média” diverge da prioridade “Normal” escolhida. |
| 3 | Controle e liberdade | 3 | Editar, concluir e reabrir são reconhecíveis; excluir não mostra confirmação nem desfazer. |
| 4 | Consistência e padrões | 2 | “Média” e “Normal” aparecem no mesmo conjunto; parte dos controles ainda parece genérica. |
| 5 | Prevenção de erros | 2 | Data sem horário é opcional, mas a consequência “sem alarme” não está explícita. |
| 6 | Reconhecimento em vez de memorização | 3 | Rótulos, abas e atalhos são visíveis; a seleção semanal concentra sete opções numa linha. |
| 7 | Flexibilidade e eficiência | 2 | Atalhos de data/hora e filtros ajudam; o escopo da busca e os atalhos editáveis não ficam claros em uso. |
| 8 | Estética e minimalismo | 3 | Preto AMOLED, divisores finos e linhas abertas seguem bem a direção aprovada. |
| 9 | Recuperação de erro | 2 | Há explicação e “Tentar novamente”; a mensagem não indica como recuperar a migração. |
| 10 | Ajuda e documentação | 1 | Há uma nota sobre o dia 31; faltam dicas para “sem horário” e para a busca. |
| **Total** |  | **23/40 — aceitável** | Boa base; corrigir semântica e densidade antes de aprovar. |

## Veredito de especificidade

As telas seguem a identidade móvel da Segunda Mente: fundo preto puro, texto quente, âmbar discreto, divisores finos e sem barra inferior persistente. A estrutura funciona para um Todo operacional. As escolhas de abas, busca, filtros e chips ainda são convencionais, então a identidade vem principalmente da composição e do tema, não de elementos próprios do produto. Isso é adequado para esta função; mantenha a clareza acima de ornamentação.

## Impressão geral

A base visual é calma e fácil de percorrer. O ponto mais fraco está em comunicar as regras do Todo: as imagens ainda deixam margem para interpretação sobre busca, tarefas sem horário e a nomenclatura de prioridade. Há também dois pontos de densidade para conferir em aparelhos estreitos e com fonte ampliada.

## O que funciona

- As listas abertas com separadores discretos respeitam o DESIGN.md e mantêm o título da tarefa como foco.
- O editor divide data, horário e repetição em passos compreensíveis. Os atalhos reduzem digitação e o botão inferior fica ao alcance do polegar.
- Os estados vazio e erro explicam o que ocorreu e oferecem uma ação. A nota de repetição mensal comunica o comportamento aprovado para o dia 31.

## Problemas prioritários

1. **[P1] A ausência de horário não comunica “sem alarme”.** “Horário (opcional)” não informa que a tarefa fica marcada para o dia e não terá alarme.
   - **Por que importa:** alguém pode esperar um alerta e perder uma tarefa.
   - **Ajuste:** junto ao campo, mostrar uma frase curta quando o horário estiver vazio: “Sem horário: tarefa do dia, sem alarme.” A tela de configurações pode manter o intervalo padrão de alerta separado.
   - **Comando sugerido:** `$impeccable clarify`.

2. **[P1] A lista mostra “Média”, mas a prioridade aprovada é “Normal”.**
   - **Por que importa:** o mesmo nível parece ter dois nomes, e a pessoa pode não saber se são opções diferentes.
   - **Ajuste:** usar “Baixa / Normal / Alta / Urgente” em todas as telas e filtros.
   - **Comando sugerido:** `$impeccable clarify`.

3. **[P1] A busca não revela seu escopo.** O campo aparece dentro de cada aba, sem indicar que também encontra tarefas concluídas.
   - **Por que importa:** a pessoa pode procurar uma tarefa na aba errada ou presumir que concluídas estão excluídas.
   - **Ajuste:** a busca deve cobrir os quatro estados, inclusive concluídas; nos resultados, mostrar estado e data para a pessoa entender onde cada tarefa está.
   - **Comando sugerido:** `$impeccable clarify`.

4. **[P2] A seleção semanal comprime sete dias numa única linha.** Os chips podem ficar estreitos e próximos, principalmente com texto ampliado.
   - **Por que importa:** seleção por toque e leitura do estado ficam menos confiáveis.
   - **Ajuste:** permitir quebra em duas linhas, manter alvos de pelo menos 48 dp e conferir o estado selecionado sem depender apenas da cor.
   - **Comando sugerido:** `$impeccable layout`.

5. **[P2] Abas, busca e filtro podem disputar espaço em telas estreitas.** A prancha mostra quatro abas, campo de busca e botão de filtro ao mesmo tempo.
   - **Por que importa:** em largura reduzida ou com fontes ampliadas, rótulos podem apertar e perder legibilidade.
   - **Ajuste:** validar a composição em 320 dp e com escala de texto ampliada; adaptar a disposição preservando os nomes das quatro abas e os alvos de toque.
   - **Comando sugerido:** `$impeccable adapt`.

## Alertas por perfil de uso

- **Casey, uso móvel distraído:** os atalhos e o botão inferior ajudam; abas e busca/filtro precisam ser conferidos com uma mão em largura estreita. A ausência de indicação “sem alarme” é um risco de expectativa.
- **Sam, acessibilidade:** os estados usam rótulo, ícone e sublinhado, o que evita depender só da cor. As imagens não demonstram alvos de 48 dp, ordem de foco, TalkBack ou contraste medido; isso precisa ser verificado nos widgets reais.
- **Riley, teste de limites:** a regra do dia 31 está anotada; não aparece o caso de concluir uma ocorrência recorrente e manter a próxima ativa. A busca por tarefas concluídas também precisa ficar evidente.

## Observações menores

- As datas de janeiro são exemplos visuais; não representam o relógio ou o fuso de São Paulo.
- A prancha de erro trata especificamente de migração e afirma que o backup foi preservado. A tela real deve exibir isso apenas quando o serviço puder confirmar esses fatos.
- A tela de “Concluídas” mostra itens riscados e marcados, uma redundância útil para distinguir estado sem depender de âmbar.

## Decisões de apresentação confirmadas pelo dono

- Resultados da busca mostram o estado da tarefa (por exemplo, “Hoje”, “Atrasada” ou “Concluída”) e a data.
- A explicação “Sem horário: tarefa do dia, sem alarme” aparece somente enquanto o campo de horário estiver vazio.

## Resolução visual dos achados

As pranchas revisadas estão no [índice do conjunto atual](REFERENCIAS.md), e a segunda passada está em [critica-impeccable-v2.md](critica-impeccable-v2.md).

| Achado inicial | Ajuste aplicado |
|---|---|
| Sem horário não explicava a ausência de alarme | A frase aparece somente com o campo de horário vazio, no editor. |
| “Média” divergia da prioridade escolhida | “Normal” agora aparece em listas, editor e filtros. |
| Busca não mostrava escopo nem estado | Busca global inclui concluídas e os resultados mostram estado e data. |
| Sete dias semanais em uma única linha | Seleção reorganizada em duas linhas, com alvos visivelmente maiores. |
| Densidade em telefone estreito | Nova referência 320 dp amplia texto e separa busca e filtro. |
| Data de janeiro e promessa excessiva no erro | Datas atualizadas para novembro de 2026 e erro não afirma existir backup; informa preservação do original e oferece nova tentativa. |

**Fluxo de exclusão resolvido pelo dono:** usar a mensagem temporária “Tarefa excluída · Desfazer”, sem diálogo de confirmação. A referência está em [06-exclusao-desfazer.png](06-exclusao-desfazer.png). A terceira passada e o fechamento do achado estão em [critica-impeccable-v3.md](critica-impeccable-v3.md).

## Verificações não executadas

- Flutter/widget tests: **NOT_RUN** — estas alterações registram referências visuais; nenhum widget foi implementado.
- `flutter analyze`: **NOT_RUN** — nenhuma alteração de código Flutter foi feita nesta revisão.
- Inspeção em Galaxy S25, TalkBack, escala de texto ampliada e teste de alvos de toque: **NOT_RUN** — as pranchas são imagens conceituais, não uma build executável.

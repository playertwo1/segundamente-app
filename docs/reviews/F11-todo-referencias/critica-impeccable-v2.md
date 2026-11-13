Method: design review only (detector not applicable, native platform)

# Crítica Impeccable — revisão visual F11 (segunda passada)

**Target:** conjunto de referências vinculado em [REFERENCIAS.md](REFERENCIAS.md). Revisão estática das cinco pranchas revisadas; não é avaliação de código Flutter.

## Design Health Score

| # | Heurística | Nota / 4 | Observação |
|---|---|---:|---|
| 1 | Visibilidade do estado | 3 | Abas, resultados globais e próxima ocorrência estão visíveis nos exemplos. |
| 2 | Correspondência com o mundo real | 3 | Horário opcional, datas e estados usam termos diretos; exemplos datados em novembro. |
| 3 | Controle e liberdade | 2 | Excluir não tem fluxo visual definido; confirmação e desfazer dependem de decisão do dono. |
| 4 | Consistência e padrões | 3 | “Baixa / Normal / Alta / Urgente” se mantém em listas, editor e filtros. |
| 5 | Prevenção de erros | 3 | Dica de sem horário, regra do dia 31 e seleção semanal espaçada reduzem ambiguidade. |
| 6 | Reconhecimento em vez de memorização | 4 | Busca global declara o escopo e cada resultado mostra estado e data. |
| 7 | Flexibilidade e eficiência | 3 | Atalhos configuráveis, filtros e busca preservam caminhos rápidos. |
| 8 | Estética e minimalismo | 3 | AMOLED, linhas abertas e acento contido mantêm a direção aprovada. |
| 9 | Recuperação de erro | 3 | O erro de migração explica que o original ficou sem alterações e oferece nova tentativa. |
| 10 | Ajuda e documentação | 2 | Regras relevantes aparecem junto aos controles; não há orientação contextual para exclusão. |
| **Total** |  | **29/40 — bom** | Os cinco achados visuais da primeira passada foram resolvidos nas referências. |

## Veredito

O conjunto revisado comunica melhor as regras do produto e mantém o visual aprovado. A busca global, a ocorrência recorrente concluída e a tarefa sem horário agora têm estados legíveis. A prancha de 320 dp demonstra uma composição adaptada, mas a escala de texto e os alvos ainda precisam ser conferidos numa tela Flutter real.

## O que funciona

- A busca abrange estados distintos e explicita estado e data em cada resultado, inclusive concluídos.
- A ocorrência concluída permanece visível junto da próxima ocorrência ativa da série.
- O editor comunica a regra de ausência de horário somente quando o campo está vazio, e a escolha semanal usa duas linhas.

## Problema restante

- **[P2] A ação de excluir não tem comportamento visual definido.** Um diálogo de confirmação interrompe menos acidentes, enquanto uma mensagem com “Desfazer” é mais rápida. Como a tarefa tem tombstone, a escolha afeta o controle de recuperação; deixei a tela de exclusão fora deste conjunto até o dono decidir.

## Alertas por perfil

- **Casey, uso móvel:** o layout estreito coloca busca e filtro em linhas separadas e mantém os quatro rótulos visíveis; a altura extra precisa ser verificada com rolagem real.
- **Sam, acessibilidade:** texto ampliado e seleção com forma/rótulo são representados; sem widgets, não foi possível confirmar semântica do leitor de tela, foco nem alvos medidos.
- **Riley, teste de limites:** dia 31, data da próxima segunda e resultado concluído estão representados; o comportamento de exclusão continua sem definição.

## Observações menores

- Os arquivos são referências geradas, não capturas de uma build; a aparência dos controles ainda exige implementação e validação no Android.
- A tela de erro diz que o arquivo original foi mantido sem alterações; a implementação deve preservar essa garantia na migração aditiva.

## Decisões de apresentação confirmadas pelo dono

- Resultados da busca mostram o estado da tarefa e a data.
- A explicação “Sem horário: tarefa do dia, sem alarme” aparece somente enquanto o campo estiver vazio.

# Segunda Mente: avaliar melhorias recentes do Memex sem mesclar o fork

O fork formal [segundamente](https://github.com/playertwo1/segundamente) está arquivado (125 commits exclusivos e 18 atrás da main de [Memex](https://github.com/memex-lab/memex)). Não tocar no arquivo histórico. O app ativo tem a mesma base `6143923e` confirmada e sua própria release 1.0.21. Os números 125/18 pertencem ao fork histórico, não ao app ativo. A [release Early](https://github.com/memex-lab/memex/releases/tag/android-early-20261112-5ecbe4c) é prévia do upstream; não é atualização direta do APK do Segunda Mente.

## Priorizar estudos isolados
1. [Captura sem rede #492](https://github.com/memex-lab/memex/pull/492): manter anotações locais e tornar a espera pela rede explícita. Não aplicar todo o commit; mistura fila e servidor local. Aceite: criar uma nota fictícia offline, reabrir, reconectar usando transporte falso e confirmar um único registro, sem trocar de conta no meio.
2. [Primeira página da linha do tempo #460](https://github.com/memex-lab/memex/pull/460): vale se um conjunto fictício grande comprovar demora. O commit usa marcador de reconstrução, consulta filtrada e cancelamento na troca de conta; não portar apenas a ordenação. Testar recuperação após interrupção, filtros completos e isolamento.
3. [Biblioteca #501](https://github.com/memex-lab/memex/pull/501): estudar pastas frequentes e fixados sem trocar a navegação atual. Separar preferências por conta; nenhum dado real em teste.

## Não mesclar
Não importar release, identidade de pacote, CI, prompts, configuração de modelo ou migrações em bloco. O app tem D-085, Lumen/MQTT e notificações próprias (#3); não misturar esses pontos com esta revisão. Gate: verificar o que já existe, escolher um item, incluir teste e preservar GPL-3.0/atribuição.

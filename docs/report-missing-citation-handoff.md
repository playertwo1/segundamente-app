# Segunda Mente: descartar apenas o item que ficou sem citação

**Base verificada:** `v1.0.13` e `44a95cb0874e37821ac38b3c643d89e2cc5f5aff` (`main`). O parser é idêntico em ambos.

## Problema e evidência

Em [session_report.dart](../lib/domain/models/session_report.dart#L338), o parser valida a citação de cada item contra o trecho original. Um trecho presente mas que não existe na fonte já faz o parser registrar e pular só o item. Quando `excerpt` está ausente, nulo ou em branco, `_requiredText` lança uma exceção antes de alcançar esse descarte por item. Isso aborta o relatório inteiro mesmo com itens válidos.

Identificado por revisão do código. O caso ainda não foi executado no Flutter nem no S25.

## Correção solicitada

Tratar a citação ausente ou inválida como falha daquele item: registrar via mecanismo existente e seguir para o próximo. Não aceitar nem inventar citações. Preservar a checagem contra a fonte, o trecho exato armazenado e a rejeição quando nenhum item válido sobrar. Não transformar erros estruturais gerais em sucesso silencioso.

## Critérios de aceite

- Em [session_report_test.dart](../test/domain/models/session_report_test.dart), usar uma fonte fictícia e dois itens: um com citação exata e outro com `excerpt` ausente, nulo ou em branco. Em ambas as ordens, conservar só o item válido e registrar um descarte.
- Se todos os itens estiverem sem evidência, manter a rejeição. Os casos existentes de citação inventada, segmento desconhecido, horário incompatível e normalização continuam passando.
- Executar os testes do parser sem chamada a modelo real.

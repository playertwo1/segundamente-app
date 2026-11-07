import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/document_request.dart';

void main() {
  test('asks only when the comment reads like a request for a document', () {
    for (final yes in [
      'junte isso numa proposta',
      'Faça um relatório disso',
      'crie um documento com as ideias',
      'write a proposal from this',
      'Redija a minuta',
    ]) {
      expect(looksLikeDocumentRequest(yes), isTrue, reason: yes);
    }
    for (final no in [
      'concordo com a ana',
      'o documento está na gaveta',
      'a proposta de ontem foi boa',
      '',
      '${'faça um relatório ' * 20}',
    ]) {
      expect(looksLikeDocumentRequest(no), isFalse, reason: no);
    }
  });
}

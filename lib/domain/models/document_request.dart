/// True when a short comment reads like "junte isso numa proposta". It only
/// decides whether to ask; the user still confirms, and can just comment.
bool looksLikeDocumentRequest(String text) {
  final t = _plain(text);
  if (t.isEmpty || t.length > 200) return false;
  return _request.hasMatch(t);
}

String _plain(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const to = 'aaaaaeeeeiiiiooooouuuuc';
  final b = StringBuffer();
  for (final c in s.toLowerCase().trim().split('')) {
    final i = from.indexOf(c);
    b.write(i < 0 ? c : to[i]);
  }
  return b.toString();
}

final _request = RegExp(
  r'\b(junte|junta|monte|montar|crie|criar|gere|gerar|escreva|redija|faca|fazer|'
  r'transforme|make|create|write|draft|generate|put)\b'
  r'.{0,40}\b(proposta|documento|relatorio|rascunho|minuta|proposal|document|'
  r'report|draft)\b',
);

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/core/cards/templates/textual/article_card.dart';

const _minutes = '''
## Decisões
- **Avançar** para a expansão.

| Responsável | Ação | Prazo |
|---|---|---|
| Rodrigo | Entregar o plano | 21/11 |
''';

void main() {
  testWidgets('headings step down in size and the body stays at 16sp',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ArticleCard(data: const {'title': 'Ata', 'body': _minutes}),
        ),
      ),
    ));

    final sheet =
        tester.widget<MarkdownBody>(find.byType(MarkdownBody)).styleSheet!;
    expect(sheet.h1!.fontSize! > sheet.h2!.fontSize!, isTrue);
    expect(sheet.h2!.fontSize! > sheet.h3!.fontSize!, isTrue);
    expect(sheet.h2!.fontSize! > sheet.p!.fontSize!, isTrue);
    expect(sheet.p!.fontSize, 16);
    expect(sheet.p!.height, 1.55);
  });

  testWidgets('a table and a list render without errors', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ArticleCard(data: const {'title': 'Ata', 'body': _minutes}),
        ),
      ),
    ));

    expect(find.byType(Table), findsOneWidget);
    expect(find.textContaining('Entregar o plano'), findsOneWidget);
    expect(find.textContaining('Avançar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

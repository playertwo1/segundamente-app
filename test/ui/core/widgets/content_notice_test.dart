import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/core/widgets/content_notice.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpIn(WidgetTester tester, String language) async {
    SharedPreferences.setMockInitialValues({'language': language});
    await UserStorage.initL10n();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ContentNoticeCaption()),
    ));
    await tester.pump();
  }

  testWidgets('content notice caption is visible in Portuguese',
      (tester) async {
    await pumpIn(tester, 'pt');

    expect(
      find.text(
          'Não registre dados de clientes, contas ou documentos do banco.'),
      findsOneWidget,
    );
  });

  testWidgets('content notice caption is visible in English', (tester) async {
    await pumpIn(tester, 'en');

    expect(
      find.text('Do not record client data, accounts or bank documents.'),
      findsOneWidget,
    );
  });
}

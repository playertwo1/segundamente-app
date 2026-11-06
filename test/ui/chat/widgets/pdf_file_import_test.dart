import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/services/pdf_import_service.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/chat/widgets/pdf_file_import.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  final pdf = File('test/fixtures/f9/c36.pdf').readAsBytesSync();

  Future<void> pump(
    WidgetTester tester,
    PdfImporter import, {
    List<int>? bytes,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('open'),
                onPressed: () => importPdfFile(
                  context,
                  name: 'ata.pdf',
                  bytes: bytes ?? pdf,
                  import: import,
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  test('recognizes a PDF by its header, not by its name', () {
    expect(isPdfBytes(pdf), isTrue);
    expect(isPdfBytes(utf8.encode('Reunião de hoje')), isFalse);
  });

  testWidgets('says the file leaves the phone and sends nothing on cancel',
      (tester) async {
    var calls = 0;
    await pump(tester, ({required bytes, required confirmedLarge}) async {
      calls++;
      return const Error('unused');
    });
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ata.pdf'), findsOneWidget);
    expect(find.text(UserStorage.l10n.pdfSendTitle), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pdf_send_cancel')));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('a scanned PDF explains that nothing was saved', (tester) async {
    await pump(
      tester,
      ({required bytes, required confirmedLarge}) async => const Ok((
        outcome: PdfImportOutcome.noSelectableText,
        sessionId: 'pdf_1',
      )),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf_send_confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(UserStorage.l10n.pdfNoText), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('a model that cannot read PDFs says so', (tester) async {
    await pump(
      tester,
      ({required bytes, required confirmedLarge}) async =>
          const Error(PdfModelUnsupported()),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf_send_confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(UserStorage.l10n.pdfModelCannotRead), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('a big file asks a second time and may be declined',
      (tester) async {
    final calls = <bool>[];
    final big = [...pdf, ...List.filled(3 * 1024 * 1024, 0x20)];
    await pump(tester, ({required bytes, required confirmedLarge}) async {
      calls.add(confirmedLarge);
      return const Ok((
        outcome: PdfImportOutcome.needsSizeConfirmation,
        sessionId: 'pdf_1',
      ));
    }, bytes: big);
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf_send_confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('MB'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pdf_send_cancel')));
    await tester.pumpAndSettle();
    expect(calls, [false]);
    expect(find.byType(AlertDialog), findsNothing);
  });
}

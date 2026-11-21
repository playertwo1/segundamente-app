import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/media_library_item.dart';
import 'package:memex/ui/media_library/view_models/media_library_viewmodel.dart';
import 'package:memex/ui/media_library/widgets/media_library_screen.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeMediaRouter implements MemexRouter {
  _FakeMediaRouter(this.result);

  final Result<List<MediaLibraryItem>> result;

  @override
  Future<Result<List<MediaLibraryItem>>> fetchMediaLibrary() async => result;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await UserStorage.initL10n();
  });

  testWidgets('MediaLibraryScreen filters by kind and search query',
      (tester) async {
    final items = [
      MediaLibraryItem(
        fileName: 'foto.png',
        filePath: '/mock/foto.png',
        kind: MediaLibraryKind.photo,
        modifiedAt: DateTime(2026, 11, 20, 10, 0),
        sizeBytes: 2048,
        cardId: 'c1',
        cardTitle: 'Quadro do projeto',
      ),
      MediaLibraryItem(
        fileName: 'contrato.pdf',
        filePath: '/mock/contrato.pdf',
        kind: MediaLibraryKind.pdf,
        modifiedAt: DateTime(2026, 11, 19, 9, 0),
        sizeBytes: 1024 * 1024 * 2,
      ),
      MediaLibraryItem(
        fileName: 'nota_voz.m4a',
        filePath: '/mock/nota_voz.m4a',
        kind: MediaLibraryKind.audio,
        modifiedAt: DateTime(2026, 11, 18, 8, 0),
        sizeBytes: 512000,
      ),
    ];

    final vm = MediaLibraryViewModel(router: _FakeMediaRouter(Ok(items)));
    await tester.pumpWidget(
      MaterialApp(home: MediaLibraryScreen(viewModel: vm)),
    );
    await tester.pump();

    expect(find.text('Quadro do projeto'), findsOneWidget);
    expect(find.text('contrato.pdf'), findsOneWidget);
    expect(find.text('nota_voz.m4a'), findsOneWidget);

    await tester.tap(find.text('PDFs (1)'));
    await tester.pump();

    expect(find.text('Quadro do projeto'), findsNothing);
    expect(find.text('contrato.pdf'), findsOneWidget);
    expect(find.text('nota_voz.m4a'), findsNothing);

    await tester.tap(find.text('All (3)'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Quadro');
    await tester.pump();

    expect(find.text('Quadro do projeto'), findsOneWidget);
    expect(find.text('contrato.pdf'), findsNothing);
  });

  testWidgets('MediaLibraryScreen shows empty state when no media exists',
      (tester) async {
    final vm = MediaLibraryViewModel(
      router: _FakeMediaRouter(const Ok([])),
    );
    await tester.pumpWidget(
      MaterialApp(home: MediaLibraryScreen(viewModel: vm)),
    );
    await tester.pump();

    expect(find.text('No photos, PDFs, or audios saved yet.'), findsOneWidget);
  });
}

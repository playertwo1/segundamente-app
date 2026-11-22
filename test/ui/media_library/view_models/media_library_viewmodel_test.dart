import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/media_library_item.dart';
import 'package:memex/ui/media_library/view_models/media_library_viewmodel.dart';
import 'package:memex/utils/result.dart';

class _FakeRouter implements MemexRouter {
  _FakeRouter(this.result);

  Result<List<MediaLibraryItem>> result;

  @override
  Future<Result<List<MediaLibraryItem>>> fetchMediaLibrary() async => result;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('load populates counts, filters by kind and search, and exposes errors',
      () async {
    final items = [
      MediaLibraryItem(
        fileName: 'img_1.png',
        filePath: '/a/img_1.png',
        kind: MediaLibraryKind.photo,
        modifiedAt: DateTime(2026, 11, 20),
        sizeBytes: 100,
        cardId: 'c1',
        cardTitle: 'Quadro branco',
      ),
      MediaLibraryItem(
        fileName: 'doc_1.pdf',
        filePath: '/a/doc_1.pdf',
        kind: MediaLibraryKind.pdf,
        modifiedAt: DateTime(2026, 11, 19),
        sizeBytes: 200,
      ),
      MediaLibraryItem(
        fileName: 'rec_1.m4a',
        filePath: '/a/rec_1.m4a',
        kind: MediaLibraryKind.audio,
        modifiedAt: DateTime(2026, 11, 18),
        sizeBytes: 300,
      ),
    ];
    final router = _FakeRouter(Ok(items));
    final vm = MediaLibraryViewModel(router: router);

    await vm.load();

    expect(vm.isLoading, isFalse);
    expect(vm.errorMessage, isNull);
    expect(vm.totalCount, 3);
    expect(vm.photoCount, 1);
    expect(vm.pdfCount, 1);
    expect(vm.audioCount, 1);

    vm.setFilter(MediaLibraryFilter.pdf);
    expect(vm.items.map((e) => e.fileName), ['doc_1.pdf']);

    vm.setFilter(MediaLibraryFilter.all);
    vm.setSearchQuery('quadro');
    expect(vm.items.map((e) => e.fileName), ['img_1.png']);

    router.result = Error(Exception('disk error'));
    await vm.load();
    expect(vm.errorMessage, contains('disk error'));
  });
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/utils/share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.memexlab.memex/system_actions');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('returns the folder the platform saved the export to', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'saveToDownloads');
      expect(call.arguments['mimeType'], 'text/markdown');
      return 'Download/SegundaMente/relatorio.md';
    });
    expect(
      await ShareService.saveToDownloads(
          path: '/x/relatorio.md', mimeType: 'text/markdown'),
      'Download/SegundaMente/relatorio.md',
    );
  });

  test('a failed copy or a platform without it is not an error', () async {
    expect(
      await ShareService.saveToDownloads(path: '/x/a', mimeType: 'text/plain'),
      isNull,
    );
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'SAVE_ERROR'),
    );
    expect(
      await ShareService.saveToDownloads(path: '/x/a', mimeType: 'text/plain'),
      isNull,
    );
  });
}

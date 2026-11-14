import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:memex/data/model/chat_events.dart';
import 'package:memex/domain/models/floating_chat_mode.dart';
import 'package:memex/ui/floating_chat/view_models/floating_capture_viewmodel.dart';

import '../../../helpers/floating_capture_fakes.dart';

void main() {
  late FakeCaptureRouter router;
  String? clipboard;
  XFile? picked;

  FloatingCaptureViewModel viewModel(FloatingChatMode mode) {
    return FloatingCaptureViewModel(
      router: router,
      mode: mode,
      readClipboard: () async => clipboard,
      pickImage: (source) async => picked,
      currentSessionId: () async => 'session-1',
    );
  }

  setUp(() {
    router = FakeCaptureRouter();
    clipboard = null;
    picked = null;
  });

  group('paste (Colar)', () {
    test('returns the trimmed clipboard text and sends nothing', () async {
      clipboard = '  ideia copiada  ';
      final vm = viewModel(FloatingChatMode.paste);

      expect(await vm.paste(), 'ideia copiada');
      expect(vm.clipboardEmpty, isFalse);
      expect(router.sent, isEmpty);
    });

    test('an empty or blank clipboard gives null and flags the message',
        () async {
      final vm = viewModel(FloatingChatMode.paste);

      clipboard = null;
      expect(await vm.paste(), isNull);
      expect(vm.clipboardEmpty, isTrue);

      clipboard = '   ';
      expect(await vm.paste(), isNull);
      expect(vm.clipboardEmpty, isTrue);
      expect(router.sent, isEmpty);
    });

    test('an unreadable clipboard is the same empty message', () async {
      final vm = FloatingCaptureViewModel(
        router: router,
        mode: FloatingChatMode.paste,
        readClipboard: () async => throw StateError('no focus'),
      );

      expect(await vm.paste(), isNull);
      expect(vm.clipboardEmpty, isTrue);
    });
  });

  group('save (Guardar)', () {
    test('sends the text to the super agent in the latest session', () async {
      final vm = viewModel(FloatingChatMode.note);

      expect(await vm.save('  comprar pão  '), isTrue);

      expect(router.sent, hasLength(1));
      expect(router.sent.single.text, 'comprar pão');
      expect(router.sent.single.sessionId, 'session-1');
      expect(router.sent.single.images, isEmpty);
      expect(vm.saveFailed, isFalse);
      expect(vm.saving, isFalse);
    });

    test('an empty note with no photo is not sent', () async {
      final vm = viewModel(FloatingChatMode.note);

      expect(vm.canSave('   '), isFalse);
      expect(await vm.save('   '), isFalse);
      expect(router.sent, isEmpty);
    });

    test('a photo alone can be saved and its hash is recorded', () async {
      final file = File('${Directory.systemTemp.path}/sm_f1504_foto_teste.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      addTearDown(() => file.deleteSync());
      picked = XFile(file.path);
      final vm = viewModel(FloatingChatMode.photo);
      await vm.pickPhoto(ImageSource.gallery);

      expect(vm.canSave(''), isTrue);
      expect(await vm.save(''), isTrue);

      expect(router.sent.single.images.single.path, file.path);
      expect(router.sent.single.originalFilenames, {file.path: picked!.name});
      // The hash is recorded in the background, after the file is read.
      for (var i = 0; i < 100 && router.recordedHashes.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(router.recordedHashes, hasLength(1));
    });

    test('an error event from the super agent is not a save', () async {
      router.sendOutcome =
          () => Stream.value(ChatErrorEvent('turn-1', 'offline'));
      final vm = viewModel(FloatingChatMode.note);

      expect(await vm.save('texto'), isFalse);
      expect(vm.saveFailed, isTrue);
    });

    test('a stream error is not a save', () async {
      router.sendOutcome = () => Stream<ChatEvent>.error(StateError('down'));
      final vm = viewModel(FloatingChatMode.note);

      expect(await vm.save('texto'), isFalse);
      expect(vm.saveFailed, isTrue);
    });

    test('a second save while one is running sends nothing extra', () async {
      final gate = Completer<void>();
      router.sendOutcome = () => Stream.fromFuture(
            gate.future.then((_) => ChatAgentStartedEvent('turn-1')),
          );
      final vm = viewModel(FloatingChatMode.note);

      final first = vm.save('primeiro');
      await Future<void>.delayed(Duration.zero);
      expect(vm.saving, isTrue);
      expect(await vm.save('segundo'), isFalse);
      gate.complete();

      expect(await first, isTrue);
      expect(router.sent.map((c) => c.text), ['primeiro']);
    });
  });

  test('picking a photo does not save it', () async {
    picked = XFile('/synthetic/foto.jpg');
    final vm = viewModel(FloatingChatMode.photo);

    await vm.pickPhoto(ImageSource.camera);

    expect(vm.image, isNotNull);
    expect(router.sent, isEmpty);
  });
}

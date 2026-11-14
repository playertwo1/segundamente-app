import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/floating_chat_service.dart';
import 'package:memex/domain/models/floating_chat_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/floating_chat');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  late FloatingChatService service;

  /// Answers the calls the app makes to the native side.
  void mockNative(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return handler(call);
    });
  }

  setUp(() {
    calls = [];
    service = FloatingChatService.forTesting(channel: channel);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMessageHandler(channel.name, null);
  });

  group('takePendingMode', () {
    test('reads type and talk', () async {
      mockNative((call) async => 'type');
      expect(await service.takePendingMode(), FloatingChatMode.type);

      mockNative((call) async => 'talk');
      expect(await service.takePendingMode(), FloatingChatMode.talk);
      expect(calls, ['takePendingMode', 'takePendingMode']);
    });

    test('reads the capture modes (F15-04)', () async {
      for (final mode in ['note', 'photo', 'paste']) {
        mockNative((call) async => mode);
        expect(await service.takePendingMode(), FloatingChatMode.parse(mode));
      }
      expect(calls, ['takePendingMode', 'takePendingMode', 'takePendingMode']);
    });

    test('an unknown value, null, or a missing plugin gives null', () async {
      mockNative((call) async => 'voice');
      expect(await service.takePendingMode(), isNull);

      mockNative((call) async => null);
      expect(await service.takePendingMode(), isNull);

      mockNative((call) async => throw MissingPluginException());
      expect(await service.takePendingMode(), isNull);
    });

    test('a platform error gives null instead of throwing', () async {
      mockNative((call) async => throw PlatformException(code: 'boom'));

      expect(await service.takePendingMode(), isNull);
    });
  });

  test('an open signal emits the pending mode on openRequests', () async {
    mockNative(
        (call) async => call.method == 'takePendingMode' ? 'talk' : null);
    service.initialize();
    addTearDown(() => channel.setMethodCallHandler(null));

    final first = service.openRequests.first;
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('open')),
      (_) {},
    );

    expect(await first, FloatingChatMode.talk);
  });

  test('an open signal with nothing pending emits nothing', () async {
    mockNative((call) async => null);
    service.initialize();
    addTearDown(() => channel.setMethodCallHandler(null));

    final emitted = <FloatingChatMode>[];
    final subscription = service.openRequests.listen(emitted.add);
    addTearDown(subscription.cancel);
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('open')),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(emitted, isEmpty);
  });

  test('close and openInApp call their native methods', () async {
    mockNative((call) async => null);

    await service.close();
    await service.openInApp();

    expect(calls, ['close', 'openInApp']);
  });

  test('close and openInApp tolerate a missing native side', () async {
    mockNative((call) async => throw MissingPluginException());

    await service.close();
    await service.openInApp();

    expect(calls, ['close', 'openInApp']);
  });
}

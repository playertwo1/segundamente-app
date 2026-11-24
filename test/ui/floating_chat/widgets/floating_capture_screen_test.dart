import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:memex/data/model/chat_events.dart';
import 'package:memex/data/services/floating_chat_service.dart';
import 'package:memex/domain/models/floating_chat_mode.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/core/widgets/content_notice.dart';
import 'package:memex/ui/floating_chat/view_models/floating_capture_viewmodel.dart';
import 'package:memex/ui/floating_chat/widgets/floating_capture_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/floating_capture_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/floating_capture_screen');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> nativeCalls;
  late FloatingChatService service;
  late FakeCaptureRouter router;
  String? clipboard;
  XFile? picked;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await UserStorage.initL10n();
  });

  setUp(() {
    nativeCalls = [];
    router = FakeCaptureRouter();
    clipboard = null;
    picked = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      return null;
    });
    service = FloatingChatService.forTesting(channel: channel);
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// Home at '/', the capture sheet over it as the app mounts it.
  Future<void> pumpSheet(WidgetTester tester, FloatingChatMode mode) async {
    final viewModel = FloatingCaptureViewModel(
      router: router,
      mode: mode,
      readClipboard: () async => clipboard,
      pickImage: (_) async => picked,
      currentSessionId: () async => 'session-1',
    );
    final goRouter = GoRouter(
      initialLocation: '/floating-capture',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('home-screen')),
        ),
        GoRoute(
          path: '/floating-capture',
          builder: (_, __) => FloatingCaptureScreen(
            viewModel: viewModel,
            service: service,
          ),
        ),
      ],
    );
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: goRouter,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  FilledButton saveButton(WidgetTester tester) => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, UserStorage.l10n.floatingCaptureSave),
      );

  testWidgets('note mode shows Anotar, a text field and the content notice',
      (tester) async {
    await pumpSheet(tester, FloatingChatMode.note);

    expect(
        find.text(UserStorage.l10n.floatingCaptureNoteTitle), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(ContentNoticeCaption), findsOneWidget);
    expect(find.text(UserStorage.l10n.contentNoticeCaption), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets('Guardar is the only path that saves, and it closes the sheet',
      (tester) async {
    await pumpSheet(tester, FloatingChatMode.note);

    await tester.enterText(find.byType(TextField), 'comprar pão');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNotNull);
    expect(router.sent, isEmpty, reason: 'typing must not save');

    await tester.tap(find.widgetWithText(
        FilledButton, UserStorage.l10n.floatingCaptureSave));
    await settle(tester);

    expect(router.sent.map((c) => c.text), ['comprar pão']);
    expect(router.sent.single.sessionId, 'session-1');
    expect(nativeCalls, ['close']);
    expect(find.text('home-screen'), findsOneWidget);
  });

  testWidgets('Fechar discards the note and never saves', (tester) async {
    await pumpSheet(tester, FloatingChatMode.note);

    await tester.enterText(find.byType(TextField), 'não guardar');
    await tester.tap(find.text(UserStorage.l10n.close));
    await settle(tester);

    expect(router.sent, isEmpty);
    expect(nativeCalls, ['close']);
    expect(find.text('home-screen'), findsOneWidget);
  });

  testWidgets('Colar pre-fills the clipboard text and saves only on Guardar',
      (tester) async {
    clipboard = 'texto copiado';
    await pumpSheet(tester, FloatingChatMode.paste);

    expect(
        find.text(UserStorage.l10n.floatingCapturePasteTitle), findsOneWidget);
    expect(find.text('texto copiado'), findsOneWidget);
    expect(router.sent, isEmpty, reason: 'pasting must not save');

    await tester.tap(find.widgetWithText(
        FilledButton, UserStorage.l10n.floatingCaptureSave));
    await settle(tester);

    expect(router.sent.map((c) => c.text), ['texto copiado']);
  });

  testWidgets('an empty clipboard says so and leaves Guardar off',
      (tester) async {
    clipboard = null;
    await pumpSheet(tester, FloatingChatMode.paste);

    expect(
        find.text(UserStorage.l10n.floatingCapturePasteEmpty), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);
    expect(router.sent, isEmpty);
  });

  testWidgets(
      'Foto offers camera and gallery, then previews and saves only on Guardar',
      (tester) async {
    picked = XFile('/synthetic/foto.jpg', name: 'foto.jpg');
    await pumpSheet(tester, FloatingChatMode.photo);

    expect(find.text(UserStorage.l10n.floatingCaptureCamera), findsOneWidget);
    expect(find.text(UserStorage.l10n.floatingCaptureGallery), findsOneWidget);

    await tester.tap(find.text(UserStorage.l10n.floatingCaptureGallery));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(UserStorage.l10n.floatingCaptureCamera), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(saveButton(tester).onPressed, isNotNull);
    expect(router.sent, isEmpty, reason: 'picking must not save');

    await tester.tap(find.widgetWithText(
        FilledButton, UserStorage.l10n.floatingCaptureSave));
    await settle(tester);

    expect(router.sent.single.images.single.path, '/synthetic/foto.jpg');
    expect(nativeCalls, ['close']);
  });

  testWidgets('a capture the super agent refuses stays on the sheet',
      (tester) async {
    router.sendOutcome = () => Stream<ChatEvent>.error(StateError('offline'));
    await pumpSheet(tester, FloatingChatMode.note);

    await tester.enterText(find.byType(TextField), 'texto');
    await tester.pump();
    await tester.tap(find.widgetWithText(
        FilledButton, UserStorage.l10n.floatingCaptureSave));
    await settle(tester);

    expect(
        find.text(UserStorage.l10n.floatingCaptureSaveFailed), findsOneWidget);
    expect(nativeCalls, isEmpty);
    expect(find.text('home-screen'), findsNothing);
  });

  testWidgets('Foto allows clearing the picked photo and picking again',
      (tester) async {
    picked = XFile('/synthetic/foto.jpg', name: 'foto.jpg');
    await pumpSheet(tester, FloatingChatMode.photo);

    await tester.tap(find.text(UserStorage.l10n.floatingCaptureGallery));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const ValueKey('floating_capture_clear_image')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('floating_capture_clear_image')));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.text(UserStorage.l10n.floatingCaptureCamera), findsOneWidget);
    expect(find.text(UserStorage.l10n.floatingCaptureGallery), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);
    expect(router.sent, isEmpty);
  });

  testWidgets(
      'Colar hides the empty clipboard notice as soon as the user types',
      (tester) async {
    clipboard = null;
    await pumpSheet(tester, FloatingChatMode.paste);

    expect(
        find.text(UserStorage.l10n.floatingCapturePasteEmpty), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'anotado manualmente');
    await tester.pump();

    expect(find.text(UserStorage.l10n.floatingCapturePasteEmpty), findsNothing);
    expect(saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('while saving, shows progress and keeps the sheet locked open',
      (tester) async {
    final gate = Completer<void>();
    router.sendOutcome = () => Stream.fromFuture(
          gate.future.then((_) => ChatAgentStartedEvent('turn-1')),
        );
    await pumpSheet(tester, FloatingChatMode.note);

    await tester.enterText(find.byType(TextField), 'lembrar');
    await tester.pump();
    await tester.tap(find.widgetWithText(
        FilledButton, UserStorage.l10n.floatingCaptureSave));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester
          .widget<TextButton>(
              find.widgetWithText(TextButton, UserStorage.l10n.close))
          .onPressed,
      isNull,
    );
    expect(nativeCalls, isEmpty);

    gate.complete();
    await settle(tester);

    expect(nativeCalls, ['close']);
    expect(find.text('home-screen'), findsOneWidget);
  });
}

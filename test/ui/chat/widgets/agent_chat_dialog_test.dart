import 'dart:io';
import '../../../helpers/fake_photo_asset.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:memex/data/services/photo_attachment_service.dart';
import 'package:memex/data/services/native_photo_picker_service.dart';
import 'package:memex/ui/chat/view_models/photo_attachments_viewmodel.dart';
import 'package:memex/ui/core/widgets/reliable_asset_picker.dart';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:memex/data/model/chat_artifact.dart';
import 'package:memex/data/model/chat_events.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/demo_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_asset_server.dart';
import 'package:memex/data/services/system_action_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/domain/models/todo_proposal.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/chat/view_models/voice_dictation_viewmodel.dart';
import 'package:memex/ui/chat/widgets/agent_chat_dialog.dart';
import 'package:memex/ui/floating_chat/floating_chat_host.dart';
import 'package:memex/ui/floating_chat/view_models/listen_once_viewmodel.dart';
import 'package:memex/ui/todo/view_models/todo_proposal_viewmodel.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/core/widgets/local_image.dart';
import 'package:memex/ui/knowledge/widgets/knowledge_file_page.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/utils/result.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../../helpers/duplex_voice_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await initializeDateFormatting('en');
    await UserStorage.initL10n();
  });

  testWidgets(
      'iOS gallery uses system picker and previews a limited-access selection before export',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final original = Completer<Map<String, Object>>();
      var pickerCalls = 0;
      final released = <String>[];
      final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          NativePhotoPickerService.channel, (call) async {
        switch (call.method) {
          case 'pickImages':
            pickerCalls++;
            expect(call.arguments['maxAssets'], 9);
            return [
              {'id': 'native-selected'}
            ];
          case 'thumbnail':
            return png;
          case 'prepareOriginal':
            return original.future;
          case 'release':
            released.add(call.arguments['id'] as String);
            return null;
        }
        throw StateError('Unexpected method');
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(NativePhotoPickerService.channel, null));
      final vm = PhotoAttachmentsViewModel.forTesting(
          loader: (_) async => throw StateError(
              'Must use picker provider, not PhotoKit export'));
      await _pumpDialogFrame(tester,
          dialog: AgentChatDialog(
              photoAttachmentsForTesting: vm,
              initialDraftText: 'keep my draft'));
      await tester.pump(const Duration(milliseconds: 600));
      await _tapGalleryFromMenu(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(pickerCalls, 1);
      expect(find.byKey(const ValueKey('selected-photo-native-selected')),
          findsOneWidget);
      expect(find.byKey(const Key('native-photo-preview')), findsOneWidget);
      final send = find.byKey(const ValueKey('super_agent_publish_button'));
      expect(tester.widget<GestureDetector>(send).onTap, isNull);
      expect(find.text('keep my draft'), findsOneWidget);
      original.complete({
        'path': '/original/IMG_native.HEIC',
        'originalName': 'IMG_native.HEIC'
      });
      await tester.pump();
      await tester.pump();
      expect(tester.widget<GestureDetector>(send).onTap, isNotNull);
      expect(vm.items.single.prepared!.originalName, 'IMG_native.HEIC');
      expect(find.byKey(const Key('native-photo-preview')), findsOneWidget);
      await tester
          .tap(find.byKey(const ValueKey('remove-photo-native-selected')));
      await tester.pump();
      expect(find.byKey(const ValueKey('selected-photo-native-selected')),
          findsNothing);
      expect(find.text('keep my draft'), findsOneWidget);
      expect(released, ['native-selected']);
      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('capture input shows the content notice in pt and en',
      (tester) async {
    final notices = {
      'pt': 'Não registre dados de clientes, contas ou documentos do banco.',
      'en': 'Do not record client data, accounts or bank documents.',
    };
    for (final entry in notices.entries) {
      SharedPreferences.setMockInitialValues({'language': entry.key});
      await UserStorage.initL10n();
      await _pumpDialogFrame(tester, dialog: const AgentChatDialog());
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(entry.value), findsOneWidget, reason: entry.key);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('attach menu offers camera, gallery, TXT, PDF and audio',
      (tester) async {
    await _pumpDialogFrame(tester, dialog: const AgentChatDialog());
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const ValueKey('super_agent_attach_button')));
    await tester.pumpAndSettle();
    for (final key in [
      'attach_camera',
      'attach_gallery',
      'attach_txt',
      'attach_pdf',
      'attach_audio',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
  });

  testWidgets('mic button records, shows status and fills the text field',
      (tester) async {
    final audio = StreamController<Uint8List>();
    addTearDown(audio.close);
    final transcript = Completer<String?>();
    final voice = VoiceDictationViewModel(
      requestPermission: () async => true,
      startStream: () async => audio.stream,
      stopStream: () async {},
      transcribe: (_) => transcript.future,
    );
    addTearDown(voice.dispose);
    await _pumpDialogFrame(
      tester,
      dialog: AgentChatDialog(voiceDictationForTesting: voice),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final mic = find.byKey(const ValueKey('super_agent_mic_button'));
    expect(mic, findsOneWidget);
    expect(find.bySemanticsLabel('Record audio'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('super_agent_duplex_voice_button')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Open voice conversation'), findsOneWidget);
    expect(find.bySemanticsLabel('Attach'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('super_agent_attach_button'))),
      const Size(48, 48),
    );
    expect(
      tester
          .getSemantics(mic)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    await tester.tap(mic);
    await tester.pump();
    expect(find.text('Recording… tap the microphone to stop'), findsOneWidget);
    expect(find.bySemanticsLabel('Stop and transcribe'), findsOneWidget);
    expect(
      tester
          .getSemantics(mic)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    audio.add(Uint8List.fromList([1, 0, 2, 0]));
    await tester.pump();
    await tester.tap(mic);
    await tester.pump();
    expect(find.text('Transcribing…'), findsOneWidget);
    expect(
      tester
          .getSemantics(mic)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );

    transcript.complete('comprar leite');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('comprar leite'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('super_agent_voice_status')), findsNothing);
  });

  testWidgets('mic button explains a denied microphone permission',
      (tester) async {
    final voice = VoiceDictationViewModel(
      requestPermission: () async => false,
      startStream: () async => const Stream<Uint8List>.empty(),
      stopStream: () async {},
      transcribe: (_) async => null,
    );
    addTearDown(voice.dispose);
    await _pumpDialogFrame(
      tester,
      dialog: AgentChatDialog(voiceDictationForTesting: voice),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const ValueKey('super_agent_mic_button')));
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        "Microphone permission denied. Enable it in this app's settings.",
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'mic only dictates: a missing local model points to Settings, '
      'no download offered', (tester) async {
    final dir = Directory.systemTemp.createTempSync('chat_no_model');
    final original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _SupportDirProvider(dir.path);
    await UserStorage.setUseLocalSpeechToText(true);
    addTearDown(() async {
      PathProviderPlatform.instance = original;
      await UserStorage.setUseLocalSpeechToText(false);
      dir.deleteSync(recursive: true);
    });
    var permissionAsked = false;
    final voice = VoiceDictationViewModel(
      requestPermission: () async => permissionAsked = true,
      startStream: () async => const Stream<Uint8List>.empty(),
      stopStream: () async {},
      transcribe: (_) async => null,
    );
    addTearDown(voice.dispose);
    await _pumpDialogFrame(
      tester,
      dialog: AgentChatDialog(voiceDictationForTesting: voice),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('super_agent_mic_button')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(find.text(UserStorage.l10n.speechModelMissingHint), findsOneWidget);
    expect(find.text(UserStorage.l10n.speechModelStartDownload), findsNothing);
    expect(permissionAsked, isFalse);
    expect(voice.isRecording, isFalse);
  });

  testWidgets(
      'gallery preview appears before original export and cannot submit an incomplete attachment',
      (tester) async {
    const channel = MethodChannel('com.fluttercandies/photo_manager');
    final original = Completer<String>();
    var exportCalls = 0;
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'getThumb') return png;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final service = PhotoAttachmentService.forTesting(
        assetLoader: (id) async => FakePhotoAsset(
            id: id,
            fileLoader: (isOrigin) async {
              expect(isOrigin, isTrue);
              exportCalls++;
              return File(await original.future);
            },
            titleLoader: () async => 'IMG_original.HEIC'));
    final vm =
        PhotoAttachmentsViewModel.forTesting(loader: service.prepareAsset);
    addTearDown(vm.dispose);
    await _pumpDialogFrame(tester,
        dialog: AgentChatDialog(
          photoAttachmentsForTesting: vm,
          imagePickerForTesting: (_) async => [
            AssetEntity(
                id: 'selection-original', typeInt: 1, width: 4000, height: 3000)
          ],
        ));
    await tester.pump(const Duration(milliseconds: 600));
    await _tapGalleryFromMenu(tester);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('selected-photo-selection-original')),
        findsOneWidget);
    expect(find.byKey(reliableThumbnailImageKey), findsOneWidget);
    expect(find.text(UserStorage.l10n.preparingSelectedPhotos), findsOneWidget);
    final send = find.byKey(const ValueKey('super_agent_publish_button'));
    expect(tester.widget<GestureDetector>(send).onTap, isNull);
    expect(exportCalls, 1);
    original.complete('/original/IMG_original.HEIC');
    await tester.pump();
    await tester.pump();
    expect(find.text(UserStorage.l10n.preparingSelectedPhotos), findsNothing);
    expect(tester.widget<GestureDetector>(send).onTap, isNotNull);
    expect(vm.items.single.prepared!.path, '/original/IMG_original.HEIC');
    expect(vm.items.single.prepared!.originalName, 'IMG_original.HEIC');
    expect(find.byKey(reliableThumbnailImageKey), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  Future<void> pickGalleryPhotoWithChatModel(
    WidgetTester tester, {
    required String type,
    required String modelId,
  }) async {
    final config = LLMConfig.createDefaultClientConfig()
        .copyWith(type: type, modelId: modelId);
    await UserStorage.saveLLMConfigs([config]);
    const channel = MethodChannel('com.fluttercandies/photo_manager');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final service = PhotoAttachmentService.forTesting(
        assetLoader: (id) async => FakePhotoAsset(
            id: id,
            fileLoader: (_) async => File('/original/photo.jpg'),
            titleLoader: () async => 'photo.jpg'));
    final vm =
        PhotoAttachmentsViewModel.forTesting(loader: service.prepareAsset);
    addTearDown(vm.dispose);
    await _pumpDialogFrame(tester,
        dialog: AgentChatDialog(
          photoAttachmentsForTesting: vm,
          imagePickerForTesting: (_) async =>
              [AssetEntity(id: 'photo', typeInt: 1, width: 10, height: 10)],
        ));
    await tester.pump(const Duration(milliseconds: 600));
    await _tapGalleryFromMenu(tester);
    // The warning waits for the stored model config; let it and the
    // thumbnail retry timer finish.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('attaching a photo warns when the chat model has no vision',
      (tester) async {
    await pickGalleryPhotoWithChatModel(tester,
        type: LLMConfig.typeChatCompletion, modelId: 'text-only-model');
    expect(find.text(UserStorage.l10n.attachNoVisionWarning), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('attaching a photo stays quiet for the gpt-6 OAuth chat model',
      (tester) async {
    await pickGalleryPhotoWithChatModel(tester,
        type: LLMConfig.typeOpenAiOauth, modelId: 'gpt-6-luna');
    expect(find.text(UserStorage.l10n.attachNoVisionWarning), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'failed gallery originals offer retry and removal without losing the draft',
      (tester) async {
    const channel = MethodChannel('com.fluttercandies/photo_manager');
    var fail = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'getThumb') {
        return base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final service = PhotoAttachmentService.forTesting(
        assetLoader: (id) async => FakePhotoAsset(
            id: id,
            fileLoader: (isOrigin) async {
              expect(isOrigin, isTrue);
              if (fail) throw PlatformException(code: 'offline');
              return File('/original/photo.heic');
            },
            titleLoader: () async => 'photo.heic'));
    final vm =
        PhotoAttachmentsViewModel.forTesting(loader: service.prepareAsset);
    addTearDown(vm.dispose);
    await _pumpDialogFrame(tester,
        dialog: AgentChatDialog(
          initialDraftText: 'keep this draft',
          photoAttachmentsForTesting: vm,
          imagePickerForTesting: (_) async => [
            AssetEntity(
                id: 'failed-selection', typeInt: 1, width: 100, height: 100)
          ],
        ));
    await tester.pump(const Duration(milliseconds: 600));
    await _tapGalleryFromMenu(tester);
    await tester.pump();
    await tester.pump();
    expect(find.text(UserStorage.l10n.selectedPhotosPreparationFailed),
        findsOneWidget);
    expect(find.text('keep this draft'), findsOneWidget);
    fail = false;
    await tester
        .tap(find.byKey(const ValueKey('retry-photo-failed-selection')));
    await tester.pump();
    await tester.pump();
    expect(vm.canSubmit, isTrue);
    await tester
        .tap(find.byKey(const ValueKey('remove-photo-failed-selection')));
    await tester.pump();
    expect(find.byKey(const ValueKey('selected-photo-failed-selection')),
        findsNothing);
    expect(find.text('keep this draft'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('AgentChatDialog layout metrics', () {
    test('resolves default sheet and full-screen heights', () {
      const viewport = Size(390, 800);

      expect(resolveAgentChatDialogHeight(viewport, isFullScreen: false), 600);
      expect(resolveAgentChatDialogHeight(viewport, isFullScreen: true), 800);
      expect(
        resolveAgentChatDialogHeight(
          viewport,
          isFullScreen: false,
          keyboardInset: 320,
        ),
        480,
      );
      expect(
        resolveAgentChatDialogHeight(
          viewport,
          isFullScreen: true,
          keyboardInset: 320,
        ),
        480,
      );
      expect(
        resolveAgentChatDialogHeight(
          viewport,
          isFullScreen: false,
          keyboardInset: 320,
          topSafeInset: 44,
        ),
        436,
      );
    });

    test('uses rounded sheet corners only outside full screen', () {
      expect(
        resolveAgentChatDialogBorderRadius(isFullScreen: false),
        const BorderRadius.vertical(top: Radius.circular(32)),
      );
      expect(
        resolveAgentChatDialogBorderRadius(isFullScreen: true),
        BorderRadius.zero,
      );
    });

    test('uses keyboard inset whenever the keyboard is visible and editable',
        () {
      expect(
        resolveSuperAgentInputBottomInset(
          keyboardInset: 320,
          inputFocused: true,
          isStreaming: false,
        ),
        320,
      );
      expect(
        resolveSuperAgentInputBottomInset(
          keyboardInset: 320,
          inputFocused: true,
          isStreaming: true,
        ),
        320,
      );
      expect(
        resolveSuperAgentInputBottomInset(
          keyboardInset: 320,
          inputFocused: false,
          isStreaming: false,
        ),
        320,
      );
    });

    test('does not create an empty assistant bubble for final done chunks', () {
      expect(
        shouldCreateAIMessageForResponseChunk(text: '', isDone: true),
        isFalse,
      );
      expect(
        shouldCreateAIMessageForResponseChunk(text: '', isDone: false),
        isTrue,
      );
      expect(
        shouldCreateAIMessageForResponseChunk(text: 'Done', isDone: true),
        isTrue,
      );
    });

    test('requests older history near the top or when content is too short',
        () {
      expect(
        shouldRequestOlderSuperAgentHistory(
          hasMoreHistory: true,
          isLoading: false,
          pixels: 0,
          maxScrollExtent: 0,
        ),
        isTrue,
      );
      expect(
        shouldRequestOlderSuperAgentHistory(
          hasMoreHistory: true,
          isLoading: false,
          pixels: 80,
          maxScrollExtent: 100,
        ),
        isTrue,
      );
      expect(
        shouldRequestOlderSuperAgentHistory(
          hasMoreHistory: true,
          isLoading: false,
          pixels: 60,
          maxScrollExtent: 100,
        ),
        isFalse,
      );
      expect(
        shouldRequestOlderSuperAgentHistory(
          hasMoreHistory: true,
          isLoading: true,
          pixels: 100,
          maxScrollExtent: 100,
        ),
        isFalse,
      );
    });

    test('snaps down when the keyboard inset shrinks', () {
      expect(
        resolveSuperAgentKeyboardInsetAnimationDuration(
          previousInset: 0,
          nextInset: 320,
        ),
        const Duration(milliseconds: 220),
      );
      expect(
        resolveSuperAgentKeyboardInsetAnimationDuration(
          previousInset: 320,
          nextInset: 0,
        ),
        Duration.zero,
      );
    });

    test('maps reversed chat list indexes around live status rows', () {
      expect(
        superAgentItemIndexForReversedList(
          listIndex: 0,
          itemCount: 10,
          extraItems: 0,
        ),
        9,
      );
      expect(
        superAgentItemIndexForReversedList(
          listIndex: 1,
          itemCount: 10,
          extraItems: 1,
        ),
        9,
      );
      expect(
        superAgentItemIndexForReversedList(
          listIndex: 10,
          itemCount: 10,
          extraItems: 1,
        ),
        0,
      );
    });

    test('formats chat time dividers like persona chat', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9, 8);

      expect(formatSuperAgentTimeDivider(today), '09:08');
      expect(
        formatSuperAgentTimeDivider(
          today.subtract(const Duration(days: 1)),
        ),
        contains(UserStorage.l10n.yesterday),
      );
    });

    test('formats token usage without estimated cost', () {
      final text = formatSuperAgentTokenUsage(
        ChatTokenUsageEvent(
          promptTokens: 100,
          completionTokens: 25,
          cachedTokens: 40,
          totalTokens: 125,
          estimatedCost: 0.12345,
          effectivePromptTokens: 100,
          cachedTokensForRate: 40,
        ),
      );

      expect(text, 'Tokens: 125 (P:100 C:25 Cache:40.0%)');
      expect(text, isNot(contains('Est')));
      expect(text, isNot(contains(r'$')));
      expect(text, isNot(contains('0.12345')));
    });

    test('shows standalone thinking only before process or reply appears', () {
      expect(
        shouldShowSuperAgentThinkingRow(
          isLoadingAgent: false,
          primaryItem: UserMessageItem('hello'),
        ),
        isFalse,
      );
      expect(
        shouldShowSuperAgentThinkingRow(
          isLoadingAgent: true,
          primaryItem: UserMessageItem('hello'),
        ),
        isTrue,
      );
      expect(
        shouldShowSuperAgentThinkingRow(
          isLoadingAgent: true,
          primaryItem: ProcessItem(),
        ),
        isFalse,
      );
      expect(
        shouldShowSuperAgentThinkingRow(
          isLoadingAgent: true,
          primaryItem: AIMessageItem('reply', isStreaming: true),
        ),
        isFalse,
      );
    });

    test('uses final process state instead of historical tool errors', () {
      final failedTool = ToolCallItem(
        'read-1',
        'read',
        '{}',
        result: 'temporary failure',
        isError: true,
      );
      final completedProcess = ProcessItem(isFinished: true)
        ..children.add(failedTool);
      final attentionProcess = ProcessItem(
        isFinished: true,
        needsAttention: true,
      )..children.add(failedTool);

      expect(
        superAgentProcessVisualState(completedProcess),
        SuperAgentProcessVisualState.done,
      );
      expect(
        superAgentProcessVisualState(attentionProcess),
        SuperAgentProcessVisualState.needsAttention,
      );
      expect(completedProcess.hasToolError, isTrue);
    });

    test('shows the photo suggestion status until suggestions resolve', () {
      expect(
        shouldShowSuperAgentPhotoSuggestionStatus(
          isLoading: true,
          hasSuggestions: false,
          hasLoadedSuggestions: false,
        ),
        isTrue,
      );
      expect(
        shouldShowSuperAgentPhotoSuggestionStatus(
          isLoading: false,
          hasSuggestions: true,
          hasLoadedSuggestions: true,
        ),
        isFalse,
      );
      expect(
        shouldShowSuperAgentPhotoSuggestionStatus(
          isLoading: false,
          hasSuggestions: false,
          hasLoadedSuggestions: true,
        ),
        isFalse,
      );
    });

    test('queues a super agent send while another run is active', () {
      expect(
        shouldQueueSuperAgentSend(
          isStreaming: false,
          hasSessionId: true,
          hasChatSubscription: true,
        ),
        isFalse,
      );
      expect(
        shouldQueueSuperAgentSend(
          isStreaming: true,
          hasSessionId: false,
          hasChatSubscription: true,
        ),
        isFalse,
      );
      expect(
        shouldQueueSuperAgentSend(
          isStreaming: true,
          hasSessionId: true,
          hasChatSubscription: false,
        ),
        isFalse,
      );
      expect(
        shouldQueueSuperAgentSend(
          isStreaming: true,
          hasSessionId: true,
          hasChatSubscription: true,
        ),
        isTrue,
      );
    });

    test(
        'explains notification permission only for first eligible Android send',
        () {
      expect(
        shouldExplainMemexAgentNotificationPermission(
          platform: TargetPlatform.android,
          isDemoActive: false,
          alreadyPrompted: false,
          notificationStatus: PermissionStatus.denied,
        ),
        isTrue,
      );
      expect(
        shouldExplainMemexAgentNotificationPermission(
          platform: TargetPlatform.iOS,
          isDemoActive: false,
          alreadyPrompted: false,
          notificationStatus: PermissionStatus.denied,
        ),
        isFalse,
      );
      expect(
        shouldExplainMemexAgentNotificationPermission(
          platform: TargetPlatform.android,
          isDemoActive: true,
          alreadyPrompted: false,
          notificationStatus: PermissionStatus.denied,
        ),
        isFalse,
      );
      expect(
        shouldExplainMemexAgentNotificationPermission(
          platform: TargetPlatform.android,
          isDemoActive: false,
          alreadyPrompted: true,
          notificationStatus: PermissionStatus.denied,
        ),
        isFalse,
      );
      expect(
        shouldExplainMemexAgentNotificationPermission(
          platform: TargetPlatform.android,
          isDemoActive: false,
          alreadyPrompted: false,
          notificationStatus: PermissionStatus.granted,
        ),
        isFalse,
      );
      expect(
        shouldExplainMemexAgentNotificationPermission(
          platform: TargetPlatform.android,
          isDemoActive: false,
          alreadyPrompted: false,
          notificationStatus: PermissionStatus.permanentlyDenied,
        ),
        isFalse,
      );
    });

    test('keeps original filenames only for selected initial images', () {
      final selected = [
        XFile('/tmp/a.jpg'),
        XFile('/tmp/b.jpg'),
      ];

      expect(
        initialOriginalFilenamesForSelectedImages(selected, {
          '/tmp/a.jpg': 'camera-original.jpg',
          '/tmp/b.jpg': ' ',
          '/tmp/unused.jpg': 'unused.jpg',
        }),
        {'/tmp/a.jpg': 'camera-original.jpg'},
      );
    });

    test('uses demo send key only while spotlighting super agent publish', () {
      expect(superAgentDemoPublishTargetKey(null), isNull);
      expect(superAgentDemoPublishTargetKey(DemoStep.tapAddButton), isNull);
      expect(
        superAgentDemoPublishTargetKey(DemoStep.tapSend),
        same(DemoService.instance.sendButtonKey),
      );
    });

    test('keeps artifacts attached to the assistant reply item', () {
      final artifact = ArtifactItem(
        ChatArtifact.schedule(title: 'Schedule presentation', updated: true),
      );
      final reply =
          AIMessageItem('Done', turnId: 'turn-1', artifacts: [artifact]);

      expect(reply.artifacts, [artifact]);
      expect(reply.artifacts.single.artifact.title, 'Schedule presentation');
    });

    test('coalesces artifact revisions without changing card order', () {
      final current = <ArtifactItem>[
        ArtifactItem(
          ChatArtifact.timelineCard(
            cardId: 'xinjiang',
            title: 'Draft',
            updated: false,
          ),
        ),
        ArtifactItem(
          ChatArtifact.schedule(title: 'Schedule', updated: false),
        ),
      ];

      mergeArtifactItems(current, [
        ArtifactItem(
          ChatArtifact.timelineCard(
            cardId: 'xinjiang',
            title: 'Final',
            updated: true,
          ),
        ),
      ]);

      expect(current, hasLength(2));
      expect(current.first.artifact.title, 'Final');
      expect(current.last.artifact.kind, ChatArtifact.kindSchedule);
    });

    test('attaches pending artifacts only to the same assistant turn', () {
      expect(
        shouldAttachArtifactsToAssistantReply(
          turnId: 'turn-1',
          primaryItem: AIMessageItem('Done', turnId: 'turn-1'),
        ),
        isTrue,
      );
      expect(
        shouldAttachArtifactsToAssistantReply(
          turnId: 'turn-2',
          primaryItem: AIMessageItem('Done', turnId: 'turn-1'),
        ),
        isFalse,
      );
      expect(
        shouldAttachArtifactsToAssistantReply(
          turnId: 'turn-1',
          primaryItem: UserMessageItem('next request'),
        ),
        isFalse,
      );
    });

    test('toggles demo overlay suspension for routed detail pages', () {
      final demo = DemoService.instance;

      demo.resumeOverlay();
      expect(demo.isOverlaySuspended, isFalse);

      demo.suspendOverlay();
      expect(demo.isOverlaySuspended, isTrue);

      demo.resumeOverlay();
      expect(demo.isOverlaySuspended, isFalse);
    });
  });

  group('AgentChatDialog full-screen affordance', () {
    testWidgets('starts as a bottom sheet with a full-screen action', (
      tester,
    ) async {
      await _pumpDialog(tester);

      expect(find.text(UserStorage.l10n.aiInputHint), findsWidgets);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip(UserStorage.l10n.chatHistory), findsNothing);
      expect(
        find.byTooltip(UserStorage.l10n.enterFullScreenTooltip),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.open_in_full), findsOneWidget);
      expect(find.byTooltip(UserStorage.l10n.close), findsOneWidget);
      expect(
        find.byKey(const ValueKey('super_agent_run_mode_chip')),
        findsNothing,
      );

      final container = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('agent_chat_dialog_container')),
      );
      final decoration = container.decoration! as BoxDecoration;

      expect(
        tester
            .getSize(find.byKey(const ValueKey('agent_chat_dialog_container')))
            .height,
        600,
      );
      expect(
        decoration.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(32)),
      );
    });

    testWidgets('keeps the keyboard sheet below the top safe area', (
      tester,
    ) async {
      const viewportSize = Size(390, 800);
      const topSafeInset = 44.0;
      const keyboardInset = 320.0;
      await _pumpDialog(
        tester,
        viewportSize: viewportSize,
        mediaQueryData: const MediaQueryData(
          size: viewportSize,
          viewPadding: EdgeInsets.only(top: topSafeInset),
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
      );

      final dialogRect = tester.getRect(
        find.byKey(const ValueKey('agent_chat_dialog_container')),
      );
      expect(dialogRect.top, topSafeInset);
      expect(dialogRect.bottom, viewportSize.height - keyboardInset);
    });

    testWidgets('expands to full screen and restores the sheet', (
      tester,
    ) async {
      await _pumpDialog(tester);

      await tester.tap(
        find.byKey(const ValueKey('agent_chat_fullscreen_toggle')),
      );
      await tester.pumpAndSettle();

      var container = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('agent_chat_dialog_container')),
      );
      var decoration = container.decoration! as BoxDecoration;

      expect(
        tester
            .getSize(find.byKey(const ValueKey('agent_chat_dialog_container')))
            .height,
        800,
      );
      expect(decoration.borderRadius, BorderRadius.zero);
      expect(
        find.byTooltip(UserStorage.l10n.exitFullScreenTooltip),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.close_fullscreen), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('agent_chat_fullscreen_toggle')),
      );
      await tester.pumpAndSettle();

      container = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('agent_chat_dialog_container')),
      );
      decoration = container.decoration! as BoxDecoration;

      expect(
        tester
            .getSize(find.byKey(const ValueKey('agent_chat_dialog_container')))
            .height,
        600,
      );
      expect(
        decoration.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(32)),
      );
      expect(
        find.byTooltip(UserStorage.l10n.enterFullScreenTooltip),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.open_in_full), findsOneWidget);
    });

    testWidgets('does not show a loading logo while opening a session', (
      tester,
    ) async {
      await _pumpDialogFrame(
        tester,
        dialog: const AgentChatDialog(initialSessionId: 'session-1'),
      );

      expect(find.byType(AgentLogoLoading), findsNothing);
    });

    testWidgets('renders selected images through the cached image widget', (
      tester,
    ) async {
      await _pumpDialogFrame(
        tester,
        dialog: AgentChatDialog(
          initialImages: [XFile('/tmp/memex-selected-image.jpg')],
        ),
      );

      expect(find.byType(LocalImage), findsOneWidget);
    });

    testWidgets('keeps process thinking and token usage inside details', (
      tester,
    ) async {
      final usage = ChatTokenUsageEvent(
        promptTokens: 100,
        completionTokens: 25,
        cachedTokens: 40,
        totalTokens: 125,
        estimatedCost: 0.0,
        effectivePromptTokens: 100,
        cachedTokensForRate: 40,
      );
      final process = ProcessItem()
        ..children.add(ThinkingItem('Inspecting the plan'));

      await _pumpDialogFrame(
        tester,
        dialog: AgentChatDialog(
          initialItems: [process],
          initialIsLoadingAgent: true,
          initialTokenUsage: usage,
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      final tokenText = formatSuperAgentTokenUsage(usage);
      expect(find.text(UserStorage.l10n.agentChat.thinking), findsNothing);
      expect(find.text('Inspecting the plan'), findsNothing);
      expect(find.text(tokenText), findsNothing);

      await tester.tap(find.byKey(const ValueKey('agent_chat_process_toggle')));
      await tester.pump();

      expect(find.text(UserStorage.l10n.agentChat.thinking), findsOneWidget);
      expect(find.text('Inspecting the plan'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('agent_chat_token_usage_debug')),
        findsOneWidget,
      );
      expect(find.text(tokenText), findsOneWidget);
    });

    testWidgets('shows completed process despite intermediate tool errors', (
      tester,
    ) async {
      final failedTool = ToolCallItem(
        'read-1',
        'read',
        '{}',
        result: 'temporary failure',
        isError: true,
      );
      final process = ProcessItem(isFinished: true)..children.add(failedTool);

      await _pumpDialogFrame(
        tester,
        dialog: AgentChatDialog(initialItems: [process]),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        find.text(UserStorage.l10n.agentChat.completedActions(1)),
        findsOneWidget,
      );
      expect(find.text(UserStorage.l10n.agentChat.actionNeedsAttention),
          findsNothing);
      expect(find.text(UserStorage.l10n.agentChat.issue), findsNothing);
    });

    test('resolves persisted user image paths as local files', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'memex_user_message_image_',
      );
      try {
        await FileSystemService.init(tempDir.path);
        const relativePath = 'workspace/_alice/Facts/assets/photo.jpg';

        expect(
          superAgentUserMessageImageSourceForLocalDisplay(relativePath),
          p.join(tempDir.path, relativePath),
        );
        expect(
          superAgentUserMessageImageSourceForLocalDisplay(
            'https://example.com/photo.jpg',
          ),
          'https://example.com/photo.jpg',
        );
      } finally {
        await LocalAssetServer.stopServer();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    testWidgets(
      'keeps header actions inside the compact header on narrow screens',
      (tester) async {
        await _pumpDialog(
          tester,
          viewportSize: const Size(320, 800),
        );

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('agent_chat_fullscreen_toggle')),
          findsOneWidget,
        );
        expect(find.byTooltip(UserStorage.l10n.close), findsOneWidget);
      },
    );

    testWidgets('super agent entry hides chat controls and uses send input', (
      tester,
    ) async {
      await _pumpDialog(tester);

      expect(find.byTooltip(UserStorage.l10n.chatHistory), findsNothing);
      expect(find.byIcon(Icons.mic), findsNothing);
      expect(
        find.byKey(const ValueKey('super_agent_attach_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('super_agent_publish_button')),
        findsOneWidget,
      );
      expect(find.text(UserStorage.l10n.sendLabel), findsOneWidget);
    });

    testWidgets('send is amber with dark text when it can submit',
        (tester) async {
      await _pumpDialog(tester);

      final fill = (tester
              .widget<AnimatedContainer>(find.descendant(
                of: find.byKey(const ValueKey('super_agent_publish_button')),
                matching: find.byType(AnimatedContainer),
              ))
              .decoration as BoxDecoration)
          .color;
      final text =
          tester.widget<Text>(find.text(UserStorage.l10n.sendLabel)).style!;

      expect(fill, AppColors.primary);
      expect(text.color, AppColors.onPrimary);
    });

    testWidgets('renders a legacy schedule artifact without a dead link', (
      tester,
    ) async {
      await _pumpDialog(
        tester,
        dialog: AgentChatDialog(
          initialItems: [
            AIMessageItem(
              'I updated your schedule.',
              artifacts: [
                ArtifactItem(
                  ChatArtifact.schedule(
                    title: 'Schedule presentation',
                    summary: 'Pending schedule items: 3',
                    updated: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      expect(find.text('I updated your schedule.'), findsOneWidget);
      expect(find.text('${UserStorage.l10n.agentChat.result} · 1'),
          findsOneWidget);
      expect(find.text(UserStorage.l10n.schedule), findsOneWidget);
      expect(find.text('Schedule presentation'), findsOneWidget);
      expect(find.text('Pending schedule items: 3'), findsOneWidget);
      expect(find.text(UserStorage.l10n.artifactOpen), findsNothing);
    });

    testWidgets('renders the task proposal card in an assistant reply', (
      tester,
    ) async {
      final router = _TodoProposalRouter();
      final viewModel = TodoProposalViewModel(router: router);
      addTearDown(viewModel.dispose);
      final proposal = TodoProposal(
        id: 'proposal-chat-1',
        title: 'Review the report',
        dateState: TodoProposalDateState.ambiguous,
        datePhrase: 'Friday',
        timeState: TodoProposalTimeState.unspecified,
      );

      await _pumpDialog(
        tester,
        dialog: AgentChatDialog(
          todoProposalViewModelForTesting: viewModel,
          initialItems: [
            AIMessageItem(
              'Here is a task suggestion.',
              artifacts: [
                ArtifactItem(ChatArtifact.todoProposalCard(proposal: proposal)),
              ],
            ),
          ],
        ),
      );

      expect(find.text('Here is a task suggestion.'), findsOneWidget);
      expect(find.text('Review the report'), findsOneWidget);
      expect(find.text(UserStorage.l10n.todoProposalReview), findsOneWidget);
      expect(router.addCalls, 0);
    });

    testWidgets('renders a system action with inline confirmation controls', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
      addTearDown(db.close);
      await SystemActionService.instance.createAction(
        id: 'calendar-action-1',
        type: 'calendar',
        data: const {
          'title': 'Team review',
          'start_time': '2026-08-01 15:30:00',
        },
      );

      await _pumpDialog(
        tester,
        dialog: AgentChatDialog(
          initialItems: [
            AIMessageItem(
              'Ready for confirmation.',
              artifacts: [
                ArtifactItem(
                  ChatArtifact.systemAction(
                    actionId: 'calendar-action-1',
                    systemActionKind: 'calendar',
                    title: 'Team review',
                    summary: '2026-08-01 15:30',
                    updated: false,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      expect(
        find.text(UserStorage.l10n.discoveredCalendarEvent),
        findsOneWidget,
      );
      expect(
        find.text(UserStorage.l10n.agentChat.calendarEventCreated),
        findsNothing,
      );
      expect(find.text('Team review'), findsOneWidget);
      expect(
        find.text(UserStorage.l10n.systemActionPendingExplanation),
        findsOneWidget,
      );
      expect(find.text(UserStorage.l10n.addToCalendar), findsOneWidget);
      expect(find.text(UserStorage.l10n.ignore), findsOneWidget);
    });

    testWidgets('opens knowledge file artifacts with normalized PKM path', (
      tester,
    ) async {
      await _pumpDialog(
        tester,
        dialog: AgentChatDialog(
          initialItems: [
            AIMessageItem(
              'I updated the knowledge file.',
              artifacts: [
                ArtifactItem(
                  ChatArtifact.knowledgeFile(
                    path: 'PKM/Projects/memex.md',
                    title: 'memex.md',
                    summary: '# Memex',
                    updated: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      expect(find.text('I updated the knowledge file.'), findsOneWidget);
      expect(find.text('${UserStorage.l10n.agentChat.result} · 1'),
          findsOneWidget);
      expect(
        find.text(UserStorage.l10n.agentChat.documentUpdated),
        findsOneWidget,
      );
      expect(find.text('memex.md'), findsOneWidget);
      expect(find.text('PKM/Projects/memex.md'), findsOneWidget);
      expect(find.text(UserStorage.l10n.artifactOpen), findsOneWidget);

      await tester.tap(find.text(UserStorage.l10n.artifactOpen));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final page = tester.widget<KnowledgeFilePage>(
        find.byType(KnowledgeFilePage),
      );
      expect(page.filePath, 'Projects/memex.md');
    });

    testWidgets('keeps super agent header actions tight to the right edge', (
      tester,
    ) async {
      const viewportSize = Size(390, 800);
      await _pumpDialog(
        tester,
        viewportSize: viewportSize,
      );

      final dialogRect = tester.getRect(
        find.byKey(const ValueKey('agent_chat_dialog_container')),
      );
      final fullscreenButtonRect = tester.getRect(
        find.byKey(const ValueKey('agent_chat_fullscreen_toggle')),
      );
      final closeButtonFinder =
          find.byKey(const ValueKey('agent_chat_close_button'));
      final closeButtonRect = tester.getRect(closeButtonFinder);
      final closeIconRect = tester.getRect(
        find.descendant(
          of: closeButtonFinder,
          matching: find.byIcon(Icons.close),
        ),
      );

      expect(dialogRect.width, moreOrLessEquals(viewportSize.width));
      expect(closeButtonRect.size, const Size.square(36));
      expect(fullscreenButtonRect.size, const Size.square(36));
      expect(
        dialogRect.right - closeButtonRect.right,
        moreOrLessEquals(4),
      );
      expect(
        viewportSize.width - closeButtonRect.right,
        moreOrLessEquals(4),
      );
      expect(closeIconRect.right, greaterThan(dialogRect.right - 13));
      expect(closeIconRect.right, greaterThan(viewportSize.width - 13));
      expect(closeButtonRect.left - fullscreenButtonRect.right, 0);
    });
  });

  group('floating chat sheet (F15-02)', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    testWidgets('header offers Open in app and Close, and no other icons',
        (tester) async {
      final l10n = UserStorage.l10n;
      await _pumpDialogFrame(
        tester,
        dialog: AgentChatDialog(
          floatingHost: FloatingChatHost(
            onClose: () {},
            onOpenInApp: (_) {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text(l10n.floatingOpenInApp), findsOneWidget);
      expect(find.text(l10n.close), findsOneWidget);
      expect(
          find.byKey(const ValueKey('agent_chat_close_button')), findsNothing);
      expect(
        find.byKey(const ValueKey('agent_chat_fullscreen_toggle')),
        findsNothing,
      );
      for (final label in [l10n.floatingOpenInApp, l10n.close]) {
        final button = find.ancestor(
          of: find.text(label),
          matching: find.byType(TextButton),
        );
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('Close and a tap outside call onClose without popping',
        (tester) async {
      var closed = 0;
      await _pumpDialogFrame(
        tester,
        dialog: AgentChatDialog(
          floatingHost: FloatingChatHost(
            onClose: () => closed++,
            onOpenInApp: (_) {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text(UserStorage.l10n.close));
      await tester.pump();
      expect(closed, 1);
      // Still on screen: nothing popped the route under the dialog.
      expect(find.byType(AgentChatDialog), findsOneWidget);

      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(closed, 2);
      expect(find.byType(AgentChatDialog), findsOneWidget);
    });

    testWidgets('Open in app passes the current session id (null when new)',
        (tester) async {
      final opened = <String?>[];
      await _pumpDialogFrame(
        tester,
        dialog: AgentChatDialog(
          floatingHost: FloatingChatHost(
            onClose: () {},
            onOpenInApp: opened.add,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text(UserStorage.l10n.floatingOpenInApp));
      await tester.pump();

      expect(opened, [null]);
    });

    testWidgets('autofocusInput focuses the message field', (tester) async {
      await _pumpDialogFrame(
        tester,
        dialog: const AgentChatDialog(autofocusInput: true),
      );
      await tester.pump(const Duration(milliseconds: 600));

      final field = tester.widget<EditableText>(find.byType(EditableText).last);
      expect(field.focusNode.hasFocus, isTrue);
    });

    testWidgets('listenOnStart shows Listening and sends the utterance',
        (tester) async {
      final l10n = UserStorage.l10n;
      final device = FakeAudioDevice();
      final listenOnce = ListenOnceViewModel(
        service: device.service,
        transcribe: (_) async => 'oi, tudo bem',
        speechModelMissing: () async => false,
      );
      addTearDown(listenOnce.dispose);

      await _pumpDialogFrame(
        tester,
        dialog: AgentChatDialog(
          listenOnStart: true,
          listenOnceForTesting: listenOnce,
        ),
      );
      await settle(tester);

      expect(device.micHeld, isTrue);
      expect(find.text(l10n.floatingListening), findsOneWidget);
      expect(find.text(l10n.floatingListeningHint), findsOneWidget);

      device.mic.add(pcm(4, loud: true));
      device.mic.add(pcm(2, loud: false));
      await settle(tester);

      expect(device.micHeld, isFalse);
      expect(find.text(l10n.floatingListening), findsNothing);
      expect(find.text('oi, tudo bem'), findsOneWidget);
    });

    testWidgets(
        'listenOnStart explains a denied microphone and keeps the keyboard',
        (tester) async {
      final l10n = UserStorage.l10n;
      final device = FakeAudioDevice()..permission = false;
      final listenOnce = ListenOnceViewModel(
        service: device.service,
        speechModelMissing: () async => false,
      );
      addTearDown(listenOnce.dispose);

      await _pumpDialogFrame(
        tester,
        dialog: AgentChatDialog(
          listenOnStart: true,
          listenOnceForTesting: listenOnce,
        ),
      );
      await settle(tester);

      expect(device.micStarts, 0);
      expect(find.text(l10n.floatingMicDenied), findsOneWidget);
      expect(find.byType(EditableText), findsOneWidget);
    });

    testWidgets('typing while listening closes the microphone and sends nothing',
        (tester) async {
      final l10n = UserStorage.l10n;
      final device = FakeAudioDevice();
      final listenOnce = ListenOnceViewModel(
        service: device.service,
        transcribe: (_) async => 'oi, tudo bem',
        speechModelMissing: () async => false,
      );
      addTearDown(listenOnce.dispose);

      await _pumpDialogFrame(
        tester,
        dialog: AgentChatDialog(
          listenOnStart: true,
          listenOnceForTesting: listenOnce,
        ),
      );
      await settle(tester);
      expect(device.micHeld, isTrue);

      await tester.enterText(find.byType(EditableText).last, 'digitando');
      await settle(tester);

      expect(device.micHeld, isFalse);
      expect(find.text(l10n.floatingListening), findsNothing);
      expect(find.text('oi, tudo bem'), findsNothing);
      expect(
        tester.widget<EditableText>(find.byType(EditableText).last).controller.text,
        'digitando',
      );
    });
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  Size viewportSize = const Size(390, 800),
  Widget dialog = const AgentChatDialog(),
  MediaQueryData? mediaQueryData,
}) async {
  await _pumpDialogFrame(
    tester,
    viewportSize: viewportSize,
    dialog: dialog,
    mediaQueryData: mediaQueryData,
  );
  await tester.pumpAndSettle();
}

Future<void> _tapGalleryFromMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('super_agent_attach_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('attach_gallery')));
}

Future<void> _pumpDialogFrame(
  WidgetTester tester, {
  Size viewportSize = const Size(390, 800),
  Widget dialog = const AgentChatDialog(),
  MediaQueryData? mediaQueryData,
}) async {
  tester.view.physicalSize = viewportSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: mediaQueryData == null
            ? dialog
            : MediaQuery(data: mediaQueryData, child: dialog),
      ),
    ),
  );
  await tester.pump();
}

class _TodoProposalRouter implements MemexRouter {
  @override
  Future<Result<String?>> todoDamagedLegacyFileName() async => const Ok(null);

  int addCalls = 0;

  @override
  Future<Result<List<TodoItem>>> loadTodos(
          {bool includeDeleted = false}) async =>
      const Ok(<TodoItem>[]);

  @override
  Future<Result<TodoShortcutSettings>> loadTodoShortcutSettings() async =>
      Ok(TodoShortcutSettings.defaults);

  @override
  Future<Result<TodoItem>> addTodo({
    required String text,
    String? id,
    String? due,
    String? dueDate,
    String? dueTime,
    String timeZone = todoTimeZone,
    int alertMinutes = 20,
    TodoPriority priority = TodoPriority.normal,
    List<TodoSubtask> subtasks = const [],
    TodoRecurrence? recurrence,
  }) async {
    addCalls++;
    return Error(StateError('Unexpected Todo proposal confirmation'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SupportDirProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _SupportDirProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

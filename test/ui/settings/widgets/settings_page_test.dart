import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/semantic_search_model_service.dart';
import 'package:memex/data/services/whisper_service.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/settings/widgets/settings_page.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SemanticSearchManagerFake extends ChangeNotifier
    implements SemanticSearchModelManager {
  _SemanticSearchManagerFake(
      {this.waitForCompletion = false,
      this.fail = false,
      this.hasDownloadedFiles = false});

  final bool waitForCompletion;
  final bool fail;
  final completion = Completer<Result<void>>();

  @override
  bool hasDownloadedFiles;

  @override
  SemanticSearchModelState state = SemanticSearchModelState.off;

  @override
  double progress = 0;

  @override
  bool get isReady => state == SemanticSearchModelState.ready;

  @override
  Future<void> refreshModelAvailability() async {}

  @override
  Future<Result<void>> ensureReady({required bool allowDownload}) async {
    expect(allowDownload, isTrue);
    state = SemanticSearchModelState.downloading;
    progress = 0.25;
    notifyListeners();
    late final Result<void> result;
    if (waitForCompletion) {
      result = await completion.future;
    } else if (fail) {
      result = Error<void>(StateError('test download failed'));
    } else {
      result = const Ok.v();
    }
    state = result.isOk
        ? SemanticSearchModelState.ready
        : SemanticSearchModelState.error;
    hasDownloadedFiles = result.isOk;
    progress = result.isOk ? 1 : 0;
    notifyListeners();
    return result;
  }

  @override
  Future<Result<void>> disable() async {
    state = SemanticSearchModelState.off;
    progress = 0;
    notifyListeners();
    return const Ok.v();
  }

  @override
  Future<Result<void>> deleteModel() async {
    hasDownloadedFiles = false;
    return disable();
  }

  @override
  Future<List<double>> embedQuery(String text) async => [1, 0];

  @override
  Future<List<double>> embedItem(String text) async => [1, 0];
}

class _SpeechModelFake implements WhisperService {
  bool downloaded = false;
  final download = Completer<void>();
  ValueChanged<double>? onProgress;

  @override
  Future<bool> isModelDownloaded() async => downloaded;

  @override
  Future<void> downloadModel({required ValueChanged<double> onProgress}) {
    this.onProgress = onProgress;
    return download.future.then((_) => downloaded = true);
  }

  @override
  Future<bool> deleteDownloadedModel() async {
    downloaded = false;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'pt'});
    await UserStorage.initL10n();
  });

  testWidgets('settings are open rows with hairline dividers, no shadows',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pump();

    expect(find.text(UserStorage.l10n.languageSettings), findsOneWidget);
    expect(find.text(UserStorage.l10n.showInsightTextTitle), findsOneWidget);

    final decorations = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>();
    expect(decorations.where((d) => d.boxShadow?.isNotEmpty ?? false), isEmpty);
    expect(
      decorations.where((d) =>
          d.border is Border &&
          (d.border! as Border).bottom.color == AppColors.divider),
      isNotEmpty,
    );
  });

  testWidgets('settings show the content notice in pt and en', (tester) async {
    final notices = {
      'pt':
          'Este app é um diário pessoal. Não digite nem importe conteúdo sensível de trabalho ou do banco.',
      'en':
          'This app is a personal diary. Do not type or import sensitive work or bank content.',
    };
    for (final entry in notices.entries) {
      SharedPreferences.setMockInitialValues({'language': entry.key});
      await UserStorage.initL10n();
      await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
      await tester.pump();
      final row = find.byKey(const ValueKey('content-notice-settings'));
      expect(row, findsOneWidget, reason: entry.key);
      expect(
        find.descendant(of: row, matching: find.text(entry.value)),
        findsOneWidget,
        reason: entry.key,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('link previews start off and the switch is remembered',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pump();
    final tile = find.byKey(const ValueKey('link-preview-switch'));
    await tester.scrollUntilVisible(tile, 200);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(await UserStorage.isLinkPreviewEnabled(), isFalse);

    await tester.tap(tile);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(await UserStorage.isLinkPreviewEnabled(), isTrue);
    expect(find.text(UserStorage.l10n.linkPreviewDesc), findsOneWidget);
  });

  testWidgets('on-device transcription starts off and the switch is remembered',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pump();
    final tile = find.byKey(const ValueKey('local-speech-switch'));
    await tester.scrollUntilVisible(tile, 200);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(await UserStorage.getUseLocalSpeechToText(), isFalse);

    await tester.tap(tile);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(await UserStorage.getUseLocalSpeechToText(), isTrue);
    expect(
        find.text(UserStorage.l10n.useLocalSpeechToTextDesc), findsOneWidget);
  });

  testWidgets(
      'the local speech model is downloaded and deleted here, '
      'only when on-device transcription is on', (tester) async {
    final speech = _SpeechModelFake();
    await tester
        .pumpWidget(MaterialApp(home: SettingsPage(speechModel: speech)));
    await tester.pump();
    final l10n = UserStorage.l10n;
    final tile = find.byKey(const ValueKey('local-speech-switch'));
    await tester.scrollUntilVisible(tile, 200);
    // Off means ChatGPT/cloud: nothing to download.
    expect(find.byKey(const ValueKey('speech-model-download')), findsNothing);

    await tester.tap(tile);
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.speechModelMissing), findsOneWidget);
    final downloadButton = find.byKey(const ValueKey('speech-model-download'));
    expect(find.text(l10n.speechModelDownloadButton(470)), findsOneWidget);

    await tester.tap(downloadButton);
    await tester.pump();
    speech.onProgress!(0.45);
    await tester.pump();
    expect(find.text('${l10n.speechModelDownloading} 45%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    expect(downloadButton, findsNothing);

    speech.download.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.speechModelReady), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('speech-model-delete')));
    await tester.pump();
    await tester.pump();
    expect(speech.downloaded, isFalse);
    expect(find.text(l10n.speechModelMissing), findsOneWidget);
  });

  testWidgets('semantic search starts off and explains the local download',
      (tester) async {
    final semantic = _SemanticSearchManagerFake();
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(semanticSearchManager: semantic)),
    );
    await tester.pumpAndSettle();

    final tile = find.byKey(const ValueKey('semantic-search-switch'));
    await tester.scrollUntilVisible(tile, 250);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(await UserStorage.isSemanticSearchEnabled(), isFalse);
    expect(find.text(UserStorage.l10n.semanticSearchStatusOff), findsOneWidget);
    expect(
      find.text(UserStorage.l10n.semanticSearchDescription),
      findsOneWidget,
    );
  });

  testWidgets('semantic search shows download progress while enabling',
      (tester) async {
    final semantic = _SemanticSearchManagerFake(waitForCompletion: true);
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(semanticSearchManager: semantic)),
    );
    await tester.pumpAndSettle();

    final tile = find.byKey(const ValueKey('semantic-search-switch'));
    await tester.scrollUntilVisible(tile, 250);
    await tester.tap(tile);
    await tester.pump();

    expect(
      find.text(UserStorage.l10n.semanticSearchStatusDownloading(25)),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).onChanged, isNull);

    semantic.completion.complete(const Ok.v());
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(await UserStorage.isSemanticSearchEnabled(), isTrue);
  });

  testWidgets('semantic search shows ready state after a verified download',
      (tester) async {
    final semantic = _SemanticSearchManagerFake();
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(semanticSearchManager: semantic)),
    );
    await tester.pumpAndSettle();

    final tile = find.byKey(const ValueKey('semantic-search-switch'));
    await tester.scrollUntilVisible(tile, 250);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(
      find.text(UserStorage.l10n.semanticSearchStatusReady),
      findsOneWidget,
    );
    expect(
        find.text(UserStorage.l10n.semanticSearchDeleteModel), findsOneWidget);
    expect(await UserStorage.isSemanticSearchEnabled(), isTrue);
  });

  testWidgets('semantic search reports a download error and stays off',
      (tester) async {
    final semantic = _SemanticSearchManagerFake(fail: true);
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(semanticSearchManager: semantic)),
    );
    await tester.pumpAndSettle();

    final tile = find.byKey(const ValueKey('semantic-search-switch'));
    await tester.scrollUntilVisible(tile, 250);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(
      find.text(UserStorage.l10n.semanticSearchStatusError),
      findsOneWidget,
    );
    expect(await UserStorage.isSemanticSearchEnabled(), isFalse);
  });

  testWidgets('downloaded model can be deleted while semantic search is off',
      (tester) async {
    final semantic = _SemanticSearchManagerFake(hasDownloadedFiles: true);
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(semanticSearchManager: semantic)),
    );
    await tester.pumpAndSettle();

    final tile = find.byKey(const ValueKey('semantic-search-switch'));
    await tester.scrollUntilVisible(tile, 250);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    final delete = find.text(UserStorage.l10n.semanticSearchDeleteModel);
    await tester.scrollUntilVisible(delete, 250);
    expect(delete, findsOneWidget);

    await tester.tap(delete);
    await tester.pumpAndSettle();

    expect(semantic.hasDownloadedFiles, isFalse);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(await UserStorage.isSemanticSearchEnabled(), isFalse);
  });
}

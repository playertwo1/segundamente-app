import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/core/widgets/language_picker.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/ui/settings/widgets/backup_restore_page.dart';
import 'package:memex/ui/settings/widgets/chat_bubble_setting.dart';
import 'package:memex/ui/settings/widgets/data_import_page.dart';
import 'package:memex/ui/settings/widgets/data_storage_page.dart';
import 'package:memex/ui/settings/widgets/location_context_settings_page.dart';
import 'package:memex/ui/lumen/view_models/lumen_pairing_viewmodel.dart';
import 'package:memex/ui/lumen/widgets/lumen_pairing_page.dart';
import 'package:memex/ui/esp32/view_models/esp32_board_viewmodel.dart';
import 'package:memex/ui/esp32/widgets/esp32_board_page.dart';
import 'package:memex/ui/todo/view_models/todo_shortcut_settings_viewmodel.dart';
import 'package:memex/ui/todo/widgets/active_assistant_settings_page.dart';
import 'package:memex/ui/todo/widgets/todo_shortcut_settings_page.dart';
import 'package:memex/ui/settings/widgets/early_update_settings_card.dart';
import 'package:memex/ui/settings/view_models/data_import_viewmodel.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/semantic_search_model_service.dart';
import 'package:memex/data/services/whisper_service.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/data/services/comment_settings_service.dart'
    show CommentSettings;
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/main.dart' show rootShellKey;
import 'package:memex/utils/result.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.semanticSearchManager, this.speechModel});

  final SemanticSearchModelManager? semanticSearchManager;
  final WhisperService? speechModel;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _currentLocaleTag = 'en';
  CommentSettings _commentSettings = const CommentSettings();
  bool _linkPreview = false;
  bool _useLocalSpeechToText = false;
  late final SemanticSearchModelManager _semanticSearch;
  bool _semanticSearchEnabled = false;
  bool _semanticSearchBusy = false;
  late final WhisperService _speechModel;
  bool _speechModelReady = false;
  double? _speechModelProgress; // non-null while downloading

  @override
  void initState() {
    super.initState();
    _semanticSearch =
        widget.semanticSearchManager ?? SemanticSearchModelService.instance;
    _semanticSearch.addListener(_onSemanticSearchChanged);
    _speechModel = widget.speechModel ?? WhisperService.instance;
    _loadSettings();
  }

  @override
  void dispose() {
    _semanticSearch.removeListener(_onSemanticSearchChanged);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final locale = await UserStorage.getLocale();
    final commentSettings = await MemexRouter().getCommentSettings();
    final linkPreview = await UserStorage.isLinkPreviewEnabled();
    final useLocalSpeechToText = await UserStorage.getUseLocalSpeechToText();
    final semanticSearch = await UserStorage.isSemanticSearchEnabled();
    await _semanticSearch.refreshModelAvailability();
    if (semanticSearch) {
      await _semanticSearch.ensureReady(allowDownload: false);
    }
    if (mounted) {
      setState(() {
        _linkPreview = linkPreview;
        _useLocalSpeechToText = useLocalSpeechToText;
        _semanticSearchEnabled = semanticSearch;
        _currentLocaleTag = UserStorage.localeTag(
          UserStorage.resolveToSupportedLocale(locale),
        );
        _commentSettings = commentSettings;
      });
    }
    await _refreshSpeechModel();
  }

  Future<void> _changeLanguage(String localeTag) async {
    if (_currentLocaleTag == localeTag) return;
    final locale = UserStorage.localeFromTag(localeTag);
    await UserStorage.setLocale(locale);
    if (mounted) {
      setState(() {
        _currentLocaleTag = UserStorage.localeTag(
          UserStorage.resolveToSupportedLocale(locale),
        );
      });
    }
  }

  Future<void> _showLanguagePicker() async {
    final localeTag = await showLanguagePickerSheet(
      context: context,
      selectedLocaleTag: _currentLocaleTag,
      title: UserStorage.l10n.chooseLanguage,
    );
    if (localeTag != null) {
      await _changeLanguage(localeTag);
    }
  }

  Future<void> _updateLinkPreview(bool value) async {
    await UserStorage.setLinkPreviewEnabled(value);
    if (mounted) setState(() => _linkPreview = value);
  }

  Future<void> _updateUseLocalSpeechToText(bool value) async {
    await UserStorage.setUseLocalSpeechToText(value);
    if (mounted) setState(() => _useLocalSpeechToText = value);
    await _refreshSpeechModel();
  }

  Future<void> _refreshSpeechModel() async {
    bool ready;
    try {
      ready = await _speechModel.isModelDownloaded();
    } catch (_) {
      ready = false; // no file access (tests); shows the download button
    }
    if (mounted) setState(() => _speechModelReady = ready);
  }

  /// The only place the local speech model is downloaded (the chat
  /// microphone just dictates and points here when it is missing).
  Future<void> _downloadSpeechModel() async {
    if (_speechModelProgress != null) return;
    setState(() => _speechModelProgress = 0);
    try {
      await _speechModel.downloadModel(
        onProgress: (p) {
          if (mounted) setState(() => _speechModelProgress = p);
        },
      );
    } catch (e) {
      if (mounted) {
        ToastHelper.showError(
            context, UserStorage.l10n.speechModelDownloadFailed('$e'));
      }
    }
    if (mounted) setState(() => _speechModelProgress = null);
    await _refreshSpeechModel();
  }

  Future<void> _deleteSpeechModel() async {
    try {
      await _speechModel.deleteDownloadedModel();
      if (mounted) {
        ToastHelper.showSuccess(
            context, UserStorage.l10n.speechModelDeletedSuccess);
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.showError(
            context, UserStorage.l10n.speechModelDeleteFailed('$e'));
      }
    }
    await _refreshSpeechModel();
  }

  void _onSemanticSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _updateSemanticSearch(bool value) async {
    if (_semanticSearchBusy) return;
    setState(() => _semanticSearchBusy = true);
    if (value) {
      final result = await _semanticSearch.ensureReady(allowDownload: true);
      final enabled = result.isOk;
      await UserStorage.setSemanticSearchEnabled(enabled);
      if (mounted) {
        setState(() {
          _semanticSearchEnabled = enabled;
          _semanticSearchBusy = false;
        });
      }
      return;
    }

    await UserStorage.setSemanticSearchEnabled(false);
    await _semanticSearch.disable();
    if (mounted) {
      setState(() {
        _semanticSearchEnabled = false;
        _semanticSearchBusy = false;
      });
    }
  }

  Future<void> _deleteSemanticModel() async {
    if (_semanticSearchBusy) return;
    setState(() => _semanticSearchBusy = true);
    await UserStorage.setSemanticSearchEnabled(false);
    await _semanticSearch.deleteModel();
    if (mounted) {
      setState(() {
        _semanticSearchEnabled = false;
        _semanticSearchBusy = false;
      });
    }
  }

  Future<void> _updateShowInsightText(bool value) async {
    final updated = _commentSettings.copyWith(showInsightText: value);
    await MemexRouter().saveCommentSettings(updated);
    if (mounted) {
      setState(() => _commentSettings = updated);
    }
  }

  Future<void> _updateEnableCharacterComment(bool value) async {
    final updated = _commentSettings.copyWith(enableCharacterComment: value);
    await MemexRouter().saveCommentSettings(updated);
    if (mounted) {
      setState(() => _commentSettings = updated);
    }
  }

  Future<void> _updateMaxCommentCharacters(int value) async {
    final updated = _commentSettings.copyWith(maxCommentCharacters: value);
    await MemexRouter().saveCommentSettings(updated);
    if (mounted) {
      setState(() => _commentSettings = updated);
    }
  }

  Widget _buildSpeechModelStatus() {
    final l10n = UserStorage.l10n;
    final progress = _speechModelProgress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          progress != null
              ? '${l10n.speechModelDownloading} ${(progress * 100).toInt()}%'
              : _speechModelReady
                  ? l10n.speechModelReady
                  : l10n.speechModelMissing,
          key: const ValueKey('speech-model-status'),
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        if (progress != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child:
                LinearProgressIndicator(value: progress > 0 ? progress : null),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: _speechModelReady
                ? TextButton.icon(
                    key: const ValueKey('speech-model-delete'),
                    onPressed: _deleteSpeechModel,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.deleteSpeechModel),
                  )
                : TextButton.icon(
                    key: const ValueKey('speech-model-download'),
                    onPressed: _downloadSpeechModel,
                    icon: const Icon(Icons.download_outlined),
                    label: Text(l10n.speechModelDownloadButton(
                        WhisperService.modelSizeMB.toInt())),
                  ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(UserStorage.l10n.settings),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ChatBubbleSetting(),
          // Language
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.language,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UserStorage.l10n.languageSettings,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            UserStorage.l10n.languageSettingsDesc,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildLanguageValueRow(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            key: const ValueKey('content-notice-settings'),
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    color: AppColors.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        UserStorage.l10n.contentNoticeCaption,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        UserStorage.l10n.contentNoticeSettingsDesc,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (Platform.isAndroid && !AppFlavor.isDev) ...[
            EarlyUpdateSettingsCard(),
            const SizedBox(height: 16),
          ],
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('todo-shortcut-settings'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TodoShortcutSettingsPage(
                    viewModel: TodoShortcutSettingsViewModel(
                      router: MemexRouter(),
                    ),
                  ),
                ),
              ),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.event_note_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UserStorage.l10n.todoShortcutsTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            UserStorage.l10n.todoShortcutsDescription,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.divider),
                  ],
                ),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('active-assistant-settings'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ActiveAssistantSettingsPage(),
                ),
              ),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.assistant_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UserStorage.l10n.activeAssistantSettingsTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            UserStorage.l10n.activeAssistantSettingsDescription,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.divider),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Show Insight Text toggle
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(
                Icons.lightbulb_outline,
                color: AppColors.primary,
                size: 22,
              ),
              title: Text(
                UserStorage.l10n.showInsightTextTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  UserStorage.l10n.showInsightTextDesc,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
              value: _commentSettings.showInsightText,
              onChanged: _updateShowInsightText,
            ),
          ),
          const SizedBox(height: 16),
          // Link previews contact the linked site, so they start off.
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: SwitchListTile(
              key: const ValueKey('link-preview-switch'),
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(
                Icons.link,
                color: AppColors.primary,
                size: 22,
              ),
              title: Text(
                UserStorage.l10n.linkPreviewTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  UserStorage.l10n.linkPreviewDesc,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
              value: _linkPreview,
              onChanged: _updateLinkPreview,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  key: const ValueKey('semantic-search-switch'),
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(
                    Icons.manage_search,
                    color: AppColors.primary,
                    size: 22,
                  ),
                  title: Text(
                    UserStorage.l10n.semanticSearchTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      UserStorage.l10n.semanticSearchDescription,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                  value: _semanticSearchEnabled,
                  onChanged: _semanticSearchBusy ? null : _updateSemanticSearch,
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 56, top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        switch (_semanticSearch.state) {
                          SemanticSearchModelState.off =>
                            UserStorage.l10n.semanticSearchStatusOff,
                          SemanticSearchModelState.downloading =>
                            UserStorage.l10n.semanticSearchStatusDownloading(
                              (_semanticSearch.progress * 100).round(),
                            ),
                          SemanticSearchModelState.ready =>
                            UserStorage.l10n.semanticSearchStatusReady,
                          SemanticSearchModelState.error =>
                            UserStorage.l10n.semanticSearchStatusError,
                        },
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (_semanticSearch.state ==
                          SemanticSearchModelState.downloading)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(
                            value: _semanticSearch.progress == 0
                                ? null
                                : _semanticSearch.progress,
                          ),
                        ),
                      if (_semanticSearch.hasDownloadedFiles)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _semanticSearchBusy
                                ? null
                                : _deleteSemanticModel,
                            icon: const Icon(Icons.delete_outline),
                            label: Text(
                              UserStorage.l10n.semanticSearchDeleteModel,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Local Whisper or cloud transcription; the local model downloads here.
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  key: const ValueKey('local-speech-switch'),
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(
                    Icons.mic_none,
                    color: AppColors.primary,
                    size: 22,
                  ),
                  title: Text(
                    UserStorage.l10n.useLocalSpeechToTextTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      UserStorage.l10n.useLocalSpeechToTextDesc,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                  value: _useLocalSpeechToText,
                  onChanged: _updateUseLocalSpeechToText,
                ),
                if (_useLocalSpeechToText)
                  Padding(
                    padding: const EdgeInsets.only(left: 56, top: 4),
                    child: _buildSpeechModelStatus(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Enable Character Comment toggle
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(
                Icons.chat_bubble_outline,
                color: AppColors.primary,
                size: 22,
              ),
              title: Text(
                UserStorage.l10n.enableCharacterCommentTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  UserStorage.l10n.enableCharacterCommentDesc,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
              value: _commentSettings.enableCharacterComment,
              onChanged: _updateEnableCharacterComment,
            ),
          ),
          // Max comment characters slider (only visible when comments are enabled)
          if (_commentSettings.enableCharacterComment) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.divider)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.groups_outlined,
                        color: AppColors.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              UserStorage.l10n.maxCommentCharactersTitle,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              UserStorage.l10n.maxCommentCharactersDesc,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_commentSettings.maxCommentCharacters}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    value: _commentSettings.maxCommentCharacters
                        .clamp(1, CommentSettings.maxCommentCharactersLimit)
                        .toDouble(),
                    min: 1,
                    max: CommentSettings.maxCommentCharactersLimit.toDouble(),
                    divisions: CommentSettings.maxCommentCharactersLimit - 1,
                    activeColor: AppColors.primary,
                    onChanged: (v) => _updateMaxCommentCharacters(v.round()),
                  ),
                ],
              ),
            ),
          ],
          // Data Storage (iOS only — Android has no storage options to choose)
          if (Platform.isIOS) ...[
            const SizedBox(height: 16),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DataStoragePage(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    border:
                        Border(bottom: BorderSide(color: AppColors.divider)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.folder_outlined,
                        color: AppColors.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              UserStorage.l10n.dataStorage,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              UserStorage.l10n.dataStorageDescriptionIOS,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textTertiary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.divider),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LocationContextSettingsPage(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.my_location_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UserStorage.l10n.location,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            UserStorage.l10n.locationContextDescription,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.divider),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                final viewModel = DataImportViewModel(router: MemexRouter());
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DataImportPage(viewModel: viewModel),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.upload_file_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UserStorage.l10n.dataImportTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            UserStorage.l10n.dataImportSettingsDescription,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.divider),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('lumen-pairing-settings'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LumenPairingPage(
                    viewModel: LumenPairingViewModel(
                      router: MemexRouter(),
                    ),
                  ),
                ),
              ),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.devices_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UserStorage.l10n.lumenPairingTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            UserStorage.l10n.lumenPairingSubtitle,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.divider),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('esp32-board-settings'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Esp32BoardPage(
                    viewModel: Esp32BoardViewModel(),
                  ),
                ),
              ),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.watch_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentLocaleTag.startsWith('pt')
                                ? 'Placa ESP32-S3 (BLE)'
                                : 'ESP32-S3 Board (BLE)',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _currentLocaleTag.startsWith('pt')
                                ? 'Pareamento Bluetooth, tarefas e notificações'
                                : 'Bluetooth pairing, tasks & notifications',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.divider),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Backup & Restore
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BackupRestorePage(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.backup_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UserStorage.l10n.backupAndRestore,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            UserStorage.l10n.backupDescription,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.divider),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Privacy Policy
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                launchUrl(
                  Uri.parse(
                    'https://github.com/memex-lab/memex/blob/main/PRIVACY_POLICY.md',
                  ),
                  mode: LaunchMode.externalApplication,
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.privacy_tip_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UserStorage.l10n.privacyPolicy,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            UserStorage.l10n.privacyPolicyDesc,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.open_in_new,
                      color: AppColors.divider,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          // Delete Account
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showDeleteAccountDialog,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.delete_forever_outlined,
                      color: Colors.red,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UserStorage.l10n.deleteAccount,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            UserStorage.l10n.deleteAccountDesc,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.divider),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    final l10n = UserStorage.l10n;
    final userId = await UserStorage.getUserId() ?? '';
    if (!mounted) return;
    final controller = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isMatch = controller.text == userId;
            final showError = controller.text.isNotEmpty && !isMatch;
            return AlertDialog(
              backgroundColor: AppColors.cardBackground,
              title: Text(l10n.deleteAccountConfirmTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.deleteAccountConfirmMessage),
                  const SizedBox(height: 16),
                  Text(
                    l10n.deleteAccountTypeName(userId),
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: l10n.deleteAccountTypeHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText:
                          showError ? l10n.deleteAccountTypeName(userId) : null,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(UserStorage.l10n.cancel),
                ),
                TextButton(
                  onPressed:
                      isMatch ? () => Navigator.pop(context, true) : null,
                  child: Text(
                    l10n.deleteAccount,
                    style: TextStyle(color: isMatch ? Colors.red : Colors.grey),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;

    // Perform deletion
    try {
      // 1. Stop background services that use the database
      await LocalTaskExecutor.instance.stop();
      await EventBusService.instance.disconnect();

      // 2. Close and delete database
      if (AppDatabase.isInitialized) {
        await AppDatabase.instance.close();
      }

      // 3. Delete workspace files
      try {
        final dataRoot = FileSystemService.instance.dataRoot;
        final dir = Directory(dataRoot);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {
        // workspace may not exist
      }

      // 4. Clear all SharedPreferences
      await UserStorage.clearAllData();

      // 5. Navigate back to home and let RootShell re-check user state
      if (mounted) {
        // Pop settings page first so we're back at the main screen
        Navigator.of(context).popUntil((route) => route.isFirst);
        // Then tell RootShell to re-check — it will find no user and show setup
        rootShellKey.currentState?.resetAndRecheck();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserStorage.l10n.operationFailed('$e'))),
        );
      }
    }
  }

  Widget _buildLanguageValueRow() {
    return LanguageValueButton(
      localeTag: _currentLocaleTag,
      onTap: _showLanguagePicker,
      trailingIcon: Icons.chevron_right,
    );
  }
}

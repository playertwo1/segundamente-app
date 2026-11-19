import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:memex/data/services/floating_chat_service.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:permission_handler/permission_handler.dart';

class ChatBubbleSetting extends StatefulWidget {
  const ChatBubbleSetting({super.key});

  @override
  State<ChatBubbleSetting> createState() => _ChatBubbleSettingState();
}

class _ChatBubbleSettingState extends State<ChatBubbleSetting> {
  final _service = FloatingChatService.instance;
  late final AppLifecycleListener _lifecycle;
  ChatBubbleStatus _status = ChatBubbleStatus.unsupported;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    try {
      final status = await _service.bubbleStatus();
      if (mounted && !_busy) setState(() => _status = status);
    } on PlatformException {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _setVisible(bool visible) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (visible && _status == ChatBubbleStatus.notifications) {
        await Permission.notification.request();
        if (!mounted) return;
      }
      final status = await _service.setBubbleVisible(visible);
      if (mounted) setState(() => _status = status);
    } on PlatformException {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSettings() async {
    try {
      await _service.openBubbleSettings(
        notifications: _status == ChatBubbleStatus.notifications,
      );
    } on PlatformException {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_status == ChatBubbleStatus.unsupported) return const SizedBox.shrink();
    final l10n = UserStorage.l10n;
    final theme = Theme.of(context);
    final needsSettings = _status == ChatBubbleStatus.notifications ||
        _status == ChatBubbleStatus.posted;
    final description = _failed
        ? l10n.chatBubbleError
        : switch (_status) {
            ChatBubbleStatus.notifications => l10n.chatBubbleNotifications,
            ChatBubbleStatus.posted => l10n.chatBubblePosted,
            _ => l10n.chatBubbleDescription,
          };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const ValueKey('chat-bubble-switch'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          secondary: Icon(
            Icons.chat_bubble_outline,
            color: theme.colorScheme.primary,
          ),
          title: Text(l10n.chatBubbleTitle, style: theme.textTheme.titleMedium),
          subtitle: Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          value: _status == ChatBubbleStatus.active ||
              _status == ChatBubbleStatus.posted,
          onChanged: _busy ? null : _setVisible,
        ),
        if (needsSettings)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 64),
            child: TextButton(
              onPressed: _busy ? null : _openSettings,
              child: Text(l10n.chatBubbleOpenSettings),
            ),
          ),
        const Divider(),
      ],
    );
  }
}

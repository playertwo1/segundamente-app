import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/data_route.dart';
import 'package:memex/ui/chat/view_models/duplex_voice_viewmodel.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/core/widgets/back_button.dart';
import 'package:memex/utils/user_storage.dart';

/// Hands-free voice conversation (F7-03). Shows where audio and text go before
/// anything starts, the microphone state at all times, and one-tap interrupt,
/// pause and end. Leaving the screen or the app ends the conversation.
class DuplexVoiceScreen extends StatefulWidget {
  const DuplexVoiceScreen({super.key, required this.viewModel});

  final DuplexVoiceViewModel viewModel;

  /// The ViewModel is created once, outside the builder: GoRouter rebuilds
  /// routes on system back, and a ViewModel made in the builder would leave
  /// the previous one holding the microphone.
  static Route<void> route({required MemexRouter router}) {
    final viewModel = DuplexVoiceViewModel(router: router);
    return MaterialPageRoute<void>(
      builder: (_) => DuplexVoiceScreen(viewModel: viewModel),
    );
  }

  @override
  State<DuplexVoiceScreen> createState() => _DuplexVoiceScreenState();
}

class _DuplexVoiceScreenState extends State<DuplexVoiceScreen>
    with WidgetsBindingObserver {
  DuplexVoiceViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_vm.loadRoutes());
  }

  /// No listening in the background: leaving the app ends the conversation.
  /// `inactive` is left out because the permission dialog causes it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_vm.cancel());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vm.dispose(); // releases the microphone and the speech engine
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: const AppBackButton(),
        title: Text(
          l10n.duplexTitle,
          style: const TextStyle(fontSize: 18, color: AppColors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _micIndicator(),
                    const SizedBox(height: 16),
                    if (_vm.problem != null) _problem(),
                    if (_vm.heard.isNotEmpty)
                      _spoken(l10n.duplexHeard, _vm.heard),
                    if (_vm.reply.isNotEmpty)
                      _spoken(l10n.duplexReply, _vm.reply),
                    _note(l10n.duplexIntro),
                    const SizedBox(height: 16),
                    _routes(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: _controls(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _micIndicator() {
    final l10n = UserStorage.l10n;
    final label = switch (_vm.state) {
      DuplexVoiceState.idle => l10n.duplexStateIdle,
      DuplexVoiceState.starting => l10n.duplexStateStarting,
      DuplexVoiceState.listening => l10n.duplexStateListening,
      DuplexVoiceState.thinking => l10n.duplexStateThinking,
      DuplexVoiceState.speaking => l10n.duplexStateSpeaking,
      DuplexVoiceState.paused => l10n.duplexStatePaused,
    };
    final on = _vm.micActive;
    return Semantics(
      key: const ValueKey('duplex-mic-indicator'),
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: on ? AppColors.primary : AppColors.divider,
            width: on ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              on ? Icons.mic : Icons.mic_off,
              key: ValueKey(on ? 'duplex-mic-on' : 'duplex-mic-off'),
              size: 32,
              color: on ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _problem() {
    final l10n = UserStorage.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        liveRegion: true,
        child: Text(
          switch (_vm.problem!) {
            DuplexVoiceProblem.permissionDenied => l10n.voiceMicDenied,
            DuplexVoiceProblem.speechModelMissing =>
              l10n.speechModelMissingHint,
            DuplexVoiceProblem.failed => l10n.duplexErrorFailed,
          },
          key: const ValueKey('duplex-problem'),
          style: const TextStyle(fontSize: 14, color: AppColors.danger),
        ),
      ),
    );
  }

  Widget _spoken(String label, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style:
                const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              height: 1.4,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          height: 1.45,
          color: AppColors.textSecondary,
        ),
      );

  /// Provider and destination of the audio, of the text and of the speech,
  /// visible before the start button can be used.
  Widget _routes() {
    final l10n = UserStorage.l10n;
    if (!_vm.routesLoaded) return const SizedBox.shrink();
    final routes = _vm.routes;
    return Column(
      key: const ValueKey('duplex-data-route'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.dataRouteTitle,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        if (routes == null)
          _note(l10n.dataRouteNone)
        else ...[
          if (_vm.localTranscription)
            _routeRow(
              l10n.dataRouteTranscription,
              l10n.duplexRouteTranscriptionLocal,
              l10n.duplexRouteTranscriptionLocalDetail,
            )
          else
            _routeRow(
              l10n.dataRouteTranscription,
              _routeName(routes.transcription),
              l10n.dataRouteAudioSentTo(routes.transcription.host),
            ),
          _routeRow(
            l10n.dataRouteChat,
            _routeName(routes.chat),
            l10n.dataRouteTextSentTo(routes.chat.host),
          ),
          _routeRow(
            l10n.duplexRouteSpeech,
            l10n.duplexRouteSpeechValue,
            l10n.duplexRouteSpeechDetail,
          ),
        ],
      ],
    );
  }

  String _routeName(DataRoute route) => route.model.isEmpty
      ? route.provider
      : UserStorage.l10n.dataRouteModel(route.provider, route.model);

  Widget _routeRow(String label, String value, String detail) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style:
                const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
          ),
          Text(
            detail,
            style:
                const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    final l10n = UserStorage.l10n;
    switch (_vm.state) {
      case DuplexVoiceState.idle:
        return _button(
          key: 'duplex-start',
          icon: Icons.mic,
          label: l10n.duplexStart,
          onTap: _vm.canStart ? _vm.start : null,
          primary: true,
        );
      case DuplexVoiceState.starting:
        return _button(
          key: 'duplex-cancel',
          icon: Icons.close,
          label: l10n.duplexCancel,
          onTap: _vm.cancel,
        );
      case DuplexVoiceState.paused:
      case DuplexVoiceState.listening:
      case DuplexVoiceState.thinking:
      case DuplexVoiceState.speaking:
        final paused = _vm.state == DuplexVoiceState.paused;
        final row = Row(
          children: [
            Expanded(
              child: paused
                  ? _button(
                      key: 'duplex-resume',
                      icon: Icons.mic,
                      label: l10n.duplexResume,
                      onTap: _vm.resume,
                      primary: true,
                    )
                  : _button(
                      key: 'duplex-pause',
                      icon: Icons.pause,
                      label: l10n.duplexPause,
                      onTap: _vm.pause,
                      primary: true,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _button(
                key: 'duplex-cancel',
                icon: Icons.close,
                label: l10n.duplexCancel,
                onTap: _vm.cancel,
              ),
            ),
          ],
        );
        if (_vm.state != DuplexVoiceState.speaking) return row;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _button(
              key: 'duplex-interrupt',
              icon: Icons.front_hand_outlined,
              label: l10n.duplexInterrupt,
              onTap: _vm.interrupt,
            ),
            const SizedBox(height: 12),
            row,
          ],
        );
    }
  }

  Widget _button({
    required String key,
    required IconData icon,
    required String label,
    required Future<void> Function()? onTap,
    bool primary = false,
  }) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: ElevatedButton.icon(
        key: ValueKey(key),
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: primary ? AppColors.primary : AppColors.surface,
          foregroundColor:
              primary ? AppColors.onPrimary : AppColors.textPrimary,
        ),
      ),
    );
  }
}

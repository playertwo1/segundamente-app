import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:memex/agent/run_mode/agent_run_mode.dart';
import 'package:memex/data/model/chat_events.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/duplex_voice_service.dart';
import 'package:memex/data/services/speech_transcription_service.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/data_route.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

enum DuplexVoiceState {
  /// Microphone closed; nothing runs.
  idle,
  starting,

  /// Microphone open, waiting for or hearing the user.
  listening,

  /// Transcribing and waiting for the reply; microphone audio is dropped.
  thinking,

  /// Reading the reply aloud with the microphone closed, so the app cannot
  /// hear itself; [DuplexVoiceViewModel.interrupt] cuts it short.
  speaking,

  /// Microphone closed by the user; [DuplexVoiceViewModel.resume] reopens it.
  paused,
}

/// Why the conversation could not start or stopped.
enum DuplexVoiceProblem { permissionDenied, speechModelMissing, failed }

/// Hands-free voice conversation (F7-03): listen → transcribe → model reply →
/// speak. The reply is cut short by a tap ([interrupt]), not by talking over
/// it: on the S25 loudspeaker the echo canceller does not keep the app from
/// hearing its own voice (D-049, docs/F7-03-voz-duplex.md).
///
/// The microphone opens only from [start] or [resume], both user actions, and
/// every exit path (pause, cancel, error, dispose) closes it.
class DuplexVoiceViewModel extends ChangeNotifier {
  DuplexVoiceViewModel({
    required MemexRouter router,
    DuplexVoiceService? service,
    Future<String?> Function(Float32List samples)? transcribe,
    Future<bool> Function()? usesLocalSpeechModel,
    Future<bool> Function()? speechModelMissing,
    Future<LLMConfig?> Function()? loadChatConfig,
    String Function()? locale,
  })  : _router = router,
        _service = service ?? DuplexVoiceService(),
        _transcribe =
            transcribe ?? SpeechTranscriptionService.instance.transcribeSamples,
        _usesLocalSpeechModel = usesLocalSpeechModel ??
            SpeechTranscriptionService.instance.isUsingLocalModel,
        _speechModelMissing = speechModelMissing ??
            SpeechTranscriptionService.instance.requiresLocalModelDownload,
        _loadChatConfig = loadChatConfig ?? _defaultChatConfig,
        _locale = locale ?? _defaultLocale;

  static final _logger = getLogger('DuplexVoice');

  // The same configuration the chat and the cloud transcription use.
  static Future<LLMConfig?> _defaultChatConfig() =>
      UserStorage.getAgentLLMConfig(
        AgentDefinitions.chatAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );

  static String _defaultLocale() =>
      UserStorage.l10n.localeName == 'pt' ? 'pt-BR' : 'en-US';

  final MemexRouter _router;
  final DuplexVoiceService _service;
  final Future<String?> Function(Float32List samples) _transcribe;
  final Future<bool> Function() _usesLocalSpeechModel;
  final Future<bool> Function() _speechModelMissing;
  final Future<LLMConfig?> Function() _loadChatConfig;
  final String Function() _locale;

  // Bumped by every pause, cancel and failure, so that work already in flight
  // (transcription, reply, speech) is dropped when it comes back.
  int _epoch = 0;
  bool _disposed = false;
  String? _sessionId;
  StreamSubscription<ChatEvent>? _replySub;
  Completer<String>? _reply;

  DuplexVoiceState state = DuplexVoiceState.idle;
  DuplexVoiceProblem? problem;
  Object? error;

  /// Last thing the user said and last reply, shown on screen.
  String heard = '';
  String reply = '';

  /// Where audio and text go; loaded by [loadRoutes] for the screen to show
  /// before the user starts. [routes] is null when no valid model is set.
  bool routesLoaded = false;
  bool localTranscription = false;
  DataRoutes? routes;

  /// True while the microphone stream is open.
  bool get micActive => _service.micOpen;

  bool get canStart =>
      state == DuplexVoiceState.idle && routesLoaded && routes != null;

  Future<void> loadRoutes() async {
    try {
      localTranscription = await _usesLocalSpeechModel();
      routes = describeDataRoutes(await _loadChatConfig());
    } catch (e, stack) {
      _logger.warning('Could not read the model configuration', e, stack);
      routes = null;
    }
    routesLoaded = true;
    _notify();
  }

  /// Asks for the microphone (first time) and starts listening. Only called
  /// from the start button.
  Future<void> start() async {
    if (!canStart) return;
    final epoch = ++_epoch;
    problem = null;
    error = null;
    heard = '';
    reply = '';
    state = DuplexVoiceState.starting;
    _notify();
    try {
      final missing = localTranscription && await _speechModelMissing();
      if (epoch != _epoch) return;
      if (missing) {
        await _stop(epoch, DuplexVoiceProblem.speechModelMissing);
        return;
      }
      final granted = await _service.requestPermission();
      if (epoch != _epoch) return;
      if (!granted) {
        await _stop(epoch, DuplexVoiceProblem.permissionDenied);
        return;
      }
      await _openMic(epoch);
    } catch (e, stack) {
      _logger.severe('Could not start the voice conversation', e, stack);
      await _fail(e, epoch);
    }
  }

  Future<void> _openMic(int epoch) async {
    await _service.openMic(
      onSpeechStart: () {},
      onUtterance: _onUtterance,
      onError: (e) => unawaited(_fail(e, _epoch)),
    );
    // Cancelled or paused while the microphone was opening: close it again.
    if (epoch != _epoch) return _service.closeMic();
    _service.discardInput = false;
    state = DuplexVoiceState.listening;
    _notify();
  }

  /// Silences the reply being read and goes back to listening.
  Future<void> interrupt() async {
    if (state != DuplexVoiceState.speaking) return;
    final epoch = _epoch;
    try {
      // Ends the speak() awaited in [_turn], which reopens the microphone.
      await _service.stopSpeaking();
    } catch (e, stack) {
      _logger.severe('Could not interrupt the reply', e, stack);
      await _fail(e, epoch);
    }
  }

  void _onUtterance(Float32List samples) {
    if (state != DuplexVoiceState.listening) return;
    unawaited(_turn(samples));
  }

  Future<void> _turn(Float32List samples) async {
    final epoch = _epoch;
    state = DuplexVoiceState.thinking;
    _service.discardInput = true;
    _notify();
    try {
      final text = (await _transcribe(samples))?.trim() ?? '';
      if (epoch != _epoch) return;
      if (text.isEmpty) return _listenAgain();
      heard = text;
      reply = '';
      _notify();

      final answer = await _askModel(text);
      if (epoch != _epoch) return;
      reply = answer;
      if (answer.isEmpty) return _listenAgain();

      // Microphone closed while the app talks: it would hear its own voice.
      await _service.closeMic();
      if (epoch != _epoch) return;
      state = DuplexVoiceState.speaking;
      _notify();
      // Returns when the reply ends or [interrupt] stops it.
      await _service.speak(_speakable(answer), _locale());
      if (epoch != _epoch) return; // paused or cancelled meanwhile
      await _openMic(epoch);
    } catch (e, stack) {
      _logger.severe('Voice turn failed', e, stack);
      await _fail(e, epoch);
    }
  }

  void _listenAgain() {
    _service.discardInput = false;
    state = DuplexVoiceState.listening;
    _notify();
  }

  /// Sends the transcript through the normal chat path, read-only: what was
  /// heard may be wrong, so a spoken turn never changes the user's records.
  Future<String> _askModel(String text) {
    final done = Completer<String>();
    final buffer = StringBuffer();
    void failWith(Object e) {
      if (!done.isCompleted) done.completeError(e);
    }

    _reply = done;
    _replySub = _router
        .sendMessage(
          text,
          sessionId: _sessionId,
          agentName: 'memex_agent',
          scene: 'super_agent_home',
          isQuickQuery: true,
          runMode: AgentRunMode.readOnly.wireName,
        )
        .listen(
          (event) {
            if (event is ChatSessionCreatedEvent) {
              _sessionId = event.sessionId;
            } else if (event is ChatResponseChunkEvent) {
              buffer.write(event.text);
            } else if (event is ChatErrorEvent) {
              failWith(StateError(event.error));
            }
          },
          onError: failWith,
          onDone: () {
            if (!done.isCompleted) done.complete(buffer.toString().trim());
          },
        );
    return done.future;
  }

  // Markdown marks would be read aloud as symbols.
  static String _speakable(String text) =>
      text.replaceAll(RegExp(r'[*_#`>|]'), '');

  /// Stops waiting for a reply. The text already sent cannot be recalled; the
  /// reply is still saved in the chat history, just not spoken.
  void _dropReply() {
    unawaited(_replySub?.cancel());
    _replySub = null;
    final pending = _reply;
    _reply = null;
    if (pending != null && !pending.isCompleted) pending.complete('');
  }

  /// Closes the microphone and silences the reply; [resume] continues.
  Future<void> pause() async {
    if (state != DuplexVoiceState.listening &&
        state != DuplexVoiceState.thinking &&
        state != DuplexVoiceState.speaking) {
      return;
    }
    final epoch = ++_epoch;
    _dropReply();
    state = DuplexVoiceState.paused;
    _notify();
    try {
      await _service.closeMic();
      await _service.stopSpeaking();
    } catch (e, stack) {
      _logger.severe('Could not pause the voice conversation', e, stack);
      await _fail(e, epoch);
    }
  }

  Future<void> resume() async {
    if (state != DuplexVoiceState.paused) return;
    final epoch = ++_epoch;
    state = DuplexVoiceState.starting;
    _notify();
    try {
      await _openMic(epoch);
    } catch (e, stack) {
      _logger.severe('Could not resume the voice conversation', e, stack);
      await _fail(e, epoch);
    }
  }

  /// Ends the conversation and releases the microphone and the speech engine.
  Future<void> cancel() async {
    if (state == DuplexVoiceState.idle) return;
    await _stop(++_epoch, null);
  }

  Future<void> _fail(Object e, int epoch) async {
    if (epoch != _epoch) return;
    error = e;
    await _stop(++_epoch, DuplexVoiceProblem.failed);
  }

  Future<void> _stop(int epoch, DuplexVoiceProblem? why) async {
    _dropReply();
    problem = why;
    state = DuplexVoiceState.idle;
    _notify();
    try {
      await _service.release();
    } catch (e, stack) {
      _logger.severe('Could not release the audio resources', e, stack);
      if (epoch == _epoch) {
        error ??= e;
        problem = DuplexVoiceProblem.failed;
      }
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _dropReply();
    state = DuplexVoiceState.idle;
    unawaited(_service.release().catchError((Object e, StackTrace stack) {
      _logger.severe('Could not release the audio resources', e, stack);
    }));
    super.dispose();
  }
}

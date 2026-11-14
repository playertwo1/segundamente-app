import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:memex/data/services/duplex_voice_service.dart';
import 'package:memex/data/services/speech_transcription_service.dart';
import 'package:memex/utils/logger.dart';

enum ListenOnceState {
  /// Nothing open; [ListenOnceViewModel.start] can be called.
  idle,

  /// Microphone open, waiting for the first utterance.
  listening,

  /// The utterance is being transcribed; the microphone is closed.
  transcribing,

  permissionDenied,

  /// The on-device speech model is not downloaded.
  modelMissing,
  error,
}

/// Listens for one utterance (F15-02, "Falar"): opens the microphone, closes
/// it at the first finished utterance, transcribes it and hands the text to
/// [onText]. The microphone is never left open after a result, a failure or
/// [dispose].
class ListenOnceViewModel extends ChangeNotifier {
  ListenOnceViewModel({
    DuplexVoiceService? service,
    Future<String?> Function(Float32List samples)? transcribe,
    Future<bool> Function()? speechModelMissing,
    this.onText,
  })  : _service = service ?? DuplexVoiceService(),
        _transcribe =
            transcribe ?? SpeechTranscriptionService.instance.transcribeSamples,
        _speechModelMissing = speechModelMissing ??
            SpeechTranscriptionService.instance.requiresLocalModelDownload;

  static final _logger = getLogger('ListenOnce');

  final DuplexVoiceService _service;
  final Future<String?> Function(Float32List samples) _transcribe;
  final Future<bool> Function() _speechModelMissing;

  /// Receives the transcript of the utterance; never empty. Set by the owner
  /// before [start] when it is not given here.
  void Function(String text)? onText;

  ListenOnceState state = ListenOnceState.idle;

  /// True after an utterance that transcribed to nothing.
  bool nothingHeard = false;

  bool _starting = false;
  // Bumped by every start, result, failure and dispose, so late work is dropped.
  int _epoch = 0;
  bool _disposed = false;

  Future<void> start() async {
    if (_starting ||
        state == ListenOnceState.listening ||
        state == ListenOnceState.transcribing) {
      return;
    }
    final epoch = ++_epoch;
    _starting = true;
    nothingHeard = false;
    try {
      if (await _speechModelMissing()) {
        _setState(ListenOnceState.modelMissing, epoch);
        return;
      }
      if (!await _service.requestPermission()) {
        _setState(ListenOnceState.permissionDenied, epoch);
        return;
      }
      await _service.openMic(
        onSpeechStart: () {},
        onUtterance: (samples) => _onUtterance(epoch, samples),
        onError: (e) => unawaited(_fail(e, epoch)),
      );
      if (epoch != _epoch) {
        await _service.closeMic();
        return;
      }
      _setState(ListenOnceState.listening, epoch);
    } catch (e, stack) {
      _logger.severe('Could not start listening', e, stack);
      await _fail(e, epoch);
    } finally {
      _starting = false;
    }
  }

  /// Stops listening without delivering text (the user typed or sent instead).
  /// No-op unless a start is in progress or the microphone is listening.
  Future<void> cancel() async {
    if (state != ListenOnceState.listening && !_starting) return;
    _epoch++;
    _setState(ListenOnceState.idle, _epoch);
    try {
      await _service.closeMic();
    } catch (closeError, stack) {
      _logger.warning('Could not close the microphone', closeError, stack);
    }
  }

  void _onUtterance(int epoch, Float32List samples) {
    if (epoch != _epoch || state != ListenOnceState.listening) return;
    // Drops the audio that follows this utterance, which the detector may
    // still hand over in the same chunk.
    _service.discardInput = true;
    _setState(ListenOnceState.transcribing, epoch);
    unawaited(_transcribeAndDeliver(epoch, samples));
  }

  Future<void> _transcribeAndDeliver(int epoch, Float32List samples) async {
    try {
      await _service.closeMic();
      final text = (await _transcribe(samples))?.trim() ?? '';
      if (epoch != _epoch) return;
      if (text.isEmpty) {
        nothingHeard = true;
        _setState(ListenOnceState.idle, epoch);
        return;
      }
      _setState(ListenOnceState.idle, epoch);
      onText?.call(text);
    } catch (e, stack) {
      _logger.severe('Could not transcribe the utterance', e, stack);
      await _fail(e, epoch);
    }
  }

  Future<void> _fail(Object e, int epoch) async {
    if (epoch != _epoch) return;
    _setState(ListenOnceState.error, epoch);
    _epoch++;
    try {
      await _service.closeMic();
    } catch (closeError, stack) {
      _logger.warning('Could not close the microphone', closeError, stack);
    }
  }

  void _setState(ListenOnceState next, int epoch) {
    if (epoch != _epoch || _disposed) return;
    state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    unawaited(_service.release().catchError((Object e, StackTrace stack) {
      _logger.warning('Could not release the audio resources', e, stack);
    }));
    super.dispose();
  }
}

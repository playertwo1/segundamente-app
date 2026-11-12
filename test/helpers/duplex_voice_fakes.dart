import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:memex/data/model/chat_events.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/duplex_voice_service.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/ui/chat/view_models/duplex_voice_viewmodel.dart';

/// Synthetic 16 kHz PCM: [windows] detector windows of a loud square wave or
/// of silence. No recorded audio is used in these tests.
Uint8List pcm(int windows, {required bool loud}) {
  final samples = Int16List(windows * SpeechDetector.windowSize);
  if (loud) {
    for (var i = 0; i < samples.length; i++) {
      samples[i] = i.isEven ? 16000 : -16000;
    }
  }
  return samples.buffer.asUint8List();
}

/// Energy gate standing in for the Silero model: a loud window is speech and
/// two silent windows end the utterance.
class FakeSpeechDetector implements SpeechDetector {
  final List<double> _current = [];
  final List<Float32List> _done = [];
  int _silent = 0;
  int resets = 0;
  bool freed = false;

  @override
  bool isSpeech = false;

  @override
  void accept(Float32List window) {
    final loud = window.any((s) => s.abs() > 0.1);
    if (loud) {
      isSpeech = true;
      _silent = 0;
      _current.addAll(window);
    } else if (isSpeech && ++_silent >= 2) {
      isSpeech = false;
      _done.add(Float32List.fromList(_current));
      _current.clear();
    }
  }

  @override
  Float32List? takeSegment() => _done.isEmpty ? null : _done.removeAt(0);

  @override
  void reset() {
    resets++;
    isSpeech = false;
    _silent = 0;
    _current.clear();
    _done.clear();
  }

  @override
  void free() => freed = true;
}

/// The device side of [DuplexVoiceService]: microphone, speech engine and
/// wakelock, all in memory.
class FakeAudioDevice {
  StreamController<Uint8List> mic = StreamController<Uint8List>();
  final detector = FakeSpeechDetector();
  bool permission = true;
  int permissionRequests = 0;
  int micStarts = 0;
  int micStops = 0;
  int speechStops = 0;
  int speechShutdowns = 0;
  bool awake = false;
  Object? startError;
  Object? stopSpeakingError;
  final List<String> spoken = [];
  final List<String> locales = [];
  Completer<bool>? _speaking;

  bool get micHeld => micStarts > micStops;
  bool get isSpeaking => _speaking != null && !_speaking!.isCompleted;

  late final service = DuplexVoiceService(
    requestPermission: () async {
      permissionRequests++;
      return permission;
    },
    startStream: () async {
      if (startError != null) throw startError!;
      micStarts++;
      mic = StreamController<Uint8List>();
      return mic.stream;
    },
    stopStream: () async => micStops++,
    createDetector: () async => detector,
    speak: (text, locale) {
      spoken.add(text);
      locales.add(locale);
      return (_speaking = Completer<bool>()).future;
    },
    stopSpeaking: () async {
      speechStops++;
      if (stopSpeakingError != null) throw stopSpeakingError!;
      if (isSpeaking) _speaking!.complete(false);
    },
    shutdownSpeech: () async => speechShutdowns++,
    keepAwake: (on) async => awake = on,
  );

  /// The speech engine reaches the end of the reply.
  void finishSpeaking() => _speaking!.complete(true);

  /// One spoken utterance followed by the silence that ends it.
  Future<void> say() async {
    mic.add(pcm(4, loud: true));
    mic.add(pcm(2, loud: false));
    await pumpEventQueue();
  }
}

class FakeChatRouter implements MemexRouter {
  final List<String> sent = [];
  final List<String?> sessionIds = [];
  final List<bool> readOnly = [];
  StreamController<ChatEvent>? reply;

  /// Answers the last message with [text] and ends the turn.
  Future<void> answer(String text) async {
    reply!
      ..add(ChatSessionCreatedEvent('voz-1'))
      ..add(ChatResponseChunkEvent('t', text, isDone: true));
    await reply!.close();
    await pumpEventQueue();
  }

  @override
  Stream<ChatEvent> sendMessage(
    String message, {
    String? sessionId,
    String? agentName = 'memex_agent',
    String? scene = 'assistant',
    String? sceneId,
    List<Map<String, String>>? refs,
    List<XFile> images = const [],
    Map<String, String>? imageOriginalFilenames,
    List<Map<String, String>> files = const [],
    bool isQuickQuery = false,
    String runMode = 'auto',
  }) {
    sent.add(message);
    sessionIds.add(sessionId);
    readOnly.add(isQuickQuery && runMode == 'read_only');
    return (reply = StreamController<ChatEvent>()).stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const fakeChatConfig = LLMConfig(
  key: 'voz',
  type: LLMConfig.typeChatCompletion,
  modelId: 'modelo-de-teste',
  apiKey: 'k',
  baseUrl: 'https://llm.example.test/v1',
);

DuplexVoiceViewModel buildDuplexViewModel({
  required FakeAudioDevice device,
  required FakeChatRouter router,
  Future<String?> Function(Float32List samples)? transcribe,
  bool localSpeech = false,
  bool speechModelMissing = false,
  LLMConfig? config,
  bool noConfig = false,
}) {
  return DuplexVoiceViewModel(
    router: router,
    service: device.service,
    transcribe: transcribe ?? (_) async => 'que horas são',
    usesLocalSpeechModel: () async => localSpeech,
    speechModelMissing: () async => speechModelMissing,
    loadChatConfig: () async => noConfig ? null : (config ?? fakeChatConfig),
    locale: () => 'pt-BR',
  );
}

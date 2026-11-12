// Sonda descartável da F7-03. Mede no aparelho, com texto sintético:
//   1. eco: quantas vezes o detector de voz dispara com a própria voz do app;
//   2. interrupção: tempo entre detectar a fala do usuário e calar a síntese;
//   3. resistência: 5 minutos de microfone aberto + síntese (bateria e
//      temperatura são lidas pelo adb, ver README).
// Nenhum áudio é gravado: só contagens e níveis saem daqui (tela e logcat).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const _fala = 'Esta é uma frase de teste da sonda de voz. O céu está azul, '
    'o café está quente e o relógio marca dez horas. Um, dois, três, quatro, '
    'cinco, seis, sete, oito, nove, dez. Fim da frase de teste.';

typedef _Config = ({
  String nome,
  AndroidAudioSource fonte,
  bool aec,
  bool saidaDeChamada,
});

const _configs = <_Config>[
  (
    nome: 'mic_sem_aec',
    fonte: AndroidAudioSource.defaultSource,
    aec: false,
    saidaDeChamada: false,
  ),
  (
    nome: 'mic_aec',
    fonte: AndroidAudioSource.defaultSource,
    aec: true,
    saidaDeChamada: false,
  ),
  // Igual a DuplexVoiceService.micConfig do app.
  (
    nome: 'voz_aec',
    fonte: AndroidAudioSource.voiceCommunication,
    aec: true,
    saidaDeChamada: false,
  ),
  (
    nome: 'voz_aec_saida_chamada',
    fonte: AndroidAudioSource.voiceCommunication,
    aec: true,
    saidaDeChamada: true,
  ),
];

void main() => runApp(const MaterialApp(home: ProbeScreen()));

class ProbeScreen extends StatefulWidget {
  const ProbeScreen({super.key});

  @override
  State<ProbeScreen> createState() => _ProbeScreenState();
}

class _ProbeScreenState extends State<ProbeScreen> with WidgetsBindingObserver {
  static const _tts = MethodChannel('f703/tts');

  final _log = <String>[];
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _sub;
  sherpa.VoiceActivityDetector? _vad;
  final _buffer = <double>[];
  bool _micOn = false;
  bool _running = false;
  bool _abort = false;

  // Counters of the current measurement window.
  int _triggers = 0;
  bool _wasSpeech = false;
  double _squares = 0;
  int _samples = 0;
  void Function()? _onTrigger;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sem captura em segundo plano.
    if (state == AppLifecycleState.paused) unawaited(_stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stop());
    _vad?.free();
    super.dispose();
  }

  void _emit(Map<String, Object?> result) {
    final line = 'F703 ${jsonEncode(result)}';
    debugPrint(line);
    if (mounted) setState(() => _log.insert(0, line));
  }

  Future<sherpa.VoiceActivityDetector> _loadVad() async {
    sherpa.initBindings();
    final dir = await getApplicationSupportDirectory();
    final model = File('${dir.path}/silero_vad.onnx');
    if (!model.existsSync()) {
      final data = await rootBundle.load('assets/silero_vad.onnx');
      await model.writeAsBytes(data.buffer.asUint8List());
    }
    // Same values as the app (duplex_voice_service.dart).
    return sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: model.path,
          threshold: 0.5,
          minSilenceDuration: 0.7,
          minSpeechDuration: 0.25,
          windowSize: 512,
          maxSpeechDuration: 30,
        ),
        sampleRate: 16000,
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: 60,
    );
  }

  Future<void> _openMic(_Config config) async {
    final vad = _vad ??= await _loadVad();
    vad.reset();
    _buffer.clear();
    _resetCounters();
    _recorder = AudioRecorder();
    final stream = await _recorder!.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: config.aec,
        noiseSuppress: config.aec,
        androidConfig: AndroidRecordConfig(audioSource: config.fonte),
      ),
    );
    _sub = stream.listen((chunk) {
      final pcm = Uint8List.fromList(chunk).buffer.asInt16List(
            0,
            chunk.length ~/ 2,
          );
      for (final s in pcm) {
        final v = s / 32768.0;
        _buffer.add(v);
        _squares += v * v;
      }
      _samples += pcm.length;
      while (_buffer.length >= 512) {
        vad.acceptWaveform(Float32List.fromList(_buffer.sublist(0, 512)));
        _buffer.removeRange(0, 512);
        final speech = vad.isDetected();
        if (speech && !_wasSpeech) {
          _triggers++;
          _onTrigger?.call();
        }
        _wasSpeech = speech;
      }
      while (!vad.isEmpty()) {
        vad.pop(); // segmentos são descartados, nunca guardados
      }
    });
    setState(() => _micOn = true);
  }

  Future<void> _closeMic() async {
    final recorder = _recorder;
    _recorder = null;
    unawaited(_sub?.cancel());
    _sub = null;
    _onTrigger = null;
    await recorder?.stop();
    await recorder?.dispose();
    if (mounted) setState(() => _micOn = false);
  }

  void _resetCounters() {
    _triggers = 0;
    _wasSpeech = false;
    _squares = 0;
    _samples = 0;
  }

  double get _dbfs => _samples == 0
      ? double.negativeInfinity
      : 10 * log(max(_squares / _samples, 1e-12)) / ln10;

  Future<Map<Object?, Object?>> _speak(_Config config) async =>
      await _tts.invokeMethod<Map<Object?, Object?>>('speak', {
        'text': _fala,
        'voiceCall': config.saidaDeChamada,
      }) ??
      const {};

  Future<void> _run(Future<void> Function() test) async {
    if (_running) return;
    if (!(await Permission.microphone.request()).isGranted) {
      _emit({'erro': 'sem permissão do microfone'});
      return;
    }
    setState(() => _running = true);
    _abort = false;
    try {
      await test();
    } catch (e) {
      _emit({'erro': '$e'});
    } finally {
      await _tts.invokeMethod('stop');
      await _closeMic();
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _stop() async {
    _abort = true;
    await _tts.invokeMethod('stop');
    await _closeMic();
  }

  /// Fique em silêncio. Qualquer disparo durante a fala é eco.
  Future<void> _eco() async {
    for (final config in _configs) {
      if (_abort) return;
      await _openMic(config);
      await Future<void>.delayed(const Duration(seconds: 2));
      final silencio = _dbfs;
      final disparosEmSilencio = _triggers;
      _resetCounters();
      final fala = await _speak(config);
      _emit({
        'teste': 'eco',
        'config': config.nome,
        'disparos_em_silencio': disparosEmSilencio,
        'disparos_durante_fala': _triggers,
        'nivel_silencio_dbfs': silencio.toStringAsFixed(1),
        'nivel_durante_fala_dbfs': _dbfs.toStringAsFixed(1),
        'ms_ate_inicio_da_voz': fala['startMs'],
        'fala_completa': fala['completed'],
      });
      await _closeMic();
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  /// Fale "espera" cerca de 3 s depois de a voz começar, 5 vezes.
  Future<void> _interrupcao() async {
    final config = _configs[3]; // a única sem eco no S25 (teste 1)
    for (var rodada = 1; rodada <= 5 && !_abort; rodada++) {
      await _openMic(config);
      final clock = Stopwatch()..start();
      int? detectadoMs;
      int? caladoMs;
      _onTrigger = () {
        if (detectadoMs != null) return;
        detectadoMs = clock.elapsedMilliseconds;
        unawaited(_tts.invokeMethod('stop').then((_) {
          caladoMs = clock.elapsedMilliseconds;
        }));
      };
      final fala = await _speak(config);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _emit({
        'teste': 'interrupcao',
        'config': config.nome,
        'rodada': rodada,
        'ms_ate_inicio_da_voz': fala['startMs'],
        'detectado_ms_apos_pedir_fala': detectadoMs,
        'ms_entre_detectar_e_calar':
            detectadoMs == null || caladoMs == null
                ? null
                : caladoMs! - detectadoMs!,
        'fala_completa': fala['completed'],
      });
      await _closeMic();
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  /// Fique em silêncio por 5 minutos. Bateria e temperatura: adb (README).
  Future<void> _resistencia() async {
    final config = _configs[3]; // a única sem eco no S25 (teste 1)
    await _openMic(config);
    final clock = Stopwatch()..start();
    var falas = 0;
    while (clock.elapsed < const Duration(minutes: 5) && !_abort) {
      await _speak(config);
      falas++;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    _emit({
      'teste': 'resistencia',
      'config': config.nome,
      'segundos': clock.elapsed.inSeconds,
      'falas': falas,
      'disparos_falsos': _triggers,
      'interrompido': _abort,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('F7-03 sonda')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              color: _micOn ? Colors.red : Colors.black12,
              child: Text(
                _micOn ? 'MICROFONE LIGADO' : 'Microfone desligado',
                style: TextStyle(
                  fontSize: 20,
                  color: _micOn ? Colors.white : Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _running ? null : () => _run(_eco),
              child: const Text('1. Eco (fique em silêncio, ~1 min)'),
            ),
            FilledButton(
              onPressed: _running ? null : () => _run(_interrupcao),
              child: const Text('2. Interrupção (fale "espera" 5 vezes)'),
            ),
            FilledButton(
              onPressed: _running ? null : () => _run(_resistencia),
              child: const Text('3. Resistência (5 min em silêncio)'),
            ),
            OutlinedButton(
              onPressed: _running ? _stop : null,
              child: const Text('Parar e desligar o microfone'),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [for (final line in _log) SelectableText(line)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

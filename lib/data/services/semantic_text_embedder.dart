import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'unigram_tokenizer.dart';

abstract interface class SemanticTextEmbedder {
  Future<List<double>> embed(String text);

  Future<void> close();
}

typedef HiddenStateRunner = Future<List<num>> Function(List<int> inputIds);

class OnnxSemanticTextEmbedder implements SemanticTextEmbedder {
  OnnxSemanticTextEmbedder({
    required UnigramTokenizer tokenizer,
    required HiddenStateRunner runHiddenState,
    Future<void> Function()? closeSession,
  })  : _tokenizer = tokenizer,
        _runHiddenState = runHiddenState,
        _closeSession = closeSession;

  final UnigramTokenizer _tokenizer;
  final HiddenStateRunner _runHiddenState;
  final Future<void> Function()? _closeSession;

  static Future<OnnxSemanticTextEmbedder> load({
    required String modelPath,
    required String tokenizerPath,
  }) async {
    final session = await OnnxRuntime().createSession(modelPath);
    try {
      final inputs = (await session.getInputInfo())
          .map((input) => input['name'] as String)
          .toSet();
      final tokenizer = await UnigramTokenizer.fromFile(tokenizerPath);
      return OnnxSemanticTextEmbedder(
        tokenizer: tokenizer,
        runHiddenState: (ids) => _runModel(session, inputs, ids),
        closeSession: session.close,
      );
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  @override
  Future<List<double>> embed(String text) async {
    return embedTokenIds(_tokenizer.encode(text));
  }

  Future<List<double>> embedTokenIds(List<int> inputIds) async {
    return meanPoolAndNormalize(
        await _runHiddenState(inputIds), inputIds.length);
  }

  @override
  Future<void> close() async => _closeSession?.call();

  static Future<List<num>> _runModel(
    OrtSession session,
    Set<String> inputNames,
    List<int> inputIds,
  ) async {
    final length = inputIds.length;
    final feeds = <String, OrtValue>{
      'input_ids': await OrtValue.fromList(
        Int64List.fromList(inputIds),
        [1, length],
      ),
      'attention_mask': await OrtValue.fromList(
        Int64List.fromList(List.filled(length, 1)),
        [1, length],
      ),
      if (inputNames.contains('token_type_ids'))
        'token_type_ids':
            await OrtValue.fromList(Int64List(length), [1, length]),
    };
    Map<String, OrtValue>? outputs;
    try {
      outputs = await session.run(feeds);
      final outputName = session.outputNames.first;
      final hidden = outputs[outputName];
      if (hidden == null) throw StateError('ONNX model output is missing');
      return (await hidden.asFlattenedList()).cast<num>();
    } finally {
      for (final value in feeds.values) {
        await value.dispose();
      }
      for (final value in outputs?.values ?? const <OrtValue>[]) {
        await value.dispose();
      }
    }
  }
}

List<double> meanPoolAndNormalize(List<num> hiddenStates, int sequenceLength) {
  if (sequenceLength <= 0 ||
      hiddenStates.isEmpty ||
      hiddenStates.length % sequenceLength != 0) {
    throw ArgumentError('Hidden states do not match the token count');
  }
  final dimensions = hiddenStates.length ~/ sequenceLength;
  final vector = List<double>.filled(dimensions, 0);
  for (var token = 0; token < sequenceLength; token++) {
    for (var dimension = 0; dimension < dimensions; dimension++) {
      final value = hiddenStates[token * dimensions + dimension].toDouble();
      if (!value.isFinite) throw ArgumentError('Hidden states must be finite');
      vector[dimension] += value / sequenceLength;
    }
  }
  final norm =
      math.sqrt(vector.fold<double>(0, (sum, value) => sum + value * value));
  if (norm == 0 || !norm.isFinite) {
    throw StateError('Embedding has no direction');
  }
  for (var dimension = 0; dimension < dimensions; dimension++) {
    vector[dimension] /= norm;
  }
  return vector;
}

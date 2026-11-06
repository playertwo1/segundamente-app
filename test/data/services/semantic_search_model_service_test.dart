import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/semantic_search_model_service.dart';
import 'package:memex/data/services/semantic_text_embedder.dart';
import 'package:memex/utils/result.dart';

class _Embedder implements SemanticTextEmbedder {
  final embedded = <String>[];
  var closed = false;

  @override
  Future<List<double>> embed(String text) async {
    embedded.add(text);
    return [1, 0];
  }

  @override
  Future<void> close() async => closed = true;
}

void main() {
  test('pins the ARM64 model and tokenizer to the approved revision', () {
    expect(semanticSearchModelArtifacts[0].bytes, 118412398);
    expect(
      semanticSearchModelArtifacts[0].sha256,
      '783fea82d71a58179b830a4dbd2d58447e640609e98eedf9ffa12622d375a672',
    );
    expect(semanticSearchModelArtifacts[1].bytes, 9081518);
    expect(
      semanticSearchModelArtifacts[1].sha256,
      '2c3387be76557bd40970cec13153b3bbf80407865484b209e655e5e4729076b8',
    );
    expect(
        semanticSearchModelArtifacts.every((a) =>
            a.url.contains('/e8f8c211226b894fcb81acc59f3b34ba3efd5f42/')),
        isTrue);
  });

  test('downloads verified files atomically, caches item vectors, and deletes',
      () async {
    final directory = await Directory.systemTemp.createTemp('semantic_model_');
    final modelBytes = [1, 2, 3, 4];
    final tokenizerBytes = [5, 6, 7];
    final artifacts = [
      _artifact('onnx/model_qint8_arm64.onnx', modelBytes),
      _artifact('tokenizer.json', tokenizerBytes),
    ];
    final embedder = _Embedder();
    final downloaded = <String>[];
    final service = SemanticSearchModelService(
      supportDirectory: () async => directory,
      artifacts: artifacts,
      download: (uri, partial, onProgress) async {
        expect(partial.path, endsWith('.part'));
        final bytes = uri.path.endsWith('model_qint8_arm64.onnx')
            ? modelBytes
            : tokenizerBytes;
        await partial.writeAsBytes(bytes);
        downloaded.add(partial.path);
        onProgress(bytes.length);
      },
      loadEmbedder: (model, tokenizer) async {
        expect(await File(model).readAsBytes(), modelBytes);
        expect(await File(tokenizer).readAsBytes(), tokenizerBytes);
        return embedder;
      },
    );

    final result = await service.ensureReady(allowDownload: true);

    expect(result.isOk, isTrue);
    expect(service.state, SemanticSearchModelState.ready);
    expect(service.progress, 1);
    expect(service.hasDownloadedFiles, isTrue);
    expect(downloaded, hasLength(2));
    expect(downloaded.every((path) => !File(path).existsSync()), isTrue);
    await service.embedItem('texto de exemplo');
    await service.embedItem('texto de exemplo');
    expect(embedder.embedded, ['texto de exemplo']);

    final deleted = await service.deleteModel();
    expect(deleted.isOk, isTrue);
    expect(embedder.closed, isTrue);
    expect(service.state, SemanticSearchModelState.off);
    expect(service.hasDownloadedFiles, isFalse);
    expect(
      await Directory('${directory.path}/semantic_search').exists(),
      isTrue,
    );
    expect(
      Directory('${directory.path}/semantic_search')
          .listSync(recursive: true)
          .whereType<File>(),
      isEmpty,
    );

    service.dispose();
    await directory.delete(recursive: true);
  });

  test('checksum failure removes partial files and never loads the model',
      () async {
    final directory = await Directory.systemTemp.createTemp('semantic_model_');
    final bytes = [1, 2, 3];
    final artifact = SemanticSearchArtifact(
      path: 'onnx/model_qint8_arm64.onnx',
      url: 'https://example.invalid/onnx/model_qint8_arm64.onnx',
      bytes: bytes.length,
      sha256: sha256.convert([9, 9, 9]).toString(),
    );
    var loadCalled = false;
    final service = SemanticSearchModelService(
      supportDirectory: () async => directory,
      artifacts: [
        artifact,
        _artifact('tokenizer.json', [4])
      ],
      download: (uri, partial, onProgress) async {
        await partial.writeAsBytes(bytes);
        onProgress(bytes.length);
      },
      loadEmbedder: (_, __) async {
        loadCalled = true;
        return _Embedder();
      },
    );

    final result = await service.ensureReady(allowDownload: true);

    expect(result.isError, isTrue);
    expect(service.state, SemanticSearchModelState.error);
    expect(loadCalled, isFalse);
    final files = Directory('${directory.path}/semantic_search')
        .listSync(recursive: true)
        .whereType<File>();
    expect(files, isEmpty);

    service.dispose();
    await directory.delete(recursive: true);
  });

  test('does not download missing files when downloads are not allowed',
      () async {
    final directory = await Directory.systemTemp.createTemp('semantic_model_');
    var downloadCalled = false;
    final service = SemanticSearchModelService(
      supportDirectory: () async => directory,
      artifacts: [
        _artifact('onnx/model_qint8_arm64.onnx', [1]),
        _artifact('tokenizer.json', [2]),
      ],
      download: (_, __, ___) async => downloadCalled = true,
      loadEmbedder: (_, __) async => _Embedder(),
    );

    final result = await service.ensureReady(allowDownload: false);

    expect(result.isError, isTrue);
    expect(downloadCalled, isFalse);
    expect(service.state, SemanticSearchModelState.error);

    service.dispose();
    await directory.delete(recursive: true);
  });
}

SemanticSearchArtifact _artifact(String path, List<int> bytes) =>
    SemanticSearchArtifact(
      path: path,
      url: 'https://example.invalid/$path',
      bytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );

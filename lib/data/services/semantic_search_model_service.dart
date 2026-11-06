import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:memex/data/services/semantic_text_embedder.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/result.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum SemanticSearchModelState { off, downloading, ready, error }

class SemanticSearchArtifact {
  const SemanticSearchArtifact({
    required this.path,
    required this.url,
    required this.bytes,
    required this.sha256,
  });

  final String path;
  final String url;
  final int bytes;
  final String sha256;
}

const semanticSearchModelArtifacts = [
  SemanticSearchArtifact(
    path: 'onnx/model_qint8_arm64.onnx',
    url:
        'https://huggingface.co/sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2/resolve/e8f8c211226b894fcb81acc59f3b34ba3efd5f42/onnx/model_qint8_arm64.onnx',
    bytes: 118412398,
    sha256: '783fea82d71a58179b830a4dbd2d58447e640609e98eedf9ffa12622d375a672',
  ),
  SemanticSearchArtifact(
    path: 'tokenizer.json',
    url:
        'https://huggingface.co/sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2/resolve/e8f8c211226b894fcb81acc59f3b34ba3efd5f42/tokenizer.json',
    bytes: 9081518,
    sha256: '2c3387be76557bd40970cec13153b3bbf80407865484b209e655e5e4729076b8',
  ),
];

typedef SemanticModelDownloader = Future<void> Function(
  Uri uri,
  File partialFile,
  void Function(int downloadedBytes) onProgress,
);

typedef SemanticEmbedderLoader = Future<SemanticTextEmbedder> Function(
  String modelPath,
  String tokenizerPath,
);

abstract interface class SemanticSearchModelManager implements Listenable {
  SemanticSearchModelState get state;
  double get progress;
  bool get isReady;
  bool get hasDownloadedFiles;

  Future<void> refreshModelAvailability();
  Future<Result<void>> ensureReady({required bool allowDownload});
  Future<Result<void>> disable();
  Future<Result<void>> deleteModel();
  Future<List<double>> embedQuery(String text);
  Future<List<double>> embedItem(String text);
}

class SemanticSearchModelService extends ChangeNotifier
    implements SemanticSearchModelManager {
  SemanticSearchModelService({
    Future<Directory> Function()? supportDirectory,
    SemanticModelDownloader? download,
    SemanticEmbedderLoader? loadEmbedder,
    List<SemanticSearchArtifact> artifacts = semanticSearchModelArtifacts,
  })  : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
        _download = download ?? _downloadToFile,
        _loadEmbedder = loadEmbedder ??
            ((modelPath, tokenizerPath) => OnnxSemanticTextEmbedder.load(
                  modelPath: modelPath,
                  tokenizerPath: tokenizerPath,
                )),
        _artifacts = artifacts;

  static final instance = SemanticSearchModelService();
  static const _modelPath = 'onnx/model_qint8_arm64.onnx';
  static const _tokenizerPath = 'tokenizer.json';

  final Future<Directory> Function() _supportDirectory;
  final SemanticModelDownloader _download;
  final SemanticEmbedderLoader _loadEmbedder;
  final List<SemanticSearchArtifact> _artifacts;
  final _logger = getLogger('SemanticSearchModelService');
  final _itemEmbeddings = <String, Future<List<double>>>{};

  SemanticSearchModelState _state = SemanticSearchModelState.off;
  double _progress = 0;
  bool _hasDownloadedFiles = false;
  SemanticTextEmbedder? _embedder;
  Future<Result<void>>? _pendingEnsure;

  @override
  SemanticSearchModelState get state => _state;

  @override
  double get progress => _progress;

  @override
  bool get isReady => _embedder != null;

  @override
  bool get hasDownloadedFiles => _hasDownloadedFiles;

  @override
  Future<void> refreshModelAvailability() async {
    try {
      final base = Directory(
        p.join((await _supportDirectory()).path, 'semantic_search'),
      );
      _hasDownloadedFiles = false;
      for (final artifact in _artifacts) {
        if (await File(_artifactPath(base, artifact)).exists()) {
          _hasDownloadedFiles = true;
          break;
        }
      }
      notifyListeners();
    } catch (error, stackTrace) {
      _logger.warning(
        'Could not inspect local semantic model files',
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<Result<void>> ensureReady({required bool allowDownload}) {
    if (isReady) return Future.value(const Ok.v());
    final pending = _pendingEnsure;
    if (pending != null) return pending;
    final operation = _ensureReady(allowDownload: allowDownload);
    _pendingEnsure = operation;
    return operation.whenComplete(() => _pendingEnsure = null);
  }

  Future<Result<void>> _ensureReady({required bool allowDownload}) async {
    _setState(SemanticSearchModelState.downloading, progress: 0);
    final result = await runResultVoid(() async {
      if (_artifacts.map((artifact) => artifact.path).toSet().length != 2 ||
          !_artifacts.any((artifact) => artifact.path == _modelPath) ||
          !_artifacts.any((artifact) => artifact.path == _tokenizerPath)) {
        throw StateError('Semantic model artifacts are incomplete');
      }

      final base = Directory(
          p.join((await _supportDirectory()).path, 'semantic_search'));
      await base.create(recursive: true);
      await refreshModelAvailability();
      final totalBytes =
          _artifacts.fold<int>(0, (sum, item) => sum + item.bytes);
      var completedBytes = 0;

      for (final artifact in _artifacts) {
        final destination = File(_artifactPath(base, artifact));
        if (await _isVerified(destination, artifact)) {
          completedBytes += artifact.bytes;
          _setProgress(completedBytes / totalBytes);
          continue;
        }
        if (!allowDownload) {
          throw StateError('A verified semantic model file is missing');
        }
        await _downloadVerified(
          destination,
          artifact,
          totalBytes: totalBytes,
          completedBytes: completedBytes,
        );
        _hasDownloadedFiles = true;
        completedBytes += artifact.bytes;
        _setProgress(completedBytes / totalBytes);
      }

      final model = File(_artifactPath(base, _artifact(_modelPath)));
      final tokenizer = File(_artifactPath(base, _artifact(_tokenizerPath)));
      _embedder = await _loadEmbedder(model.path, tokenizer.path);
    });

    if (result.isError) await refreshModelAvailability();
    result.when(
      onOk: (_) => _setState(SemanticSearchModelState.ready, progress: 1),
      onError: (error, stackTrace) {
        _embedder = null;
        _itemEmbeddings.clear();
        _logger.warning(
            'Could not prepare the local semantic model', error, stackTrace);
        _setState(SemanticSearchModelState.error, progress: 0);
      },
    );
    return result;
  }

  @override
  Future<Result<void>> disable() => runResultVoid(() async {
        final embedder = _embedder;
        _embedder = null;
        _itemEmbeddings.clear();
        try {
          await embedder?.close();
        } finally {
          _setState(SemanticSearchModelState.off, progress: 0);
        }
      });

  @override
  Future<Result<void>> deleteModel() async {
    final result = await runResultVoid(() async {
      final embedder = _embedder;
      _embedder = null;
      _itemEmbeddings.clear();
      await embedder?.close();
      final base = Directory(
          p.join((await _supportDirectory()).path, 'semantic_search'));
      for (final artifact in _artifacts) {
        final file = File(_artifactPath(base, artifact));
        final partial = File('${file.path}.part');
        if (await file.exists()) await file.delete();
        if (await partial.exists()) await partial.delete();
      }
      _hasDownloadedFiles = false;
      _setState(SemanticSearchModelState.off, progress: 0);
    });
    result.when(
      onOk: (_) {},
      onError: (error, stackTrace) {
        _logger.warning(
            'Could not remove the local semantic model', error, stackTrace);
        _setState(SemanticSearchModelState.error, progress: 0);
      },
    );
    return result;
  }

  @override
  Future<List<double>> embedQuery(String text) =>
      _requiredEmbedder().embed(text);

  @override
  Future<List<double>> embedItem(String text) async {
    final cached = _itemEmbeddings[text];
    if (cached != null) return cached;
    final pending = _requiredEmbedder().embed(text);
    _itemEmbeddings[text] = pending;
    try {
      return await pending;
    } catch (_) {
      if (identical(_itemEmbeddings[text], pending)) {
        _itemEmbeddings.remove(text);
      }
      rethrow;
    }
  }

  SemanticTextEmbedder _requiredEmbedder() =>
      _embedder ?? (throw StateError('Semantic model is not ready'));

  Future<void> _downloadVerified(
    File destination,
    SemanticSearchArtifact artifact, {
    required int totalBytes,
    required int completedBytes,
  }) async {
    final partial = File('${destination.path}.part');
    await destination.parent.create(recursive: true);
    if (await partial.exists()) await partial.delete();
    if (await destination.exists()) await destination.delete();
    try {
      await _download(Uri.parse(artifact.url), partial, (downloadedBytes) {
        _setProgress((completedBytes + downloadedBytes) / totalBytes);
      });
      if (await partial.length() != artifact.bytes) {
        throw StateError('Semantic model file size did not match');
      }
      final digest = await sha256.bind(partial.openRead()).first;
      if (digest.toString() != artifact.sha256) {
        throw StateError('Semantic model checksum did not match');
      }
      if (await destination.exists()) await destination.delete();
      await partial.rename(destination.path);
    } catch (_) {
      if (await partial.exists()) {
        await partial.delete();
      }
      rethrow;
    }
  }

  Future<bool> _isVerified(
    File file,
    SemanticSearchArtifact artifact,
  ) async {
    if (!await file.exists() || await file.length() != artifact.bytes) {
      return false;
    }
    return (await sha256.bind(file.openRead()).first).toString() ==
        artifact.sha256;
  }

  SemanticSearchArtifact _artifact(String path) =>
      _artifacts.firstWhere((artifact) => artifact.path == path);

  static String _artifactPath(Directory base, SemanticSearchArtifact artifact) {
    final relative = p.normalize(artifact.path);
    if (p.isAbsolute(relative) ||
        relative == '..' ||
        relative.startsWith('..${p.separator}')) {
      throw FormatException('Invalid semantic model path: ${artifact.path}');
    }
    return p.join(base.path, relative);
  }

  void _setProgress(double progress) {
    final bounded = progress.clamp(0.0, 1.0).toDouble();
    if ((_progress * 100).floor() == (bounded * 100).floor()) return;
    _progress = bounded;
    notifyListeners();
  }

  void _setState(SemanticSearchModelState state, {required double progress}) {
    _state = state;
    _progress = progress;
    notifyListeners();
  }

  static Future<void> _downloadToFile(
    Uri uri,
    File partialFile,
    void Function(int downloadedBytes) onProgress,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('Model download returned ${response.statusCode}',
            uri: uri);
      }
      final sink = partialFile.openWrite();
      var downloaded = 0;
      try {
        await for (final chunk in response) {
          downloaded += chunk.length;
          sink.add(chunk);
          onProgress(downloaded);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } finally {
      client.close(force: true);
    }
  }
}

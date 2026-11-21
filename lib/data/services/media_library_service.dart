import 'dart:io';

import 'package:logging/logging.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/media_library_item.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as p;

/// Scans the user's `Facts/assets/` directory for photos, PDFs, and audios,
/// and best-effort links each file back to its timeline card.
class MediaLibraryService {
  MediaLibraryService({
    Future<String?> Function()? getAssetsDir,
    Future<List<TimelineCardModel>> Function()? loadCards,
  })  : _getAssetsDir = getAssetsDir ?? _defaultGetAssetsDir,
        _loadCards = loadCards ?? _emptyCards;

  static final Logger _logger = getLogger('MediaLibraryService');

  final Future<String?> Function() _getAssetsDir;
  final Future<List<TimelineCardModel>> Function() _loadCards;

  static Future<String?> _defaultGetAssetsDir() async {
    final userId = await UserStorage.getUserId();
    if (userId == null || userId.isEmpty) return null;
    return FileSystemService.instance.getAssetsPath(userId);
  }

  static Future<List<TimelineCardModel>> _emptyCards() async => const [];

  /// Returns all local photos, PDFs, and audio files sorted newest-first.
  Future<List<MediaLibraryItem>> listAll() async {
    final assetsDirPath = await _getAssetsDir();
    if (assetsDirPath == null || assetsDirPath.isEmpty) return const [];

    final dir = Directory(assetsDirPath);
    if (!await dir.exists()) return const [];

    final cardByFileName = await _indexCardsByAssetName();
    final items = <MediaLibraryItem>[];

    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      if (entity is! File) continue;
      final fileName = p.basename(entity.path);
      final kind = classifyMediaKind(fileName);
      if (kind == null) continue;

      try {
        final stat = await entity.stat();
        final linkedCard = cardByFileName[fileName];
        items.add(
          MediaLibraryItem(
            fileName: fileName,
            filePath: entity.path,
            kind: kind,
            modifiedAt: stat.modified,
            sizeBytes: stat.size,
            cardId: linkedCard?.id,
            cardTitle: linkedCard?.title,
          ),
        );
      } catch (e) {
        _logger.warning('Failed to stat asset $fileName: $e');
      }
    }

    items.sort((a, b) {
      final cmp = b.modifiedAt.compareTo(a.modifiedAt);
      return cmp != 0 ? cmp : a.fileName.compareTo(b.fileName);
    });
    return items;
  }

  Future<Map<String, TimelineCardModel>> _indexCardsByAssetName() async {
    final map = <String, TimelineCardModel>{};
    try {
      final cards = await _loadCards();
      for (final card in cards) {
        final assets = card.assets;
        if (assets == null || assets.isEmpty) continue;
        for (final asset in assets) {
          final name = _extractFileName(asset.url);
          if (name != null && name.isNotEmpty) {
            map.putIfAbsent(name, () => card);
          }
        }
      }
    } catch (e) {
      _logger.warning('Best-effort card indexing for media library failed: $e');
    }
    return map;
  }

  static String? _extractFileName(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('fs://')) {
      return p.basename(trimmed.substring('fs://'.length));
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return p.basename(trimmed);
  }
}

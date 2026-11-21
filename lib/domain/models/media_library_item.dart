import 'package:path/path.dart' as p;

/// Supported media categories in the aggregated library.
enum MediaLibraryKind {
  photo,
  pdf,
  audio,
}

/// Classifies a file name or path into a [MediaLibraryKind], or `null` if
/// it is not a photo, PDF, or audio file.
MediaLibraryKind? classifyMediaKind(String fileNameOrPath) {
  final ext = p.extension(fileNameOrPath).toLowerCase();
  return switch (ext) {
    '.png' ||
    '.jpg' ||
    '.jpeg' ||
    '.webp' ||
    '.gif' ||
    '.heic' ||
    '.bmp' =>
      MediaLibraryKind.photo,
    '.pdf' => MediaLibraryKind.pdf,
    '.m4a' ||
    '.mp3' ||
    '.wav' ||
    '.aac' ||
    '.ogg' ||
    '.opus' ||
    '.flac' =>
      MediaLibraryKind.audio,
    _ => null,
  };
}

/// One local media asset stored in the user's `Facts/assets/` directory.
class MediaLibraryItem {
  const MediaLibraryItem({
    required this.fileName,
    required this.filePath,
    required this.kind,
    required this.modifiedAt,
    required this.sizeBytes,
    this.cardId,
    this.cardTitle,
  });

  final String fileName;
  final String filePath;
  final MediaLibraryKind kind;
  final DateTime modifiedAt;
  final int sizeBytes;
  final String? cardId;
  final String? cardTitle;
}

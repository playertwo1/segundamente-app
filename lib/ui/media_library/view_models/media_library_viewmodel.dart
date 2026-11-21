import 'package:flutter/foundation.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/media_library_item.dart';
import 'package:memex/utils/result.dart';

/// Filter tabs for [MediaLibraryScreen].
enum MediaLibraryFilter {
  all,
  photo,
  pdf,
  audio,
}

/// ViewModel managing the aggregated local library of photos, PDFs, and audios.
class MediaLibraryViewModel extends ChangeNotifier {
  MediaLibraryViewModel({required MemexRouter router}) : _router = router;

  final MemexRouter _router;

  bool _isLoading = false;
  String? _errorMessage;
  List<MediaLibraryItem> _allItems = const [];
  MediaLibraryFilter _filter = MediaLibraryFilter.all;
  String _searchQuery = '';
  bool _disposed = false;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  MediaLibraryFilter get filter => _filter;
  String get searchQuery => _searchQuery;

  int get totalCount => _allItems.length;
  int get photoCount =>
      _allItems.where((i) => i.kind == MediaLibraryKind.photo).length;
  int get pdfCount =>
      _allItems.where((i) => i.kind == MediaLibraryKind.pdf).length;
  int get audioCount =>
      _allItems.where((i) => i.kind == MediaLibraryKind.audio).length;

  /// Items matching both the active [filter] and [searchQuery].
  List<MediaLibraryItem> get items {
    final query = _searchQuery.trim().toLowerCase();
    return _allItems.where((item) {
      final matchesKind = switch (_filter) {
        MediaLibraryFilter.all => true,
        MediaLibraryFilter.photo => item.kind == MediaLibraryKind.photo,
        MediaLibraryFilter.pdf => item.kind == MediaLibraryKind.pdf,
        MediaLibraryFilter.audio => item.kind == MediaLibraryKind.audio,
      };
      if (!matchesKind) return false;
      if (query.isEmpty) return true;
      return item.fileName.toLowerCase().contains(query) ||
          (item.cardTitle?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Loads all local media items via [MemexRouter].
  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    _notify();

    final result = await _router.fetchMediaLibrary();
    result.when(
      onOk: (list) {
        _allItems = list;
        _isLoading = false;
        _notify();
      },
      onError: (e, _) {
        _errorMessage = e.toString();
        _isLoading = false;
        _notify();
      },
    );
  }

  void setFilter(MediaLibraryFilter next) {
    if (_filter == next) return;
    _filter = next;
    _notify();
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    _notify();
  }
}

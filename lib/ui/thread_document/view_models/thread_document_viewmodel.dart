import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/session_report_export.dart';
import 'package:memex/domain/models/thread_document.dart';
import 'package:memex/utils/result.dart';

enum ThreadDocumentIssue { none, stale, failed }

class ThreadDocumentViewModel extends ChangeNotifier {
  ThreadDocumentViewModel({
    required MemexRouter router,
    required this.docId,
    this.pollEvery = const Duration(seconds: 3),
    this.maxPolls = 60,
  }) : _router = router;

  final MemexRouter _router;
  final String docId;
  final Duration pollEvery;
  final int maxPolls;

  ThreadDocument? doc;
  int? _selected;
  bool loading = false;

  /// A revision was queued and has not shown up yet.
  bool waiting = false;
  ThreadDocumentIssue issue = ThreadDocumentIssue.none;
  Timer? _timer;
  bool _disposed = false;

  int get selectedNumber => _selected ?? doc?.latest.number ?? 1;
  DocumentVersion? get shown => doc?.version(selectedNumber);
  bool get viewingLatest => doc != null && selectedNumber == doc!.latest.number;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    final result = await _router.loadThreadDocument(docId);
    result.when(
      onOk: (loaded) => doc = loaded,
      onError: (_, __) => issue = ThreadDocumentIssue.failed,
    );
    loading = false;
    if (!_disposed) notifyListeners();
  }

  void select(int number) {
    _selected = number;
    notifyListeners();
  }

  /// Queues a revision of the latest version; the new one appears when ready.
  Future<void> revise(String instruction) async {
    final current = doc;
    if (current == null || instruction.trim().isEmpty || waiting) return;
    issue = ThreadDocumentIssue.none;
    final result = await _router.requestThreadDocument(
      cardId: current.cardId,
      instruction: instruction.trim(),
      docId: current.id,
      expectedLatest: current.latest.number,
    );
    if (result.isError) {
      issue = ThreadDocumentIssue.failed;
      notifyListeners();
      return;
    }
    waiting = true;
    notifyListeners();
    var polls = 0;
    _timer?.cancel();
    _timer = Timer.periodic(pollEvery, (timer) async {
      polls++;
      await load();
      final fresh = doc;
      if (fresh != null && fresh.latest.number > current.latest.number) {
        _selected = null;
        waiting = false;
        timer.cancel();
        if (!_disposed) notifyListeners();
      } else if (polls >= maxPolls) {
        waiting = false;
        issue = ThreadDocumentIssue.failed;
        timer.cancel();
        if (!_disposed) notifyListeners();
      }
    });
  }

  /// The text to show: charts and record photos drawn in; the plain text when
  /// that fails.
  Future<String> render(String content) async {
    final result =
        await _router.renderThreadDocument(content, cardId: doc?.cardId);
    return result.when(onOk: (text) => text, onError: (_, __) => content);
  }

  /// Saves a manual edit as a new version. [basedOn] is the version the editor
  /// was opened on, not the latest now: a revision that finished meanwhile must
  /// refuse the edit instead of being overwritten by it.
  Future<bool> saveEdit(String content, {required int basedOn}) async {
    final current = doc;
    if (current == null || content.trim().isEmpty) return false;
    final result = await _router.editThreadDocument(
      id: current.id,
      expectedLatest: basedOn,
      content: content,
    );
    var saved = false;
    result.when(
      onOk: (updated) {
        doc = updated;
        _selected = null;
        issue = ThreadDocumentIssue.none;
        saved = true;
      },
      onError: (error, _) => issue = error is StaleDocumentEdit
          ? ThreadDocumentIssue.stale
          : ThreadDocumentIssue.failed,
    );
    notifyListeners();
    return saved;
  }

  /// Path of the exported file for the version on screen, or null on failure.
  Future<String?> export(ReportExportFormat format,
      {bool draft = false}) async {
    final result = await _router.exportThreadDocument(
      id: docId,
      version: selectedNumber,
      format: format,
      draft: draft,
    );
    String? path;
    result.when(
      onOk: (value) => path = value,
      onError: (_, __) => issue = ThreadDocumentIssue.failed,
    );
    if (path == null) notifyListeners();
    return path;
  }

  Future<bool> delete() async =>
      (await _router.deleteThreadDocument(docId)).isOk;

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/thread_document.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';

/// Documents made from this record's comment thread, plus the button that
/// asks for a new one. Nothing is sent to the model before the user confirms.
class ThreadDocumentsSection extends StatefulWidget {
  const ThreadDocumentsSection({
    super.key,
    required this.router,
    required this.cardId,
    this.refresh,
    this.pollEvery = const Duration(seconds: 3),
    this.maxPolls = 60,
  });

  /// Bumped by the screen when a document may have been added elsewhere.
  final Listenable? refresh;

  final MemexRouter router;
  final String cardId;
  final Duration pollEvery;
  final int maxPolls;

  @override
  State<ThreadDocumentsSection> createState() => _ThreadDocumentsSectionState();
}

class _ThreadDocumentsSectionState extends State<ThreadDocumentsSection> {
  List<ThreadDocument> _docs = const [];
  List<({String asset, int bytes})> _largePdfs = const [];
  bool _preparing = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.refresh?.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_load);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await widget.router.listThreadDocuments(widget.cardId);
    if (!mounted) return;
    result.when(
      onOk: (docs) => setState(() => _docs = docs),
      onError: (_, __) {},
    );
    final large = await widget.router.largePdfsAwaiting(widget.cardId);
    if (!mounted) return;
    large.when(
      onOk: (list) => setState(() => _largePdfs = list),
      onError: (_, __) {},
    );
  }

  Future<void> _sendLargePdf(String asset) async {
    await widget.router.confirmLargePdf(asset);
    await _load();
  }

  Future<void> _create() async {
    final l10n = UserStorage.l10n;
    final choice = await showDialog<({String instruction, List<String> related})>(
      context: context,
      builder: (context) => _CreateDialog(
        router: widget.router,
        cardId: widget.cardId,
      ),
    );
    if (choice == null || choice.instruction.trim().isEmpty || !mounted) return;
    final result = await widget.router.requestThreadDocument(
      cardId: widget.cardId,
      instruction: choice.instruction.trim(),
      relatedIds: choice.related,
    );
    if (!mounted) return;
    if (result.isError) {
      ToastHelper.showError(context, l10n.threadDocFailed);
      return;
    }
    final before = _docs.length;
    setState(() => _preparing = true);
    var polls = 0;
    _timer?.cancel();
    _timer = Timer.periodic(widget.pollEvery, (timer) async {
      polls++;
      await _load();
      if (_docs.length > before || polls >= widget.maxPolls) {
        timer.cancel();
        if (mounted) setState(() => _preparing = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.threadDocsSection,
            style: Theme.of(context).textTheme.titleSmall),
        for (final doc in _docs)
          ListTile(
            key: ValueKey('thread_doc_${doc.id}'),
            leading: const Icon(Icons.description_outlined),
            title: Text(
              '${doc.title} — ${l10n.threadDocVersion(doc.latest.number.toString())}',
            ),
            onTap: () async {
              await context.push('${AppRoutes.threadDocument}/${doc.id}');
              if (mounted) _load();
            },
          ),
        for (final pdf in _largePdfs)
          ListTile(
            key: ValueKey('thread_doc_large_pdf_${pdf.asset}'),
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(l10n.threadDocLargePdf(
                (pdf.bytes / (1024 * 1024)).toStringAsFixed(1))),
            trailing: TextButton(
              key: const ValueKey('thread_doc_large_pdf_send'),
              onPressed: () => _sendLargePdf(pdf.asset),
              child: Text(l10n.threadDocLargePdfSend),
            ),
          ),
        if (_preparing)
          ListTile(
            key: const ValueKey('thread_docs_preparing'),
            leading: const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text(l10n.threadDocPreparing),
          ),
        TextButton.icon(
          key: const ValueKey('thread_doc_create'),
          icon: const Icon(Icons.note_add_outlined),
          label: Text(l10n.threadDocCreate),
          onPressed: _preparing ? null : _create,
        ),
      ],
    );
  }
}

class _CreateDialog extends StatefulWidget {
  const _CreateDialog({required this.router, required this.cardId});

  final MemexRouter router;
  final String cardId;

  @override
  State<_CreateDialog> createState() => _CreateDialogState();
}

class _CreateDialogState extends State<_CreateDialog> {
  final _controller =
      TextEditingController(text: UserStorage.l10n.threadDocInstructionDefault);
  List<({String id, String title})>? _found;
  final _ticked = <String>{};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final result =
        await widget.router.findRelatedRecords(widget.cardId, _controller.text);
    if (!mounted) return;
    setState(() => _found = result.when(
          onOk: (list) => list,
          onError: (_, __) => const [],
        ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: Text(l10n.threadDocCreateTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.threadDocCreateBody),
            TextField(
              key: const ValueKey('thread_doc_instruction'),
              controller: _controller,
              decoration:
                  InputDecoration(hintText: l10n.threadDocInstructionHint),
            ),
            TextButton(
              key: const ValueKey('thread_doc_related_find'),
              onPressed: _find,
              child: Text(l10n.threadDocRelatedFind),
            ),
            if (_found != null && _found!.isEmpty)
              Text(l10n.threadDocRelatedNone),
            for (final r in _found ?? const <({String id, String title})>[])
              CheckboxListTile(
                key: ValueKey('thread_doc_related_${r.id}'),
                value: _ticked.contains(r.id),
                title: Text(r.title, maxLines: 2),
                onChanged: (on) => setState(
                    () => on == true ? _ticked.add(r.id) : _ticked.remove(r.id)),
              ),
            if (_found != null && _found!.isNotEmpty)
              Text(l10n.threadDocRelatedNote),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('thread_doc_create_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const ValueKey('thread_doc_create_confirm'),
          onPressed: () => Navigator.of(context)
              .pop((instruction: _controller.text, related: _ticked.toList())),
          child: Text(l10n.threadDocCreate),
        ),
      ],
    );
  }
}

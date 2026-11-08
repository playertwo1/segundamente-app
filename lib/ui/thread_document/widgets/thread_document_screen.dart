import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:memex/domain/models/session_report_export.dart';
import 'package:memex/domain/models/thread_document.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/thread_document/view_models/thread_document_viewmodel.dart';
import 'package:memex/utils/share_service.dart';
import 'package:memex/utils/user_storage.dart';

class ThreadDocumentScreen extends StatefulWidget {
  const ThreadDocumentScreen({super.key, required this.viewModel});

  final ThreadDocumentViewModel viewModel;

  @override
  State<ThreadDocumentScreen> createState() => _ThreadDocumentScreenState();
}

class _ThreadDocumentScreenState extends State<ThreadDocumentScreen> {
  final _revise = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.viewModel.load();
  }

  @override
  void dispose() {
    _revise.dispose();
    widget.viewModel.dispose(); // stops the revision polling
    super.dispose();
  }

  Future<void> _edit() async {
    final vm = widget.viewModel;
    final basedOn = vm.doc!.latest.number;
    final controller = TextEditingController(text: vm.doc!.latest.content);
    final l10n = UserStorage.l10n;
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text(l10n.threadDocEdit),
        content: TextField(
          key: const ValueKey('thread_doc_edit_text'),
          controller: controller,
          maxLines: 14,
          minLines: 6,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const ValueKey('thread_doc_save'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.threadDocSaveVersion),
          ),
        ],
      ),
    );
    if (text != null) await vm.saveEdit(text, basedOn: basedOn);
  }

  Future<void> _export(ReportExportFormat format) async {
    final path = await widget.viewModel.export(format);
    if (path == null || !mounted) return;
    await ShareService.shareExistingFile(
      context,
      path: path,
      mimeType: reportExportMimeType(format),
    );
  }

  Future<void> _delete() async {
    final l10n = UserStorage.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        content: Text(l10n.threadDocDeleteMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const ValueKey('thread_doc_delete_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.threadDocDelete),
          ),
        ],
      ),
    );
    if (ok == true && await widget.viewModel.delete() && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final doc = vm.doc;
        return Scaffold(
          appBar: AppBar(
            title: Text(doc?.title ?? l10n.threadDocsSection),
            actions: [
              if (doc != null)
                IconButton(
                  key: const ValueKey('thread_doc_delete'),
                  tooltip: l10n.threadDocDelete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _delete,
                ),
            ],
          ),
          body: doc == null
              ? Center(
                  child: vm.loading
                      ? const CircularProgressIndicator()
                      : Text(l10n.threadDocFailed),
                )
              : _body(vm, doc, l10n),
        );
      },
    );
  }

  Widget _body(ThreadDocumentViewModel vm, ThreadDocument doc, AppLocalizations l10n) {
    final shown = vm.shown!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final v in doc.versions)
              ChoiceChip(
                key: ValueKey('thread_doc_version_${v.number}'),
                label: Text(l10n.threadDocVersion(v.number.toString())),
                selected: v.number == vm.selectedNumber,
                onSelected: (_) => vm.select(v.number),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          shown.author == DocumentAuthor.user
              ? l10n.threadDocByUser
              : l10n.threadDocByModel,
          key: const ValueKey('thread_doc_author'),
        ),
        if (doc.originDeleted)
          Text(l10n.threadDocOriginDeleted,
              key: const ValueKey('thread_doc_origin_deleted')),
        if (shown.warnings.isNotEmpty)
          Text(
            l10n.threadDocWarnings(shown.warnings.join(', ')),
            key: const ValueKey('thread_doc_warnings'),
          ),
        const Divider(),
        _ExpandedMarkdown(content: shown.content, render: vm.render),
        const Divider(),
        if (vm.issue == ThreadDocumentIssue.stale)
          Semantics(
            liveRegion: true,
            child:
                Text(l10n.threadDocStale, key: const ValueKey('thread_doc_stale')),
          ),
        if (vm.issue == ThreadDocumentIssue.failed)
          Semantics(
            liveRegion: true,
            child: Text(l10n.threadDocFailed,
                key: const ValueKey('thread_doc_failed')),
          ),
        if (vm.waiting)
          Semantics(
            liveRegion: true,
            child: Row(
            key: const ValueKey('thread_doc_waiting'),
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(l10n.threadDocPreparing),
            ],
          ),
          ),
        Wrap(
          spacing: 8,
          children: [
            if (vm.viewingLatest)
              OutlinedButton.icon(
                key: const ValueKey('thread_doc_edit'),
                icon: const Icon(Icons.edit_outlined),
                label: Text(l10n.threadDocEdit),
                onPressed: _edit,
              ),
            PopupMenuButton<ReportExportFormat>(
              key: const ValueKey('thread_doc_export'),
              tooltip: l10n.threadDocExport,
              onSelected: _export,
              itemBuilder: (_) => [
                for (final f in const [
                  ReportExportFormat.markdown,
                  ReportExportFormat.pdf,
                  ReportExportFormat.docx,
                ])
                  PopupMenuItem(
                    key: ValueKey('thread_doc_export_${f.name}'),
                    value: f,
                    child: Text(f.name.toUpperCase()),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(l10n.threadDocExport),
              ),
            ),
          ],
        ),
        if (vm.viewingLatest)
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('thread_doc_revise_text'),
                  controller: _revise,
                  decoration: InputDecoration(hintText: l10n.threadDocReviseHint),
                ),
              ),
              TextButton(
                key: const ValueKey('thread_doc_revise'),
                onPressed: vm.waiting
                    ? null
                    : () async {
                        final text = _revise.text;
                        _revise.clear();
                        await vm.revise(text);
                      },
                child: Text(l10n.threadDocRevise),
              ),
            ],
          ),
      ],
    );
  }
}

/// Markdown with its chart blocks drawn; the plain text shows until they are.
class _ExpandedMarkdown extends StatefulWidget {
  const _ExpandedMarkdown({required this.content, required this.render});

  final String content;
  final Future<String> Function(String) render;

  @override
  State<_ExpandedMarkdown> createState() => _ExpandedMarkdownState();
}

class _ExpandedMarkdownState extends State<_ExpandedMarkdown> {
  late Future<String> _future = widget.render(widget.content);

  @override
  void didUpdateWidget(_ExpandedMarkdown old) {
    super.didUpdateWidget(old);
    if (old.content != widget.content) _future = widget.render(widget.content);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: _future,
        initialData: widget.content,
        builder: (context, snap) =>
            MarkdownBody(data: snap.data ?? widget.content, selectable: true),
      );
}

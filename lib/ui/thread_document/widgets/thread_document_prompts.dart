import 'package:flutter/material.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/utils/user_storage.dart';

/// Asked when a record with documents is deleted. Null means the user backed
/// out; true keeps the documents, false deletes them together.
Future<bool?> askKeepDocuments(BuildContext context, int count) {
  final l10n = UserStorage.l10n;
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.background,
      title: Text(l10n.threadDocKeepTitle),
      content: Text(l10n.threadDocKeepBody(count.toString())),
      actions: [
        TextButton(
          key: const ValueKey('thread_doc_keep_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const ValueKey('thread_doc_keep_no'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.threadDocKeepNo),
        ),
        TextButton(
          key: const ValueKey('thread_doc_keep_yes'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.threadDocKeepYes),
        ),
      ],
    ),
  );
}

/// Asked when a comment reads like a request for a document. True creates it,
/// false keeps the text as a plain comment, null cancels sending.
Future<bool?> askCreateFromText(BuildContext context) {
  final l10n = UserStorage.l10n;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.background,
      title: Text(l10n.threadDocFromTextTitle),
      content: Text(l10n.threadDocFromTextBody),
      actions: [
        TextButton(
          key: const ValueKey('thread_doc_text_no'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.threadDocFromTextNo),
        ),
        TextButton(
          key: const ValueKey('thread_doc_text_yes'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.threadDocFromTextYes),
        ),
      ],
    ),
  );
}

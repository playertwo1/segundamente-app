import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/pdf_import_service.dart';
import 'package:memex/ui/chat/widgets/session_report_screen.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';

final _logger = getLogger('PdfFileImport');

typedef PdfImporter
    = Future<Result<({PdfImportOutcome outcome, String sessionId})>> Function(
        {required List<int> bytes, required bool confirmedLarge});

bool isPdfBytes(List<int> bytes) =>
    bytes.length >= 5 &&
    bytes[0] == 0x25 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x44 &&
    bytes[3] == 0x46 &&
    bytes[4] == 0x2d;

Future<bool> _ask(
    BuildContext context, String title, String body, String ok) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.background,
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          key: const ValueKey('pdf_send_cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(UserStorage.l10n.sendBack),
        ),
        TextButton(
          key: const ValueKey('pdf_send_confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return accepted ?? false;
}

/// Asks before the PDF leaves the phone, lets the chat model copy its pages,
/// then opens the report screen for the new session. Nothing is sent until
/// the user confirms.
Future<void> importPdfFile(
  BuildContext context, {
  required String name,
  required List<int> bytes,
  PdfImporter? import,
}) async {
  final l10n = UserStorage.l10n;
  final run = import ?? MemexRouter().importPdfFile;
  if (!await _ask(
      context, l10n.pdfSendTitle, l10n.pdfSendBody(name), l10n.pdfSendButton)) {
    return;
  }
  if (!context.mounted) return;

  final navigator = Navigator.of(context, rootNavigator: true);
  var progressOpen = false;
  Future<void> openProgress() async {
    progressOpen = true;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.background,
          content: Row(
            children: [
              const CircularProgressIndicator(color: AppColors.textSecondary),
              const SizedBox(width: 20),
              Expanded(child: Text(l10n.pdfReading)),
            ],
          ),
        ),
      ),
    ));
  }

  void closeProgress() {
    if (progressOpen && navigator.mounted && navigator.canPop()) {
      navigator.pop();
    }
    progressOpen = false;
  }

  Result<({PdfImportOutcome outcome, String sessionId})> result;
  try {
    await openProgress();
    result = await run(bytes: bytes, confirmedLarge: false);
    if (result case Ok(:final value)
        when value.outcome == PdfImportOutcome.needsSizeConfirmation) {
      closeProgress();
      if (!context.mounted) return;
      final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      if (!await _ask(context, l10n.pdfSendTitle, l10n.pdfLargeBody(mb),
          l10n.pdfSendButton)) {
        return;
      }
      if (!context.mounted) return;
      await openProgress();
      result = await run(bytes: bytes, confirmedLarge: true);
    }
  } finally {
    closeProgress();
  }
  if (!context.mounted) return;

  switch (result) {
    case Ok(:final value):
      switch (value.outcome) {
        case PdfImportOutcome.stored:
          ToastHelper.showSuccess(context, l10n.dataImportSuccess);
          await Navigator.of(context).push(
            SessionReportScreen.route(
              router: MemexRouter(),
              sessionId: value.sessionId,
            ),
          );
        case PdfImportOutcome.noSelectableText:
          ToastHelper.showError(context, l10n.pdfNoText);
        case PdfImportOutcome.notConfirmed:
        case PdfImportOutcome.needsSizeConfirmation:
          break;
      }
    case Error(:final error, :final stackTrace):
      _logger.warning('PDF was not imported: $error', error, stackTrace);
      ToastHelper.showError(
        context,
        error is PdfModelUnsupported
            ? l10n.pdfModelCannotRead
            : l10n.operationFailed(error),
      );
  }
}

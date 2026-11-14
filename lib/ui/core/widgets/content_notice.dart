import 'package:flutter/material.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/utils/user_storage.dart';

/// Fixed caption in the capture input: do not record client, account or bank
/// documents (F11-06). Plain text, no dialog and no extra tap.
class ContentNoticeCaption extends StatelessWidget {
  const ContentNoticeCaption({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      UserStorage.l10n.contentNoticeCaption,
      key: const ValueKey('content-notice-caption'),
      style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
    );
  }
}

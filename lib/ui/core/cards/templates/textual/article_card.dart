import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:memex/ui/core/cards/ui/glass_card.dart';
import 'package:memex/ui/core/widgets/local_image.dart';
import 'package:memex/ui/core/themes/app_colors.dart';

class ArticleCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onTap;

  const ArticleCard({super.key, required this.data, this.onTap});

  @override
  Widget build(BuildContext context) {
    final String title = data['title'] ?? 'Article';
    final String body = data['body'] ?? '';
    final String? imageUrl = data['image_url'];

    return GlassCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Cover Image (if available) - Full width
          if (imageUrl != null && imageUrl.isNotEmpty)
            SizedBox(
              height: 160,
              width: double.infinity,
              child: LocalImage(
                url: imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => Container(color: AppColors.divider),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 2. Title - Headline style
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),

                // 3. Body - Markdown content
                MarkdownBody(
                    data: body, styleSheet: articleMarkdownStyleSheet()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Reading-first Markdown style for long text such as minutes and reports.
///
/// Clear heading steps, one-idea blocks with room between them, amber list
/// markers and a ruled table keep the text scannable (Nielsen Norman Group,
/// "How Users Read on the Web"); 16sp body with 1.55 line height follows the
/// font-size findings of Rello et al., CHI 2016. See docs/EXTRACAO-DOCUMENTOS.md.
MarkdownStyleSheet articleMarkdownStyleSheet() {
  const body = TextStyle(
    fontSize: 16,
    height: 1.55,
    color: AppColors.textSecondary,
  );
  const heading = TextStyle(
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.3,
  );
  return MarkdownStyleSheet(
    p: body,
    pPadding: const EdgeInsets.only(bottom: 4),
    strong: body.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
    em: body.copyWith(fontStyle: FontStyle.italic),
    h1: heading.copyWith(fontSize: 22),
    h1Padding: const EdgeInsets.only(top: 4, bottom: 8),
    h2: heading.copyWith(fontSize: 19),
    h2Padding: const EdgeInsets.only(top: 18, bottom: 6),
    h3: heading.copyWith(fontSize: 16),
    h3Padding: const EdgeInsets.only(top: 12, bottom: 4),
    blockSpacing: 10,
    listIndent: 20,
    listBullet: body.copyWith(color: AppColors.primary),
    listBulletPadding: const EdgeInsets.only(right: 6),
    blockquote: body.copyWith(fontStyle: FontStyle.italic),
    blockquotePadding: const EdgeInsets.only(left: 12),
    blockquoteDecoration: const BoxDecoration(
      border: Border(left: BorderSide(color: AppColors.primary, width: 2)),
    ),
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.divider)),
    ),
    tableHead: body.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
    tableBody: body.copyWith(fontSize: 14, height: 1.4),
    tableBorder: TableBorder.all(color: AppColors.divider, width: 1),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    tableHeadAlign: TextAlign.left,
    code: const TextStyle(
      backgroundColor: AppColors.surface,
      color: AppColors.textPrimary,
      fontFamily: 'monospace',
      fontSize: 14,
    ),
    codeblockDecoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
    ),
  );
}

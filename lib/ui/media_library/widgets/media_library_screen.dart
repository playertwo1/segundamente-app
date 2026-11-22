import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:memex/domain/models/media_library_item.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/media_library/view_models/media_library_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/timeline/asset_header_gallery.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';

/// Aggregated library of local photos, PDFs, and audio files.
class MediaLibraryScreen extends StatefulWidget {
  const MediaLibraryScreen({
    super.key,
    required this.viewModel,
  });

  final MediaLibraryViewModel viewModel;

  @override
  State<MediaLibraryScreen> createState() => _MediaLibraryScreenState();
}

class _MediaLibraryScreenState extends State<MediaLibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    widget.viewModel.load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        widget.viewModel.setSearchQuery('');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final items = vm.items;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            surfaceTintColor: AppColors.background,
            elevation: 0,
            title: _searching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: l10n.mediaLibrarySearchHint,
                      hintStyle:
                          const TextStyle(color: AppColors.textSecondary),
                      border: InputBorder.none,
                    ),
                    onChanged: vm.setSearchQuery,
                  )
                : Text(
                    l10n.mediaLibraryTitle,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            actions: [
              IconButton(
                onPressed: _toggleSearch,
                icon: Icon(
                  _searching ? Icons.close : Icons.search,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              _FilterBar(viewModel: vm),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: vm.load,
                  child: _buildBody(context, vm, items),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    MediaLibraryViewModel vm,
    List<MediaLibraryItem> items,
  ) {
    final l10n = UserStorage.l10n;
    if (vm.isLoading && vm.totalCount == 0) {
      return const Center(child: AgentLogoLoading());
    }

    if (vm.errorMessage != null && vm.totalCount == 0) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                Text(
                  l10n.loadFailed,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: vm.load,
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                vm.totalCount == 0
                    ? l10n.mediaLibraryEmpty
                    : l10n.mediaLibraryNoMatches,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const Divider(color: AppColors.divider, height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return _MediaRow(
          item: item,
          onTap: () => _openItem(context, item),
        );
      },
    );
  }

  void _openItem(BuildContext context, MediaLibraryItem item) {
    switch (item.kind) {
      case MediaLibraryKind.photo:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _MediaPhotoViewer(item: item),
          ),
        );
      case MediaLibraryKind.pdf:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _MediaPdfViewer(item: item),
          ),
        );
      case MediaLibraryKind.audio:
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: AppColors.surface,
          builder: (sheetCtx) => _MediaAudioSheet(item: item),
        );
    }
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.viewModel});

  final MediaLibraryViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    final filters = [
      (MediaLibraryFilter.all, l10n.mediaLibraryFilterAll, viewModel.totalCount),
      (
        MediaLibraryFilter.photo,
        l10n.mediaLibraryFilterPhotos,
        viewModel.photoCount
      ),
      (MediaLibraryFilter.pdf, l10n.mediaLibraryFilterPdfs, viewModel.pdfCount),
      (
        MediaLibraryFilter.audio,
        l10n.mediaLibraryFilterAudios,
        viewModel.audioCount
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          for (final (filter, label, count) in filters) ...[
            ChoiceChip(
              label: Text('$label ($count)'),
              selected: viewModel.filter == filter,
              onSelected: (_) => viewModel.setFilter(filter),
              selectedColor: AppColors.primary.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                color: viewModel.filter == filter
                    ? AppColors.primary
                    : AppColors.textSecondary,
                fontWeight: viewModel.filter == filter
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
              backgroundColor: AppColors.surface,
              side: BorderSide(
                color: viewModel.filter == filter
                    ? AppColors.primary
                    : AppColors.divider,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({
    required this.item,
    required this.onTap,
  });

  final MediaLibraryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = (item.cardTitle ?? '').trim().isNotEmpty
        ? item.cardTitle!
        : item.fileName;
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(item.modifiedAt);
    final sizeStr = _formatBytes(item.sizeBytes);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      onTap: onTap,
      leading: _buildLeading(),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        '$dateStr · $sizeStr',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _buildLeading() {
    const size = 48.0;
    if (item.kind == MediaLibraryKind.photo) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(item.filePath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _iconBox(Icons.image_outlined),
        ),
      );
    }
    return _iconBox(
      item.kind == MediaLibraryKind.pdf
          ? Icons.picture_as_pdf_outlined
          : Icons.audiotrack_outlined,
    );
  }

  Widget _iconBox(IconData icon) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Icon(icon, color: AppColors.primary),
    );
  }
}

class _MediaPhotoViewer extends StatelessWidget {
  const _MediaPhotoViewer({required this.item});

  final MediaLibraryItem item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _viewerAppBar(context, item, dark: true),
      body: PhotoView(
        imageProvider: FileImage(File(item.filePath)),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 3,
      ),
    );
  }
}

class _MediaPdfViewer extends StatelessWidget {
  const _MediaPdfViewer({required this.item});

  final MediaLibraryItem item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _viewerAppBar(context, item, dark: false),
      body: PdfViewer.file(item.filePath),
    );
  }
}

class _MediaAudioSheet extends StatelessWidget {
  const _MediaAudioSheet({required this.item});

  final MediaLibraryItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    final title = (item.cardTitle ?? '').trim().isNotEmpty
        ? item.cardTitle!
        : item.fileName;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            AudioPlayerWidget(url: item.filePath),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => Share.shareXFiles([XFile(item.filePath)]),
                  icon: const Icon(Icons.share_outlined),
                  label: Text(l10n.mediaLibraryShare),
                ),
                if (item.cardId != null) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push(
                        '${AppRoutes.timelineCardDetail}/${item.cardId}',
                      );
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: Text(l10n.mediaLibraryOpenRecord),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

PreferredSizeWidget _viewerAppBar(
  BuildContext context,
  MediaLibraryItem item, {
  required bool dark,
}) {
  final l10n = UserStorage.l10n;
  final title = (item.cardTitle ?? '').trim().isNotEmpty
      ? item.cardTitle!
      : item.fileName;

  return AppBar(
    backgroundColor: dark ? Colors.black : AppColors.background,
    foregroundColor: dark ? Colors.white : AppColors.textPrimary,
    title: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    actions: [
      if (item.cardId != null)
        IconButton(
          tooltip: l10n.mediaLibraryOpenRecord,
          icon: const Icon(Icons.open_in_new),
          onPressed: () =>
              context.push('${AppRoutes.timelineCardDetail}/${item.cardId}'),
        ),
      IconButton(
        tooltip: l10n.mediaLibraryShare,
        icon: const Icon(Icons.share_outlined),
        onPressed: () => Share.shareXFiles([XFile(item.filePath)]),
      ),
    ],
  );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

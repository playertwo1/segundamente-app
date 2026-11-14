import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:memex/data/services/floating_chat_service.dart';
import 'package:memex/domain/models/floating_chat_mode.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/core/widgets/content_notice.dart';
import 'package:memex/ui/floating_chat/floating_chat_host.dart';
import 'package:memex/ui/floating_chat/view_models/floating_capture_viewmodel.dart';
import 'package:memex/utils/user_storage.dart';

/// The compact capture sheet over the home screen (F15-04): Anotar, Foto or
/// Colar. Only the Guardar tap saves; Fechar, the backdrop and system back
/// discard. Closing returns to the screen below, as the chat sheet does.
class FloatingCaptureScreen extends StatefulWidget {
  const FloatingCaptureScreen({
    super.key,
    required this.viewModel,
    this.service,
  });

  final FloatingCaptureViewModel viewModel;
  final FloatingChatService? service;

  @override
  State<FloatingCaptureScreen> createState() => _FloatingCaptureScreenState();
}

class _FloatingCaptureScreenState extends State<FloatingCaptureScreen> {
  final TextEditingController _text = TextEditingController();

  FloatingCaptureViewModel get _vm => widget.viewModel;

  FloatingChatService get _service =>
      widget.service ?? FloatingChatService.instance;

  @override
  void initState() {
    super.initState();
    // Colar reads the clipboard once the sheet is on screen (it has focus).
    if (_vm.mode == FloatingChatMode.paste) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _paste());
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final text = await _vm.paste();
    if (text != null && mounted) _text.text = text;
  }

  Future<void> _save() async {
    final saved = await _vm.save(_text.text);
    if (saved && mounted) await closeFloatingSheet(context, _service);
  }

  Future<void> _close() => closeFloatingSheet(context, _service);

  String _title() {
    final l10n = UserStorage.l10n;
    return switch (_vm.mode) {
      FloatingChatMode.photo => l10n.floatingCapturePhotoTitle,
      FloatingChatMode.paste => l10n.floatingCapturePasteTitle,
      _ => l10n.floatingCaptureNoteTitle,
    };
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _close,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {},
              child: _buildSheet(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSheet(BuildContext context) {
    final l10n = UserStorage.l10n;
    return ListenableBuilder(
      listenable: Listenable.merge([_vm, _text]),
      builder: (context, _) {
        final canSave = _vm.canSave(_text.text) && !_vm.saving;
        return Material(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _title(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_vm.mode == FloatingChatMode.photo && _vm.image == null)
                    _buildPhotoChoice(),
                  if (_vm.image != null) _buildImagePreview(_vm.image!),
                  if (_vm.mode != FloatingChatMode.photo ||
                      _vm.image != null) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _text,
                      autofocus: _vm.mode == FloatingChatMode.note,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: _vm.mode == FloatingChatMode.photo
                            ? l10n.floatingCapturePhotoTextHint
                            : l10n.floatingCaptureTextHint,
                      ),
                    ),
                  ],
                  if (_vm.clipboardEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.floatingCapturePasteEmpty,
                      style: const TextStyle(color: AppColors.warning),
                    ),
                  ],
                  if (_vm.saveFailed) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.floatingCaptureSaveFailed,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const ContentNoticeCaption(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(onPressed: _close, child: Text(l10n.close)),
                      const Spacer(),
                      FilledButton(
                        onPressed: canSave ? _save : null,
                        child: Text(l10n.floatingCaptureSave),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Foto before a pick: the camera or the gallery, as the attachments do.
  Widget _buildPhotoChoice() {
    final l10n = UserStorage.l10n;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _vm.pickPhoto(ImageSource.camera),
            child: Text(l10n.floatingCaptureCamera),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: () => _vm.pickPhoto(ImageSource.gallery),
            child: Text(l10n.floatingCaptureGallery),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview(XFile image) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        File(image.path),
        height: 160,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox(
          height: 160,
          child: Center(
            child: Icon(Icons.broken_image_outlined,
                color: AppColors.textTertiary),
          ),
        ),
      ),
    );
  }
}

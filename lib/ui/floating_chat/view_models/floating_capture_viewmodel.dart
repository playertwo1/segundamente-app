import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:memex/data/model/chat_events.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/floating_chat_mode.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';

/// The compact capture sheet (F15-04): Anotar, Foto or Colar. Nothing is saved
/// by reading or picking; [save] runs only from the Guardar tap, and it sends
/// the capture through the same super agent path as the Registrar sheet.
class FloatingCaptureViewModel extends ChangeNotifier {
  FloatingCaptureViewModel({
    required MemexRouter router,
    required this.mode,
    Future<String?> Function()? readClipboard,
    Future<XFile?> Function(ImageSource source)? pickImage,
    Future<String?> Function()? currentSessionId,
  })  : _router = router,
        _readClipboard = readClipboard ?? _systemClipboardText,
        _pickImage = pickImage ?? _systemPickImage,
        _sessionIdOverride = currentSessionId;

  static final _logger = getLogger('FloatingCapture');

  final FloatingChatMode mode;
  final MemexRouter _router;
  final Future<String?> Function() _readClipboard;
  final Future<XFile?> Function(ImageSource source) _pickImage;

  /// Test seam for the conversation lookup; null means the Registrar's lookup.
  final Future<String?> Function()? _sessionIdOverride;

  /// The photo to save with the text (Foto), if one was picked.
  XFile? image;

  /// True after Colar found nothing to paste (empty or unreadable clipboard).
  bool clipboardEmpty = false;

  bool saving = false;

  /// True after a Guardar that the super agent did not accept.
  bool saveFailed = false;

  /// Whether Guardar has something to save: text or a photo.
  bool canSave(String text) => text.trim().isNotEmpty || image != null;

  /// Foto: the camera or gallery pick, as the app does for attachments.
  Future<void> pickPhoto(ImageSource source) async {
    final picked = await _pickImage(source);
    if (picked == null) return;
    image = picked;
    notifyListeners();
  }

  /// Removes the picked photo so the user can pick another one or type only.
  void clearImage() {
    if (image == null) return;
    image = null;
    notifyListeners();
  }

  /// Colar: the clipboard text, or null (and [clipboardEmpty] set) when there is none.
  Future<String?> paste() async {
    String? text;
    try {
      text = (await _readClipboard())?.trim();
    } catch (error, stackTrace) {
      _logger.warning('Could not read the clipboard', error, stackTrace);
    }
    clipboardEmpty = text == null || text.isEmpty;
    notifyListeners();
    return clipboardEmpty ? null : text;
  }

  /// Guardar. Returns true when the super agent accepted the capture; the run
  /// keeps going in the background, as a message sent from the chat does.
  Future<bool> save(String text) async {
    final trimmed = text.trim();
    if (saving || !canSave(trimmed)) return false;
    saving = true;
    saveFailed = false;
    notifyListeners();

    final accepted = await _send(trimmed, image);
    saving = false;
    saveFailed = !accepted;
    notifyListeners();
    return accepted;
  }

  /// Resolves on the first event, or at the end of the stream. An error event,
  /// a stream error or a failed session lookup means the capture was not accepted.
  Future<bool> _send(String text, XFile? picked) async {
    final accepted = Completer<bool>();
    void settle(bool value) {
      if (!accepted.isCompleted) accepted.complete(value);
    }

    try {
      final sessionId =
          await (_sessionIdOverride?.call() ?? _latestSessionId());
      _router
          .sendMessage(
            text,
            sessionId: sessionId,
            agentName: 'memex_agent',
            scene: 'super_agent_home',
            images: picked == null ? const [] : [picked],
            imageOriginalFilenames:
                picked == null ? null : {picked.path: picked.name},
          )
          .listen(
            (event) => settle(event is! ChatErrorEvent),
            onError: (Object error, StackTrace stackTrace) {
              _logger.warning('Capture was not accepted', error, stackTrace);
              settle(false);
            },
            onDone: () => settle(true),
          );
      if (picked != null) unawaited(_recordPhotoHash(picked));
    } catch (error, stackTrace) {
      _logger.warning('Capture could not start', error, stackTrace);
      settle(false);
    }
    return accepted.future;
  }

  /// Same hash the chat sheet records for a sent photo, so it is not offered again.
  Future<void> _recordPhotoHash(XFile picked) async {
    try {
      final length = await picked.length();
      final hash = crypto.md5
          .convert(utf8.encode('photo_${picked.name}_$length'))
          .toString();
      await _router.recordProcessedHashes([hash]);
    } catch (error, stackTrace) {
      _logger.warning('Could not record the photo hash', error, stackTrace);
    }
  }

  /// The conversation the Registrar sheet appends to: the latest one, if it still exists.
  Future<String?> _latestSessionId() async {
    final cached = await UserStorage.getLatestSuperAgentHomeSessionId();
    if (cached == null) return null;
    final exists = await _router.chatSessionExists(cached);
    return exists.when(
        onOk: (found) => found ? cached : null, onError: (_, __) => null);
  }

  static Future<String?> _systemClipboardText() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  static Future<XFile?> _systemPickImage(ImageSource source) =>
      ImagePicker().pickImage(source: source, imageQuality: 85);
}

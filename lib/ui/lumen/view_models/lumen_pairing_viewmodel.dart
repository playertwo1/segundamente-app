import 'package:flutter/foundation.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/lumen_pairing_service.dart';
import 'package:memex/domain/models/lumen_pairing.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';

/// ViewModel managing Lumen pairing state, QR/link validation, and revocation.
class LumenPairingViewModel extends ChangeNotifier {
  LumenPairingViewModel({required MemexRouter router}) : _router = router;

  final MemexRouter _router;

  bool _loading = true;
  bool _busy = false;
  LumenPairingStatus? _status;
  String? _errorMessage;
  String? _infoMessage;
  bool _disposed = false;

  bool get loading => _loading;
  bool get busy => _busy;
  LumenPairingStatus? get status => _status;
  String? get errorMessage => _errorMessage;
  String? get infoMessage => _infoMessage;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Loads current pairing state and ensures a stable local `device_id`.
  Future<void> load() async {
    _errorMessage = null;
    _loading = true;
    _notify();
    try {
      (await _router.getLumenPairingStatus()).when(
        onOk: (value) => _status = value,
        onError: (_, __) => _errorMessage = UserStorage.l10n.loadFailed,
      );
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Validates and persists a `coucou://pair?...` link.
  Future<bool> pairFromUri(String raw) async {
    if (_busy) return false;
    _errorMessage = null;
    _infoMessage = null;
    _busy = true;
    _notify();

    var paired = false;
    try {
      (await _router.pairWithLumen(raw)).when(
        onOk: (value) {
          _status = value;
          _infoMessage = UserStorage.l10n.lumenPairingPairedSuccess;
          paired = true;
        },
        onError: (error, _) {
          _errorMessage = error is LumenPairingParseException
              ? UserStorage.l10n.lumenPairingInvalidQrError
              : UserStorage.l10n.unknownError;
        },
      );
    } finally {
      _busy = false;
      _notify();
    }
    return paired;
  }

  /// Revokes the active room on the relay (best-effort) and clears local keys.
  Future<void> unlink() async {
    if (_busy) return;
    _errorMessage = null;
    _infoMessage = null;
    _busy = true;
    _notify();

    try {
      final result = await _router.unlinkLumen();
      await result.when(
        onOk: (res) async {
          final refreshed = await _router.getLumenPairingStatus();
          refreshed.when(
            onOk: (value) => _status = value,
            onError: (_, __) {
              _status = LumenPairingStatus(
                pairing: null,
                deviceId: _status?.deviceId ?? '',
              );
            },
          );
          _infoMessage = res.remoteRevoked
              ? UserStorage.l10n.lumenPairingUnlinkedSuccess
              : UserStorage.l10n.lumenPairingUnlinkedLocalOnlyWarning;
        },
        onError: (_, __) async {
          _errorMessage = UserStorage.l10n.unknownError;
        },
      );
    } finally {
      _busy = false;
      _notify();
    }
  }
}

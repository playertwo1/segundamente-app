import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_pairing.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_service.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_transport.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/esp32/view_models/esp32_board_viewmodel.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Settings screen for the ESP32-S3 board over MQTT (F17-05): link state,
/// pairing by QR or pasted code, forwarded notification apps and "Forget".
/// Never shows the password, the room key or the pairing text.
class Esp32BoardPage extends StatefulWidget {
  const Esp32BoardPage({
    super.key,
    required this.viewModel,
    this.qrScannerBuilder,
  });

  final Esp32BoardViewModel viewModel;

  /// Test seam for the camera. When null, a [MobileScanner] is used.
  final Widget Function(BuildContext context, ValueChanged<String> onDetect)?
      qrScannerBuilder;

  @override
  State<Esp32BoardPage> createState() => _Esp32BoardPageState();
}

class _Esp32BoardPageState extends State<Esp32BoardPage>
    with WidgetsBindingObserver {
  final TextEditingController _pasteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.viewModel.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may have enabled notification access in the Android settings.
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.viewModel.refreshNotificationAccess());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pasteController.dispose();
    widget.viewModel.dispose();
    super.dispose();
  }

  Future<void> _openScanner() async {
    final l10n = UserStorage.l10n;
    var handled = false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (scannerContext) {
          Future<void> handleCode(String code) async {
            if (handled || code.trim().isEmpty) return;
            handled = true;
            if (scannerContext.mounted) {
              Navigator.of(scannerContext).pop();
            }
            if (!mounted) return;
            await widget.viewModel.pairFromCode(code);
          }

          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              title: Text(l10n.esp32ScannerTitle),
              backgroundColor: AppColors.background,
              surfaceTintColor: AppColors.background,
              foregroundColor: AppColors.textPrimary,
            ),
            body: widget.qrScannerBuilder?.call(
                  scannerContext,
                  (code) => unawaited(handleCode(code)),
                ) ??
                MobileScanner(
                  onDetect: (BarcodeCapture capture) {
                    for (final barcode in capture.barcodes) {
                      final raw = barcode.rawValue;
                      if (raw != null && raw.trim().isNotEmpty) {
                        unawaited(handleCode(raw));
                        break;
                      }
                    }
                  },
                ),
          );
        },
      ),
    );
  }

  Future<void> _pairFromPaste() async {
    final paired = await widget.viewModel.pairFromCode(_pasteController.text);
    if (paired && mounted) _pasteController.clear();
  }

  Future<void> _confirmForget() async {
    final l10n = UserStorage.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          l10n.esp32ForgetConfirmTitle,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          l10n.esp32ForgetConfirmBody,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const ValueKey('esp32-forget-confirm-btn'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(l10n.esp32ForgetConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.viewModel.forget();
  }

  String _pairingErrorText(Esp32PairingError error) {
    final l10n = UserStorage.l10n;
    return switch (error) {
      Esp32PairingError.notJson => l10n.esp32PairErrorNotJson,
      Esp32PairingError.wrongType => l10n.esp32PairErrorWrongType,
      Esp32PairingError.unsupportedVersion =>
        l10n.esp32PairErrorUnsupportedVersion,
      Esp32PairingError.badUri => l10n.esp32PairErrorBadUri,
      Esp32PairingError.missingCredentials =>
        l10n.esp32PairErrorMissingCredentials,
      Esp32PairingError.badRoom => l10n.esp32PairErrorBadRoom,
      Esp32PairingError.badKey => l10n.esp32PairErrorBadKey,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    final vm = widget.viewModel;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        title: Text(l10n.esp32BoardTitle),
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (vm.busy) ...<Widget>[
              const LinearProgressIndicator(
                color: AppColors.primary,
                backgroundColor: AppColors.surface,
              ),
              const SizedBox(height: 16),
            ],
            _buildStatusCard(vm),
            const SizedBox(height: 16),
            _buildPairingCard(vm),
            const SizedBox(height: 16),
            _buildNotificationsCard(vm),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) =>
      Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );

  Widget _buildBanner({
    Key? key,
    required String message,
    required Color color,
    required IconData icon,
    Widget? action,
  }) =>
      Container(
        key: key,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: 8),
              action,
            ],
          ],
        ),
      );

  Widget _buildStatusCard(Esp32BoardViewModel vm) {
    final l10n = UserStorage.l10n;
    final linkLabel = switch (vm.link) {
      Esp32MqttLinkState.notPaired => l10n.esp32LinkNotPaired,
      Esp32MqttLinkState.disconnected => l10n.esp32LinkDisconnected,
      Esp32MqttLinkState.connecting => l10n.esp32LinkConnecting,
      Esp32MqttLinkState.connected => l10n.esp32LinkConnected,
    };
    final linkColor = switch (vm.link) {
      Esp32MqttLinkState.connected => AppColors.success,
      Esp32MqttLinkState.connecting => AppColors.warning,
      _ => AppColors.textTertiary,
    };
    return _buildSection(
      title: l10n.esp32SectionStatus,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              vm.link == Esp32MqttLinkState.connected
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              color: linkColor,
            ),
            const SizedBox(width: 8),
            Text(
              linkLabel,
              key: const ValueKey('esp32-link-label'),
              style: const TextStyle(color: AppColors.textPrimary),
            ),
            if (vm.paired) ...<Widget>[
              const SizedBox(width: 16),
              Text(
                vm.boardOnline ? l10n.esp32BoardOnline : l10n.esp32BoardOffline,
                key: const ValueKey('esp32-board-online-label'),
                style: TextStyle(
                  color: vm.boardOnline
                      ? AppColors.success
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
        if (vm.keyRejected) ...<Widget>[
          const SizedBox(height: 12),
          _buildBanner(
            key: const ValueKey('esp32-key-rejected-banner'),
            message: l10n.esp32KeyRejectedWarning,
            color: AppColors.danger,
            icon: Icons.key_off_outlined,
            action: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: const ValueKey('esp32-key-rescan-btn'),
                onPressed: vm.busy ? null : _openScanner,
                child: Text(l10n.esp32ScanQr),
              ),
            ),
          ),
        ],
        if (vm.lastError == Esp32MqttConnectResult.badCredentials) ...<Widget>[
          const SizedBox(height: 12),
          _buildBanner(
            key: const ValueKey('esp32-bad-credentials-banner'),
            message: l10n.esp32BadCredentialsWarning,
            color: AppColors.warning,
            icon: Icons.warning_amber_rounded,
          ),
        ],
        if (vm.paired) ...<Widget>[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ElevatedButton.icon(
                key: const ValueKey('esp32-sync-btn'),
                onPressed: vm.busy ? null : vm.syncNow,
                icon: const Icon(Icons.sync),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                ),
                label: Text(l10n.esp32SyncNow),
              ),
              if (vm.link == Esp32MqttLinkState.disconnected)
                OutlinedButton(
                  key: const ValueKey('esp32-connect-btn'),
                  onPressed: vm.busy ? null : vm.connect,
                  child: Text(l10n.esp32ConnectNow),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildPairingCard(Esp32BoardViewModel vm) {
    final l10n = UserStorage.l10n;
    final pairingError = vm.pairingError;
    return _buildSection(
      title: l10n.esp32SectionPairing,
      children: <Widget>[
        Text(
          vm.paired
              ? l10n.esp32PairingPairedHint
              : l10n.esp32PairingUnpairedHint,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        if (!vm.paired || vm.keyRejected) ...<Widget>[
          FilledButton.icon(
            key: const ValueKey('esp32-scan-qr-btn'),
            onPressed: vm.busy ? null : _openScanner,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(l10n.esp32ScanQr),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('esp32-paste-code-input'),
            controller: _pasteController,
            minLines: 1,
            maxLines: 3,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: l10n.esp32PasteCodeLabel,
              labelStyle: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('esp32-paste-pair-btn'),
            onPressed: vm.busy ? null : _pairFromPaste,
            child: Text(l10n.esp32PairButton),
          ),
          if (pairingError != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _pairingErrorText(pairingError),
              key: const ValueKey('esp32-pairing-error'),
              style: const TextStyle(color: AppColors.danger, height: 1.4),
            ),
          ],
        ] else ...<Widget>[
          OutlinedButton.icon(
            key: const ValueKey('esp32-forget-btn'),
            onPressed: vm.busy ? null : _confirmForget,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
            ),
            icon: const Icon(Icons.link_off),
            label: Text(l10n.esp32ForgetBoard),
          ),
        ],
      ],
    );
  }

  Widget _buildNotificationsCard(Esp32BoardViewModel vm) {
    final l10n = UserStorage.l10n;
    final apps = <String, String>{
      'whatsapp': l10n.esp32NotifAppWhatsapp,
      'call': l10n.esp32NotifAppCall,
      'msg': l10n.esp32NotifAppMessages,
      'calendar': l10n.esp32NotifAppCalendar,
    };
    return _buildSection(
      title: l10n.esp32SectionNotifications,
      children: <Widget>[
        if (!vm.hasNotificationAccess) ...<Widget>[
          Text(
            l10n.esp32NotifAccessHint,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('esp32-notif-access-btn'),
            onPressed: vm.openNotificationAccessSettings,
            child: Text(l10n.esp32EnableNotifAccess),
          ),
          const SizedBox(height: 8),
        ],
        for (final entry in apps.entries)
          SwitchListTile(
            key: ValueKey('esp32-notif-${entry.key}'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              entry.value,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
            value: vm.allowedApps.contains(entry.key),
            activeThumbColor: AppColors.primary,
            onChanged: (val) => vm.toggleAllowedApp(entry.key, val),
          ),
      ],
    );
  }
}

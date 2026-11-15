import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/domain/models/lumen_pairing.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/lumen/view_models/lumen_pairing_viewmodel.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Screen for pairing this device with Lumen Desktop via QR code or link.
class LumenPairingPage extends StatefulWidget {
  const LumenPairingPage({
    super.key,
    required this.viewModel,
    this.qrScannerBuilder,
  });

  final LumenPairingViewModel viewModel;
  final Widget Function(BuildContext context, ValueChanged<String> onDetect)?
      qrScannerBuilder;

  @override
  State<LumenPairingPage> createState() => _LumenPairingPageState();
}

class _LumenPairingPageState extends State<LumenPairingPage> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.load();
  }

  String _devicePrefix(String? deviceId) {
    final trimmed = deviceId?.trim() ?? '';
    if (trimmed.isEmpty) return '—';
    return trimmed.length > 8 ? trimmed.substring(0, 8) : trimmed;
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
            await widget.viewModel.pairFromUri(code);
          }

          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              title: Text(l10n.lumenPairingScannerTitle),
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

  Future<void> _showPasteLinkDialog() async {
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => const _PastePairingLinkDialog(),
    );
    if (raw == null || !mounted) return;
    await widget.viewModel.pairFromUri(raw);
  }

  Future<void> _showRepairOptions() async {
    final l10n = UserStorage.l10n;
    final action = await showModalBottomSheet<_RepairAction>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.qr_code_scanner, color: AppColors.primary),
              title: Text(
                l10n.lumenPairingScanQr,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () => Navigator.of(sheetContext).pop(_RepairAction.scanQr),
            ),
            const Divider(color: AppColors.divider, height: 1),
            ListTile(
              leading: const Icon(Icons.link, color: AppColors.primary),
              title: Text(
                l10n.lumenPairingPasteLink,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_RepairAction.pasteLink),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _RepairAction.scanQr:
        await _openScanner();
      case _RepairAction.pasteLink:
        await _showPasteLinkDialog();
    }
  }

  Future<void> _confirmUnlink() async {
    final l10n = UserStorage.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          l10n.lumenPairingUnlinkConfirmTitle,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          l10n.lumenPairingUnlinkConfirmBody,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const ValueKey('lumen-unlink-confirm-button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(l10n.lumenPairingUnlink),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.viewModel.unlink();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.lumenPairingTitle),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
      ),
      body: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) {
          final vm = widget.viewModel;
          if (vm.loading && vm.status == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.primary),
                    const SizedBox(height: 16),
                    Text(
                      l10n.lumenPairingLoading,
                      style: const TextStyle(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          final status = vm.status;
          final pairing = status?.pairing;
          final devicePrefix = _devicePrefix(status?.deviceId);
          final busy = vm.busy;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (busy) ...[
                const LinearProgressIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.surface,
                ),
                const SizedBox(height: 16),
              ],
              if (vm.errorMessage != null) ...[
                _InlineBanner(
                  message: vm.errorMessage!,
                  color: AppColors.danger,
                  icon: Icons.error_outline,
                ),
                const SizedBox(height: 16),
              ],
              if (vm.infoMessage != null) ...[
                _InlineBanner(
                  message: vm.infoMessage!,
                  color: vm.infoMessage == l10n.lumenPairingUnlinkedLocalOnlyWarning
                      ? AppColors.warning
                      : AppColors.success,
                  icon: vm.infoMessage == l10n.lumenPairingUnlinkedLocalOnlyWarning
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                ),
                const SizedBox(height: 16),
              ],
              if (status == null || !status.isPaired)
                _buildUnpairedCard(devicePrefix)
              else
                _buildPairedCard(pairing!, devicePrefix),
              const SizedBox(height: 20),
              if (status == null || !status.isPaired) ...[
                FilledButton.icon(
                  key: const ValueKey('lumen-scan-qr-button'),
                  onPressed: busy ? null : _openScanner,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(l10n.lumenPairingScanQr),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('lumen-paste-link-button'),
                  onPressed: busy ? null : _showPasteLinkDialog,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.divider),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.link),
                  label: Text(l10n.lumenPairingPasteLink),
                ),
              ] else ...[
                FilledButton.icon(
                  key: const ValueKey('lumen-repair-button'),
                  onPressed: busy ? null : _showRepairOptions,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.lumenPairingRepair),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('lumen-unlink-button'),
                  onPressed: busy ? null : _confirmUnlink,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.link_off),
                  label: Text(l10n.lumenPairingUnlink),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildUnpairedCard(String devicePrefix) {
    final l10n = UserStorage.l10n;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link_off, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.lumenPairingStatusUnpaired,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l10n.lumenPairingStatusHintUnpaired,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(color: AppColors.divider, height: 1),
          ),
          _MetadataRow(
            label: l10n.lumenPairingDeviceIdLabel,
            value: devicePrefix,
          ),
        ],
      ),
    );
  }

  Widget _buildPairedCard(LumenPairing pairing, String devicePrefix) {
    final l10n = UserStorage.l10n;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.devices_outlined, color: AppColors.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.lumenPairingStatusPaired(pairing.name),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(color: AppColors.divider, height: 1),
          ),
          _MetadataRow(
            label: l10n.lumenPairingRelayLabel,
            value: pairing.relayHost,
          ),
          const SizedBox(height: 10),
          _MetadataRow(
            label: l10n.lumenPairingLanHostLabel,
            value: '${pairing.host}:${pairing.port}',
          ),
          const SizedBox(height: 10),
          _MetadataRow(
            label: l10n.lumenPairingDeviceIdLabel,
            value: devicePrefix,
          ),
        ],
      ),
    );
  }
}

enum _RepairAction { scanQr, pasteLink }

class _InlineBanner extends StatelessWidget {
  const _InlineBanner({
    required this.message,
    required this.color,
    required this.icon,
  });

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _PastePairingLinkDialog extends StatefulWidget {
  const _PastePairingLinkDialog();

  @override
  State<_PastePairingLinkDialog> createState() =>
      _PastePairingLinkDialogState();
}

class _PastePairingLinkDialogState extends State<_PastePairingLinkDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        l10n.lumenPairingPasteDialogTitle,
        style: const TextStyle(color: AppColors.textPrimary),
      ),
      content: TextField(
        key: const ValueKey('lumen-paste-input'),
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 3,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: l10n.lumenPairingPasteHint,
          hintStyle: const TextStyle(color: AppColors.textTertiary),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('lumen-paste-confirm-button'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
          ),
          child: Text(l10n.lumenPairingConfirm),
        ),
      ],
    );
  }
}

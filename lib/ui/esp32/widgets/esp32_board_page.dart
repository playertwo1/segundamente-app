import 'package:flutter/material.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/esp32/view_models/esp32_board_viewmodel.dart';

/// Settings screen to pair, sync tasks, filter notifications and configure the
/// ESP32-S3 AMOLED hardware companion over BLE GATT (F16).
class Esp32BoardPage extends StatefulWidget {
  const Esp32BoardPage({super.key, required this.viewModel});

  final Esp32BoardViewModel viewModel;

  @override
  State<Esp32BoardPage> createState() => _Esp32BoardPageState();
}

class _Esp32BoardPageState extends State<Esp32BoardPage> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();

  bool get _isPt =>
      Localizations.maybeLocaleOf(context)?.languageCode == 'pt';

  @override
  void initState() {
    super.initState();
    widget.viewModel.initialize();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _ssidController.dispose();
    _passController.dispose();
    _cityController.dispose();
    widget.viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          _isPt ? 'Placa ESP32-S3 (BLE)' : 'ESP32-S3 Board (BLE)',
        ),
      ),
      body: AnimatedBuilder(
        animation: vm,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _buildConnectionCard(vm),
            const SizedBox(height: 16),
            _buildPairingCard(vm),
            const SizedBox(height: 16),
            _buildTasksCard(vm),
            const SizedBox(height: 16),
            _buildNotificationCard(vm),
            const SizedBox(height: 16),
            _buildConfigCard(vm),
            if (vm.statusMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                vm.statusMessage!,
                key: const ValueKey('esp32-status-text'),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
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

  Widget _buildConnectionCard(Esp32BoardViewModel vm) {
    final statusLabel = vm.connected
        ? (_isPt ? 'Conectado' : 'Connected')
        : (_isPt ? 'Desconectado' : 'Disconnected');
    return _buildSection(
      title: _isPt ? 'Conexão BLE GATT' : 'BLE GATT Connection',
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              vm.connected ? Icons.bluetooth_connected : Icons.bluetooth,
              color: vm.connected ? AppColors.success : AppColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Text(
              statusLabel,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
            const Spacer(),
            ElevatedButton(
              key: const ValueKey('esp32-connect-btn'),
              onPressed: vm.busy
                  ? null
                  : (vm.connected ? vm.disconnect : vm.connect),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    vm.connected ? AppColors.danger : AppColors.primary,
                foregroundColor: AppColors.onPrimary,
              ),
              child: Text(
                vm.connected
                    ? (_isPt ? 'Desconectar' : 'Disconnect')
                    : (_isPt ? 'Conectar' : 'Connect'),
              ),
            ),
          ],
        ),
        if (!vm.hasBlePermissions) ...<Widget>[
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: vm.busy ? null : vm.requestPermissions,
            child: Text(
              _isPt ? 'Conceder permissões Bluetooth' : 'Grant Bluetooth permissions',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPairingCard(Esp32BoardViewModel vm) => _buildSection(
        title: _isPt ? 'Pareamento (PIN 6 dígitos)' : 'Pairing (6-digit PIN)',
        children: <Widget>[
          Text(
            vm.paired
                ? (_isPt
                    ? 'Dispositivo pareado com chave HMAC.'
                    : 'Device paired with HMAC key.')
                : (_isPt
                    ? 'Toque em "Gerar código" e digite o PIN exibido na placa.'
                    : 'Tap "Request PIN" and enter the 6-digit code shown on the board.'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (!vm.paired) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const ValueKey('esp32-pair-code-input'),
                    controller: _codeController,
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: _isPt ? 'PIN 6 dígitos' : '6-digit PIN',
                      hintStyle: const TextStyle(color: AppColors.textTertiary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const ValueKey('esp32-pair-start-btn'),
                  onPressed: vm.busy ? null : vm.startPairing,
                  child: Text(_isPt ? 'Gerar' : 'Request'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  key: const ValueKey('esp32-pair-confirm-btn'),
                  onPressed: vm.busy
                      ? null
                      : () => vm.confirmPairing(_codeController.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                  ),
                  child: Text(_isPt ? 'Confirmar' : 'Confirm'),
                ),
              ],
            ),
          ] else ...<Widget>[
            OutlinedButton.icon(
              key: const ValueKey('esp32-revoke-btn'),
              onPressed: vm.busy ? null : vm.revokePairing,
              icon: const Icon(Icons.link_off, color: AppColors.danger),
              label: Text(
                _isPt ? 'Revogar pareamento' : 'Revoke pairing',
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          ],
        ],
      );

  Widget _buildTasksCard(Esp32BoardViewModel vm) => _buildSection(
        title: _isPt ? 'Sincronização de Tarefas' : 'Task Sync',
        children: <Widget>[
          Text(
            _isPt
                ? 'Na fila offline: ${vm.pendingTasksCount} • Último retorno: ${vm.lastSyncedRemoteCount}'
                : 'Offline queue: ${vm.pendingTasksCount} • Last pulled: ${vm.lastSyncedRemoteCount}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            key: const ValueKey('esp32-sync-tasks-btn'),
            onPressed: vm.busy ? null : vm.syncTasks,
            icon: const Icon(Icons.sync),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
            label: Text(_isPt ? 'Sincronizar agora' : 'Sync now'),
          ),
        ],
      );

  Widget _buildNotificationCard(Esp32BoardViewModel vm) {
    final labels = <String, String>{
      'whatsapp': 'WhatsApp',
      'call': _isPt ? 'Chamadas' : 'Calls',
      'msg': _isPt ? 'Mensagens (SMS)' : 'Messages (SMS)',
      'calendar': _isPt ? 'Agenda / Calendário' : 'Calendar',
    };
    return _buildSection(
      title: _isPt ? 'Notificações encaminhadas' : 'Forwarded Notifications',
      children: <Widget>[
        if (!vm.hasNotificationAccess) ...<Widget>[
          OutlinedButton(
            key: const ValueKey('esp32-notif-access-btn'),
            onPressed: vm.openNotificationAccessSettings,
            child: Text(
              _isPt
                  ? 'Habilitar acesso a notificações'
                  : 'Enable notification access',
            ),
          ),
          const SizedBox(height: 8),
        ],
        for (final entry in labels.entries)
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

  Widget _buildConfigCard(Esp32BoardViewModel vm) => _buildSection(
        title: _isPt ? 'Configuração da Placa' : 'Board Settings',
        children: <Widget>[
          TextField(
            key: const ValueKey('esp32-ssid-input'),
            controller: _ssidController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Wi-Fi SSID',
              labelStyle: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('esp32-pass-input'),
            controller: _passController,
            obscureText: true,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: _isPt ? 'Senha Wi-Fi' : 'Wi-Fi Password',
              labelStyle: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('esp32-city-input'),
            controller: _cityController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: _isPt ? 'Cidade do clima' : 'Weather City',
              labelStyle: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _isPt ? 'Personagem' : 'Character',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (var i = 0; i < kEsp32CharacterNames.length; i++)
                ChoiceChip(
                  key: ValueKey('esp32-char-$i'),
                  label: Text(kEsp32CharacterNames[i]),
                  selected: vm.selectedCharIdx == i,
                  onSelected: (_) => vm.selectCharacter(i),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const ValueKey('esp32-save-config-btn'),
            onPressed: vm.busy
                ? null
                : () => vm.sendConfig(
                      ssid: _ssidController.text,
                      pass: _passController.text,
                      city: _cityController.text,
                    ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
            child: Text(_isPt ? 'Enviar configuração' : 'Send settings'),
          ),
        ],
      );
}

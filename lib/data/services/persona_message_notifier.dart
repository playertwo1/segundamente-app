import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:memex/utils/logger.dart';

/// Shows a system notification when a persona starts contact on her own.
/// The plugin is already initialized by TodoAlarmService (same singleton).
class PersonaMessageNotifier {
  PersonaMessageNotifier._();
  static final PersonaMessageNotifier instance = PersonaMessageNotifier._();

  static const channelId = 'persona_messages';

  final _plugin = FlutterLocalNotificationsPlugin();
  final _logger = getLogger('PersonaMessageNotifier');

  Future<void> notify({
    required String characterId,
    required String characterName,
    required String body,
  }) async {
    if (!Platform.isAndroid) return;
    // The chat already shows the message when the app is in front.
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return;
    }
    try {
      await _plugin.show(
        id: 2000000000 + characterId.hashCode % 100000000,
        title: characterName,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            'Persona messages',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
          ),
        ),
        payload: 'persona:$characterId',
      );
    } catch (e, st) {
      _logger.warning('Persona notification failed', e, st);
    }
  }
}

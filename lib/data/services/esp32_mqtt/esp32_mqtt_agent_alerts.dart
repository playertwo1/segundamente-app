import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_crypto.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

const String kEsp32AgentRequestTopic = 'pc/agentes/pedido';
const String kEsp32AgentDecisionTopic = 'pc/agentes/decisao';
const String kEsp32AgentStatusTopic = 'pc/agentes/status';

/// Notification payload prefix. Carries only the request id, never the text.
const String kEsp32AgentPayloadPrefix = 'esp32Agent:';

/// Age limit for `waiting`/`error` jobs to still count as active (PROTOCOLO.md).
const int kEsp32AgentActiveWindowMs = 120000;

/// A pending action tapped before the matching request arrived (cold start)
/// is dropped after this long.
const Duration kEsp32AgentPendingActionTtl = Duration(seconds: 60);

enum Esp32AgentVerdict { approve, deny, terminal }

/// Display name of a provider id from the protocol.
String esp32AgentProviderLabel(String provider) => switch (provider) {
      'claude' => 'Claude',
      'codex' => 'Codex',
      _ => provider,
    };

enum Esp32AgentDecisionResult {
  published,
  noRequest,
  expired,
  notAllowed,
  offline,
}

/// Pending request published by the Lumen in `pc/agentes/pedido` (D-083).
class Esp32AgentRequest {
  const Esp32AgentRequest({
    required this.requestId,
    required this.provider,
    required this.kind,
    required this.project,
    required this.expiresAt,
    required this.viewSha256,
    required this.canApprove,
    required this.title,
    required this.subtitle,
    required this.prompt,
  });

  final String requestId;

  /// `claude` or `codex`.
  final String provider;

  /// `question` or `permission`.
  final String kind;
  final String project;

  /// Unix seconds.
  final int expiresAt;
  final String viewSha256;
  final bool canApprove;
  final String title;
  final String subtitle;
  final String prompt;

  bool isExpiredAt(DateTime now) =>
      now.millisecondsSinceEpoch ~/ 1000 >= expiresAt;

  String get providerLabel => esp32AgentProviderLabel(provider);

  /// Returns null when a required field is missing or has the wrong type.
  static Esp32AgentRequest? tryParse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final map = decoded;
    final requestId = map['request_id'];
    final provider = map['provider'];
    final expiresAt = map['expires_at'];
    final viewSha256 = map['view_sha256'];
    if (requestId is! String || requestId.isEmpty) return null;
    if (provider is! String || provider.isEmpty) return null;
    if (expiresAt is! num) return null;
    if (viewSha256 is! String || viewSha256.isEmpty) return null;
    String text(String key) {
      final value = map[key];
      return value is String ? value : '';
    }

    return Esp32AgentRequest(
      requestId: requestId,
      provider: provider,
      kind: text('kind'),
      project: text('project'),
      expiresAt: expiresAt.toInt(),
      viewSha256: viewSha256,
      canApprove: map['can_approve'] == true,
      title: text('title'),
      subtitle: text('subtitle'),
      prompt: text('prompt'),
    );
  }
}

/// One job of the agents snapshot (`pc/agentes/status`, v2).
class Esp32AgentJob {
  const Esp32AgentJob({
    required this.provider,
    required this.state,
    required this.project,
    required this.activity,
  });

  final String provider;
  final String state;
  final String project;
  final String activity;
}

/// Active jobs of a v2 snapshot: `working`, or `waiting`/`error` with age up
/// to [kEsp32AgentActiveWindowMs]. Returns null for an unreadable snapshot.
@visibleForTesting
List<Esp32AgentJob>? parseActiveAgentJobs(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } catch (_) {
    return null;
  }
  if (decoded is! Map || decoded['v'] != 2) return null;
  final agents = decoded['agents'];
  if (agents is! Map) return null;
  final active = <Esp32AgentJob>[];
  for (final provider in agents.keys) {
    final entry = agents[provider];
    if (provider is! String || entry is! Map) continue;
    final jobs = entry['jobs'];
    if (jobs is! List) continue;
    for (final job in jobs) {
      if (job is! Map) continue;
      final state = job['state'];
      final age = job['updated_ms'];
      final isActive = state == 'working' ||
          ((state == 'waiting' || state == 'error') &&
              age is num &&
              age <= kEsp32AgentActiveWindowMs);
      if (!isActive) continue;
      final project = job['project'];
      final activity = job['activity'];
      active.add(
        Esp32AgentJob(
          provider: provider,
          state: state as String,
          project: project is String ? project : '',
          activity: activity is String ? activity : '',
        ),
      );
    }
  }
  return active;
}

/// What the system notification shows. Built apart from the plugin so the
/// actions can be tested.
class Esp32AgentAlertContent {
  const Esp32AgentAlertContent({
    required this.title,
    required this.body,
    required this.actions,
    required this.payload,
  });

  factory Esp32AgentAlertContent.forRequest(Esp32AgentRequest request) {
    final l10n = UserStorage.l10n;
    final project =
        request.project.isEmpty ? l10n.esp32AgentUnknownProject : request.project;
    final body = request.title.isNotEmpty ? request.title : request.prompt;
    return Esp32AgentAlertContent(
      title: l10n.esp32AgentNeedsYou(request.providerLabel, project),
      body: body,
      actions: <Esp32AgentVerdict>[
        if (request.canApprove) ...<Esp32AgentVerdict>[
          Esp32AgentVerdict.approve,
          Esp32AgentVerdict.deny,
        ],
        Esp32AgentVerdict.terminal,
      ],
      payload: '$kEsp32AgentPayloadPrefix${request.requestId}',
    );
  }

  final String title;
  final String body;

  /// Order of the notification buttons. Each verdict's name is the action id.
  final List<Esp32AgentVerdict> actions;
  final String payload;
}

/// Seam over the system notification, so tests run without Android.
abstract class Esp32AgentNotifier {
  Future<void> show(Esp32AgentAlertContent content);
  Future<void> cancel();
}

/// Uses the plugin already initialized by `TodoAlarmService`. Taps reach
/// `main.dart`, which hands them to [Esp32MqttAgentAlerts.handleNotificationAction].
class LocalEsp32AgentNotifier implements Esp32AgentNotifier {
  const LocalEsp32AgentNotifier();

  static const String channelId = 'pc_agents';
  static const int notificationId = 1900000001;
  static final _logger = getLogger('Esp32AgentNotifier');

  @override
  Future<void> show(Esp32AgentAlertContent content) async {
    if (!Platform.isAndroid) return;
    final l10n = UserStorage.l10n;
    String label(Esp32AgentVerdict verdict) => switch (verdict) {
          Esp32AgentVerdict.approve => l10n.esp32AgentActionApprove,
          Esp32AgentVerdict.deny => l10n.esp32AgentActionDeny,
          Esp32AgentVerdict.terminal => l10n.esp32AgentActionTerminal,
        };
    try {
      await FlutterLocalNotificationsPlugin().show(
        id: notificationId,
        title: content.title,
        body: content.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            l10n.esp32AgentChannelName,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.status,
            visibility: NotificationVisibility.private,
            autoCancel: false,
            onlyAlertOnce: true,
            actions: <AndroidNotificationAction>[
              for (final verdict in content.actions)
                AndroidNotificationAction(
                  verdict.name,
                  label(verdict),
                  // Runs in the main isolate, where the MQTT link lives.
                  showsUserInterface: true,
                ),
            ],
          ),
        ),
        payload: content.payload,
      );
    } catch (error, stackTrace) {
      _logger.warning('Agent notification failed', error, stackTrace);
    }
  }

  @override
  Future<void> cancel() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterLocalNotificationsPlugin().cancel(id: notificationId);
    } catch (error, stackTrace) {
      _logger.warning('Agent notification cancel failed', error, stackTrace);
    }
  }
}

class _PendingAction {
  const _PendingAction(this.requestId, this.verdict, this.at);

  final String requestId;
  final Esp32AgentVerdict verdict;
  final DateTime at;
}

/// Agent alerts from the PC (F17-08, D-083): shows the pending request from
/// the Lumen as a notification and publishes the user's decision.
///
/// Nothing here logs or stores the request texts. Silence never approves.
class Esp32MqttAgentAlerts {
  Esp32MqttAgentAlerts({
    required Esp32MqttService service,
    Esp32AgentNotifier? notifier,
    DateTime Function()? now,
    Timer Function(Duration, void Function())? timerFactory,
  })  : _service = service,
        _notifier = notifier ?? const LocalEsp32AgentNotifier(),
        _now = now ?? DateTime.now,
        _timerFactory = timerFactory ?? _defaultTimer;

  static final Esp32MqttAgentAlerts instance =
      Esp32MqttAgentAlerts(service: Esp32MqttService.instance);

  static final _logger = getLogger('Esp32MqttAgentAlerts');

  final Esp32MqttService _service;
  final Esp32AgentNotifier _notifier;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _timerFactory;

  final ValueNotifier<List<Esp32AgentJob>> _activeAgents =
      ValueNotifier<List<Esp32AgentJob>>(const <Esp32AgentJob>[]);

  bool _started = false;
  StreamSubscription<Esp32MqttMessage>? _messageSub;
  StreamSubscription<void>? _connectedSub;
  Esp32AgentRequest? _current;
  Timer? _expiryTimer;
  _PendingAction? _pendingAction;
  Future<void> _requestQueue = Future<void>.value();

  /// Request ids already answered from this phone, so the retained copy that
  /// comes back on reconnect does not show the notification again.
  final Set<String> _answered = <String>{};

  /// The request on screen, if any.
  Esp32AgentRequest? get current => _current;

  /// Active jobs from the last snapshot of `pc/agentes/status`.
  ValueListenable<List<Esp32AgentJob>> get activeAgents => _activeAgents;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _messageSub = _service.messages.listen(_onMessage);
    _connectedSub = _service.onConnected.listen((_) => _subscribe());
    if (_service.status.value.link == Esp32MqttLinkState.connected) {
      _subscribe();
    }
  }

  Future<void> stop() async {
    _started = false;
    await _messageSub?.cancel();
    _messageSub = null;
    await _connectedSub?.cancel();
    _connectedSub = null;
    await _clear();
  }

  /// Drops the request, the agents list and the notification ("Esquecer placa").
  Future<void> reset() async {
    _answered.clear();
    _activeAgents.value = const <Esp32AgentJob>[];
    await _clear();
  }

  /// Called with a tap on the notification. A tap on the body (no action id)
  /// only opens the app.
  Future<void> handleNotificationAction(String? actionId, String? payload) async {
    if (actionId == null || payload == null) return;
    if (!payload.startsWith(kEsp32AgentPayloadPrefix)) return;
    final requestId = payload.substring(kEsp32AgentPayloadPrefix.length);
    final verdict = Esp32AgentVerdict.values
        .where((value) => value.name == actionId)
        .firstOrNull;
    if (requestId.isEmpty || verdict == null) return;

    final current = _current;
    if (current == null || current.requestId != requestId) {
      // Cold start: the retained request arrives after connecting.
      _pendingAction = _PendingAction(requestId, verdict, _now());
      return;
    }
    await decide(requestId, verdict);
  }

  /// Publishes the decision for the request on screen. `approve` and `deny`
  /// need `can_approve`; `terminal` is always allowed.
  Future<Esp32AgentDecisionResult> decide(
    String requestId,
    Esp32AgentVerdict verdict,
  ) async {
    final request = _current;
    if (request == null || request.requestId != requestId) {
      return Esp32AgentDecisionResult.noRequest;
    }
    final now = _now();
    if (request.isExpiredAt(now)) {
      await _clear();
      return Esp32AgentDecisionResult.expired;
    }
    if (verdict != Esp32AgentVerdict.terminal && !request.canApprove) {
      return Esp32AgentDecisionResult.notAllowed;
    }
    if (_service.status.value.link != Esp32MqttLinkState.connected) {
      await _service.connect();
    }
    final decision = jsonEncode(<String, Object>{
      'request_id': request.requestId,
      'view_sha256': request.viewSha256,
      'verdict': verdict.name,
      'ts': now.millisecondsSinceEpoch ~/ 1000,
    });
    final sent = await _service.publishEncrypted(
      kEsp32AgentDecisionTopic,
      decision,
    );
    if (!sent) {
      _logger.warning('Agent decision not sent: offline');
      return Esp32AgentDecisionResult.offline;
    }
    _answered.add(request.requestId);
    await _clear();
    return Esp32AgentDecisionResult.published;
  }

  /// Completes after every request message received so far is handled.
  @visibleForTesting
  Future<void> waitForIdle() => _requestQueue;

  void dispose() {
    _expiryTimer?.cancel();
    unawaited(_messageSub?.cancel());
    unawaited(_connectedSub?.cancel());
    _activeAgents.dispose();
  }

  void _subscribe() {
    unawaited(_service.subscribe(kEsp32AgentRequestTopic));
    unawaited(_service.subscribe(kEsp32AgentStatusTopic));
  }

  void _onMessage(Esp32MqttMessage message) {
    if (message.suffix == kEsp32AgentRequestTopic) {
      // Serialized, so a quick replacement never shows the older request.
      _requestQueue = _requestQueue.then(
        (_) => _onRequest(message).catchError(
          (Object error, StackTrace stackTrace) {
            _logger.warning('Agent request failed', error, stackTrace);
          },
        ),
      );
    } else if (message.suffix == kEsp32AgentStatusTopic) {
      _onStatus(message);
    }
  }

  void _onStatus(Esp32MqttMessage message) {
    final text = message.plaintext;
    if (text == null) {
      _activeAgents.value = const <Esp32AgentJob>[];
      return;
    }
    if (message.from != kEsp32FromLumen) return;
    final jobs = parseActiveAgentJobs(text);
    if (jobs == null) {
      _logger.warning('Agents snapshot dropped: unreadable');
      return;
    }
    _activeAgents.value = List<Esp32AgentJob>.unmodifiable(jobs);
  }

  Future<void> _onRequest(Esp32MqttMessage message) async {
    final text = message.plaintext;
    if (text == null) {
      // Lumen cleared the request: answered elsewhere or gone.
      _pendingAction = null;
      await _clear();
      return;
    }
    if (message.from != kEsp32FromLumen) {
      _logger.warning('Agent request dropped: not from the Lumen');
      return;
    }
    final request = Esp32AgentRequest.tryParse(text);
    if (request == null) {
      _logger.warning('Agent request dropped: unreadable');
      return;
    }
    final now = _now();
    if (request.isExpiredAt(now) || _answered.contains(request.requestId)) {
      // The Lumen's pending request is no longer the one on screen.
      await _clear();
      return;
    }
    if (_current?.requestId == request.requestId) {
      // Same request again (retained copy on reconnect): keep it as is.
      _current = request;
      await _applyPendingAction(request);
      return;
    }

    await _clear();
    _current = request;
    final delay = Duration(
      milliseconds: request.expiresAt * 1000 - now.millisecondsSinceEpoch,
    );
    _expiryTimer = _timerFactory(delay, () {
      _expiryTimer = null;
      if (identical(_current, request)) unawaited(_clear());
    });
    if (await _applyPendingAction(request)) return;
    await _notifier.show(Esp32AgentAlertContent.forRequest(request));
  }

  /// Returns true when a tap made before this request arrived was published.
  Future<bool> _applyPendingAction(Esp32AgentRequest request) async {
    final pending = _pendingAction;
    if (pending == null) return false;
    _pendingAction = null;
    if (pending.requestId != request.requestId) return false;
    if (_now().difference(pending.at) > kEsp32AgentPendingActionTtl) {
      return false;
    }
    final result = await decide(request.requestId, pending.verdict);
    return result == Esp32AgentDecisionResult.published;
  }

  Future<void> _clear() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _current = null;
    // Always, so a notification left by a killed process also goes away.
    await _notifier.cancel();
  }

  static Timer _defaultTimer(Duration delay, void Function() callback) =>
      Timer(delay, callback);
}

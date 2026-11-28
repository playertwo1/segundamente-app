import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_agent_alerts.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_crypto.dart';
import 'package:memex/data/services/esp32_mqtt/esp32_mqtt_service.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_esp32_mqtt_transport.dart';

class _FakeNotifier implements Esp32AgentNotifier {
  final List<Esp32AgentAlertContent> shown = <Esp32AgentAlertContent>[];
  int cancels = 0;
  bool visible = false;

  @override
  Future<void> show(Esp32AgentAlertContent content) async {
    shown.add(content);
    visible = true;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    visible = false;
  }
}

const String _kRequestTopic = 'sm/$kFakeRoom/pc/agentes/pedido';
const String _kStatusTopic = 'sm/$kFakeRoom/pc/agentes/status';
const String _kDecisionTopic = 'sm/$kFakeRoom/pc/agentes/decisao';

/// Fixed clock: 2026-11-28 12:00:00 UTC.
final DateTime _t0 = DateTime.utc(2026, 11, 28, 12);
int _secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

Map<String, Object> _request({
  String id = 'req-1',
  bool canApprove = true,
  int expiresIn = 120,
  String provider = 'claude',
}) =>
    <String, Object>{
      'request_id': id,
      'provider': provider,
      'kind': 'question',
      'project': 'demo-projeto',
      'expires_at': _secs(_t0) + expiresIn,
      'hold_ms': 0,
      'view_sha256': 'ab' * 32,
      'can_approve': canApprove,
      'title': 'Rodar os testes sintéticos?',
      'subtitle': 'Opção recomendada: sim',
      'prompt': 'Pergunta sintética',
      'options_total': 2,
      'tool': 'AskUserQuestion',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeEsp32MqttTransport transport;
  late FakeEsp32MqttTimers timers;
  late Esp32MqttService service;
  late _FakeNotifier notifier;
  late DateTime now;
  late Esp32MqttAgentAlerts alerts;
  final lumen = Esp32RoomCrypto(kFakeRoomKey, random: Random(3));

  Future<void> inject(String topic, Object? plaintext, {String from = 'lumen'}) async {
    final payload = plaintext == null
        ? Uint8List(0)
        : Uint8List.fromList(
            utf8.encode(lumen.seal(from: from, plaintext: jsonEncode(plaintext))),
          );
    await transport.inject(topic, payload, retained: true);
    await alerts.waitForIdle();
    await flushEvents();
  }

  List<Map<String, dynamic>> decisions() => <Map<String, dynamic>>[
        for (final call in transport.publishes)
          if (call.topic == _kDecisionTopic)
            jsonDecode(lumen.open(call.text, self: kEsp32FromLumen).plaintext!)
                as Map<String, dynamic>,
      ];

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{'language': 'pt'});
    await UserStorage.initL10n();
    transport = FakeEsp32MqttTransport();
    timers = FakeEsp32MqttTimers();
    service = Esp32MqttService(
      transportFactory: () => transport,
      secretStore: MemoryEsp32MqttSecretStore(),
      random: Random(7),
      timerFactory: timers.create,
    );
    notifier = _FakeNotifier();
    now = _t0;
    alerts = Esp32MqttAgentAlerts(
      service: service,
      notifier: notifier,
      now: () => now,
      timerFactory: timers.create,
    );
    await alerts.start();
    expect(await service.pairFromCode(kFakeQrJson), isNull);
    await flushEvents();
  });

  tearDown(() async {
    await alerts.stop();
    alerts.dispose();
    service.dispose();
    await transport.close();
  });

  test('subscribes to the request and status topics on connect', () {
    expect(transport.subscribes, contains(_kRequestTopic));
    expect(transport.subscribes, contains(_kStatusTopic));
  });

  test('a request shows the notification with the project', () async {
    await inject(_kRequestTopic, _request());

    expect(notifier.shown, hasLength(1));
    final content = notifier.shown.single;
    expect(content.title, 'Claude precisa de você em demo-projeto');
    expect(content.body, 'Rodar os testes sintéticos?');
    expect(content.payload, '${kEsp32AgentPayloadPrefix}req-1');
    expect(content.actions, <Esp32AgentVerdict>[
      Esp32AgentVerdict.approve,
      Esp32AgentVerdict.deny,
      Esp32AgentVerdict.terminal,
    ]);
    expect(alerts.current?.requestId, 'req-1');
  });

  test('Approve publishes the right encrypted decision', () async {
    await inject(_kRequestTopic, _request());
    now = _t0.add(const Duration(seconds: 5));

    await alerts.handleNotificationAction(
      'approve',
      '${kEsp32AgentPayloadPrefix}req-1',
    );

    final sent = transport.publishes.where((c) => c.topic == _kDecisionTopic);
    expect(sent, hasLength(1));
    expect(sent.single.retain, isFalse);
    expect(sent.single.text, isNot(contains('req-1')), reason: 'cifrado');
    expect(decisions().single, <String, dynamic>{
      'request_id': 'req-1',
      'view_sha256': 'ab' * 32,
      'verdict': 'approve',
      'ts': _secs(now),
    });
    expect(notifier.visible, isFalse);
    expect(alerts.current, isNull);
  });

  test('Deny and Leave on PC publish their verdicts', () async {
    await inject(_kRequestTopic, _request());
    await alerts.handleNotificationAction('deny', '${kEsp32AgentPayloadPrefix}req-1');
    await inject(_kRequestTopic, _request(id: 'req-2'));
    await alerts.handleNotificationAction(
      'terminal',
      '${kEsp32AgentPayloadPrefix}req-2',
    );

    expect(decisions().map((d) => d['verdict']), <String>['deny', 'terminal']);
  });

  test('without can_approve there is no Approve nor Deny button', () async {
    await inject(_kRequestTopic, _request(canApprove: false));

    expect(notifier.shown.single.actions, <Esp32AgentVerdict>[
      Esp32AgentVerdict.terminal,
    ]);
    expect(
      await alerts.decide('req-1', Esp32AgentVerdict.approve),
      Esp32AgentDecisionResult.notAllowed,
    );
    expect(decisions(), isEmpty);
    expect(
      await alerts.decide('req-1', Esp32AgentVerdict.terminal),
      Esp32AgentDecisionResult.published,
    );
    expect(decisions().single['verdict'], 'terminal');
  });

  test('an expired request shows no notification and no action', () async {
    await inject(_kRequestTopic, _request(expiresIn: -1));

    expect(notifier.shown, isEmpty);
    expect(alerts.current, isNull);
    expect(
      await alerts.decide('req-1', Esp32AgentVerdict.approve),
      Esp32AgentDecisionResult.noRequest,
    );
    expect(decisions(), isEmpty);
  });

  test('the notification goes away when the request expires', () async {
    await inject(_kRequestTopic, _request(expiresIn: 30));
    expect(notifier.visible, isTrue);

    final expiry = timers.active.single;
    expect(expiry.delay, const Duration(seconds: 30));
    now = _t0.add(const Duration(seconds: 30));
    expiry.fire();
    await flushEvents();

    expect(notifier.visible, isFalse);
    expect(alerts.current, isNull);
    await alerts.handleNotificationAction(
      'approve',
      '${kEsp32AgentPayloadPrefix}req-1',
    );
    expect(decisions(), isEmpty);
  });

  test('a decision after the deadline is refused', () async {
    await inject(_kRequestTopic, _request(expiresIn: 30));
    now = _t0.add(const Duration(seconds: 31));

    expect(
      await alerts.decide('req-1', Esp32AgentVerdict.approve),
      Esp32AgentDecisionResult.expired,
    );
    expect(decisions(), isEmpty);
    expect(notifier.visible, isFalse);
  });

  test('an empty payload clears the request', () async {
    await inject(_kRequestTopic, _request());
    await inject(_kRequestTopic, null);

    expect(notifier.visible, isFalse);
    expect(alerts.current, isNull);
    expect(
      await alerts.decide('req-1', Esp32AgentVerdict.approve),
      Esp32AgentDecisionResult.noRequest,
    );
  });

  test('another request_id replaces the notification', () async {
    await inject(_kRequestTopic, _request());
    await inject(_kRequestTopic, _request(id: 'req-2', provider: 'codex'));

    expect(notifier.shown, hasLength(2));
    expect(notifier.shown.last.title, startsWith('Codex'));
    expect(notifier.visible, isTrue);
    expect(alerts.current?.requestId, 'req-2');
    expect(
      await alerts.decide('req-1', Esp32AgentVerdict.approve),
      Esp32AgentDecisionResult.noRequest,
    );
  });

  test('the retained copy of the same request does not notify twice', () async {
    await inject(_kRequestTopic, _request());
    await inject(_kRequestTopic, _request());
    expect(notifier.shown, hasLength(1));
  });

  test('an answered request does not come back on reconnect', () async {
    await inject(_kRequestTopic, _request());
    await alerts.decide('req-1', Esp32AgentVerdict.approve);
    await inject(_kRequestTopic, _request());

    expect(notifier.shown, hasLength(1));
    expect(decisions(), hasLength(1));
  });

  test('a request not sent by the Lumen is ignored', () async {
    await inject(_kRequestTopic, _request(), from: kEsp32FromBoard);
    expect(notifier.shown, isEmpty);
  });

  test('a tap before the request arrives (cold start) is applied once',
      () async {
    await alerts.handleNotificationAction(
      'approve',
      '${kEsp32AgentPayloadPrefix}req-1',
    );
    expect(decisions(), isEmpty);

    await inject(_kRequestTopic, _request());

    expect(decisions().single['verdict'], 'approve');
    expect(notifier.shown, isEmpty);
  });

  test('a tap on the notification body does nothing', () async {
    await inject(_kRequestTopic, _request());
    await alerts.handleNotificationAction(null, '${kEsp32AgentPayloadPrefix}req-1');
    expect(decisions(), isEmpty);
    expect(notifier.visible, isTrue);
  });

  test('offline decision is reported and keeps the request', () async {
    await inject(_kRequestTopic, _request());
    transport.publishSucceeds = false;

    expect(
      await alerts.decide('req-1', Esp32AgentVerdict.approve),
      Esp32AgentDecisionResult.offline,
    );
    expect(alerts.current?.requestId, 'req-1');
  });

  test('status snapshot keeps only active agents', () async {
    await inject(_kStatusTopic, <String, Object>{
      'v': 2,
      'seq': 1,
      'agents': <String, Object>{
        'claude': <String, Object>{
          'active_count': 2,
          'jobs': <Object>[
            <String, Object>{
              'task_id': 'a',
              'state': 'working',
              'project': 'proj-a',
              'activity': 'Edit',
              'updated_ms': 999999,
            },
            <String, Object>{
              'task_id': 'b',
              'state': 'waiting',
              'project': 'proj-b',
              'activity': '',
              'updated_ms': 120000,
            },
            <String, Object>{
              'task_id': 'c',
              'state': 'waiting',
              'project': 'proj-c',
              'activity': '',
              'updated_ms': 120001,
            },
            <String, Object>{
              'task_id': 'd',
              'state': 'done',
              'project': 'proj-d',
              'activity': '',
              'updated_ms': 0,
            },
          ],
        },
        'codex': <String, Object>{
          'active_count': 1,
          'jobs': <Object>[
            <String, Object>{
              'task_id': 'e',
              'state': 'error',
              'project': 'proj-e',
              'activity': '',
              'updated_ms': 1000,
            },
          ],
        },
      },
    });

    expect(
      alerts.activeAgents.value.map((j) => '${j.provider}/${j.project}'),
      <String>['claude/proj-a', 'claude/proj-b', 'codex/proj-e'],
    );

    await inject(_kStatusTopic, null);
    expect(alerts.activeAgents.value, isEmpty);
  });

  test('an empty payload also removes a notification left by a killed process',
      () async {
    notifier.visible = true; // shown before the process died
    await inject(_kRequestTopic, null);
    expect(notifier.visible, isFalse);
  });

  test('reset drops the request and the agents list', () async {
    await inject(_kRequestTopic, _request());
    await alerts.reset();
    expect(notifier.visible, isFalse);
    expect(alerts.current, isNull);
  });
}

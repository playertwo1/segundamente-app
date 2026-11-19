import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/settings/widgets/chat_bubble_setting.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const channel = MethodChannel('com.memexlab.memex/floating_chat');
  const setting = ValueKey('chat-bubble-switch');

  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'pt'});
    await UserStorage.initL10n();
  });

  testWidgets('the settings switch posts and removes the chat bubble',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'showBubble' => 'posted',
        'openBubbleSettings' => null,
        _ => 'off',
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ChatBubbleSetting()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Bolha do chat'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(setting)).value, isFalse);
    await tester.tap(find.byKey(setting));
    await tester.pumpAndSettle();
    expect(find.text(UserStorage.l10n.chatBubblePosted), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(setting)).value, isTrue);

    await tester.tap(find.text(UserStorage.l10n.chatBubbleOpenSettings));
    await tester.pumpAndSettle();
    expect(calls.last.arguments, {'notifications': false});
    await tester.tap(find.byKey(setting));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byKey(setting)).value, isFalse);
    expect(calls.map((call) => call.method), [
      'bubbleStatus',
      'showBubble',
      'openBubbleSettings',
      'hideBubble',
    ]);
  });

  testWidgets('the settings switch is hidden without the Android bridge',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ChatBubbleSetting()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(setting), findsNothing);
  });
}

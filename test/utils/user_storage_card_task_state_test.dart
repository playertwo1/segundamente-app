import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/card_task_state.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('keeps one entry per record and removes it when cleared', () async {
    await UserStorage.setCardTaskState(
      'card-a',
      const CardTaskState(status: CardTaskStatus.added, todoIds: ['t1']),
    );
    await UserStorage.setCardTaskState(
      'card-b',
      const CardTaskState(status: CardTaskStatus.dismissed),
    );

    final a = await UserStorage.getCardTaskState('card-a');
    final b = await UserStorage.getCardTaskState('card-b');
    expect(a?.status, CardTaskStatus.added);
    expect(a?.todoIds, ['t1']);
    expect(b?.status, CardTaskStatus.dismissed);

    await UserStorage.setCardTaskState('card-a', null);

    expect(await UserStorage.getCardTaskState('card-a'), isNull);
    expect(await UserStorage.getCardTaskState('card-b'), isNotNull);
  });

  test('removes the stored key once the last entry is cleared', () async {
    await UserStorage.setCardTaskState(
      'card-a',
      const CardTaskState(status: CardTaskStatus.dismissed),
    );
    await UserStorage.setCardTaskState('card-a', null);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('card_task_states'), isNull);
  });

  test('returns null for a record with no state', () async {
    expect(await UserStorage.getCardTaskState('missing'), isNull);
  });
}

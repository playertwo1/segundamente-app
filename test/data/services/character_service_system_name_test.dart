import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/character_service.dart';

void main() {
  test('the system author (character 0) is named after the app, not Memex',
      () async {
    final character = await CharacterService.instance.getCharacter('u', '0');

    expect(character?.name, 'Segunda Mente');
  });
}

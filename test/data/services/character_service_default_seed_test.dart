import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/character_selection_service.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
    tempRoot = await Directory.systemTemp.createTemp('memex_char_seed_');
    await FileSystemService.init(tempRoot.path);
    await EventBusService.instance.connect();
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('default characters store examples and interest filters separately',
      () async {
    final userId = 'seed_user_${DateTime.now().microsecondsSinceEpoch}';
    final characters = await CharacterService.instance.getAllCharacters(userId);
    final auntie = characters.firstWhere((c) => c.id == 'socio_tecnico');

    expect(auntie.persona, contains('## Voice'));
    expect(auntie.persona, isNot(contains('## Example Dialogue')));
    expect(auntie.persona, isNot(contains('## PKM Interest Filter')));
    expect(auntie.mesExample, isNotNull);
    expect(auntie.mesExample, isNotEmpty);
    expect(auntie.interestFilter, isNotNull);
    expect(auntie.interestFilter, isNotEmpty);
    expect(auntie.firstMessage, isNotNull);
    expect(auntie.postHistoryInstructions, isNotNull);
  });

  test('seed 4 adds the personal characters and retires unedited originals',
      () async {
    final userId = 'migration_user_${DateTime.now().microsecondsSinceEpoch}';
    final charsPath = CharacterService.instance.getCharactersPath(userId);
    await Directory(charsPath).create(recursive: true);
    await File(p.join(charsPath, '.characters_seed_version'))
        .writeAsString('3');
    await File(p.join(charsPath, '3.yaml')).writeAsString(
      '''
name: Tia acolhedora
tags: []
persona: "Parece uma tia familiar que se preocupa se o usuário comeu."
avatar: "18"
enabled: true
''',
    );
    await File(p.join(charsPath, '5.yaml')).writeAsString(
      '''
name: Meu amigo
tags: []
persona: "Escrevi este personagem do meu jeito."
avatar: "5"
enabled: true
''',
    );

    final ids = (await CharacterService.instance.getAllCharacters(userId))
        .map((c) => c.id)
        .toSet();

    expect(ids, isNot(contains('3')));
    expect(ids, contains('5'));
    expect(ids, containsAll(['socio_tecnico', 'amigo_bar', 'curador']));
    expect(ids, contains('facilitador_execucao'));
    expect(ids, isNot(contains('gerente_escopo')));
    expect(ids, isNot(contains('parceiro_foco')));
    expect(ids, hasLength(16));
  });

  test('seed 5 swaps the seed avatar for the bundled portrait only', () async {
    final userId = 'portrait_user_${DateTime.now().microsecondsSinceEpoch}';
    final charsPath = CharacterService.instance.getCharactersPath(userId);
    await Directory(charsPath).create(recursive: true);
    await File(p.join(charsPath, '.characters_seed_version'))
        .writeAsString('4');
    await File(p.join(charsPath, 'curador.yaml')).writeAsString(
      '''
name: Curador
tags: []
persona: "x"
avatar: "curador"
enabled: true
''',
    );
    await File(p.join(charsPath, 'tradutor.yaml')).writeAsString(
      '''
name: Tradutor
tags: []
persona: "x"
avatar: "workspace/_u/_System/media/mine.png"
enabled: true
''',
    );

    final curador =
        await CharacterService.instance.getCharacter(userId, 'curador');
    final tradutor =
        await CharacterService.instance.getCharacter(userId, 'tradutor');

    expect(curador!.avatar, 'asset://characters/curador.png');
    expect(tradutor!.avatar, endsWith('mine.png'));
    expect(tradutor.avatar, isNot(startsWith('asset://')));
  });

  test('every default portrait is a declared asset that exists', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/characters/'));

    for (final data in UserStorage.l10n.defaultCharacters) {
      final avatar = data['avatar'] as String;
      expect(avatar, startsWith('asset://characters/'), reason: avatar);
      final file = File('assets/${avatar.substring('asset://'.length)}');
      expect(file.existsSync(), isTrue, reason: file.path);
    }
  });

  test('new users get exactly the 15 personal characters', () async {
    final userId = 'fresh_user_${DateTime.now().microsecondsSinceEpoch}';
    final ids = (await CharacterService.instance.getAllCharacters(userId))
        .map((c) => c.id)
        .toList();

    expect(ids, hasLength(15));
    expect(ids, isNot(contains('counselor')));
  });

  test('seed 6 fuses default diary into memory and preserves custom personas',
      () async {
    final userId = 'merge_user_${DateTime.now().microsecondsSinceEpoch}';
    final charsPath = CharacterService.instance.getCharactersPath(userId);
    await Directory(charsPath).create(recursive: true);
    await File(p.join(charsPath, '.characters_seed_version'))
        .writeAsString('5');
    await File(p.join(charsPath, 'memoria_projeto.yaml')).writeAsString(
      '''
name: Memória do projeto
tags: []
persona: "Recupera decisões, motivos e tentativas anteriores dos registros."
avatar: "asset://characters/memoria_projeto.png"
enabled: true
''',
    );
    await File(p.join(charsPath, 'diario_bordo.yaml')).writeAsString(
      '''
name: Diário de bordo
tags: []
persona: "Organiza relatos em feito, travado e próximo passo quando solicitado."
avatar: "asset://characters/diario_bordo.png"
enabled: true
''',
    );
    final legacyNote = File(p.join(
      FileSystemService.instance.getCharacterWorkspacePath(
        userId,
        'diario_bordo',
      ),
      'Journal',
      'note.md',
    ));
    await legacyNote.parent.create(recursive: true);
    await legacyNote.writeAsString('registro privado');

    final ids = (await CharacterService.instance.getAllCharacters(userId))
        .map((character) => character.id)
        .toSet();

    expect(
        ids,
        containsAll([
          'memoria_projeto',
          'observador_progresso',
          'escuta_atenta',
        ]));
    expect(ids, isNot(contains('diario_bordo')));
    expect(await legacyNote.readAsString(), 'registro privado');
    expect(
      (await CharacterService.instance.getCharacter(userId, 'memoria_projeto'))!
          .persona,
      anyOf(
        contains('organiza o dia em feito'),
        contains('organizes a day into done'),
      ),
    );

    final customUserId =
        'custom_merge_user_${DateTime.now().microsecondsSinceEpoch}';
    final customPath =
        CharacterService.instance.getCharactersPath(customUserId);
    await Directory(customPath).create(recursive: true);
    await File(p.join(customPath, '.characters_seed_version'))
        .writeAsString('5');
    await File(p.join(customPath, 'memoria_projeto.yaml')).writeAsString(
      '''
name: Minha memória
tags: [pessoal]
persona: "Perfil escrito e ajustado por mim."
avatar: "mine.png"
enabled: true
''',
    );
    await File(p.join(customPath, 'diario_bordo.yaml')).writeAsString(
      '''
name: Diário de bordo
tags: []
persona: "Organiza relatos em feito, travado e próximo passo quando solicitado."
avatar: "asset://characters/diario_bordo.png"
enabled: true
''',
    );

    final customCharacters =
        await CharacterService.instance.getAllCharacters(customUserId);
    final customIds = customCharacters.map((character) => character.id).toSet();

    expect(customIds, contains('memoria_projeto'));
    expect(customIds, isNot(contains('diario_bordo')));
    expect(
        customCharacters.firstWhere((c) => c.id == 'memoria_projeto').persona,
        'Perfil escrito e ajustado por mim.');
  });

  test('resolves imported HEIC avatar paths when loading characters', () async {
    final userId = 'heic_user_${DateTime.now().microsecondsSinceEpoch}';
    final charsPath = CharacterService.instance.getCharactersPath(userId);
    await Directory(charsPath).create(recursive: true);
    const relativeAvatar = 'workspace/_heic_user/_System/media/avatar.heic';
    await File(p.join(charsPath, 'custom.yaml')).writeAsString(
      '''
name: Custom
tags: []
persona: ""
avatar: "$relativeAvatar"
enabled: true
''',
    );

    final character =
        await CharacterService.instance.getCharacter(userId, 'custom');

    expect(character, isNotNull);
    expect(character!.avatar, p.join(tempRoot.path, relativeAvatar));
  });

  test('deleting a character emits a character update event', () async {
    final userId = 'delete_user_${DateTime.now().microsecondsSinceEpoch}';
    await CharacterService.instance.getAllCharacters(userId);
    final messages = <CharacterUpdatedMessage>[];
    void handler(EventBusMessage message) {
      if (message is CharacterUpdatedMessage) messages.add(message);
    }

    EventBusService.instance.addHandler(
      EventBusMessageType.characterUpdated,
      handler,
    );
    addTearDown(() {
      EventBusService.instance.removeHandler(
        EventBusMessageType.characterUpdated,
        handler,
      );
    });

    expect(
      await CharacterService.instance.deleteCharacter(userId, 'socio_tecnico'),
      isTrue,
    );
    await Future<void>.delayed(Duration.zero);

    expect(messages, hasLength(1));
    expect(messages.single.userId, userId);
    expect(messages.single.characterId, 'socio_tecnico');
  });

  test('multi-character routing includes policy and only adds distinct voices',
      () async {
    final userId = 'selection_user_${DateTime.now().microsecondsSinceEpoch}';
    final client = _CapturingTextClient('amigo_bar');

    final selected = await CharacterSelectionService.selectMultipleCharacters(
      userId: userId,
      inputContent: '今天又没睡好，还被项目需求折腾得很烦。',
      factId: '2026/05/29.md#ts_1',
      client: client,
      modelConfig: ModelConfig(model: 'test-model'),
      maxCharacters: 5,
    );

    expect(selected, hasLength(1));
    expect(selected.first.id, 'amigo_bar');
    expect(client.lastPrompt,
        contains('usually select the best-fitting character'));
    expect(
      client.lastPrompt,
      contains('Return no IDs only for a trivial or content-free entry'),
    );
    expect(client.lastPrompt, contains('comment policy:'));
    expect(
      client.lastPrompt,
      anyOf(contains('Pule quando:'), contains('Skip when:')),
    );
    // Profiles with a policy don't repeat their interest filter.
    expect(client.lastPrompt, isNot(contains(' — Foque em')));
    expect(client.lastPrompt, isNot(contains(' — Focus on')));
  });

  test('multi-character selection respects the configured cap', () async {
    final userId = 'selection_cap_${DateTime.now().microsecondsSinceEpoch}';
    final selected = await CharacterSelectionService.selectMultipleCharacters(
      userId: userId,
      inputContent: 'Consegui terminar o teste e o resultado abriu no celular.',
      factId: '2026/05/29.md#ts_selection_cap',
      client: _CapturingTextClient(
        'amigo_bar,observador_progresso,escuta_atenta',
      ),
      modelConfig: ModelConfig(model: 'test-model'),
      maxCharacters: 2,
    );

    expect(
      selected.map((character) => character.id),
      ['amigo_bar', 'observador_progresso'],
    );
  });

  test('Portuguese fatigue and frustration route to matching personas',
      () async {
    final userId = 'affinity_user_${DateTime.now().microsecondsSinceEpoch}';
    final tired = await CharacterSelectionService.selectCharacter(
      userId: userId,
      inputContent: 'Estou exausta, dormi pouco e não consigo pensar.',
      factId: '2026/05/29.md#ts_2',
    );
    final frustrated = await CharacterSelectionService.selectCharacter(
      userId: userId,
      inputContent: 'Estou de saco cheio e irritada com isso.',
      factId: '2026/05/29.md#ts_3',
    );
    final sad = await CharacterSelectionService.selectCharacter(
      userId: userId,
      inputContent: 'Fiquei triste e com saudade depois da conversa.',
      factId: '2026/05/29.md#ts_3b',
    );

    expect(tired?.id, 'guardiao_energia');
    expect(frustrated?.id, 'amigo_bar');
    expect(sad?.id, 'escuta_atenta');
  });

  test('no affinity returns no character unless a primary companion is set',
      () async {
    final userId = 'no_affinity_user_${DateTime.now().microsecondsSinceEpoch}';
    const input = 'xyzzy qwvz';

    expect(
      await CharacterSelectionService.selectCharacter(
        userId: userId,
        inputContent: input,
        factId: '2026/05/29.md#ts_no_match',
      ),
      isNull,
    );

    await CharacterService.instance.setPrimaryCompanion(
      userId,
      'socio_tecnico',
    );
    final fallback = await CharacterSelectionService.selectCharacter(
      userId: userId,
      inputContent: input,
      factId: '2026/05/29.md#ts_primary_fallback',
    );

    expect(fallback?.id, 'socio_tecnico');
  });

  test('a substring inside an unrelated word does not attract a persona',
      () async {
    final userId = 'substring_user_${DateTime.now().microsecondsSinceEpoch}';
    final selected = await CharacterSelectionService.selectCharacter(
      userId: userId,
      inputContent: 'O relatório foi adiado.',
      factId: '2026/05/29.md#ts_substring',
    );

    expect(selected, isNull);
  });

  test('a tie between day-focused personas does not depend on ID order',
      () async {
    final userId = 'affinity_tie_${DateTime.now().microsecondsSinceEpoch}';
    final selected = await CharacterSelectionService.selectCharacter(
      userId: userId,
      inputContent: 'Meu dia foi tranquilo.',
      factId: '2026/05/29.md#ts_affinity_tie',
    );

    expect(selected, isNull);
  });

  test('multi-character selection leaves unmatched entries unanswered',
      () async {
    final userId = 'no_match_multi_${DateTime.now().microsecondsSinceEpoch}';
    final selected = await CharacterSelectionService.selectMultipleCharacters(
      userId: userId,
      inputContent: 'xyzzy qwvz',
      factId: '2026/05/29.md#ts_no_match_multi',
      client: _CapturingTextClient(''),
      modelConfig: ModelConfig(model: 'test-model'),
    );

    expect(selected, isEmpty);

    final failedRoute =
        await CharacterSelectionService.selectMultipleCharacters(
      userId: userId,
      inputContent: 'xyzzy qwvz',
      factId: '2026/05/29.md#ts_failed_no_match',
      client: _CapturingTextClient('')..fail = true,
      modelConfig: ModelConfig(model: 'test-model'),
    );
    expect(failedRoute, isEmpty);

    await CharacterService.instance.setPrimaryCompanion(
      userId,
      'curador',
    );
    final primaryFallback =
        await CharacterSelectionService.selectMultipleCharacters(
      userId: userId,
      inputContent: 'xyzzy qwvz',
      factId: '2026/05/29.md#ts_primary_multi_fallback',
      client: _CapturingTextClient('')..fail = true,
      modelConfig: ModelConfig(model: 'test-model'),
    );
    expect(primaryFallback.single.id, 'curador');
  });

  test('empty LLM route falls back to a clear persona match', () async {
    final userId = 'empty_route_match_${DateTime.now().microsecondsSinceEpoch}';
    final selected = await CharacterSelectionService.selectMultipleCharacters(
      userId: userId,
      inputContent: 'Estou exausta e dormi muito pouco.',
      factId: '2026/05/29.md#ts_empty_route_match',
      client: _CapturingTextClient(''),
      modelConfig: ModelConfig(model: 'test-model'),
    );

    expect(selected.map((character) => character.id), ['guardiao_energia']);
  });

  test('excluded topics in an interest filter do not attract a persona',
      () async {
    final userId =
        'excluded_interest_user_${DateTime.now().microsecondsSinceEpoch}';
    final selected = await CharacterSelectionService.selectCharacter(
      userId: userId,
      inputContent: 'Fui ao hospital hoje.',
      factId: '2026/05/29.md#ts_6',
    );

    expect(selected?.id, 'guardiao_energia');
  });

  test('selection failure chooses a clearly better keyword match', () async {
    final userId = 'fallback_user_${DateTime.now().microsecondsSinceEpoch}';
    final selected = await CharacterSelectionService.selectMultipleCharacters(
      userId: userId,
      inputContent: 'Estou exausta e dormi muito pouco.',
      factId: '2026/05/29.md#ts_4',
      client: _CapturingTextClient('')..fail = true,
      modelConfig: ModelConfig(model: 'test-model'),
    );

    expect(selected.single.id, 'guardiao_energia');
  });

  test('long entry excerpt keeps its ending for persona selection', () async {
    final userId =
        'long_selection_user_${DateTime.now().microsecondsSinceEpoch}';
    final client = _CapturingTextClient('amigo_bar');

    await CharacterSelectionService.selectMultipleCharacters(
      userId: userId,
      inputContent: '${'x' * 700} FINAL_SELECTION_MARKER',
      factId: '2026/05/29.md#ts_5',
      client: client,
      modelConfig: ModelConfig(model: 'test-model'),
    );

    expect(client.lastPrompt, contains('FINAL_SELECTION_MARKER'));
  });
}

class _CapturingTextClient extends LLMClient {
  _CapturingTextClient(this.text);

  final String text;
  String lastPrompt = '';
  bool fail = false;

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    lastPrompt = messages
        .whereType<UserMessage>()
        .expand((message) => message.contents)
        .whereType<TextPart>()
        .map((part) => part.text)
        .join('\n');
    if (fail) throw StateError('selection unavailable');
    return ModelMessage(model: modelConfig.model, textOutput: text);
  }

  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) {
    throw UnimplementedError();
  }
}

import 'dart:math';
import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/comment_settings_service.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/mention_parser.dart';

typedef ReplySelectionCandidate = ({
  CharacterModel character,
  bool forceReply,
});

/// Selects characters to comment on a given input.
///
/// - [selectCharacter]: lightweight keyword-matching for single-character
///   scenarios (reprocess, explicit triggers). No LLM call.
/// - [selectMultipleCharacters]: LLM-based selection for multi-character
///   interaction on new records. One short LLM call decides which characters
///   should participate.
class CharacterSelectionService {
  static final Logger _logger = getLogger('CharacterSelectionService');
  static const double _minimumAffinityMargin = 2;

  // ---------------------------------------------------------------------------
  // Single-character selection (keyword-based, no LLM) — original logic
  // ---------------------------------------------------------------------------

  /// Select the best character for the given input content.
  /// Falls back to the primary companion if no character has a clear match.
  static Future<CharacterModel?> selectCharacter({
    required String userId,
    required String inputContent,
    required String factId,
  }) async {
    final characters = await CharacterService.instance.getAllCharacters(userId);
    final enabled = characters.where((c) => c.enabled).toList();

    if (enabled.isEmpty) return null;
    if (enabled.length == 1) return enabled.first;

    final winner = _bestMatch(enabled, inputContent);
    if (winner != null) {
      _logger.info('Selected ${winner.name} for fact $factId');
      return winner;
    }

    return _primaryCompanion(enabled);
  }

  /// Selects a character for an in-chat voice only when the topic has a clear
  /// affinity. Unlike record comments, chat does not fall back to a companion.
  static Future<CharacterModel?> selectRelevantCharacter({
    required String userId,
    required String inputContent,
  }) async {
    final content = inputContent.trim();
    if (content.isEmpty) return null;
    final characters = await CharacterService.instance.getAllCharacters(userId);
    return _bestMatch(
      characters.where((character) => character.enabled).toList(),
      content,
    );
  }

  /// Score how well a character matches the input content.
  /// Higher is better; uses tags, positive interests and emotional tone.
  static double scoreAffinity(CharacterModel char, String content) {
    final lower = _normalizeAffinityText(content);
    var score = 0.0;

    // 1. Tag matching (tags are the primary signal)
    for (final tag in char.tags) {
      if (_containsAffinityPhrase(lower, tag)) {
        score += 3.0;
      }
    }

    // 2. Extract interest keywords from the dedicated interest filter.
    // Legacy characters may still have this embedded in persona, so keep a
    // fallback for compatibility.
    final interestKeywords = _extractInterestKeywords(
      char.interestFilter?.trim().isNotEmpty == true
          ? char.interestFilter!
          : char.persona,
    );
    for (final keyword in interestKeywords) {
      if (_containsAffinityPhrase(lower, keyword)) {
        score += 2.0;
      }
    }

    // 3. Emotional tone matching
    score += _emotionalAffinity(char, lower);

    return score;
  }

  /// Extract keywords from a character interest filter or legacy persona text.
  static List<String> _extractInterestKeywords(String text) {
    final keywords = <String>[];

    if (!text.contains('\n') && !text.contains('#')) {
      return _tokenizeInterestKeywords(text);
    }

    // Look for "PKM Interest Filter" or "Focus on" sections in legacy
    // personas created before interest_filter was stored separately.
    final filterMatch = RegExp(
      r'(?:PKM Interest Filter|Focus on)[:\s]*(.*?)(?:\n#|\n\n|$)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);

    if (filterMatch != null) {
      final filterText = filterMatch.group(1) ?? '';
      keywords.addAll(_tokenizeInterestKeywords(filterText));
    } else {
      keywords.addAll(_tokenizeInterestKeywords(text));
    }

    return keywords;
  }

  static List<String> _tokenizeInterestKeywords(String text) {
    // Default filters name excluded topics after "Ignore"; those are not matches.
    final focusText = text
        .split(
          RegExp(
            r'\b(?:ignore|do not focus on|não foque em|nao foque em)\b',
            caseSensitive: false,
          ),
        )
        .first;
    return _normalizeAffinityText(focusText)
        .split(' ')
        .where((w) => w.length > 1)
        .where((w) => !_stopWords.contains(w.toLowerCase()))
        .toList();
  }

  static String _normalizeAffinityText(String text) => text
      .toLowerCase()
      .replaceAll('和', ' ')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  static bool _containsAffinityPhrase(String normalizedText, String phrase) {
    final normalizedPhrase = _normalizeAffinityText(phrase);
    return normalizedPhrase.isNotEmpty &&
        (' $normalizedText ').contains(' $normalizedPhrase ');
  }

  static CharacterModel? _bestMatch(
    List<CharacterModel> characters,
    String content,
  ) {
    if (characters.isEmpty) return null;
    final ranked = characters
        .map((character) => (
              character: character,
              score: scoreAffinity(character, content),
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    final runnerUpScore = ranked.length > 1 ? ranked[1].score : 0.0;
    if (ranked.first.score <= 0 ||
        ranked.first.score - runnerUpScore < _minimumAffinityMargin) {
      return null;
    }
    return ranked.first.character;
  }

  static CharacterModel? _primaryCompanion(List<CharacterModel> characters) {
    for (final character in characters) {
      if (character.isPrimaryCompanion) return character;
    }
    return null;
  }

  /// Score emotional affinity between character and content tone.
  static double _emotionalAffinity(CharacterModel char, String lowerContent) {
    final positiveInterests = _extractInterestKeywords(
      char.interestFilter ?? '',
    ).join(' ');
    final charLower =
        '${char.id} ${char.name} ${char.tags.join(' ')} $positiveInterests'
            .toLowerCase();
    var score = 0.0;

    // Health/fatigue signals → caring characters
    if (_matchesAny(lowerContent, _healthSignals)) {
      if (_matchesAny(charLower, [
        'care',
        'health',
        'warmth',
        'energy',
        'guardiao_energia',
        'sono',
        'cansaço',
        'ritmo',
        'saúde',
        '关心',
        '健康',
      ])) {
        score += 4.0;
      }
    }

    // Venting/frustration signals → bestie characters
    if (_matchesAny(lowerContent, _ventingSignals)) {
      if (_matchesAny(charLower, [
        'bestie',
        'venting',
        'company',
        'amigo_bar',
        'informal',
        'humor',
        'desabafo',
        'companhia',
        '闺蜜',
        '吐槽',
      ])) {
        score += 4.0;
      }
    }

    // Reflective/philosophical signals → mentor characters
    if (_matchesAny(lowerContent, _reflectiveSignals)) {
      if (_matchesAny(charLower, [
        'wisdom',
        'mentor',
        'validation',
        '导师',
        '智慧',
      ])) {
        score += 4.0;
      }
    }

    // Explicit emotional signals → attentive listener; retain poetic routing
    // for legacy custom profiles that still use that role.
    if (_matchesAny(lowerContent, _emotionalSignals)) {
      if (_matchesAny(charLower, [
        'escuta_atenta',
        'attentive listener',
        'apoio',
        'support',
        'beauty',
        'nostalgia',
        'distant',
        'poetic',
        '诗意',
        '月光',
      ])) {
        score += 4.0;
      }
    }

    return score;
  }

  static bool _matchesAny(String text, List<String> patterns) {
    final normalizedText = _normalizeAffinityText(text);
    return patterns.any(
      (pattern) => _containsAffinityPhrase(normalizedText, pattern),
    );
  }

  // --- Signal word lists ---

  static const _healthSignals = [
    'tired',
    'exhausted',
    'sick',
    'headache',
    'sleep',
    'insomnia',
    'hospital',
    'doctor',
    'medicine',
    'pain',
    'fever',
    'cold',
    'cansado',
    'cansada',
    'cansaço',
    'exausto',
    'exausta',
    'dorm',
    'sono',
    'insônia',
    'febre',
    'doente',
    'madrugada',
    '累',
    '困',
    '生病',
    '头疼',
    '失眠',
    '医院',
    '吃药',
    '发烧',
    '感冒',
    '加班',
    '熬夜',
    '疲惫',
    '身体',
  ];

  static const _ventingSignals = [
    'angry',
    'annoyed',
    'frustrated',
    'hate',
    'ugh',
    'wtf',
    'unfair',
    'stupid',
    'ridiculous',
    'done with',
    'fed up',
    'pissed',
    'irritado',
    'irritada',
    'frustrado',
    'frustrada',
    'raiva',
    'odeio',
    'injusto',
    'injusta',
    'absurdo',
    'absurda',
    'de saco cheio',
    'que saco',
    'que droga',
    '烦',
    '气死',
    '无语',
    '崩溃',
    '受不了',
    '讨厌',
    '垃圾',
    '傻逼',
    '操',
    '吐了',
    '服了',
    '离谱',
  ];

  static const _reflectiveSignals = [
    'thinking about',
    'wondering',
    'realize',
    'perspective',
    'growth',
    'decision',
    'career',
    'future',
    'meaning',
    'purpose',
    'goal',
    'pensando sobre',
    'refletindo',
    'percebi',
    'decisão',
    'decidir',
    'carreira',
    'futuro',
    'sentido',
    'propósito',
    'objetivo',
    'escolha',
    'rumo',
    '思考',
    '反思',
    '成长',
    '方向',
    '意义',
    '目标',
    '选择',
    '人生',
    '职业',
    '未来',
  ];

  static const _emotionalSignals = [
    'miss',
    'remember',
    'nostalgia',
    'rain',
    'sunset',
    'music',
    'lonely',
    'quiet',
    'dream',
    'memory',
    'beautiful',
    'melancholy',
    'saudade',
    'lembrei',
    'chuva',
    'pôr do sol',
    'música',
    'sozinho',
    'sozinha',
    'silêncio',
    'sonho',
    'memória',
    'tristeza',
    'melancolia',
    '想念',
    '回忆',
    '孤独',
    '安静',
    '梦',
    '月亮',
    '雨',
    '夕阳',
    '音乐',
    '美',
    '忧伤',
    '感慨',
  ];

  static const _stopWords = {
    'the',
    'and',
    'for',
    'that',
    'this',
    'with',
    'from',
    'about',
    'into',
    'like',
    'just',
    'only',
    'also',
    'more',
    'than',
    'when',
    'will',
    'what',
    'which',
    'their',
    'them',
    'they',
    'have',
    'been',
    'focus',
    'ignore',
    'on',
    'to',
    'as',
    'at',
    'of',
    'in',
    'or',
    'by',
    'be',
    'is',
    'unless',
    'based',
    'user',
    'de',
    'do',
    'da',
    'dos',
    'das',
    'em',
    'no',
    'na',
    'nos',
    'nas',
    'para',
    'por',
    'com',
    'que',
    'quando',
    'uma',
    'uns',
    'umas',
    'foco',
    'foque',
    'registros',
    'assuntos',
  };

  // ---------------------------------------------------------------------------
  // Multi-character selection (LLM-based)
  // ---------------------------------------------------------------------------

  /// Use an LLM call to decide which characters should comment on this input.
  /// Returns up to [maxCharacters] (default 15) pertinent characters in the
  /// live group chat, while respecting each persona's comment policy.
  static Future<List<CharacterModel>> selectMultipleCharacters({
    required String userId,
    required String inputContent,
    required String factId,
    required LLMClient client,
    required ModelConfig modelConfig,
    int maxCharacters = CommentSettings.defaultMaxCommentCharacters,
    List<CharacterModel>? excludeCharacters,
  }) async {
    if (maxCharacters <= 0) return [];

    final characters = await CharacterService.instance.getAllCharacters(userId);
    final excludedIds = {
      for (final c in excludeCharacters ?? const <CharacterModel>[]) c.id,
    };
    final enabled = characters
        .where((c) => c.enabled && !excludedIds.contains(c.id))
        .toList();

    if (enabled.isEmpty) return [];
    if (enabled.length == 1 && excludedIds.isEmpty) return [enabled.first];

    // Try LLM-based selection
    try {
      final selected = await _llmSelectCharacters(
        client: client,
        modelConfig: modelConfig,
        characters: enabled,
        inputContent: inputContent,
        maxCharacters: maxCharacters,
      );
      if (selected.isNotEmpty) {
        _logger.info(
            'LLM selected ${selected.length} characters for fact $factId: '
            '${selected.map((c) => c.name).join(', ')}');
        return selected;
      }

      // An empty router answer should not suppress a clear policy/keyword fit.
      if (excludedIds.isNotEmpty) return [];
      final bestMatch = _bestMatch(enabled, inputContent);
      return bestMatch == null ? [] : [bestMatch];
    } catch (e) {
      _logger.warning('LLM character selection failed, falling back: $e');
    }

    if (excludedIds.isNotEmpty) return [];
    // A failed router falls back to a clear match, then the primary companion.
    final fallback =
        _bestMatch(enabled, inputContent) ?? _primaryCompanion(enabled);
    return fallback == null ? [] : [fallback];
  }

  /// Selects personas to respond to a user comment in a thread.
  ///
  /// Priority:
  /// 1. Explicit `@mentions` (including multiple mentions and unique `@first_name`)
  ///    -> all mentioned personas with `forceReply: true`.
  /// 2. Direct reply (`replyToId != null`) -> owner persona of the replied-to
  ///    comment with `forceReply: true`.
  /// 3. Open follow-up user comment -> pertinent personas via LLM routing /
  ///    affinity / recent thread speaker / primary companion, ensuring at least
  ///    the first responder always has `forceReply: true`.
  static Future<List<ReplySelectionCandidate>> selectReplyCharacters({
    required String userId,
    required String postContent,
    required String userComment,
    required List<CardComment> existingComments,
    String? replyToId,
    required bool enableCharacterComment,
    int maxCharacters = CommentSettings.defaultMaxCommentCharacters,
    LLMClient? client,
    ModelConfig? modelConfig,
    List<CharacterModel>? charactersOverride,
  }) async {
    final allCharacters =
        charactersOverride ?? await CharacterService.instance.getAllCharacters(userId);
    if (allCharacters.isEmpty) return const [];

    final enabled = allCharacters.where((c) => c.enabled).toList();
    final safeMax = maxCharacters <= 0 ? 1 : maxCharacters;

    // 1. Multiple or single explicit @mentions (matches @id, @name, unique @first_name)
    final mentionPool = _mentionSearchPool(allCharacters);
    final mentioned = extractAllMentions<CharacterModel>(
      userComment,
      mentionPool,
      idOf: (c) => c.id,
      nameOf: (c) => c.name,
    );
    if (mentioned.isNotEmpty) {
      return mentioned
          .take(safeMax)
          .map((c) => (character: c, forceReply: true))
          .toList(growable: false);
    }

    // 2. Explicit reply-to-comment routing
    if (replyToId != null && replyToId.trim().isNotEmpty) {
      final targetCharId =
          _resolveReplyTargetCharacterId(existingComments, replyToId);
      if (targetCharId != null) {
        final target =
            allCharacters.where((c) => c.id == targetCharId).firstOrNull;
        if (target != null) {
          return [(character: target, forceReply: true)];
        }
      }
    }

    // 3. Open follow-up comment from the user without replyToId or @mention
    final hasPersonaHistory = existingComments.any((c) => c.isAi);
    if (!enableCharacterComment && !hasPersonaHistory) {
      return const [];
    }
    if (enabled.isEmpty) return const [];

    final limit = min(safeMax, enabled.length);
    final combinedContent =
        postContent.trim().isEmpty ? userComment : '$postContent\n$userComment';

    if (client != null && modelConfig != null && enabled.length > 1 && limit > 1) {
      try {
        final llmPicked = await _llmSelectReplyCharacters(
          client: client,
          modelConfig: modelConfig,
          characters: enabled,
          postContent: postContent,
          userComment: userComment,
          existingComments: existingComments,
          maxCharacters: limit,
        );
        if (llmPicked.isNotEmpty) {
          return [
            for (var i = 0; i < llmPicked.length; i++)
              (character: llmPicked[i], forceReply: i == 0),
          ];
        }
      } catch (e) {
        _logger.warning('LLM reply routing failed, using fallback: $e');
      }
    }

    // Deterministic fallback: positive affinity on user comment first -> most recent
    // AI speaker in thread -> best affinity on post+comment / primary / first enabled.
    final rankedUserHits = [
      for (final c in enabled)
        (character: c, score: scoreAffinity(c, userComment)),
    ].where((e) => e.score > 0).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    if (rankedUserHits.isNotEmpty) {
      final pickCount = min(limit, min(rankedUserHits.length, 3));
      return [
        for (var i = 0; i < pickCount; i++)
          (character: rankedUserHits[i].character, forceReply: i == 0),
      ];
    }

    final enabledById = {for (final c in enabled) c.id: c};
    for (final existing in existingComments.reversed) {
      if (existing.isAi && existing.characterId != null) {
        final speaker = enabledById[existing.characterId!];
        if (speaker != null) {
          return [(character: speaker, forceReply: true)];
        }
      }
    }

    final fallback = _bestMatch(enabled, combinedContent) ??
        _primaryCompanion(enabled) ??
        enabled.first;
    return [(character: fallback, forceReply: true)];
  }

  /// Coordinates which remaining personas have a genuine non-repetitive
  /// reaction, counterpoint, question, or complement for the cross-persona wave.
  static Future<List<CharacterModel>> selectGroupFollowupCharacters({
    required List<CharacterModel> candidates,
    required String postContent,
    required List<CardComment> existingComments,
    required LLMClient client,
    required ModelConfig modelConfig,
    required int maxCharacters,
  }) async {
    if (candidates.isEmpty || maxCharacters <= 0) return const [];

    final byId = {for (final c in candidates) c.id: c};
    final charDescriptions = _buildRoutingDescriptions(candidates);
    final recentStart =
        existingComments.length > 12 ? existingComments.length - 12 : 0;
    final threadBuf = StringBuffer();
    for (final c in existingComments.sublist(recentStart)) {
      final speaker = c.isAi
          ? (byId[c.characterId]?.name ?? c.characterId ?? 'Persona')
          : 'Usuário';
      threadBuf.writeln(
        '- [${c.id}] $speaker: ${_selectionInputExcerpt(c.content)}',
      );
    }

    final targetCount = min(maxCharacters, candidates.length);
    final prompt = 'Subagentes/personas candidatas a réplica:\n'
        '$charDescriptions\n'
        'Post original:\n"${_selectionInputExcerpt(postContent)}"\n\n'
        'Conversa atual no grupo:\n$threadBuf\n'
        'Quais personas acima (até $targetCount) têm uma réplica direta, '
        'contraponto, complemento ou pergunta pertinente a um dos comentários acima? '
        'Responda SOMENTE os `id`s ordenados por relevância separados por vírgula '
        '(ou deixe vazio se a discussão já estiver bem fechada).';

    final response = await client.generate(
      [
        SystemMessage(
          'You coordinate a live group chat between persona subagents. Pick up '
          'to $targetCount personas that have a genuine, non-repetitive reaction '
          'to recent comments. Reply only with comma-separated IDs or an empty string.',
        ),
        UserMessage([TextPart(prompt)]),
      ],
      modelConfig: ModelConfig(
        model: modelConfig.model,
        maxTokens: 160,
        extra: modelConfig.extra,
      ),
    );

    final text = response.textOutput;
    if (text == null || text.trim().isEmpty) return const [];
    return _mapIdsToCharacters(text, candidates, maxCharacters);
  }

  /// Prioritizes enabled characters first when deduplicating names, while
  /// keeping disabled characters addressable by explicit `@id` or `@name`.
  static List<CharacterModel> _mentionSearchPool(
    List<CharacterModel> allCharacters,
  ) {
    final enabled = allCharacters.where((c) => c.enabled);
    final disabled = allCharacters.where((c) => !c.enabled);
    return [...enabled, ...disabled];
  }

  static String? _resolveReplyTargetCharacterId(
    List<CardComment> comments,
    String replyToId,
  ) {
    final byId = {for (final c in comments) c.id: c};
    CardComment? current = byId[replyToId];
    final seen = <String>{};
    while (current != null && seen.add(current.id)) {
      if (current.isAi && current.characterId != null) {
        return current.characterId;
      }
      final nextId = current.replyToId;
      if (nextId == null || nextId.isEmpty) break;
      current = byId[nextId];
    }
    return null;
  }

  static Future<List<CharacterModel>> _llmSelectReplyCharacters({
    required LLMClient client,
    required ModelConfig modelConfig,
    required List<CharacterModel> characters,
    required String postContent,
    required String userComment,
    required List<CardComment> existingComments,
    required int maxCharacters,
  }) async {
    final charDescriptions = _buildRoutingDescriptions(characters);
    final participants = <String>[];
    for (final c in existingComments.reversed) {
      final id = c.characterId;
      if (c.isAi && id != null && !participants.contains(id)) {
        participants.add(id);
      }
    }

    final recentStart =
        existingComments.length > 10 ? existingComments.length - 10 : 0;
    final threadBuf = StringBuffer();
    for (final c in existingComments.sublist(recentStart)) {
      final speaker = c.isAi ? (c.characterId ?? 'AI') : 'User';
      threadBuf.writeln(
        '- [${c.id}] $speaker: ${_selectionInputExcerpt(c.content)}',
      );
    }

    final targetCount = min(maxCharacters, characters.length);
    final prompt = 'Personas ativas:\n$charDescriptions\n'
        '${participants.isEmpty ? '' : 'Personas que já participaram neste fio: ${participants.join(', ')}\n\n'}'
        'Registro original:\n"${_selectionInputExcerpt(postContent)}"\n\n'
        '${existingComments.isEmpty ? '' : 'Histórico recente:\n$threadBuf\n'}'
        'Novo comentário aberto do usuário:\n"${_selectionInputExcerpt(userComment)}"\n\n'
        'Escolha de 1 até $targetCount personas pertinentes para responder a essa fala '
        'aberta do usuário no chat em grupo. Dê prioridade a quem já conversava no fio '
        'ou cujo papel/política traz resposta direta e útil.\n'
        'Reply with ONLY comma-separated IDs (e.g. id1,id2). No explanation.';

    final response = await client.generate(
      [
        SystemMessage(
          'You coordinate a live group chat and select which active personas '
          'should reply to an open user comment (up to $targetCount). Always pick '
          'at least 1 relevant persona. Reply with ONLY comma-separated IDs.',
        ),
        UserMessage([TextPart(prompt)]),
      ],
      modelConfig: ModelConfig(
        model: modelConfig.model,
        maxTokens: 200,
        extra: modelConfig.extra,
      ),
    );

    final text = response.textOutput;
    if (text == null || text.trim().isEmpty) return const [];
    return _mapIdsToCharacters(text, characters, maxCharacters);
  }

  /// One-shot LLM call to pick which characters should respond.
  static Future<List<CharacterModel>> _llmSelectCharacters({
    required LLMClient client,
    required ModelConfig modelConfig,
    required List<CharacterModel> characters,
    required String inputContent,
    int maxCharacters = CommentSettings.defaultMaxCommentCharacters,
  }) async {
    final charDescriptions = _buildRoutingDescriptions(characters);
    final truncatedInput = _selectionInputExcerpt(inputContent);

    final targetCount = min(maxCharacters, characters.length);
    final prompt = 'Pick which characters should comment on this user entry.\n'
        'The user allows up to $targetCount character comments in this live group chat. For a substantive entry, usually select the best-fitting character when a natural reply is possible, even if the user did not ask a direct question. Then add every other character, up to the allowance ($targetCount, whether that means 2, 5, or all relevant ones without stopping early), that brings a different and useful angle: the user wants to hear a lively multi-voice discussion. Leave out only a voice that would repeat another or has nothing of its own to say.\n'
        'Follow each character’s comment policy, using its reply occasions as guidance for when it fits. Do not select a character whose policy says to stay quiet. Return no IDs only for a trivial or content-free entry, when a reply would feel intrusive, or when no character has a natural reason to respond.\n'
        'Rank selected characters from strongest fit to weakest fit. Do not include redundant or forced voices.\n\n'
        'Characters:\n$charDescriptions\n'
        'User entry:\n"$truncatedInput"\n\n'
        'Reply with ONLY comma-separated IDs, e.g. id1,id2. Reply with an empty string if none fit. No explanation.';

    final selectionConfig = ModelConfig(
      model: modelConfig.model,
      maxTokens: 256,
      extra: modelConfig.extra,
    );

    final response = await client.generate(
      [
        SystemMessage(
            'You are a character routing assistant for a live group chat. Reply with only comma-separated IDs.'),
        UserMessage([TextPart(prompt)]),
      ],
      modelConfig: selectionConfig,
    );

    final text = response.textOutput;
    if (text == null || text.isEmpty) return [];
    return _mapIdsToCharacters(text, characters, maxCharacters);
  }

  static String _buildRoutingDescriptions(List<CharacterModel> characters) {
    final charDescriptions = StringBuffer();
    for (final c in characters) {
      final tags = c.tags.isNotEmpty ? ' [${c.tags.join(', ')}]' : '';
      // The policy already says when to reply or skip; the interest filter
      // repeats it, so it is sent only for profiles without a policy.
      final policy = _extractCommentPolicy(c.persona);
      final interest = policy.isEmpty && (c.interestFilter ?? '').isNotEmpty
          ? ' — ${c.interestFilter}'
          : '';
      charDescriptions.writeln(
        '- id: "${c.id}", name: "${c.name}"$tags$interest'
        '${policy.isEmpty ? '' : '\n  comment policy: $policy'}',
      );
    }
    return charDescriptions.toString();
  }

  static List<CharacterModel> _mapIdsToCharacters(
    String raw,
    List<CharacterModel> characters,
    int maxCharacters,
  ) {
    final ids = _parseIdList(raw);
    if (ids.isEmpty) return [];

    final selected = <CharacterModel>[];
    for (final id in ids) {
      final foldedId = foldPtAscii(id);
      final match = characters.where(
        (c) =>
            c.id == id ||
            foldPtAscii(c.id) == foldedId ||
            foldPtAscii(c.name) == foldedId,
      );
      if (match.isNotEmpty && !selected.contains(match.first)) {
        selected.add(match.first);
      }
    }
    return selected.take(maxCharacters).toList();
  }

  static String _extractCommentPolicy(String persona) {
    final heading = RegExp(
      r'^\s*##\s*(?:Comment Policy|Política de comentários)\s*$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(persona);
    if (heading == null) return '';
    final body = persona.substring(heading.end);
    final nextHeading = RegExp(r'^\s*##\s+', multiLine: true).firstMatch(body);
    return body.substring(0, nextHeading?.start ?? body.length).trim();
  }

  static String _selectionInputExcerpt(String input) {
    final runeCount = input.runes.length;
    if (runeCount <= 500) return input;
    final beginning = String.fromCharCodes(input.runes.take(350));
    final ending = String.fromCharCodes(input.runes.skip(runeCount - 145));
    return '$beginning\n…\n$ending';
  }

  /// Parse comma-separated IDs from LLM output.
  /// Tolerant of whitespace, quotes, and markdown fences.
  static List<String> _parseIdList(String text) {
    var cleaned = text.trim();
    // Strip markdown code fences if present
    cleaned = cleaned.replaceAll(RegExp(r'^```\w*\n?'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\n?```$'), '');
    cleaned = cleaned.trim();
    // Strip surrounding brackets/quotes if the model wrapped them
    cleaned = cleaned.replaceAll(RegExp(r'[\[\]"' ']'), '');
    // Split by comma, trim each, drop empties
    return cleaned
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}

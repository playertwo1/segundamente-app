import 'package:memex/domain/models/todo_proposal.dart';

/// A task suggestion proposed by a persona waiting for owner confirmation.
///
/// It never writes directly to Todo; it holds a [TodoProposal] that only becomes
/// a [TodoItem] after the owner reviews and confirms it.
class PersonaTaskSuggestion {
  PersonaTaskSuggestion({
    required String id,
    required String characterId,
    required String characterName,
    required String message,
    required this.proposal,
    required String createdAt,
    this.dismissed = false,
  })  : id = id.trim(),
        characterId = characterId.trim(),
        characterName = characterName.trim(),
        message = message.trim(),
        createdAt = createdAt.trim() {
    if (this.id.isEmpty) {
      throw ArgumentError('PersonaTaskSuggestion id must not be empty');
    }
    if (this.characterId.isEmpty) {
      throw ArgumentError(
          'PersonaTaskSuggestion characterId must not be empty');
    }
    if (this.characterName.isEmpty) {
      throw ArgumentError(
          'PersonaTaskSuggestion characterName must not be empty');
    }
    if (this.message.isEmpty) {
      throw ArgumentError('PersonaTaskSuggestion message must not be empty');
    }
    if (this.createdAt.isEmpty) {
      throw ArgumentError('PersonaTaskSuggestion createdAt must not be empty');
    }
    if (DateTime.tryParse(this.createdAt) == null) {
      throw ArgumentError.value(
        createdAt,
        'createdAt',
        'createdAt must be a valid ISO-8601 string',
      );
    }
  }

  final String id;
  final String characterId;
  final String characterName;
  final String message;
  final TodoProposal proposal;
  final String createdAt;
  final bool dismissed;

  PersonaTaskSuggestion copyWith({
    String? id,
    String? characterId,
    String? characterName,
    String? message,
    TodoProposal? proposal,
    String? createdAt,
    bool? dismissed,
  }) =>
      PersonaTaskSuggestion(
        id: id ?? this.id,
        characterId: characterId ?? this.characterId,
        characterName: characterName ?? this.characterName,
        message: message ?? this.message,
        proposal: proposal ?? this.proposal,
        createdAt: createdAt ?? this.createdAt,
        dismissed: dismissed ?? this.dismissed,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'character_id': characterId,
        'character_name': characterName,
        'message': message,
        'proposal': proposal.toJson(),
        'created_at': createdAt,
        'dismissed': dismissed,
      };

  static PersonaTaskSuggestion fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawCharacterId = json['character_id'];
    final rawCharacterName = json['character_name'];
    final rawMessage = json['message'];
    final rawProposal = json['proposal'];
    final rawCreatedAt = json['created_at'];
    final rawDismissed = json['dismissed'];

    if (rawId == null || rawId is! String || rawId.trim().isEmpty) {
      throw const FormatException('id must be a non-empty string');
    }
    if (rawCharacterId == null ||
        rawCharacterId is! String ||
        rawCharacterId.trim().isEmpty) {
      throw const FormatException('character_id must be a non-empty string');
    }
    if (rawCharacterName == null ||
        rawCharacterName is! String ||
        rawCharacterName.trim().isEmpty) {
      throw const FormatException('character_name must be a non-empty string');
    }
    if (rawMessage == null ||
        rawMessage is! String ||
        rawMessage.trim().isEmpty) {
      throw const FormatException('message must be a non-empty string');
    }
    if (rawProposal == null || rawProposal is! Map) {
      throw const FormatException('proposal must be a map');
    }
    if (rawCreatedAt == null ||
        rawCreatedAt is! String ||
        rawCreatedAt.trim().isEmpty) {
      throw const FormatException('created_at must be a non-empty string');
    }
    if (rawDismissed != null && rawDismissed is! bool) {
      throw const FormatException('dismissed must be a boolean');
    }

    try {
      final proposal =
          TodoProposal.fromJson(rawProposal.cast<String, dynamic>());
      return PersonaTaskSuggestion(
        id: rawId,
        characterId: rawCharacterId,
        characterName: rawCharacterName,
        message: rawMessage,
        proposal: proposal,
        createdAt: rawCreatedAt,
        dismissed: rawDismissed as bool? ?? false,
      );
    } on ArgumentError catch (e) {
      throw FormatException('Invalid persona task suggestion: ${e.message}');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersonaTaskSuggestion &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          characterId == other.characterId &&
          characterName == other.characterName &&
          message == other.message &&
          proposal.id == other.proposal.id &&
          createdAt == other.createdAt &&
          dismissed == other.dismissed;

  @override
  int get hashCode => Object.hash(
        id,
        characterId,
        characterName,
        message,
        proposal.id,
        createdAt,
        dismissed,
      );
}

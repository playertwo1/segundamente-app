import 'package:collection/collection.dart';
import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/domain/models/card_props.dart';

typedef CardSubtask = ({String text, bool done});

class CardTaskCandidate {
  const CardTaskCandidate(this.text, {this.subtasks = const []});

  final String text;
  final List<CardSubtask> subtasks;

  @override
  bool operator ==(Object other) =>
      other is CardTaskCandidate &&
      text == other.text &&
      const ListEquality<CardSubtask>().equals(subtasks, other.subtasks);

  @override
  int get hashCode =>
      Object.hash(text, const ListEquality<CardSubtask>().hash(subtasks));
}

/// Most candidates offered for one record.
const int cardTaskMaxCandidates = 10;

const int _maxCandidateLength = 200;

/// Field names (lower case) whose string lists are task candidates.
const Set<String> _listKeys = {
  'items',
  'bullets',
  'points',
  'tasks',
  'todos',
  'ideas',
  'list',
};

const Set<String> _skippedTemplates = {'audio_card'};

const List<String> _skippedPrefixes = [
  'http',
  'fs://',
  'file://',
  '/',
];

/// Bullet, numbered or checklist marker; group 1 is the text after it.
final RegExp _markerPattern = RegExp(
  r'^(?:[-*•–]|\d+[.)])\s+(?:\[[ xX]\](?:\s+|$))?(.*)$',
);

/// Tasks a record suggests: task cards, markdown lines and list-valued fields.
/// Pure: no Flutter, no I/O. Deduped case-insensitively, capped at
/// [cardTaskMaxCandidates].
List<CardTaskCandidate> extractCardTaskCandidates(CardDetailModel detail) {
  final candidates = <CardTaskCandidate>[];
  final seen = <String>{};

  void offer(String raw, {List<CardSubtask> subtasks = const []}) {
    if (candidates.length >= cardTaskMaxCandidates) return;
    final text = _cleanCandidate(raw);
    if (text == null || !seen.add(text.toLowerCase())) return;
    candidates.add(CardTaskCandidate(text, subtasks: subtasks));
  }

  void visit(Object? node) {
    switch (node) {
      case String():
        for (final line in node.split('\n')) {
          final match = _markerPattern.firstMatch(line.trim());
          if (match != null) offer(match.group(1)!);
        }
      case Map():
        node.forEach((key, value) {
          final isTaskList =
              value is List && _listKeys.contains(key.toString().toLowerCase());
          if (isTaskList) {
            for (final element in value) {
              if (element is String) offer(_stripMarker(element));
            }
          } else {
            visit(value);
          }
        });
      case List():
        node.forEach(visit);
    }
  }

  for (final config in detail.uiConfigs) {
    if (config.templateId != 'task') continue;
    final title = config.data['title'];
    if (title is! String) continue;
    final rawSubtasks = config.data['subtasks'];
    final subtasks = <CardSubtask>[
      if (rawSubtasks is List)
        for (final subtask in rawSubtasks)
          if (subtask case {'title': final String title})
            if (_cleanCandidate(title) case final text?)
              (text: text, done: isCardTaskChecked(subtask['completed'])),
    ];
    offer(title, subtasks: List.unmodifiable(subtasks));
  }

  // The original text often repeats the subtasks already on the card.
  seen.addAll(candidates.expand(
    (candidate) =>
        candidate.subtasks.map((subtask) => subtask.text.toLowerCase()),
  ));
  visit(detail.rawContent);
  for (final config in detail.uiConfigs) {
    if (_skippedTemplates.contains(config.templateId)) continue;
    visit(config.data);
  }
  return candidates;
}

String _stripMarker(String element) {
  final trimmed = element.trim();
  return _markerPattern.firstMatch(trimmed)?.group(1) ?? trimmed;
}

/// Trims, drops one trailing `.` or `;`, and rejects empty, too long, or
/// link/path-like text. Returns null when the text is not a task.
String? _cleanCandidate(String raw) {
  var text = raw.trim();
  if (text.endsWith('.') || text.endsWith(';')) {
    text = text.substring(0, text.length - 1).trim();
  }
  if (text.isEmpty || text.length > _maxCandidateLength) return null;
  final lower = text.toLowerCase();
  if (_skippedPrefixes.any((prefix) => lower.startsWith(prefix))) return null;
  return text;
}

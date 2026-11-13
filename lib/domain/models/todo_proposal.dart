enum TodoProposalDateState { unspecified, explicit, ambiguous }

enum TodoProposalTimeState { unspecified, explicit, ambiguous }

/// A task suggestion that becomes a TodoItem only after the owner confirms it.
class TodoProposal {
  TodoProposal({
    required this.id,
    required String title,
    required this.dateState,
    required this.timeState,
    this.dueDate,
    this.datePhrase,
    this.dueTime,
    this.timePhrase,
  }) : title = title.trim() {
    if (id.trim().isEmpty || this.title.isEmpty) {
      throw ArgumentError('Todo proposal needs an id and title');
    }
    if (dateState == TodoProposalDateState.explicit && !_isValidDate(dueDate)) {
      throw ArgumentError.value(dueDate, 'dueDate');
    }
    if (dateState != TodoProposalDateState.explicit && dueDate != null) {
      throw ArgumentError('only an explicit proposal date may have dueDate');
    }
    if (timeState == TodoProposalTimeState.explicit &&
        (!_isValidTime(dueTime) ||
            dateState == TodoProposalDateState.unspecified)) {
      throw ArgumentError.value(dueTime, 'dueTime');
    }
    if (timeState != TodoProposalTimeState.explicit && dueTime != null) {
      throw ArgumentError('only an explicit proposal time may have dueTime');
    }
  }

  final String id;
  final String title;
  final TodoProposalDateState dateState;
  final String? dueDate;
  final String? datePhrase;
  final TodoProposalTimeState timeState;
  final String? dueTime;
  final String? timePhrase;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date_state': dateState.name,
        if (dueDate != null) 'due_date': dueDate,
        if (datePhrase?.trim().isNotEmpty == true)
          'date_phrase': datePhrase!.trim(),
        'time_state': timeState.name,
        if (dueTime != null) 'due_time': dueTime,
        if (timePhrase?.trim().isNotEmpty == true)
          'time_phrase': timePhrase!.trim(),
      };

  static TodoProposal fromJson(Map<String, dynamic> json) {
    TodoProposalDateState parseDateState(Object? value) =>
        TodoProposalDateState.values.firstWhere(
          (state) => state.name == value,
          orElse: () => throw const FormatException('unknown Todo date state'),
        );
    TodoProposalTimeState parseTimeState(Object? value) =>
        TodoProposalTimeState.values.firstWhere(
          (state) => state.name == value,
          orElse: () => throw const FormatException('unknown Todo time state'),
        );

    return TodoProposal(
      id: _requiredText(json['id'], 'id'),
      title: _requiredText(json['title'], 'title'),
      dateState: parseDateState(json['date_state']),
      dueDate: _optionalText(json['due_date']),
      datePhrase: _optionalText(json['date_phrase']),
      timeState: parseTimeState(json['time_state']),
      dueTime: _optionalText(json['due_time']),
      timePhrase: _optionalText(json['time_phrase']),
    );
  }

  static bool _isValidDate(String? value) {
    if (value == null) return false;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return false;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }

  static bool _isValidTime(String? value) =>
      value != null && RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value);

  static String _requiredText(Object? value, String field) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) throw FormatException('Todo proposal has no $field');
    return text;
  }

  static String? _optionalText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

/// How the floating sheet starts (F15-02 chat, F15-04 capture, F15-05 Todo).
///
/// [type] opens an empty conversation with the keyboard up; [talk] opens it
/// already listening. [note], [photo] and [paste] open the compact capture
/// sheet (Anotar, Foto, Colar), which saves only on its Guardar tap. [todoAdd]
/// opens the Todo editor over the home screen; [todoComplete] completes one
/// task and closes without a sheet (its id travels in [FloatingLaunch]). The
/// wire names are what the Android side sends.
enum FloatingChatMode {
  type('type'),
  bubble('bubble'),
  talk('talk'),
  note('note'),
  photo('photo'),
  paste('paste'),
  todoAdd('todo_add'),
  todoComplete('todo_complete');

  const FloatingChatMode(this.wireName);

  final String wireName;

  /// True for the capture sheet (F15-04), false for the chat sheet.
  bool get isCapture =>
      this == FloatingChatMode.note ||
      this == FloatingChatMode.photo ||
      this == FloatingChatMode.paste;

  /// Null for anything other than a known wire name.
  static FloatingChatMode? parse(String? value) {
    for (final mode in values) {
      if (mode.wireName == value) return mode;
    }
    return null;
  }
}

/// A launch from the Android side: a [mode], and for [FloatingChatMode.todoComplete]
/// the id of the task to complete (F15-05). The wire form of that one is
/// `todo_complete:<id>`.
class FloatingLaunch {
  const FloatingLaunch(this.mode, {this.todoId});

  static const todoCompletePrefix = 'todo_complete:';

  final FloatingChatMode mode;
  final String? todoId;

  /// Null for a missing or unknown wire value, and for a completion without an id.
  static FloatingLaunch? parse(String? value) {
    if (value == null) return null;
    if (value.startsWith(todoCompletePrefix)) {
      final id = value.substring(todoCompletePrefix.length).trim();
      return id.isEmpty
          ? null
          : FloatingLaunch(FloatingChatMode.todoComplete, todoId: id);
    }
    final mode = FloatingChatMode.parse(value);
    if (mode == null || mode == FloatingChatMode.todoComplete) return null;
    return FloatingLaunch(mode);
  }

  @override
  bool operator ==(Object other) =>
      other is FloatingLaunch && other.mode == mode && other.todoId == todoId;

  @override
  int get hashCode => Object.hash(mode, todoId);

  @override
  String toString() => 'FloatingLaunch($mode, todoId: $todoId)';
}

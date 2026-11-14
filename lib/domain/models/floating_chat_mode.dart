/// How the floating chat sheet starts (F15-02).
///
/// [type] opens an empty conversation with the keyboard up; [talk] opens it
/// already listening. The wire names are what the Android side sends.
enum FloatingChatMode {
  type('type'),
  talk('talk');

  const FloatingChatMode(this.wireName);

  final String wireName;

  /// Null for anything other than a known wire name.
  static FloatingChatMode? parse(String? value) {
    for (final mode in values) {
      if (mode.wireName == value) return mode;
    }
    return null;
  }
}

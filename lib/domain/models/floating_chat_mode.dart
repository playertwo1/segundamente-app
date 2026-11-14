/// How the floating sheet starts (F15-02 chat, F15-04 capture).
///
/// [type] opens an empty conversation with the keyboard up; [talk] opens it
/// already listening. [note], [photo] and [paste] open the compact capture
/// sheet (Anotar, Foto, Colar), which saves only on its Guardar tap. The wire
/// names are what the Android side sends.
enum FloatingChatMode {
  type('type'),
  talk('talk'),
  note('note'),
  photo('photo'),
  paste('paste');

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

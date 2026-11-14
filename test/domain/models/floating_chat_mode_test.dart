import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/floating_chat_mode.dart';

void main() {
  test('parses every wire name, chat and capture', () {
    expect(FloatingChatMode.parse('type'), FloatingChatMode.type);
    expect(FloatingChatMode.parse('talk'), FloatingChatMode.talk);
    expect(FloatingChatMode.parse('note'), FloatingChatMode.note);
    expect(FloatingChatMode.parse('photo'), FloatingChatMode.photo);
    expect(FloatingChatMode.parse('paste'), FloatingChatMode.paste);
  });

  test('an unknown or missing wire name is not a mode', () {
    expect(FloatingChatMode.parse(null), isNull);
    expect(FloatingChatMode.parse(''), isNull);
    expect(FloatingChatMode.parse('Note'), isNull);
    expect(FloatingChatMode.parse('camera'), isNull);
  });

  test('only note, photo and paste are capture sheets', () {
    expect(FloatingChatMode.type.isCapture, isFalse);
    expect(FloatingChatMode.talk.isCapture, isFalse);
    expect(FloatingChatMode.note.isCapture, isTrue);
    expect(FloatingChatMode.photo.isCapture, isTrue);
    expect(FloatingChatMode.paste.isCapture, isTrue);
  });
}

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

  test('parses the Todo modes (F15-05) and they are not capture sheets', () {
    expect(FloatingChatMode.parse('todo_add'), FloatingChatMode.todoAdd);
    expect(FloatingChatMode.todoAdd.isCapture, isFalse);
    expect(FloatingChatMode.todoComplete.isCapture, isFalse);
  });

  test('a launch carries the task id only for todo_complete:<id>', () {
    expect(FloatingLaunch.parse('talk'),
        const FloatingLaunch(FloatingChatMode.talk));
    expect(FloatingLaunch.parse('todo_add'),
        const FloatingLaunch(FloatingChatMode.todoAdd));
    expect(
      FloatingLaunch.parse('todo_complete:abc-1'),
      const FloatingLaunch(FloatingChatMode.todoComplete, todoId: 'abc-1'),
    );
  });

  test('a completion without an id, or an unknown value, is no launch', () {
    expect(FloatingLaunch.parse('todo_complete:'), isNull);
    expect(FloatingLaunch.parse('todo_complete:   '), isNull);
    expect(FloatingLaunch.parse('todo_complete'), isNull);
    expect(FloatingLaunch.parse('camera'), isNull);
    expect(FloatingLaunch.parse(null), isNull);
  });
}

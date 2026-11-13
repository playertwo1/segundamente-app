import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/todo_repository.dart';
import 'package:memex/data/services/file_system_service.dart';

void main() {
  test('constructs before the filesystem service is initialized', () {
    expect(FileSystemService.isInitialized, isFalse);
    expect(() => TodoRepository(), returnsNormally);
  });
}

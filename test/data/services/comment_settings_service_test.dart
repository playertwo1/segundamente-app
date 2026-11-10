import 'package:memex/data/services/comment_settings_service.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('CommentSettings', () {
    test('defaults to two commenting characters', () {
      expect(const CommentSettings().maxCommentCharacters, 2);
    });

    test('upgrades the previous single-character default', () {
      final settings = CommentSettings.fromYaml({
        'version': 1,
        'max_comment_characters': 1,
      });

      expect(settings.maxCommentCharacters, 2);
    });

    test('preserves an explicit one-character choice in current settings', () {
      final settings = CommentSettings.fromYaml({
        'version': 2,
        'max_comment_characters': 1,
      });

      expect(settings.maxCommentCharacters, 1);
    });

    test('writes the version needed to preserve future user choices', () {
      final yaml = loadYaml(
        const CommentSettings(maxCommentCharacters: 1).toYaml(),
      ) as YamlMap;
      final settings = CommentSettings.fromYaml(yaml);

      expect(yaml['version'], 2);
      expect(settings.maxCommentCharacters, 1);
    });
  });
}

import 'package:memex/data/services/comment_settings_service.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('CommentSettings', () {
    test('defaults to fifteen commenting characters', () {
      expect(const CommentSettings().maxCommentCharacters, 15);
    });

    test('upgrades previous single and two-character defaults to fifteen', () {
      final v1 = CommentSettings.fromYaml({
        'version': 1,
        'max_comment_characters': 1,
      });
      final v2Default = CommentSettings.fromYaml({
        'version': 2,
        'max_comment_characters': 2,
      });

      expect(v1.maxCommentCharacters, 15);
      expect(v2Default.maxCommentCharacters, 15);
    });

    test('preserves an explicit one-character choice in previous or current settings', () {
      final v2Explicit = CommentSettings.fromYaml({
        'version': 2,
        'max_comment_characters': 1,
      });
      final v3Explicit = CommentSettings.fromYaml({
        'version': 3,
        'max_comment_characters': 2,
      });

      expect(v2Explicit.maxCommentCharacters, 1);
      expect(v3Explicit.maxCommentCharacters, 2);
    });

    test('clamps out-of-range values to 1..15', () {
      expect(
        CommentSettings.fromYaml({'version': 3, 'max_comment_characters': 0})
            .maxCommentCharacters,
        1,
      );
      expect(
        CommentSettings.fromYaml({'version': 3, 'max_comment_characters': 99})
            .maxCommentCharacters,
        15,
      );
    });

    test('writes the version needed to preserve future user choices', () {
      final yaml = loadYaml(
        const CommentSettings(maxCommentCharacters: 1).toYaml(),
      ) as YamlMap;
      final settings = CommentSettings.fromYaml(yaml);

      expect(yaml['version'], 3);
      expect(settings.maxCommentCharacters, 1);
    });
  });
}

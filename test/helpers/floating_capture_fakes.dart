import 'package:image_picker/image_picker.dart';
import 'package:memex/data/model/chat_events.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/utils/result.dart';

/// One capture the sheet asked the super agent to take (F15-04).
class SentCapture {
  SentCapture(this.text, this.sessionId, this.images, this.originalFilenames);

  final String text;
  final String? sessionId;
  final List<XFile> images;
  final Map<String, String>? originalFilenames;
}

/// Stands in for [MemexRouter] in the capture tests. It records what the sheet
/// sends; [sendOutcome] decides how the super agent answers.
class FakeCaptureRouter implements MemexRouter {
  final List<SentCapture> sent = [];
  final List<String> recordedHashes = [];

  /// The stream a send returns; the default accepts with one event.
  Stream<ChatEvent> Function() sendOutcome = () => Stream.value(
        ChatAgentStartedEvent('turn-1'),
      );

  @override
  Stream<ChatEvent> sendMessage(
    String message, {
    String? sessionId,
    String? agentName = 'memex_agent',
    String? scene = 'assistant',
    String? sceneId,
    List<Map<String, String>>? refs,
    List<XFile> images = const [],
    Map<String, String>? imageOriginalFilenames,
    List<Map<String, String>> files = const [],
    bool isQuickQuery = false,
    String runMode = 'auto',
  }) {
    sent.add(SentCapture(message, sessionId, images, imageOriginalFilenames));
    return sendOutcome();
  }

  @override
  Future<Result<bool>> chatSessionExists(String sessionId) async =>
      const Ok(true);

  @override
  Future<void> recordProcessedHashes(List<String> hashes) async {
    recordedHashes.addAll(hashes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

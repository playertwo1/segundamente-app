import 'dart:io';

import 'package:memex/agent/built_in_tools/related_sessions_tool.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/chat_session_storage.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/related_sessions_service.dart';
import 'package:memex/data/services/semantic_search_model_service.dart';
import 'package:memex/data/services/session_report_service.dart';
import 'package:memex/data/services/topic_service.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/topic.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SemanticSearchFake extends ChangeNotifier
    implements SemanticSearchModelManager {
  _SemanticSearchFake({
    required this.itemVectors,
    required this.queryVectors,
  });

  final Map<String, List<double>> itemVectors;
  final Map<String, List<double>> queryVectors;
  var ensureCalls = 0;
  var itemCalls = 0;
  var queryCalls = 0;

  @override
  SemanticSearchModelState state = SemanticSearchModelState.ready;

  @override
  double get progress => 1;

  @override
  bool get isReady => true;

  @override
  bool get hasDownloadedFiles => true;

  @override
  Future<void> refreshModelAvailability() async {}

  @override
  Future<Result<void>> ensureReady({required bool allowDownload}) async {
    ensureCalls++;
    return const Ok.v();
  }

  @override
  Future<Result<void>> disable() async => const Ok.v();

  @override
  Future<Result<void>> deleteModel() async => const Ok.v();

  @override
  Future<List<double>> embedItem(String text) async {
    itemCalls++;
    return itemVectors[text] ?? [0, 1];
  }

  @override
  Future<List<double>> embedQuery(String text) async {
    queryCalls++;
    return queryVectors[text] ?? [0, 1];
  }
}

class _MemoryReports extends SessionReportService {
  _MemoryReports(this.reports, SemanticSearchModelManager semanticSearch)
      : super(semanticSearch: semanticSearch);

  final List<SessionReport> reports;

  @override
  Future<List<SessionReport>> loadAll(String userId) async => reports;
}

class _EmptyTopics extends Fake implements TopicService {
  @override
  Future<List<Topic>> load(String userId) async => const [];
}

class _EmptySessions extends Fake implements ChatSessionStorage {
  @override
  Future<List<Map<String, dynamic>>> listSessionMetadata(String userId) async =>
      const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDirectory;

  const report = SessionReport(
    schemaVersion: sessionReportSchemaVersion,
    sessionId: 'launch-review',
    kind: ReportKind.reuniao,
    title: 'Reunião de acompanhamento',
    sections: [ReportItemKind.summary],
    items: [
      ReportItem(
        id: 'item-1',
        kind: ReportItemKind.summary,
        text: 'Publicação adiada após revisão do orçamento.',
        status: ReportItemStatus.unconfirmed,
        assignee: reportAssigneeUnknown,
        due: reportDueUnknown,
        source: ReportSource(
          segmentId: 'segment-1',
          excerpt: 'revisão do orçamento',
        ),
      ),
    ],
  );
  const reformulatedQuery = 'Lançamento suspenso: auditoria das despesas';
  const indexedText =
      'Reunião de acompanhamento\nPublicação adiada após revisão do orçamento.';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('semantic_reports_');
    await FileSystemService.init(tempDirectory.path);
    await UserStorage.saveUser('semantic-search-user');
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test('a paraphrased query finds a report item with no shared content words',
      () async {
    await UserStorage.setSemanticSearchEnabled(true);
    final semantic = _SemanticSearchFake(
      itemVectors: {
        indexedText: [1, 0]
      },
      queryVectors: {
        reformulatedQuery: [1, 0]
      },
    );
    final reports = _MemoryReports([report], semantic);

    final hits = await reports.search(
      userId: 'semantic-search-user',
      query: reformulatedQuery,
    );

    expect(hits, hasLength(1));
    expect(hits.single.item.id, 'item-1');
    expect(semantic.ensureCalls, 1);
    expect(semantic.itemCalls, 1);
    expect(semantic.queryCalls, 1);
  });

  test('an off-topic semantic query stays empty', () async {
    await UserStorage.setSemanticSearchEnabled(true);
    final semantic = _SemanticSearchFake(
      itemVectors: {
        indexedText: [1, 0]
      },
      queryVectors: {
        'astronomia eclipses satélites': [0, 1]
      },
    );
    final reports = _MemoryReports([report], semantic);

    final hits = await reports.search(
      userId: 'semantic-search-user',
      query: 'astronomia eclipses satélites',
    );

    expect(hits, isEmpty);
  });

  test('disabled semantic search preserves the text-only results', () async {
    final semantic = _SemanticSearchFake(
      itemVectors: {
        indexedText: [1, 0]
      },
      queryVectors: {
        'publicação adiada': [1, 0]
      },
    );
    final reports = _MemoryReports([report], semantic);

    final hits = await reports.search(
      userId: 'semantic-search-user',
      query: 'publicação adiada',
    );

    expect(hits, hasLength(1));
    expect(semantic.ensureCalls, 0);
    expect(semantic.itemCalls, 0);
    expect(semantic.queryCalls, 0);
  });

  test('three text matches do not trigger semantic inference', () async {
    await UserStorage.setSemanticSearchEnabled(true);
    final semantic = _SemanticSearchFake(
      itemVectors: const {},
      queryVectors: const {},
    );
    final reports = _MemoryReports(
      [
        for (var i = 0; i < 3; i++)
          SessionReport(
            schemaVersion: sessionReportSchemaVersion,
            sessionId: 'text-$i',
            kind: ReportKind.reuniao,
            title: 'Reunião $i',
            sections: const [ReportItemKind.summary],
            items: [
              ReportItem(
                id: 'item-$i',
                kind: ReportItemKind.summary,
                text: 'Publicação adiada por revisão.',
                status: ReportItemStatus.unconfirmed,
                assignee: reportAssigneeUnknown,
                due: reportDueUnknown,
                source: const ReportSource(segmentId: 's', excerpt: ''),
              ),
            ],
          ),
      ],
      semantic,
    );

    final hits = await reports.search(
      userId: 'semantic-search-user',
      query: 'publicação adiada',
    );

    expect(hits, hasLength(3));
    expect(semantic.ensureCalls, 0);
  });

  test('RelatedSessionsService receives semantic report seeds', () async {
    await UserStorage.setSemanticSearchEnabled(true);
    final semantic = _SemanticSearchFake(
      itemVectors: {
        indexedText: [1, 0]
      },
      queryVectors: {
        reformulatedQuery: [1, 0]
      },
    );
    final service = RelatedSessionsService(
      reports: _MemoryReports([report], semantic),
      topics: _EmptyTopics(),
      sessions: _EmptySessions(),
    );

    final sessions =
        await service.find('semantic-search-user', reformulatedQuery);

    expect(sessions, hasLength(1));
    expect(sessions.single.sessionId, report.sessionId);
    expect(sessions.single.isSeed, isTrue);
    expect(
      renderRelatedSession(sessions.single, report),
      contains('matches the query'),
    );
  });
}

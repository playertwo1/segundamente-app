import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/global_event_bus.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/insight_trigger.dart';
import 'package:memex/domain/models/system_event.dart';
import 'package:memex/utils/logger.dart';

final _logger = getLogger('KnowledgeInsightTrigger');

/// Starts the automatic Knowledge Insight analysis once a record is saved.
///
/// It listens to `userInputSubmitted`, which is published only after a new
/// card has been written, so a message that never became a record never
/// starts anything. The work itself runs later, in the persistent task queue
/// (with retry); here we only queue it, so capture and chat never wait on the
/// model.
class KnowledgeInsightTriggerService {
  KnowledgeInsightTriggerService({
    LocalTaskExecutor? executor,
    FileSystemService? files,
    this.debounce = insightDebounce,
  })  : _executor = executor ?? LocalTaskExecutor.instance,
        _files = files ?? FileSystemService.instance;

  final LocalTaskExecutor _executor;
  final FileSystemService _files;
  final Duration debounce;

  /// Queues the record for analysis. Returns false, and queues nothing, when
  /// the record is gone, is an insight summary, has no readable text, or was
  /// already handed to an analysis (a record is analysed at most once).
  Future<bool> onRecordSaved(
    String userId,
    SystemEvent<UserInputSubmittedPayload> event,
  ) async {
    final factId = event.payload.factId;
    if (factId.isEmpty) return false;

    final card = await _files.readCardFile(userId, factId);
    if (card == null || !startsInsightAnalysis(card)) return false;

    if (await _executor.hasTaskForFact(
      taskType: insightTaskType,
      factId: factId,
    )) {
      return false;
    }

    final runAt = DateTime.now().add(debounce).millisecondsSinceEpoch ~/ 1000;
    await _executor.enqueueOrRescheduleTask(
      userId: userId,
      taskType: insightTaskType,
      bizId: insightBatchKey(userId),
      payload: {
        'fact_ids': [factId],
      },
      scheduledAt: runAt,
      maxRetries: 3,
      mergePayload: (waiting) => {
        'fact_ids': mergeFactIds(
          (waiting?['fact_ids'] as List?)?.cast<String>() ?? const [],
          [factId],
        ),
      },
    );
    _logger.info('Queued insight analysis for $factId');
    return true;
  }
}

/// The user asked for an analysis now: queues the latest records, with no
/// waiting and no "analysed once" rule, since the user wants a fresh look.
/// False when one is already waiting or running, or no record can be read.
Future<bool> requestManualInsightAnalysis(
  String userId, {
  LocalTaskExecutor? executor,
  FileSystemService? files,
  bool periodic = false,
}) async {
  final exec = executor ?? LocalTaskExecutor.instance;
  final fs = files ?? FileSystemService.instance;
  final latest = await exec.latestTask(
    insightTaskType,
    bizIds: insightTaskBizIds(userId),
  );
  if (latest != null &&
      latest.status != 'completed' &&
      latest.status != 'failed') {
    return false;
  }
  final rows = await AppDatabase.instance.cardDao.getCards(limit: 100);
  if (periodic) {
    // Only when a week passed since the last run and something new was saved.
    final lastRun = latest?.completedAt ?? latest?.createdAt;
    final newest = rows
        .where((r) => !r.tags.contains('"insight"'))
        .map((r) => r.timestamp)
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (lastRun != null &&
        (DateTime.now().millisecondsSinceEpoch ~/ 1000 - lastRun <
                insightPeriodicInterval.inSeconds ||
            newest <= lastRun)) {
      return false;
    }
  }
  final factIds = <String>[];
  for (final row in rows) {
    final card = await fs.readCardFile(userId, row.factId);
    if (card != null && startsInsightAnalysis(card)) factIds.add(row.factId);
    if (factIds.length == manualInsightRecords) break;
  }
  if (factIds.isEmpty) return false;
  await exec.enqueueTask(
    userId: userId,
    taskType: insightTaskType,
    payload: {'fact_ids': factIds, periodic ? 'periodic' : 'manual': true},
    bizId: insightManualBatchKey(userId),
    maxRetries: 1,
  );
  return true;
}

/// Weekly fresh look at the latest records, checked when the app starts.
/// Never throws: a failure here must not break startup.
Future<bool> requestPeriodicInsightAnalysis(
  String userId, {
  LocalTaskExecutor? executor,
  FileSystemService? files,
}) async {
  try {
    return await requestManualInsightAnalysis(
      userId,
      executor: executor,
      files: files,
      periodic: true,
    );
  } catch (e) {
    _logger.warning('Periodic insight analysis not queued: $e');
    return false;
  }
}

/// Subscribes the trigger to saved records on [bus]. A sync subscriber, because
/// the record has to merge into the user's waiting task instead of adding a
/// task per record; the bus logs and swallows a failure, so a broken trigger
/// never breaks capture.
void registerKnowledgeInsightTrigger(
  GlobalEventBus bus, {
  KnowledgeInsightTriggerService? service,
}) {
  bus.subscribeSync<UserInputSubmittedPayload>(
    eventType: SystemEventTypes.userInputSubmitted,
    subscription: EventSyncSubscription<UserInputSubmittedPayload>(
      subscriptionId: 'knowledge_insight_trigger',
      handler: (userId, event) async {
        await (service ?? KnowledgeInsightTriggerService())
            .onRecordSaved(userId, event);
      },
    ),
  );
}

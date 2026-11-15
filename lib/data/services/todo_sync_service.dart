import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/services/file_logger_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/lumen_mailbox_client.dart';
import 'package:memex/data/services/lumen_pairing_service.dart';
import 'package:memex/data/services/lumen_relay_crypto.dart';
import 'package:memex/data/services/todo_service.dart';
import 'package:memex/domain/models/lumen_pairing.dart';
import 'package:memex/domain/models/session_report.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

const int todoSyncContractVersion = 1;
const String todoSyncFileName = 'todo-sync-v1.json';
const String lumenTodoPeriodicSyncTask = 'lumenTodoPeriodicSyncTask';
const String lumenTodoPeriodicSyncUniqueName = 'lumen_todo_periodic_sync';

const int _syncSchemaVersion = 1;
const int _maxAppliedMutations = 2000;
const int _maxPoisonAttempts = 3;
const int _maxQuarantinedEnvelopes = 500;
const Duration _ninetyDays = Duration(days: 90);

const Set<String> _knownTaskFieldKeys = {
  'id',
  'text',
  'due',
  'due_date',
  'due_time',
  'time_zone',
  'alert_minutes',
  'priority',
  'subtasks',
  'recurrence',
  'series_id',
  'done',
  'created_at',
  'done_at',
  'snoozed_until',
  'source',
  'source_stale',
  'version',
  'deleted_at',
};

/// Current badge/sync state exposed to the UI and sync consumers.
enum TodoSyncBadgeState {
  localOnly,
  syncing,
  savedOnDevice,
  waitingPc,
  synced,
  revoked,
  error,
}

/// Wire envelope matching `docs/lumen/CONTRATO-SYNC.md` (contract v1).
class SyncEnvelope {
  final int contractVersion;
  final String mutationId;
  final String deviceId;
  final String originRole;
  final String entityType;
  final String entityId;
  final int baseVersion;
  final int newVersion;
  final String updatedAt;
  final Map<String, dynamic> payload;

  const SyncEnvelope({
    required this.contractVersion,
    required this.mutationId,
    required this.deviceId,
    required this.originRole,
    required this.entityType,
    required this.entityId,
    required this.baseVersion,
    required this.newVersion,
    required this.updatedAt,
    required this.payload,
  });

  /// Serializes [item] into the v1 wire payload, merging unknown [extraFields]
  /// and converting [reportDueUnknown] into `""` per the wire contract.
  static Map<String, dynamic> itemToWirePayload(
    TodoItem item, {
    Map<String, dynamic>? extraFields,
  }) {
    final map = <String, dynamic>{};
    if (extraFields != null) {
      for (final entry in extraFields.entries) {
        if (!_knownTaskFieldKeys.contains(entry.key)) {
          map[entry.key] = _deepCloneJsonValue(entry.value);
        }
      }
    }
    map.addAll(item.toJson());
    map['due'] = item.due.trim() == reportDueUnknown ? '' : item.due;
    map['source'] = item.source?.toJson();
    map['source_stale'] = item.sourceStale;
    return map;
  }

  Map<String, dynamic> toJson() => {
        'contract_version': contractVersion,
        'mutation_id': mutationId,
        'device_id': deviceId,
        'origin_role': originRole,
        'entity_type': entityType,
        'entity_id': entityId,
        'base_version': baseVersion,
        'new_version': newVersion,
        'updated_at': updatedAt,
        'payload': payload,
      };

  static SyncEnvelope fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    if (rawPayload is! Map) {
      throw const FormatException('envelope payload must be a JSON object');
    }
    final contractVersion = _requireInt(json['contract_version'], 'contract_version');
    final mutationId = _requireNonEmptyString(json['mutation_id'], 'mutation_id');
    final deviceId = _requireNonEmptyString(json['device_id'], 'device_id');
    final originRole = _requireNonEmptyString(json['origin_role'], 'origin_role');
    final entityType = _requireNonEmptyString(json['entity_type'], 'entity_type');
    final entityId = _requireNonEmptyString(json['entity_id'], 'entity_id');
    final baseVersion = _requireInt(json['base_version'], 'base_version');
    final newVersion = _requireInt(json['new_version'], 'new_version');
    final updatedAt = _requireNonEmptyString(json['updated_at'], 'updated_at');

    return SyncEnvelope(
      contractVersion: contractVersion,
      mutationId: mutationId,
      deviceId: deviceId,
      originRole: originRole,
      entityType: entityType,
      entityId: entityId,
      baseVersion: baseVersion,
      newVersion: newVersion,
      updatedAt: updatedAt,
      payload: Map<String, dynamic>.from(rawPayload),
    );
  }
}

/// Concurrent free-text conflict awaiting explicit user resolution.
class TaskTextConflict {
  final String id;
  final String entityId;
  final String field;
  final String localText;
  final String remoteText;
  final String winnerSide;
  final String winnerText;
  final String loserText;
  final String localUpdatedAt;
  final String remoteUpdatedAt;
  final String conflictState;

  const TaskTextConflict({
    required this.id,
    required this.entityId,
    required this.field,
    required this.localText,
    required this.remoteText,
    required this.winnerSide,
    required this.winnerText,
    required this.loserText,
    required this.localUpdatedAt,
    required this.remoteUpdatedAt,
    this.conflictState = 'pending_review',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'entity_id': entityId,
        'field': field,
        'local_text': localText,
        'remote_text': remoteText,
        'winner_side': winnerSide,
        'winner_text': winnerText,
        'loser_text': loserText,
        'local_updated_at': localUpdatedAt,
        'remote_updated_at': remoteUpdatedAt,
        'conflict_state': conflictState,
      };

  static TaskTextConflict fromJson(Map<String, dynamic> json) => TaskTextConflict(
        id: _requireNonEmptyString(json['id'], 'id'),
        entityId: _requireNonEmptyString(json['entity_id'], 'entity_id'),
        field: _requireNonEmptyString(json['field'], 'field'),
        localText: _requireStringAllowEmpty(json['local_text'], 'local_text'),
        remoteText: _requireStringAllowEmpty(json['remote_text'], 'remote_text'),
        winnerSide: _requireNonEmptyString(json['winner_side'], 'winner_side'),
        winnerText: _requireStringAllowEmpty(json['winner_text'], 'winner_text'),
        loserText: _requireStringAllowEmpty(json['loser_text'], 'loser_text'),
        localUpdatedAt:
            _requireStringAllowEmpty(json['local_updated_at'], 'local_updated_at'),
        remoteUpdatedAt:
            _requireStringAllowEmpty(json['remote_updated_at'], 'remote_updated_at'),
        conflictState:
            json['conflict_state']?.toString().trim().isNotEmpty == true
                ? json['conflict_state'].toString().trim()
                : 'pending_review',
      );
}

/// Snapshot of task synchronization status and pending text conflicts.
class TodoSyncStatus {
  final TodoSyncBadgeState state;
  final bool paired;
  final String deviceId;
  final int pendingOutbox;
  final int? pendingPc;
  final String? lastSyncedAt;
  final String? lastError;
  final int quarantinedCount;
  final int poisonCount;
  final bool revoked;
  final List<TaskTextConflict> conflicts;
  final Set<String> unsyncedItemIds;
  final bool hasCompletedSync;
  final Set<String> _awaitingPcIds;

  TodoSyncStatus({
    required this.state,
    required this.paired,
    required this.deviceId,
    required this.pendingOutbox,
    this.pendingPc,
    this.lastSyncedAt,
    this.lastError,
    this.quarantinedCount = 0,
    this.poisonCount = 0,
    this.revoked = false,
    List<TaskTextConflict> conflicts = const [],
    Set<String> unsyncedItemIds = const {},
    this.hasCompletedSync = false,
    Set<String> awaitingPcIds = const {},
  })  : conflicts = List.unmodifiable(conflicts),
        unsyncedItemIds = Set.unmodifiable(unsyncedItemIds),
        _awaitingPcIds = Set.unmodifiable(awaitingPcIds);

  bool get hasConflicts => conflicts.isNotEmpty;

  /// True only when paired, not revoked, at least one clean sync completed,
  /// and [itemId] has no pending local outbox or unconsumed relay entry.
  bool isItemSynced(String itemId) {
    if (!paired || revoked || !hasCompletedSync) return false;
    if (unsyncedItemIds.contains(itemId)) return false;
    if (_awaitingPcIds.contains(itemId)) return false;
    return true;
  }
}

/// Result of symmetric 3-way reconciliation against a remote task version.
class TodoSyncReconcileResult {
  final TodoItem item;
  final Map<String, dynamic> extraFields;
  final List<TaskTextConflict> conflicts;
  final bool divergesFromRemote;

  const TodoSyncReconcileResult({
    required this.item,
    required this.extraFields,
    required this.conflicts,
    required this.divergesFromRemote,
  });
}

/// Local outbox, E2EE relay transport, and 3-way task sync engine.
class TodoSyncService {
  static final TodoSyncService instance = TodoSyncService();

  static final Logger _logger = getLogger('TodoSyncService');
  static final Map<String, Lock> _fileLocks = {};
  static const Uuid _defaultUuid = Uuid();

  final LumenPairingService? _pairingService;
  final LumenMailboxClient _mailboxClient;
  final FileSystemService? _fileService;
  final TodoService? _todoServiceOverride;
  final DateTime Function() _now;
  final String Function() _uuidGenerator;
  final Future<String?> Function()? _userIdResolver;
  bool autoSyncEnabled;

  final Lock _syncRunLock = Lock();
  int _activeSyncCount = 0;

  /// Broadcasts the latest observed [TodoSyncStatus].
  final ValueNotifier<TodoSyncStatus?> statusNotifier =
      ValueNotifier<TodoSyncStatus?>(null);

  TodoSyncService({
    LumenPairingService? pairingService,
    LumenMailboxClient? mailboxClient,
    FileSystemService? fileService,
    TodoService? todoService,
    DateTime Function()? now,
    String Function()? uuidGenerator,
    Future<String?> Function()? userIdResolver,
    this.autoSyncEnabled = true,
  })  : _pairingService = pairingService,
        _mailboxClient = mailboxClient ?? const LumenMailboxClient(),
        _fileService = fileService,
        _todoServiceOverride = todoService,
        _now = now ?? (() => DateTime.now().toUtc()),
        _uuidGenerator = uuidGenerator ?? _defaultUuid.v4,
        _userIdResolver = userIdResolver;

  static bool isPeriodicSyncTask(String taskName) =>
      taskName == lumenTodoPeriodicSyncTask ||
      taskName == lumenTodoPeriodicSyncUniqueName;

  /// Entrypoint invoked from the Workmanager background isolate dispatcher.
  static Future<bool> runBackgroundSyncTask({
    TodoSyncService? service,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    await setupLogger();
    final logger = getLogger('TodoSyncBackgroundWorker');
    try {
      await UserStorage.initL10n();
      final userId = await UserStorage.getUserId();
      if (userId == null || userId.isEmpty) {
        return true;
      }
      final engine = service ?? TodoSyncService.instance;
      await engine.syncNow(userId: userId, reason: 'background_periodic');
      return true;
    } catch (e) {
      logger.warning('Periodic Lumen task sync failed: ${e.runtimeType}');
      return true;
    } finally {
      await FileLoggerService.instance.dispose();
    }
  }

  /// Loads current sync state without making network calls.
  Future<TodoSyncStatus> loadStatus({
    String? userId,
    FileSystemService? files,
  }) async {
    final resolvedUserId = await _resolveUserId(userId);
    if (resolvedUserId == null || resolvedUserId.isEmpty) {
      final status = TodoSyncStatus(
        state: _activeSyncCount > 0
            ? TodoSyncBadgeState.syncing
            : TodoSyncBadgeState.localOnly,
        paired: false,
        deviceId: '',
        pendingOutbox: 0,
      );
      statusNotifier.value = status;
      return status;
    }

    final resolvedFiles = await _resolveFileService(resolvedUserId, files);
    final pairingStatus = await _safeLoadPairingStatus();
    if (pairingStatus?.pairing != null) {
      await _ensureRoomState(
        userId: resolvedUserId,
        files: resolvedFiles,
        pairing: pairingStatus!.pairing!,
        preferredDeviceId: pairingStatus.deviceId,
      );
    }

    final filePath = _syncFilePath(resolvedFiles, resolvedUserId);
    final state = await _withStateLock(
      filePath,
      () => _readOrInitState(
        filePath,
        preferredDeviceId: pairingStatus?.deviceId,
      ),
    );
    final status = _buildStatus(
      state: state,
      paired: pairingStatus?.isPaired ?? false,
    );
    statusNotifier.value = status;
    return status;
  }

  /// Records local task mutations emitted by [TodoService] into `todo-sync-v1.json`.
  ///
  /// Returns `true` when paired (and therefore eligible for background push).
  /// Never throws on missing secure storage or uninitialized pairing.
  Future<bool> recordLocalMutations({
    required String userId,
    required List<({TodoItem item, int baseVersion})> mutations,
    List<TodoItem>? allItems,
    FileSystemService? files,
  }) async {
    if (mutations.isEmpty) return false;
    final resolvedFiles = await _resolveFileService(userId, files);
    final pairingStatus = await _safeLoadPairingStatus();
    final pairing = pairingStatus?.pairing;
    final roomDigest = pairing == null ? null : _sha256Hex(pairing.room);
    final filePath = _syncFilePath(resolvedFiles, userId);

    final state = await _withStateLock(filePath, () async {
      final state = await _readOrInitState(
        filePath,
        preferredDeviceId: pairingStatus?.deviceId,
      );
      final nowUtc = _now().toUtc();
      final nowIso = nowUtc.toIso8601String();
      final nowMs = nowUtc.millisecondsSinceEpoch;

      if (pairing != null && roomDigest != null) {
        if (state.pairedRoom != roomDigest) {
          final mutatedIds = {for (final m in mutations) m.item.id};
          _resetForNewRoom(state, roomDigest);
          if (allItems != null) {
            for (final existing in allItems) {
              if (mutatedIds.contains(existing.id)) continue;
              if (_isExpiredTombstone(existing, nowUtc)) continue;
              _upsertOutboxItem(
                state: state,
                item: existing,
                baseVersion: 0,
                extraFields: state.extraFields[existing.id],
                updatedAtIso: nowIso,
                queuedAtMs: nowMs,
              );
            }
          }
          for (final mutation in mutations) {
            _upsertOutboxItem(
              state: state,
              item: mutation.item,
              baseVersion: 0,
              extraFields: state.extraFields[mutation.item.id],
              updatedAtIso: nowIso,
              queuedAtMs: nowMs,
            );
          }
        } else {
          for (final mutation in mutations) {
            _upsertOutboxItem(
              state: state,
              item: mutation.item,
              baseVersion: mutation.baseVersion,
              extraFields: state.extraFields[mutation.item.id],
              updatedAtIso: nowIso,
              queuedAtMs: nowMs,
            );
          }
        }
      } else {
        for (final mutation in mutations) {
          state.itemMeta[mutation.item.id] = _ItemSyncMeta(
            lastUpdatedAt: nowIso,
            lastDeviceId: state.deviceId,
            unsynced: false,
          );
        }
      }

      await _writeStateAtomic(filePath, state);
      return state;
    });

    statusNotifier.value = _buildStatus(
      state: state,
      paired: pairing != null,
    );
    return pairing != null;
  }

  /// Resolves a [TaskTextConflict] explicitly chosen by the user and syncs.
  Future<TodoSyncStatus> resolveConflict({
    required String userId,
    required String conflictId,
    required bool keepLocal,
    FileSystemService? files,
  }) async {
    final resolvedFiles = await _resolveFileService(userId, files);
    final todoService = _resolveTodoService(resolvedFiles);
    final pairingStatus = await _safeLoadPairingStatus();
    final pairing = pairingStatus?.pairing;
    final roomDigest = pairing == null ? null : _sha256Hex(pairing.room);
    final filePath = _syncFilePath(resolvedFiles, userId);

    await todoService.applyRemoteMutationBatch(userId, (current) async {
      return _withStateLock(filePath, () async {
        final state = await _readOrInitState(
          filePath,
          preferredDeviceId: pairingStatus?.deviceId,
        );
        final conflict = state.conflicts.remove(conflictId);
        if (conflict == null) {
          return null;
        }

        final index = current.indexWhere((item) => item.id == conflict.entityId);
        if (index < 0) {
          await _writeStateAtomic(filePath, state);
          return null;
        }

        final chosenText = keepLocal ? conflict.localText : conflict.remoteText;
        final existing = current[index];
        final nextVersion = existing.version + 1;
        final updatedItem = _applyConflictText(
          existing,
          field: conflict.field,
          text: chosenText,
          version: nextVersion,
        );
        if (updatedItem == null) {
          await _writeStateAtomic(filePath, state);
          return null;
        }

        final nextItems = [...current];
        nextItems[index] = updatedItem;

        final nowUtc = _now().toUtc();
        final nowIso = nowUtc.toIso8601String();
        final nowMs = nowUtc.millisecondsSinceEpoch;

        if (pairing != null && roomDigest != null && state.pairedRoom == roomDigest) {
          _upsertOutboxItem(
            state: state,
            item: updatedItem,
            baseVersion: existing.version,
            extraFields: state.extraFields[updatedItem.id],
            updatedAtIso: nowIso,
            queuedAtMs: nowMs,
          );
        } else {
          state.itemMeta[updatedItem.id] = _ItemSyncMeta(
            lastUpdatedAt: nowIso,
            lastDeviceId: state.deviceId,
            unsynced: pairing != null,
          );
        }

        await _writeStateAtomic(filePath, state);
        return nextItems;
      });
    });

    return syncNow(
      userId: userId,
      reason: 'conflict_resolved',
      files: resolvedFiles,
    );
  }

  /// Executes one serialized sync cycle: outbox push -> paginated pull & merge
  /// -> post-merge push (if diverged) -> stats check.
  Future<TodoSyncStatus> syncNow({
    String? userId,
    String reason = 'manual',
    FileSystemService? files,
  }) =>
      _syncRunLock.synchronized(() async {
        _activeSyncCount++;
        try {
          final resolvedUserId = await _resolveUserId(userId);
          if (resolvedUserId == null || resolvedUserId.isEmpty) {
            final status = TodoSyncStatus(
              state: TodoSyncBadgeState.localOnly,
              paired: false,
              deviceId: '',
              pendingOutbox: 0,
            );
            statusNotifier.value = status;
            return status;
          }

          final resolvedFiles = await _resolveFileService(resolvedUserId, files);
          final filePath = _syncFilePath(resolvedFiles, resolvedUserId);
          final pairingStatus = await _safeLoadPairingStatus();
          final pairing = pairingStatus?.pairing;

          if (pairing == null) {
            final state = await _withStateLock(
              filePath,
              () => _readOrInitState(
                filePath,
                preferredDeviceId: pairingStatus?.deviceId,
              ),
            );
            final status = _buildStatus(
              state: state,
              paired: false,
              allowSyncingBadge: false,
            );
            statusNotifier.value = status;
            return status;
          }

          final initialState = await _ensureRoomState(
            userId: resolvedUserId,
            files: resolvedFiles,
            pairing: pairing,
            preferredDeviceId: pairingStatus?.deviceId,
          );

          statusNotifier.value = _buildStatus(
            state: initialState,
            paired: true,
            allowSyncingBadge: true,
          );

          final derived = LumenRelayCrypto.deriveFromBase64Url(pairing.key);

          // 1. Push outbox sequentially.
          final pushOutcome = await _pushOutbox(
            filePath: filePath,
            pairing: pairing,
            derived: derived,
          );
          if (!pushOutcome.proceed) {
            final latest = await _withStateLock(
              filePath,
              () => _readOrInitState(filePath),
            );
            final status = _buildStatus(
              state: latest,
              paired: true,
              allowSyncingBadge: false,
            );
            statusNotifier.value = status;
            return status;
          }

          // 2. Pull and apply remote mutations in batches.
          final pullOutcome = await _pullAndApplyMessages(
            userId: resolvedUserId,
            files: resolvedFiles,
            filePath: filePath,
            pairing: pairing,
            derived: derived,
          );
          if (!pullOutcome.proceed) {
            final latest = await _withStateLock(
              filePath,
              () => _readOrInitState(filePath),
            );
            final status = _buildStatus(
              state: latest,
              paired: true,
              allowSyncingBadge: false,
            );
            statusNotifier.value = status;
            return status;
          }

          // 3. If 3-way merge queued a converged item back to outbox, push it now.
          final midState = await _withStateLock(
            filePath,
            () => _readOrInitState(filePath),
          );
          if (midState.outbox.isNotEmpty) {
            final postMergePush = await _pushOutbox(
              filePath: filePath,
              pairing: pairing,
              derived: derived,
            );
            if (!postMergePush.proceed) {
              final latest = await _withStateLock(
                filePath,
                () => _readOrInitState(filePath),
              );
              final status = _buildStatus(
                state: latest,
                paired: true,
                allowSyncingBadge: false,
              );
              statusNotifier.value = status;
              return status;
            }
          }

          // 4. Query mailbox stats so "Sincronizado" reflects PC consumption.
          final statsStatus = await _refreshStats(
            filePath: filePath,
            pairing: pairing,
            derived: derived,
          );
          statusNotifier.value = statsStatus;
          return statsStatus;
        } finally {
          _activeSyncCount--;
        }
      });

  /// Symmetric 3-way reconciliation of a concurrent local vs remote task.
  static TodoSyncReconcileResult reconcileThreeWay({
    TodoItem? base,
    required TodoItem local,
    Map<String, dynamic> localExtras = const {},
    required String localUpdatedAt,
    required String localDeviceId,
    required TodoItem remote,
    Map<String, dynamic> remoteExtras = const {},
    required String remoteUpdatedAt,
    required String remoteDeviceId,
    required int remoteNewVersion,
  }) {
    final remoteWins = _remoteWinsLww(
      localTs: localUpdatedAt,
      localDev: localDeviceId,
      remoteTs: remoteUpdatedAt,
      remoteDev: remoteDeviceId,
    );
    final conflicts = <TaskTextConflict>[];

    final textMerge = _mergeFreeText(
      entityId: local.id,
      field: 'text',
      baseText: base?.text,
      localText: local.text,
      remoteText: remote.text,
      localTs: localUpdatedAt,
      remoteTs: remoteUpdatedAt,
      remoteWins: remoteWins,
    );
    if (textMerge.conflict != null) {
      conflicts.add(textMerge.conflict!);
    }

    final doneMerge = _mergeDone(base: base, local: local, remote: remote);
    final deletedAt = _mergeDeletedAt(
      baseDeletedAt: base?.deletedAt,
      hasBase: base != null,
      localDeletedAt: local.deletedAt,
      remoteDeletedAt: remote.deletedAt,
      remoteWins: remoteWins,
    );
    final snoozedUntil = _mergeSnoozedUntil(
      baseSnoozedUntil: base?.snoozedUntil,
      hasBase: base != null,
      localSnoozedUntil: local.snoozedUntil,
      remoteSnoozedUntil: remote.snoozedUntil,
      remoteWins: remoteWins,
    );
    final subtasks = _mergeSubtasks(
      entityId: local.id,
      base: base?.subtasks,
      local: local.subtasks,
      remote: remote.subtasks,
      localTs: localUpdatedAt,
      remoteTs: remoteUpdatedAt,
      remoteWins: remoteWins,
      conflictsOut: conflicts,
    );

    final nextVersion =
        (local.version > remoteNewVersion ? local.version : remoteNewVersion) +
            1;

    final mergedItem = TodoItem(
      id: local.id,
      text: textMerge.text,
      due: _mergeFieldLww<String>(
        hasBase: base != null,
        baseVal: base?.due,
        localVal: local.due,
        remoteVal: remote.due,
        remoteWins: remoteWins,
      ),
      dueDate: _mergeFieldLww<String?>(
        hasBase: base != null,
        baseVal: base?.dueDate,
        localVal: local.dueDate,
        remoteVal: remote.dueDate,
        remoteWins: remoteWins,
      ),
      dueTime: _mergeFieldLww<String?>(
        hasBase: base != null,
        baseVal: base?.dueTime,
        localVal: local.dueTime,
        remoteVal: remote.dueTime,
        remoteWins: remoteWins,
      ),
      timeZone: _mergeFieldLww<String>(
        hasBase: base != null,
        baseVal: base?.timeZone,
        localVal: local.timeZone,
        remoteVal: remote.timeZone,
        remoteWins: remoteWins,
      ),
      alertMinutes: _mergeFieldLww<int>(
        hasBase: base != null,
        baseVal: base?.alertMinutes,
        localVal: local.alertMinutes,
        remoteVal: remote.alertMinutes,
        remoteWins: remoteWins,
      ),
      priority: _mergeFieldLww<TodoPriority>(
        hasBase: base != null,
        baseVal: base?.priority,
        localVal: local.priority,
        remoteVal: remote.priority,
        remoteWins: remoteWins,
      ),
      subtasks: subtasks,
      recurrence: _mergeFieldLww<TodoRecurrence?>(
        hasBase: base != null,
        baseVal: base?.recurrence,
        localVal: local.recurrence,
        remoteVal: remote.recurrence,
        remoteWins: remoteWins,
        equals: _sameRecurrence,
      ),
      seriesId: _mergeFieldLww<String?>(
        hasBase: base != null,
        baseVal: base?.seriesId,
        localVal: local.seriesId,
        remoteVal: remote.seriesId,
        remoteWins: remoteWins,
      ),
      done: doneMerge.done,
      createdAt: _mergeFieldLww<String>(
        hasBase: base != null,
        baseVal: base?.createdAt,
        localVal: local.createdAt,
        remoteVal: remote.createdAt,
        remoteWins: remoteWins,
      ),
      doneAt: doneMerge.doneAt,
      snoozedUntil: snoozedUntil,
      source: _mergeFieldLww<TodoSource?>(
        hasBase: base != null,
        baseVal: base?.source,
        localVal: local.source,
        remoteVal: remote.source,
        remoteWins: remoteWins,
        equals: _sameSource,
      ),
      sourceStale: _mergeFieldLww<bool>(
        hasBase: base != null,
        baseVal: base?.sourceStale,
        localVal: local.sourceStale,
        remoteVal: remote.sourceStale,
        remoteWins: remoteWins,
      ),
      version: nextVersion,
      deletedAt: deletedAt,
    );

    final mergedExtras = _mergeExtraFields(
      localExtras: localExtras,
      remoteExtras: remoteExtras,
      remoteWins: remoteWins,
    );

    final diverges = !_sameTaskContentIgnoringVersion(mergedItem, remote) ||
        !_jsonEquals(mergedExtras, remoteExtras);

    return TodoSyncReconcileResult(
      item: mergedItem,
      extraFields: mergedExtras,
      conflicts: conflicts,
      divergesFromRemote: diverges,
    );
  }

  Future<String?> _resolveUserId(String? explicitUserId) async {
    if (explicitUserId != null && explicitUserId.isNotEmpty) {
      return explicitUserId;
    }
    final resolver = _userIdResolver;
    if (resolver != null) {
      return resolver();
    }
    try {
      return await UserStorage.getUserId();
    } catch (_) {
      return null;
    }
  }

  Future<FileSystemService> _resolveFileService(
    String userId,
    FileSystemService? explicitFiles,
  ) async {
    if (explicitFiles != null) return explicitFiles;
    final explicitService = _fileService;
    if (explicitService != null) return explicitService;
    if (FileSystemService.isInitialized) return FileSystemService.instance;
    final dataRoot = await UserStorage.resolveDataRoot(userId);
    await FileSystemService.init(dataRoot);
    return FileSystemService.instance;
  }

  TodoService _resolveTodoService(FileSystemService files) =>
      _todoServiceOverride ?? TodoService(fileService: files, syncService: this);

  Future<LumenPairingStatus?> _safeLoadPairingStatus() async {
    try {
      final service = _pairingService ?? LumenPairingService();
      return await service.loadStatus();
    } on LumenSecretStoreException {
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  String _syncFilePath(FileSystemService files, String userId) =>
      p.join(files.getTodoPath(userId), todoSyncFileName);

  Future<T> _withStateLock<T>(
    String filePath,
    FutureOr<T> Function() action,
  ) {
    final normalized = p.normalize(filePath);
    final lock = _fileLocks.putIfAbsent(normalized, Lock.new);
    return lock.synchronized(action);
  }

  Future<_SyncFileState> _ensureRoomState({
    required String userId,
    required FileSystemService files,
    required LumenPairing pairing,
    String? preferredDeviceId,
  }) async {
    final roomDigest = _sha256Hex(pairing.room);
    final filePath = _syncFilePath(files, userId);

    // Fast path check avoids locking TodoService if room did not change.
    final quickState = await _withStateLock(
      filePath,
      () => _readOrInitState(filePath, preferredDeviceId: preferredDeviceId),
    );
    if (quickState.pairedRoom == roomDigest) {
      return quickState;
    }

    final todoService = _resolveTodoService(files);
    final allItems = await todoService.load(userId, includeDeleted: true);

    return _withStateLock(filePath, () async {
      final state = await _readOrInitState(
        filePath,
        preferredDeviceId: preferredDeviceId,
      );
      if (state.pairedRoom != roomDigest) {
        final nowUtc = _now().toUtc();
        final nowIso = nowUtc.toIso8601String();
        final nowMs = nowUtc.millisecondsSinceEpoch;
        _resetForNewRoom(state, roomDigest);
        for (final item in allItems) {
          if (_isExpiredTombstone(item, nowUtc)) continue;
          _upsertOutboxItem(
            state: state,
            item: item,
            baseVersion: 0,
            extraFields: state.extraFields[item.id],
            updatedAtIso: nowIso,
            queuedAtMs: nowMs,
          );
        }
        await _writeStateAtomic(filePath, state);
      }
      return state;
    });
  }

  void _resetForNewRoom(_SyncFileState state, String roomDigest) {
    state.pairedRoom = roomDigest;
    state.lastPhoneSeq = 0;
    state.revoked = false;
    state.pendingPc = null;
    state.hasCompletedSync = false;
    state.lastError = null;
    state.lastSyncedAt = null;
    state.outbox.clear();
    state.appliedMutations.clear();
    state.baseCopies.clear();
    state.baseExtraFields.clear();
    state.itemMeta.clear();
    state.conflicts.clear();
    state.poisonAttempts.clear();
    state.awaitingPcIds.clear();
    state.prePushAncestors.clear();
  }

  bool _isExpiredTombstone(TodoItem item, DateTime nowUtc) {
    final deletedAt = item.deletedAt;
    if (deletedAt == null) return false;
    final parsed = DateTime.tryParse(deletedAt);
    if (parsed == null) return false;
    return nowUtc.difference(parsed.toUtc()) >= _ninetyDays;
  }

  void _upsertOutboxItem({
    required _SyncFileState state,
    required TodoItem item,
    required int baseVersion,
    required Map<String, dynamic>? extraFields,
    required String updatedAtIso,
    required int queuedAtMs,
  }) {
    final existingIdx =
        state.outbox.indexWhere((e) => e.envelope.entityId == item.id);
    final effectiveBase = existingIdx >= 0
        ? state.outbox[existingIdx].envelope.baseVersion
        : baseVersion;

    final envelope = SyncEnvelope(
      contractVersion: todoSyncContractVersion,
      mutationId: _uuidGenerator(),
      deviceId: state.deviceId,
      originRole: LumenMailboxRole.phone.wireName,
      entityType: 'task',
      entityId: item.id,
      baseVersion: effectiveBase,
      newVersion: item.version,
      updatedAt: updatedAtIso,
      payload: SyncEnvelope.itemToWirePayload(item, extraFields: extraFields),
    );
    final entry = _OutboxEntry(envelope: envelope, queuedAtMs: queuedAtMs);

    if (existingIdx >= 0) {
      state.outbox[existingIdx] = entry;
    } else {
      state.outbox.add(entry);
    }

    state.itemMeta[item.id] = _ItemSyncMeta(
      lastUpdatedAt: updatedAtIso,
      lastDeviceId: state.deviceId,
      unsynced: true,
    );
    state.awaitingPcIds.remove(item.id);
  }

  void _replaceOutboxWithMerged({
    required _SyncFileState state,
    required TodoItem mergedItem,
    required Map<String, dynamic> mergedExtras,
    required int remoteVersion,
    required int nowMs,
    required String updatedAtIso,
  }) {
    state.outbox.removeWhere((e) => e.envelope.entityId == mergedItem.id);
    _upsertOutboxItem(
      state: state,
      item: mergedItem,
      baseVersion: remoteVersion,
      extraFields: mergedExtras,
      updatedAtIso: updatedAtIso,
      queuedAtMs: nowMs,
    );
    if (mergedExtras.isEmpty) {
      state.extraFields.remove(mergedItem.id);
    } else {
      state.extraFields[mergedItem.id] = _deepCloneJsonMap(mergedExtras);
    }
  }

  Future<({bool proceed})> _pushOutbox({
    required String filePath,
    required LumenPairing pairing,
    required LumenDerivedKeys derived,
  }) async {
    while (true) {
      final snapshot = await _withStateLock(filePath, () async {
        final state = await _readOrInitState(filePath);
        if (state.outbox.isEmpty) return null;
        return state.outbox.first;
      });
      if (snapshot == null) {
        return (proceed: true);
      }

      final env = snapshot.envelope;
      final Uint8List encryptedBody;
      try {
        encryptedBody = LumenRelayCrypto.sealMailboxEnvelope(
          kMailbox: derived.kMailbox,
          room: pairing.room,
          to: LumenMailboxRole.pc,
          envelope: env.toJson(),
        );
      } on LumenMailboxCipherException catch (e) {
        await _recordError(filePath, 'cipher:${e.reason}');
        return (proceed: false);
      }

      try {
        await _mailboxClient.postMessage(
          pairing: pairing,
          joinProof: derived.joinProof,
          mutationId: env.mutationId,
          encryptedBody: encryptedBody,
          to: LumenMailboxRole.pc,
        );
      } on LumenMailboxHttpException catch (e) {
        if (e.isRevoked) {
          await _markRevoked(filePath);
        } else {
          await _recordError(filePath, 'http_${e.statusCode}');
        }
        return (proceed: false);
      } catch (e) {
        await _recordError(filePath, _sanitizeErrorType(e));
        return (proceed: false);
      }

      await _withStateLock(filePath, () async {
        final state = await _readOrInitState(filePath);
        final idx = state.outbox.indexWhere(
          (entry) =>
              entry.envelope.entityId == env.entityId &&
              entry.envelope.mutationId == env.mutationId,
        );
        if (idx >= 0) {
          state.outbox.removeAt(idx);
          final ancestors =
              state.prePushAncestors.putIfAbsent(env.entityId, () => []);
          if (!ancestors.any((a) => a.pushedBaseVersion == env.baseVersion)) {
            ancestors.add(
              _PendingBaseAncestor(
                pushedBaseVersion: env.baseVersion,
                item: state.baseCopies[env.entityId],
                extras: _deepCloneJsonMap(
                  state.baseExtraFields[env.entityId] ?? const {},
                ),
              ),
            );
            ancestors.sort(
              (a, b) => a.pushedBaseVersion.compareTo(b.pushedBaseVersion),
            );
          }
          final pushedItem = TodoItem.fromJson(env.payload);
          final pushedExtras = _extractExtraFields(env.payload);
          state.baseCopies[env.entityId] = pushedItem;
          if (pushedExtras.isEmpty) {
            state.baseExtraFields.remove(env.entityId);
            state.extraFields.remove(env.entityId);
          } else {
            state.baseExtraFields[env.entityId] = _deepCloneJsonMap(pushedExtras);
            state.extraFields[env.entityId] = _deepCloneJsonMap(pushedExtras);
          }
          state.itemMeta[env.entityId] = _ItemSyncMeta(
            lastUpdatedAt: env.updatedAt,
            lastDeviceId: env.deviceId,
            unsynced: false,
          );
          state.awaitingPcIds.add(env.entityId);
          state.lastError = null;
          await _writeStateAtomic(filePath, state);
        }
      });
    }
  }

  Future<({bool proceed})> _pullAndApplyMessages({
    required String userId,
    required FileSystemService files,
    required String filePath,
    required LumenPairing pairing,
    required LumenDerivedKeys derived,
  }) async {
    final todoService = _resolveTodoService(files);

    while (true) {
      final afterSeq = await _withStateLock(
        filePath,
        () async => (await _readOrInitState(filePath)).lastPhoneSeq,
      );

      final LumenMailboxListResult listResult;
      try {
        listResult = await _mailboxClient.listMessages(
          pairing: pairing,
          joinProof: derived.joinProof,
          afterSeq: afterSeq,
          limit: LumenMailboxClient.maxListLimit,
          recipient: LumenMailboxRole.phone,
        );
      } on LumenMailboxHttpException catch (e) {
        if (e.isRevoked) {
          await _markRevoked(filePath);
        } else {
          await _recordError(filePath, 'http_${e.statusCode}');
        }
        return (proceed: false);
      } catch (e) {
        await _recordError(filePath, _sanitizeErrorType(e));
        return (proceed: false);
      }

      if (listResult.messages.isEmpty) {
        return (proceed: true);
      }

      final sorted = [...listResult.messages]
        ..sort((a, b) => a.seq.compareTo(b.seq));
      final existingPoisonAttempts = await _withStateLock(
        filePath,
        () async => Map<String, int>.from(
          (await _readOrInitState(filePath)).poisonAttempts,
        ),
      );

      final decodedRecords = <_DecodedMailboxRecord>[];
      var blockedByPoison = false;

      for (final record in sorted) {
        if (record.seq <= afterSeq) continue;
        final decoded = _decodeRecord(
          record: record,
          pairing: pairing,
          derived: derived,
        );
        if (decoded.kind == _DecodedKind.poison) {
          final key = '${record.seq}';
          final nextAttempt = (existingPoisonAttempts[key] ?? 0) + 1;
          decodedRecords.add(
            _DecodedMailboxRecord.poisonDecision(
              seq: record.seq,
              attemptCount: nextAttempt,
              dropAndAck: nextAttempt >= _maxPoisonAttempts,
            ),
          );
          if (nextAttempt < _maxPoisonAttempts) {
            blockedByPoison = true;
            break;
          }
        } else {
          decodedRecords.add(decoded);
        }
      }

      var ackUptoSeq = afterSeq;
      var poisonRetryBlocked = false;

      await todoService.applyRemoteMutationBatch(userId, (current) async {
        return _withStateLock(filePath, () async {
          final state = await _readOrInitState(filePath);
          final items = [...current];
          var tasksChanged = false;
          var stateDirty = false;
          final nowUtc = _now().toUtc();
          final nowMs = nowUtc.millisecondsSinceEpoch;
          final nowIso = nowUtc.toIso8601String();

          for (final entry in decodedRecords) {
            switch (entry.kind) {
              case _DecodedKind.poison:
                final key = '${entry.seq}';
                if (entry.dropAndAck) {
                  state.poisonAttempts.remove(key);
                  state.poisonCount++;
                  state.lastError = null;
                  if (entry.seq > ackUptoSeq) {
                    ackUptoSeq = entry.seq;
                  }
                } else {
                  state.poisonAttempts[key] = entry.attemptCount;
                  state.lastError = 'poison_envelope_retry';
                  poisonRetryBlocked = true;
                }
                stateDirty = true;
                break;

              case _DecodedKind.quarantine:
                state.poisonAttempts.remove('${entry.seq}');
                _appendQuarantine(
                  state: state,
                  seq: entry.seq,
                  receivedAt: nowIso,
                  rawMap: entry.rawEnvelope!,
                );
                if (entry.seq > ackUptoSeq) {
                  ackUptoSeq = entry.seq;
                }
                stateDirty = true;
                break;

              case _DecodedKind.validTask:
                state.poisonAttempts.remove('${entry.seq}');
                final env = entry.envelope!;
                final remoteItem = entry.remoteItem!;
                final remoteExtras = entry.remoteExtras!;
                if (entry.seq > ackUptoSeq) {
                  ackUptoSeq = entry.seq;
                }

                if (env.deviceId == state.deviceId ||
                    _hasAppliedMutation(state, env.mutationId)) {
                  stateDirty = true;
                  continue;
                }

                final applied = _applySingleRemoteTask(
                  state: state,
                  items: items,
                  envelope: env,
                  remoteItem: remoteItem,
                  remoteExtras: remoteExtras,
                  nowMs: nowMs,
                  nowIso: nowIso,
                );
                if (applied) {
                  tasksChanged = true;
                }
                _recordAppliedMutation(state, env.mutationId, nowMs);
                _pruneAppliedMutations(state, nowMs);
                stateDirty = true;
                break;
            }
          }

          if (stateDirty) {
            await _writeStateAtomic(filePath, state);
          }
          return tasksChanged ? items : null;
        });
      });

      if (ackUptoSeq > afterSeq) {
        try {
          await _mailboxClient.ackMessages(
            pairing: pairing,
            joinProof: derived.joinProof,
            uptoSeq: ackUptoSeq,
            recipient: LumenMailboxRole.phone,
          );
        } on LumenMailboxHttpException catch (e) {
          if (e.isRevoked) {
            await _markRevoked(filePath);
          } else {
            await _recordError(filePath, 'http_${e.statusCode}');
          }
          return (proceed: false);
        } catch (e) {
          await _recordError(filePath, _sanitizeErrorType(e));
          return (proceed: false);
        }

        await _withStateLock(filePath, () async {
          final state = await _readOrInitState(filePath);
          if (ackUptoSeq > state.lastPhoneSeq) {
            state.lastPhoneSeq = ackUptoSeq;
          }
          if (!poisonRetryBlocked) {
            state.lastError = null;
          }
          await _writeStateAtomic(filePath, state);
        });
      }

      if (blockedByPoison || poisonRetryBlocked) {
        return (proceed: false);
      }
      if (listResult.messages.length < LumenMailboxClient.maxListLimit ||
          ackUptoSeq <= afterSeq) {
        return (proceed: true);
      }
    }
  }

  _DecodedMailboxRecord _decodeRecord({
    required LumenMailboxEnvelopeRecord record,
    required LumenPairing pairing,
    required LumenDerivedKeys derived,
  }) {
    final Map<String, dynamic> map;
    try {
      map = LumenRelayCrypto.openMailboxMap(
        kMailbox: derived.kMailbox,
        room: pairing.room,
        to: LumenMailboxRole.phone,
        body: record.bodyBytes,
      );
    } on LumenMailboxCipherException {
      return _DecodedMailboxRecord.poison(seq: record.seq);
    } on FormatException {
      return _DecodedMailboxRecord.poison(seq: record.seq);
    } catch (_) {
      return _DecodedMailboxRecord.poison(seq: record.seq);
    }

    final rawContractVersion = map['contract_version'];
    if (rawContractVersion is! int || rawContractVersion < 1) {
      return _DecodedMailboxRecord.poison(seq: record.seq);
    }
    if (rawContractVersion > todoSyncContractVersion) {
      return _DecodedMailboxRecord.quarantine(seq: record.seq, rawEnvelope: map);
    }

    final rawEntityType = map['entity_type'];
    if (rawEntityType is! String || rawEntityType.trim().isEmpty) {
      return _DecodedMailboxRecord.poison(seq: record.seq);
    }
    if (rawEntityType != 'task') {
      return _DecodedMailboxRecord.quarantine(seq: record.seq, rawEnvelope: map);
    }

    try {
      final envelope = SyncEnvelope.fromJson(map);
      if (envelope.baseVersion < 0 || envelope.newVersion < 1) {
        return _DecodedMailboxRecord.poison(seq: record.seq);
      }
      if (DateTime.tryParse(envelope.updatedAt) == null) {
        return _DecodedMailboxRecord.poison(seq: record.seq);
      }
      final payload = envelope.payload;
      if (payload['id'] is! String ||
          (payload['id'] as String).trim() != envelope.entityId) {
        return _DecodedMailboxRecord.poison(seq: record.seq);
      }
      if (payload['text'] is! String ||
          (payload['text'] as String).trim().isEmpty) {
        return _DecodedMailboxRecord.poison(seq: record.seq);
      }
      if (payload['created_at'] is! String ||
          (payload['created_at'] as String).trim().isEmpty) {
        return _DecodedMailboxRecord.poison(seq: record.seq);
      }
      if (payload['done'] is! bool) {
        return _DecodedMailboxRecord.poison(seq: record.seq);
      }
      if (payload['version'] is! int ||
          payload['version'] != envelope.newVersion) {
        return _DecodedMailboxRecord.poison(seq: record.seq);
      }
      if (payload['due'] != null && payload['due'] is! String) {
        return _DecodedMailboxRecord.poison(seq: record.seq);
      }

      final remoteItem = TodoItem.fromJson(payload);
      final remoteExtras = _extractExtraFields(payload);
      return _DecodedMailboxRecord.validTask(
        seq: record.seq,
        envelope: envelope,
        remoteItem: remoteItem,
        remoteExtras: remoteExtras,
      );
    } catch (_) {
      return _DecodedMailboxRecord.poison(seq: record.seq);
    }
  }

  bool _applySingleRemoteTask({
    required _SyncFileState state,
    required List<TodoItem> items,
    required SyncEnvelope envelope,
    required TodoItem remoteItem,
    required Map<String, dynamic> remoteExtras,
    required int nowMs,
    required String nowIso,
  }) {
    final entityId = envelope.entityId;
    final localIndex = items.indexWhere((item) => item.id == entityId);
    final inOutbox =
        state.outbox.any((entry) => entry.envelope.entityId == entityId);
    final meta = state.itemMeta[entityId];
    final isUnsynced = meta?.unsynced == true;

    if (localIndex < 0) {
      // Remote task missing locally: apply directly (fast-forward create/tombstone).
      items.add(remoteItem);
      state.baseCopies[entityId] = remoteItem;
      _setExtraFields(state, entityId, remoteExtras);
      state.itemMeta[entityId] = _ItemSyncMeta(
        lastUpdatedAt: envelope.updatedAt,
        lastDeviceId: envelope.deviceId,
        unsynced: false,
      );
      _clearConflictsForEntity(state, entityId);
      return true;
    }

    final local = items[localIndex];
    final ancestors = state.prePushAncestors[entityId];
    _PendingBaseAncestor? matchingAncestor;
    if (ancestors != null) {
      for (final a in ancestors) {
        if (a.pushedBaseVersion >= envelope.baseVersion) {
          matchingAncestor = a;
          break;
        }
      }
      ancestors.removeWhere((a) => a.pushedBaseVersion <= envelope.baseVersion);
      if (ancestors.isEmpty) {
        state.prePushAncestors.remove(entityId);
      }
    }
    final usePendingAncestor = matchingAncestor != null;
    final baseCopy =
        usePendingAncestor ? matchingAncestor.item : state.baseCopies[entityId];
    final baseMatchesLocal =
        baseCopy != null && baseCopy.version == local.version;

    // Fast-forward when no unsynced local edits diverge and version matches base.
    if (envelope.baseVersion == local.version &&
        !inOutbox &&
        (!isUnsynced || baseMatchesLocal)) {
      items[localIndex] = remoteItem;
      state.baseCopies[entityId] = remoteItem;
      _setExtraFields(state, entityId, remoteExtras);
      state.itemMeta[entityId] = _ItemSyncMeta(
        lastUpdatedAt: envelope.updatedAt,
        lastDeviceId: envelope.deviceId,
        unsynced: false,
      );
      _clearConflictsForEntity(state, entityId);
      return true;
    }

    // Concurrent 3-way merge.
    final localTieBreak = _resolveLocalTieBreak(state, local);
    final merge = reconcileThreeWay(
      base: baseCopy,
      local: local,
      localExtras: state.extraFields[entityId] ?? const {},
      localUpdatedAt: localTieBreak.updatedAt,
      localDeviceId: localTieBreak.deviceId,
      remote: remoteItem,
      remoteExtras: remoteExtras,
      remoteUpdatedAt: envelope.updatedAt,
      remoteDeviceId: envelope.deviceId,
      remoteNewVersion: envelope.newVersion,
    );

    items[localIndex] = merge.item;
    for (final conflict in merge.conflicts) {
      state.conflicts[conflict.id] = conflict;
    }
    if (merge.conflicts.isEmpty) {
      _clearConflictsForEntity(state, entityId);
    }

    if (merge.divergesFromRemote) {
      // Keep remoteItem as common ancestor until the merged outbox mutation pushes.
      state.baseCopies[entityId] = remoteItem;
      _replaceOutboxWithMerged(
        state: state,
        mergedItem: merge.item,
        mergedExtras: merge.extraFields,
        remoteVersion: envelope.newVersion,
        nowMs: nowMs,
        updatedAtIso: nowIso,
      );
    } else {
      state.outbox.removeWhere((e) => e.envelope.entityId == entityId);
      state.baseCopies[entityId] = merge.item;
      _setExtraFields(state, entityId, merge.extraFields);
      state.itemMeta[entityId] = _ItemSyncMeta(
        lastUpdatedAt: envelope.updatedAt,
        lastDeviceId: envelope.deviceId,
        unsynced: false,
      );
    }
    return true;
  }

  ({String updatedAt, String deviceId}) _resolveLocalTieBreak(
    _SyncFileState state,
    TodoItem local,
  ) {
    final outboxIdx =
        state.outbox.indexWhere((e) => e.envelope.entityId == local.id);
    if (outboxIdx >= 0) {
      final env = state.outbox[outboxIdx].envelope;
      return (updatedAt: env.updatedAt, deviceId: env.deviceId);
    }
    final meta = state.itemMeta[local.id];
    if (meta != null && meta.lastUpdatedAt.isNotEmpty) {
      return (updatedAt: meta.lastUpdatedAt, deviceId: meta.lastDeviceId);
    }
    final fallbackTs =
        local.deletedAt ?? local.doneAt ?? local.snoozedUntil ?? local.createdAt;
    return (updatedAt: fallbackTs, deviceId: state.deviceId);
  }

  Future<TodoSyncStatus> _refreshStats({
    required String filePath,
    required LumenPairing pairing,
    required LumenDerivedKeys derived,
  }) async {
    final LumenMailboxStatsResult stats;
    try {
      stats = await _mailboxClient.getStats(
        pairing: pairing,
        joinProof: derived.joinProof,
      );
    } on LumenMailboxHttpException catch (e) {
      if (e.isRevoked) {
        await _markRevoked(filePath);
      } else {
        await _recordError(filePath, 'http_${e.statusCode}');
      }
      final state = await _withStateLock(
        filePath,
        () => _readOrInitState(filePath),
      );
      return _buildStatus(
        state: state,
        paired: true,
        allowSyncingBadge: false,
      );
    } catch (e) {
      await _recordError(filePath, _sanitizeErrorType(e));
      final state = await _withStateLock(
        filePath,
        () => _readOrInitState(filePath),
      );
      return _buildStatus(
        state: state,
        paired: true,
        allowSyncingBadge: false,
      );
    }

    final state = await _withStateLock(filePath, () async {
      final state = await _readOrInitState(filePath);
      if (stats.revoked) {
        state.revoked = true;
        state.pendingPc = null;
        state.lastError = null;
      } else {
        state.revoked = false;
        state.pendingPc = stats.pendingPc;
        state.lastError = null;
        if (state.outbox.isEmpty && stats.pendingPc == 0) {
          state.awaitingPcIds.clear();
          state.prePushAncestors.clear();
          state.hasCompletedSync = true;
          state.lastSyncedAt = _now().toUtc().toIso8601String();
        }
      }
      await _writeStateAtomic(filePath, state);
      return state;
    });

    return _buildStatus(
      state: state,
      paired: true,
      allowSyncingBadge: false,
    );
  }

  Future<void> _markRevoked(String filePath) => _withStateLock(filePath, () async {
        final state = await _readOrInitState(filePath);
        state.revoked = true;
        state.pendingPc = null;
        state.lastError = null;
        await _writeStateAtomic(filePath, state);
      });

  Future<void> _recordError(String filePath, String code) =>
      _withStateLock(filePath, () async {
        final state = await _readOrInitState(filePath);
        state.lastError = code;
        await _writeStateAtomic(filePath, state);
      });

  TodoSyncStatus _buildStatus({
    required _SyncFileState state,
    required bool paired,
    bool allowSyncingBadge = true,
  }) {
    final unsyncedIds = <String>{
      for (final entry in state.outbox) entry.envelope.entityId,
    };
    final conflicts = state.conflicts.values.toList(growable: false);
    final pendingOutbox = state.outbox.length;
    final pendingPc = state.pendingPc;

    final TodoSyncBadgeState badgeState;
    if (allowSyncingBadge && _activeSyncCount > 0) {
      badgeState = TodoSyncBadgeState.syncing;
    } else if (!paired) {
      badgeState = TodoSyncBadgeState.localOnly;
    } else if (state.revoked) {
      badgeState = TodoSyncBadgeState.revoked;
    } else if (state.lastError != null && state.lastError!.isNotEmpty) {
      badgeState = TodoSyncBadgeState.error;
    } else if (pendingOutbox > 0 || unsyncedIds.isNotEmpty || pendingPc == null) {
      badgeState = TodoSyncBadgeState.savedOnDevice;
    } else if (pendingPc > 0) {
      badgeState = TodoSyncBadgeState.waitingPc;
    } else if (!state.hasCompletedSync) {
      badgeState = TodoSyncBadgeState.savedOnDevice;
    } else {
      badgeState = TodoSyncBadgeState.synced;
    }

    return TodoSyncStatus(
      state: badgeState,
      paired: paired,
      deviceId: state.deviceId,
      pendingOutbox: pendingOutbox,
      pendingPc: pendingPc,
      lastSyncedAt: state.lastSyncedAt,
      lastError: state.lastError,
      quarantinedCount: state.quarantinedEnvelopes.length,
      poisonCount: state.poisonCount,
      revoked: state.revoked,
      conflicts: conflicts,
      unsyncedItemIds: unsyncedIds,
      hasCompletedSync: state.hasCompletedSync,
      awaitingPcIds: state.awaitingPcIds,
    );
  }

  Future<_SyncFileState> _readOrInitState(
    String filePath, {
    String? preferredDeviceId,
  }) async {
    final file = File(filePath);
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            final state = _SyncFileState.fromJson(decoded);
            if (state.deviceId.trim().isEmpty) {
              state.deviceId = (preferredDeviceId != null &&
                      preferredDeviceId.trim().isNotEmpty)
                  ? preferredDeviceId.trim()
                  : _uuidGenerator();
              await _writeStateAtomic(filePath, state);
            }
            return state;
          }
        }
      } catch (e) {
        _logger.warning('Corrupted todo-sync-v1.json reset (${e.runtimeType})');
      }
    }

    final initialDeviceId =
        (preferredDeviceId != null && preferredDeviceId.trim().isNotEmpty)
            ? preferredDeviceId.trim()
            : _uuidGenerator();
    final state = _SyncFileState.empty(deviceId: initialDeviceId);
    await _writeStateAtomic(filePath, state);
    return state;
  }

  Future<void> _writeStateAtomic(String filePath, _SyncFileState state) async {
    final dir = Directory(p.dirname(filePath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final tmp = File('$filePath.tmp-${DateTime.now().microsecondsSinceEpoch}');
    await tmp.writeAsString(jsonEncode(state.toJson()), flush: true);
    await tmp.rename(filePath);
  }

  void _setExtraFields(
    _SyncFileState state,
    String entityId,
    Map<String, dynamic> extras,
  ) {
    if (extras.isEmpty) {
      state.extraFields.remove(entityId);
      state.baseExtraFields.remove(entityId);
    } else {
      state.extraFields[entityId] = _deepCloneJsonMap(extras);
      state.baseExtraFields[entityId] = _deepCloneJsonMap(extras);
    }
  }

  void _clearConflictsForEntity(_SyncFileState state, String entityId) {
    state.conflicts.removeWhere((_, c) => c.entityId == entityId);
  }

  bool _hasAppliedMutation(_SyncFileState state, String mutationId) =>
      state.appliedMutations.any((m) => m.mutationId == mutationId);

  void _recordAppliedMutation(
    _SyncFileState state,
    String mutationId,
    int nowMs,
  ) {
    if (_hasAppliedMutation(state, mutationId)) return;
    state.appliedMutations.add(
      _AppliedMutationRecord(mutationId: mutationId, appliedAtMs: nowMs),
    );
  }

  void _pruneAppliedMutations(_SyncFileState state, int nowMs) {
    final cutoffMs = nowMs - _ninetyDays.inMilliseconds;
    state.appliedMutations.removeWhere((m) => m.appliedAtMs < cutoffMs);
    if (state.appliedMutations.length > _maxAppliedMutations) {
      final excess = state.appliedMutations.length - _maxAppliedMutations;
      state.appliedMutations.removeRange(0, excess);
    }
  }

  void _appendQuarantine({
    required _SyncFileState state,
    required int seq,
    required String receivedAt,
    required Map<String, dynamic> rawMap,
  }) {
    state.quarantinedEnvelopes.add({
      'seq': seq,
      'received_at': receivedAt,
      'contract_version': rawMap['contract_version'],
      'entity_type': rawMap['entity_type'],
      'entity_id': rawMap['entity_id'],
      'mutation_id': rawMap['mutation_id'],
      'envelope': _deepCloneJsonMap(rawMap),
    });
    if (state.quarantinedEnvelopes.length > _maxQuarantinedEnvelopes) {
      final excess =
          state.quarantinedEnvelopes.length - _maxQuarantinedEnvelopes;
      state.quarantinedEnvelopes.removeRange(0, excess);
    }
  }
}

TodoItem? _applyConflictText(
  TodoItem existing, {
  required String field,
  required String text,
  required int version,
}) {
  if (field == 'text') {
    return existing.copyWith(text: text, version: version);
  }
  if (field.startsWith('subtasks.') && field.endsWith('.text')) {
    final subId = field.substring(
      'subtasks.'.length,
      field.length - '.text'.length,
    );
    var found = false;
    final updatedSubtasks = [
      for (final sub in existing.subtasks)
        if (sub.id == subId)
          (() {
            found = true;
            return sub.copyWith(text: text);
          })()
        else
          sub,
    ];
    if (!found) return null;
    return existing.copyWith(subtasks: updatedSubtasks, version: version);
  }
  return null;
}

bool _remoteWinsLww({
  required String localTs,
  required String localDev,
  required String remoteTs,
  required String remoteDev,
}) {
  final remoteMicros = _parseUtcMicros(remoteTs);
  final localMicros = _parseUtcMicros(localTs);
  if (remoteMicros != null && localMicros != null) {
    if (remoteMicros != localMicros) {
      return remoteMicros > localMicros;
    }
    return remoteDev.compareTo(localDev) > 0;
  }
  final cmp = remoteTs.compareTo(localTs);
  if (cmp != 0) return cmp > 0;
  return remoteDev.compareTo(localDev) > 0;
}

int? _parseUtcMicros(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw.trim())?.toUtc().microsecondsSinceEpoch;
}

({String text, TaskTextConflict? conflict}) _mergeFreeText({
  required String entityId,
  required String field,
  required String? baseText,
  required String localText,
  required String remoteText,
  required String localTs,
  required String remoteTs,
  required bool remoteWins,
}) {
  final bothDiverged = baseText != null
      ? localText != baseText && remoteText != baseText && localText != remoteText
      : localText != remoteText;

  if (bothDiverged) {
    final winnerSide = remoteWins ? 'remote' : 'local';
    final winnerText = remoteWins ? remoteText : localText;
    final loserText = remoteWins ? localText : remoteText;
    final conflict = TaskTextConflict(
      id: '$entityId:$field',
      entityId: entityId,
      field: field,
      localText: localText,
      remoteText: remoteText,
      winnerSide: winnerSide,
      winnerText: winnerText,
      loserText: loserText,
      localUpdatedAt: localTs,
      remoteUpdatedAt: remoteTs,
      conflictState: 'pending_review',
    );
    return (text: winnerText, conflict: conflict);
  }

  if (baseText != null && localText == baseText && remoteText != baseText) {
    return (text: remoteText, conflict: null);
  }
  return (text: localText, conflict: null);
}

({bool done, String? doneAt}) _mergeDone({
  required TodoItem? base,
  required TodoItem local,
  required TodoItem remote,
}) {
  if (base != null) {
    final lChanged = local.done != base.done || local.doneAt != base.doneAt;
    final rChanged = remote.done != base.done || remote.doneAt != base.doneAt;
    if (!lChanged && rChanged) {
      return (done: remote.done, doneAt: remote.doneAt);
    }
    if ((lChanged && !rChanged) || (!lChanged && !rChanged)) {
      return (done: local.done, doneAt: local.doneAt);
    }
  }

  if (local.done && remote.done) {
    return (
      done: true,
      doneAt: _earlierOptIso(local.doneAt, remote.doneAt),
    );
  }
  if (local.done) {
    return (done: true, doneAt: local.doneAt);
  }
  if (remote.done) {
    return (done: true, doneAt: remote.doneAt);
  }
  return (done: false, doneAt: null);
}

String? _mergeDeletedAt({
  required String? baseDeletedAt,
  required bool hasBase,
  required String? localDeletedAt,
  required String? remoteDeletedAt,
  required bool remoteWins,
}) {
  if (hasBase && baseDeletedAt != null) {
    if (localDeletedAt == baseDeletedAt && remoteDeletedAt == null) {
      return null;
    }
    if (remoteDeletedAt == baseDeletedAt && localDeletedAt == null) {
      return null;
    }
  }
  if (localDeletedAt == null && remoteDeletedAt == null) return null;
  if (localDeletedAt != null && remoteDeletedAt == null) return localDeletedAt;
  if (localDeletedAt == null && remoteDeletedAt != null) return remoteDeletedAt;
  if (localDeletedAt == remoteDeletedAt || !remoteWins) return localDeletedAt;
  return remoteDeletedAt;
}

String? _mergeSnoozedUntil({
  required String? baseSnoozedUntil,
  required bool hasBase,
  required String? localSnoozedUntil,
  required String? remoteSnoozedUntil,
  required bool remoteWins,
}) {
  if (hasBase) {
    final lChanged = localSnoozedUntil != baseSnoozedUntil;
    final rChanged = remoteSnoozedUntil != baseSnoozedUntil;
    if (!lChanged && rChanged) return remoteSnoozedUntil;
    if (!rChanged) return localSnoozedUntil;
  }
  return _laterOptIso(localSnoozedUntil, remoteSnoozedUntil, remoteWins);
}

String? _earlierOptIso(String? a, String? b) {
  if (a == null) return b;
  if (b == null) return a;
  final ma = _parseUtcMicros(a);
  final mb = _parseUtcMicros(b);
  if (ma != null && mb != null && ma != mb) {
    return ma <= mb ? a : b;
  }
  return a.compareTo(b) <= 0 ? a : b;
}

String? _laterOptIso(String? a, String? b, bool remoteWins) {
  if (a == null) return b;
  if (b == null) return a;
  final ma = _parseUtcMicros(a);
  final mb = _parseUtcMicros(b);
  if (ma != null && mb != null && ma != mb) {
    return ma > mb ? a : b;
  }
  return remoteWins ? b : a;
}

List<TodoSubtask> _mergeSubtasks({
  required String entityId,
  required List<TodoSubtask>? base,
  required List<TodoSubtask> local,
  required List<TodoSubtask> remote,
  required String localTs,
  required String remoteTs,
  required bool remoteWins,
  required List<TaskTextConflict> conflictsOut,
}) {
  final baseMap = {
    if (base != null)
      for (final s in base) s.id: s,
  };
  final localMap = {for (final s in local) s.id: s};
  final remoteMap = {for (final s in remote) s.id: s};

  final orderedIds = _collectSubtaskOrder(
    base: base,
    local: local,
    remote: remote,
    remoteWins: remoteWins,
  );
  final out = <TodoSubtask>[];

  for (final subId in orderedIds) {
    final bSub = baseMap[subId];
    final lSub = localMap[subId];
    final rSub = remoteMap[subId];

    if (lSub != null && rSub != null) {
      final bool done;
      if (bSub != null) {
        if (lSub.done == bSub.done && rSub.done != bSub.done) {
          done = rSub.done;
        } else if (rSub.done == bSub.done && lSub.done != bSub.done) {
          done = lSub.done;
        } else {
          done = lSub.done || rSub.done;
        }
      } else {
        done = lSub.done || rSub.done;
      }

      final textMerge = _mergeFreeText(
        entityId: entityId,
        field: 'subtasks.$subId.text',
        baseText: bSub?.text,
        localText: lSub.text,
        remoteText: rSub.text,
        localTs: localTs,
        remoteTs: remoteTs,
        remoteWins: remoteWins,
      );
      if (textMerge.conflict != null) {
        conflictsOut.add(textMerge.conflict!);
      }
      out.add(TodoSubtask(id: subId, text: textMerge.text, done: done));
    } else if (bSub != null && lSub != null && rSub == null) {
      if (!_sameSubtask(lSub, bSub) && !remoteWins) {
        out.add(lSub);
      }
    } else if (bSub != null && lSub == null && rSub != null) {
      if (!_sameSubtask(rSub, bSub) && remoteWins) {
        out.add(rSub);
      }
    } else if (bSub == null && lSub != null) {
      out.add(lSub);
    } else if (bSub == null && rSub != null) {
      out.add(rSub);
    }
  }
  return out;
}

List<String> _collectSubtaskOrder({
  required List<TodoSubtask>? base,
  required List<TodoSubtask> local,
  required List<TodoSubtask> remote,
  required bool remoteWins,
}) {
  final order = <String>[];
  void pushUnique(String id) {
    if (!order.contains(id)) order.add(id);
  }

  if (base != null) {
    final baseIds = {for (final s in base) s.id};
    final localIds = {for (final s in local) s.id};
    final remoteIds = {for (final s in remote) s.id};

    final bExisting = [
      for (final s in base)
        if (localIds.contains(s.id) && remoteIds.contains(s.id)) s.id,
    ];
    final lExisting = [
      for (final s in local)
        if (baseIds.contains(s.id) && remoteIds.contains(s.id)) s.id,
    ];
    final rExisting = [
      for (final s in remote)
        if (baseIds.contains(s.id) && localIds.contains(s.id)) s.id,
    ];

    final List<TodoSubtask> firstSlice;
    final List<TodoSubtask> secondSlice;
    if (_listEquals(rExisting, bExisting) && !_listEquals(lExisting, bExisting)) {
      firstSlice = local;
      secondSlice = remote;
    } else if (_listEquals(lExisting, bExisting) &&
        !_listEquals(rExisting, bExisting)) {
      firstSlice = remote;
      secondSlice = local;
    } else if (remoteWins) {
      firstSlice = remote;
      secondSlice = local;
    } else {
      firstSlice = local;
      secondSlice = remote;
    }

    for (final s in firstSlice) {
      if (baseIds.contains(s.id)) pushUnique(s.id);
    }
    for (final s in secondSlice) {
      if (baseIds.contains(s.id)) pushUnique(s.id);
    }
    final winner = remoteWins ? remote : local;
    final loser = remoteWins ? local : remote;
    for (final s in winner) {
      if (!baseIds.contains(s.id)) pushUnique(s.id);
    }
    for (final s in loser) {
      if (!baseIds.contains(s.id)) pushUnique(s.id);
    }
    return order;
  }

  final winner = remoteWins ? remote : local;
  final loser = remoteWins ? local : remote;
  for (final s in winner) {
    pushUnique(s.id);
  }
  for (final s in loser) {
    pushUnique(s.id);
  }
  return order;
}

T _mergeFieldLww<T>({
  required bool hasBase,
  required T? baseVal,
  required T localVal,
  required T remoteVal,
  required bool remoteWins,
  bool Function(T a, T b)? equals,
}) {
  bool eq(T a, T b) => equals != null ? equals(a, b) : a == b;
  if (hasBase) {
    final lChanged = !eq(localVal, baseVal as T);
    final rChanged = !eq(remoteVal, baseVal);
    if (!lChanged && rChanged) return remoteVal;
    if (!rChanged) return localVal;
  }
  if (eq(localVal, remoteVal) || !remoteWins) return localVal;
  return remoteVal;
}

Map<String, dynamic> _mergeExtraFields({
  required Map<String, dynamic> localExtras,
  required Map<String, dynamic> remoteExtras,
  required bool remoteWins,
}) {
  final merged = <String, dynamic>{};
  for (final entry in localExtras.entries) {
    if (!remoteExtras.containsKey(entry.key)) {
      merged[entry.key] = _deepCloneJsonValue(entry.value);
    }
  }
  for (final entry in remoteExtras.entries) {
    final lVal = localExtras[entry.key];
    if (localExtras.containsKey(entry.key)) {
      final pickRemote = _jsonEquals(lVal, entry.value) || remoteWins;
      merged[entry.key] = _deepCloneJsonValue(pickRemote ? entry.value : lVal);
    } else {
      merged[entry.key] = _deepCloneJsonValue(entry.value);
    }
  }
  return merged;
}

bool _sameSubtask(TodoSubtask a, TodoSubtask b) =>
    a.id == b.id && a.text == b.text && a.done == b.done;

bool _sameRecurrence(TodoRecurrence? a, TodoRecurrence? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.frequency == b.frequency &&
      a.dayOfMonth == b.dayOfMonth &&
      _listEquals(a.weekdays, b.weekdays);
}

bool _sameSource(TodoSource? a, TodoSource? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.sessionId == b.sessionId &&
      a.itemId == b.itemId &&
      a.excerpt == b.excerpt &&
      a.clock == b.clock;
}

bool _sameTaskContentIgnoringVersion(TodoItem a, TodoItem b) {
  if (a.id != b.id ||
      a.text != b.text ||
      a.due != b.due ||
      a.dueDate != b.dueDate ||
      a.dueTime != b.dueTime ||
      a.timeZone != b.timeZone ||
      a.alertMinutes != b.alertMinutes ||
      a.priority != b.priority ||
      a.seriesId != b.seriesId ||
      a.done != b.done ||
      a.createdAt != b.createdAt ||
      a.doneAt != b.doneAt ||
      a.snoozedUntil != b.snoozedUntil ||
      a.sourceStale != b.sourceStale ||
      a.deletedAt != b.deletedAt) {
    return false;
  }
  if (!_sameRecurrence(a.recurrence, b.recurrence)) return false;
  if (!_sameSource(a.source, b.source)) return false;
  if (a.subtasks.length != b.subtasks.length) return false;
  for (var i = 0; i < a.subtasks.length; i++) {
    if (!_sameSubtask(a.subtasks[i], b.subtasks[i])) return false;
  }
  return true;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _jsonEquals(dynamic a, dynamic b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_jsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

Map<String, dynamic> _extractExtraFields(Map<String, dynamic> payload) {
  final extras = <String, dynamic>{};
  for (final entry in payload.entries) {
    if (!_knownTaskFieldKeys.contains(entry.key)) {
      extras[entry.key] = _deepCloneJsonValue(entry.value);
    }
  }
  return extras;
}

dynamic _deepCloneJsonValue(dynamic value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _deepCloneJsonValue(entry.value),
    };
  }
  if (value is List) {
    return [for (final item in value) _deepCloneJsonValue(item)];
  }
  return value;
}

Map<String, dynamic> _deepCloneJsonMap(Map<String, dynamic> map) =>
    <String, dynamic>{
      for (final entry in map.entries)
        entry.key: _deepCloneJsonValue(entry.value),
    };

String _sha256Hex(String value) =>
    sha256.convert(utf8.encode(value)).toString();

String _sanitizeErrorType(Object error) {
  if (error is SocketException) return 'network_unavailable';
  if (error is TimeoutException) return 'network_timeout';
  if (error is HttpException) return 'network_http';
  return error.runtimeType.toString();
}

int _requireInt(Object? value, String field) {
  if (value is int) return value;
  throw FormatException('$field must be an int');
}

String _requireNonEmptyString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value.trim();
}

String _requireStringAllowEmpty(Object? value, String field) {
  if (value is! String) {
    throw FormatException('$field must be a string');
  }
  return value;
}

enum _DecodedKind { validTask, quarantine, poison }

class _DecodedMailboxRecord {
  final _DecodedKind kind;
  final int seq;
  final SyncEnvelope? envelope;
  final TodoItem? remoteItem;
  final Map<String, dynamic>? remoteExtras;
  final Map<String, dynamic>? rawEnvelope;
  final int attemptCount;
  final bool dropAndAck;

  const _DecodedMailboxRecord._({
    required this.kind,
    required this.seq,
    this.envelope,
    this.remoteItem,
    this.remoteExtras,
    this.rawEnvelope,
    this.attemptCount = 0,
    this.dropAndAck = false,
  });

  factory _DecodedMailboxRecord.validTask({
    required int seq,
    required SyncEnvelope envelope,
    required TodoItem remoteItem,
    required Map<String, dynamic> remoteExtras,
  }) =>
      _DecodedMailboxRecord._(
        kind: _DecodedKind.validTask,
        seq: seq,
        envelope: envelope,
        remoteItem: remoteItem,
        remoteExtras: remoteExtras,
      );

  factory _DecodedMailboxRecord.quarantine({
    required int seq,
    required Map<String, dynamic> rawEnvelope,
  }) =>
      _DecodedMailboxRecord._(
        kind: _DecodedKind.quarantine,
        seq: seq,
        rawEnvelope: rawEnvelope,
      );

  factory _DecodedMailboxRecord.poison({required int seq}) =>
      _DecodedMailboxRecord._(kind: _DecodedKind.poison, seq: seq);

  factory _DecodedMailboxRecord.poisonDecision({
    required int seq,
    required int attemptCount,
    required bool dropAndAck,
  }) =>
      _DecodedMailboxRecord._(
        kind: _DecodedKind.poison,
        seq: seq,
        attemptCount: attemptCount,
        dropAndAck: dropAndAck,
      );
}

class _OutboxEntry {
  final SyncEnvelope envelope;
  final int queuedAtMs;

  const _OutboxEntry({
    required this.envelope,
    required this.queuedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'envelope': envelope.toJson(),
        'queued_at_ms': queuedAtMs,
      };

  static _OutboxEntry fromJson(Map<String, dynamic> json) => _OutboxEntry(
        envelope: SyncEnvelope.fromJson(
          (json['envelope'] as Map).cast<String, dynamic>(),
        ),
        queuedAtMs: (json['queued_at_ms'] as num?)?.toInt() ?? 0,
      );
}

class _AppliedMutationRecord {
  final String mutationId;
  final int appliedAtMs;

  const _AppliedMutationRecord({
    required this.mutationId,
    required this.appliedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'mutation_id': mutationId,
        'applied_at_ms': appliedAtMs,
      };

  static _AppliedMutationRecord fromJson(Map<String, dynamic> json) =>
      _AppliedMutationRecord(
        mutationId: _requireNonEmptyString(json['mutation_id'], 'mutation_id'),
        appliedAtMs: (json['applied_at_ms'] as num?)?.toInt() ?? 0,
      );
}

class _ItemSyncMeta {
  final String lastUpdatedAt;
  final String lastDeviceId;
  final bool unsynced;

  const _ItemSyncMeta({
    required this.lastUpdatedAt,
    required this.lastDeviceId,
    required this.unsynced,
  });

  Map<String, dynamic> toJson() => {
        'last_updated_at': lastUpdatedAt,
        'last_device_id': lastDeviceId,
        'unsynced': unsynced,
      };

  static _ItemSyncMeta fromJson(Map<String, dynamic> json) => _ItemSyncMeta(
        lastUpdatedAt: json['last_updated_at']?.toString() ?? '',
        lastDeviceId: json['last_device_id']?.toString() ?? '',
        unsynced: json['unsynced'] == true,
      );
}

class _PendingBaseAncestor {
  final int pushedBaseVersion;
  final TodoItem? item;
  final Map<String, dynamic> extras;

  const _PendingBaseAncestor({
    required this.pushedBaseVersion,
    this.item,
    this.extras = const {},
  });

  Map<String, dynamic> toJson() => {
        'pushed_base_version': pushedBaseVersion,
        'item': item?.toJson(),
        'extras': extras,
      };

  static _PendingBaseAncestor fromJson(Map<String, dynamic> json) =>
      _PendingBaseAncestor(
        pushedBaseVersion:
            (json['pushed_base_version'] as num?)?.toInt() ?? 0,
        item: json['item'] is Map
            ? TodoItem.fromJson((json['item'] as Map).cast<String, dynamic>())
            : null,
        extras: json['extras'] is Map
            ? _deepCloneJsonMap((json['extras'] as Map).cast<String, dynamic>())
            : const {},
      );
}

class _SyncFileState {
  int schemaVersion;
  String deviceId;
  String? pairedRoom;
  int lastPhoneSeq;
  final List<_OutboxEntry> outbox;
  final List<_AppliedMutationRecord> appliedMutations;
  final Map<String, TodoItem> baseCopies;
  final Map<String, Map<String, dynamic>> baseExtraFields;
  final Map<String, Map<String, dynamic>> extraFields;
  final Map<String, _ItemSyncMeta> itemMeta;
  final Map<String, TaskTextConflict> conflicts;
  final List<Map<String, dynamic>> quarantinedEnvelopes;
  final Map<String, int> poisonAttempts;
  final Set<String> awaitingPcIds;
  final Map<String, List<_PendingBaseAncestor>> prePushAncestors;
  int poisonCount;
  int? pendingPc;
  bool hasCompletedSync;
  bool revoked;
  String? lastSyncedAt;
  String? lastError;

  _SyncFileState({
    required this.schemaVersion,
    required this.deviceId,
    this.pairedRoom,
    this.lastPhoneSeq = 0,
    List<_OutboxEntry>? outbox,
    List<_AppliedMutationRecord>? appliedMutations,
    Map<String, TodoItem>? baseCopies,
    Map<String, Map<String, dynamic>>? baseExtraFields,
    Map<String, Map<String, dynamic>>? extraFields,
    Map<String, _ItemSyncMeta>? itemMeta,
    Map<String, TaskTextConflict>? conflicts,
    List<Map<String, dynamic>>? quarantinedEnvelopes,
    Map<String, int>? poisonAttempts,
    Set<String>? awaitingPcIds,
    Map<String, List<_PendingBaseAncestor>>? prePushAncestors,
    this.poisonCount = 0,
    this.pendingPc,
    this.hasCompletedSync = false,
    this.revoked = false,
    this.lastSyncedAt,
    this.lastError,
  })  : outbox = outbox ?? [],
        appliedMutations = appliedMutations ?? [],
        baseCopies = baseCopies ?? {},
        baseExtraFields = baseExtraFields ?? {},
        extraFields = extraFields ?? {},
        itemMeta = itemMeta ?? {},
        conflicts = conflicts ?? {},
        quarantinedEnvelopes = quarantinedEnvelopes ?? [],
        poisonAttempts = poisonAttempts ?? {},
        awaitingPcIds = awaitingPcIds ?? {},
        prePushAncestors = prePushAncestors ?? {};

  factory _SyncFileState.empty({required String deviceId}) => _SyncFileState(
        schemaVersion: _syncSchemaVersion,
        deviceId: deviceId,
      );

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'device_id': deviceId,
        'paired_room': pairedRoom,
        'last_phone_seq': lastPhoneSeq,
        'outbox': [for (final entry in outbox) entry.toJson()],
        'applied_mutations': [for (final m in appliedMutations) m.toJson()],
        'base_copies': {
          for (final entry in baseCopies.entries) entry.key: entry.value.toJson(),
        },
        'base_extra_fields': baseExtraFields,
        'extra_fields': extraFields,
        'item_meta': {
          for (final entry in itemMeta.entries) entry.key: entry.value.toJson(),
        },
        'conflicts': {
          for (final entry in conflicts.entries) entry.key: entry.value.toJson(),
        },
        'quarantined_envelopes': quarantinedEnvelopes,
        'poison_attempts': poisonAttempts,
        'awaiting_pc_ids': awaitingPcIds.toList()..sort(),
        'pre_push_ancestors': {
          for (final entry in prePushAncestors.entries)
            entry.key: [for (final item in entry.value) item.toJson()],
        },
        'poison_count': poisonCount,
        'pending_pc': pendingPc,
        'has_completed_sync': hasCompletedSync,
        'revoked': revoked,
        'last_synced_at': lastSyncedAt,
        'last_error': lastError,
      };

  static _SyncFileState fromJson(Map<String, dynamic> json) {
    final outbox = <_OutboxEntry>[];
    final rawOutbox = json['outbox'];
    if (rawOutbox is List) {
      for (final raw in rawOutbox) {
        if (raw is Map) {
          outbox.add(_OutboxEntry.fromJson(raw.cast<String, dynamic>()));
        }
      }
    }

    final applied = <_AppliedMutationRecord>[];
    final rawApplied = json['applied_mutations'];
    if (rawApplied is List) {
      for (final raw in rawApplied) {
        if (raw is Map) {
          applied.add(
            _AppliedMutationRecord.fromJson(raw.cast<String, dynamic>()),
          );
        }
      }
    }

    final baseCopies = <String, TodoItem>{};
    final rawBase = json['base_copies'];
    if (rawBase is Map) {
      for (final entry in rawBase.entries) {
        if (entry.value is Map) {
          baseCopies[entry.key.toString()] = TodoItem.fromJson(
            (entry.value as Map).cast<String, dynamic>(),
          );
        }
      }
    }

    Map<String, Map<String, dynamic>> readNestedExtras(Object? raw) {
      final result = <String, Map<String, dynamic>>{};
      if (raw is Map) {
        for (final entry in raw.entries) {
          if (entry.value is Map) {
            result[entry.key.toString()] = _deepCloneJsonMap(
              (entry.value as Map).cast<String, dynamic>(),
            );
          }
        }
      }
      return result;
    }

    final itemMeta = <String, _ItemSyncMeta>{};
    final rawMeta = json['item_meta'];
    if (rawMeta is Map) {
      for (final entry in rawMeta.entries) {
        if (entry.value is Map) {
          itemMeta[entry.key.toString()] = _ItemSyncMeta.fromJson(
            (entry.value as Map).cast<String, dynamic>(),
          );
        }
      }
    }

    final conflicts = <String, TaskTextConflict>{};
    final rawConflicts = json['conflicts'];
    if (rawConflicts is Map) {
      for (final entry in rawConflicts.entries) {
        if (entry.value is Map) {
          conflicts[entry.key.toString()] = TaskTextConflict.fromJson(
            (entry.value as Map).cast<String, dynamic>(),
          );
        }
      }
    }

    final quarantined = <Map<String, dynamic>>[];
    final rawQuarantine = json['quarantined_envelopes'];
    if (rawQuarantine is List) {
      for (final raw in rawQuarantine) {
        if (raw is Map) {
          quarantined.add(_deepCloneJsonMap(raw.cast<String, dynamic>()));
        }
      }
    }

    final poisonAttempts = <String, int>{};
    final rawPoison = json['poison_attempts'];
    if (rawPoison is Map) {
      for (final entry in rawPoison.entries) {
        final count = entry.value;
        if (count is num) {
          poisonAttempts[entry.key.toString()] = count.toInt();
        }
      }
    }

    final awaitingPcIds = <String>{};
    final rawAwaiting = json['awaiting_pc_ids'];
    if (rawAwaiting is List) {
      for (final id in rawAwaiting) {
        if (id is String && id.isNotEmpty) {
          awaitingPcIds.add(id);
        }
      }
    }

    final prePushAncestors = <String, List<_PendingBaseAncestor>>{};
    final rawAncestors = json['pre_push_ancestors'];
    if (rawAncestors is Map) {
      for (final entry in rawAncestors.entries) {
        if (entry.value is List) {
          prePushAncestors[entry.key.toString()] = [
            for (final rawItem in entry.value as List)
              if (rawItem is Map)
                _PendingBaseAncestor.fromJson(
                  rawItem.cast<String, dynamic>(),
                ),
          ];
        }
      }
    }

    return _SyncFileState(
      schemaVersion:
          (json['schema_version'] as num?)?.toInt() ?? _syncSchemaVersion,
      deviceId: json['device_id']?.toString() ?? '',
      pairedRoom: json['paired_room']?.toString(),
      lastPhoneSeq: (json['last_phone_seq'] as num?)?.toInt() ?? 0,
      outbox: outbox,
      appliedMutations: applied,
      baseCopies: baseCopies,
      baseExtraFields: readNestedExtras(json['base_extra_fields']),
      extraFields: readNestedExtras(json['extra_fields']),
      itemMeta: itemMeta,
      conflicts: conflicts,
      quarantinedEnvelopes: quarantined,
      poisonAttempts: poisonAttempts,
      awaitingPcIds: awaitingPcIds,
      prePushAncestors: prePushAncestors,
      poisonCount: (json['poison_count'] as num?)?.toInt() ?? 0,
      pendingPc: (json['pending_pc'] as num?)?.toInt(),
      hasCompletedSync: json['has_completed_sync'] == true,
      revoked: json['revoked'] == true,
      lastSyncedAt: json['last_synced_at']?.toString(),
      lastError: json['last_error']?.toString(),
    );
  }
}

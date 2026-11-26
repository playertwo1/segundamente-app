import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

abstract class AgentQueueDrainScheduler {
  Future<void> schedule({Duration? initialDelay, bool expedited});

  /// Schedules the next drain from inside a running drain. [fromFollowUp] is
  /// true when the running drain is itself a follow-up.
  Future<void> scheduleFollowUp({
    required Duration initialDelay,
    required bool fromFollowUp,
  });

  Future<void> cancel();
}

class WorkmanagerAgentQueueDrainScheduler implements AgentQueueDrainScheduler {
  static const String uniqueName = 'agent_queue_drain';
  static const String taskName = 'agentQueueDrainTask';
  static const String tag = 'agent_queue';
  static const String followUpUniqueName = 'agent_queue_drain_follow_up';
  static const String followUpSource = 'agent_queue_follow_up';
  @visibleForTesting
  static const ExistingWorkPolicy existingWorkPolicy = ExistingWorkPolicy.keep;

  @override
  Future<void> schedule({
    Duration? initialDelay,
    bool expedited = false,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    await Workmanager().registerOneOffTask(
      uniqueName,
      taskName,
      inputData: const {'source': 'agent_background_coordinator'},
      initialDelay: initialDelay,
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      existingWorkPolicy: existingWorkPolicy,
      tag: tag,
      outOfQuotaPolicy:
          expedited ? OutOfQuotaPolicy.runAsNonExpeditedWorkRequest : null,
    );
    debugPrint(
      'Agent queue drain scheduled '
      '(delay: ${initialDelay?.inSeconds ?? 0}s, expedited: $expedited)',
    );
  }

  /// KEEP would drop a follow-up: the running drain is still unfinished work
  /// under its own unique name. A follow-up run appends after itself (REPLACE
  /// would cancel it); any other run replaces a stale follow-up.
  @visibleForTesting
  static ExistingWorkPolicy followUpPolicy({required bool fromFollowUp}) =>
      fromFollowUp ? ExistingWorkPolicy.append : ExistingWorkPolicy.replace;

  @override
  Future<void> scheduleFollowUp({
    required Duration initialDelay,
    required bool fromFollowUp,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    await Workmanager().registerOneOffTask(
      followUpUniqueName,
      taskName,
      inputData: const {'source': followUpSource},
      initialDelay: initialDelay,
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      existingWorkPolicy: followUpPolicy(fromFollowUp: fromFollowUp),
      tag: tag,
    );
    debugPrint(
      'Agent queue follow-up drain scheduled '
      '(delay: ${initialDelay.inSeconds}s, fromFollowUp: $fromFollowUp)',
    );
  }

  @override
  Future<void> cancel() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future<void>.value();
    }
    return Workmanager().cancelByUniqueName(uniqueName);
  }
}

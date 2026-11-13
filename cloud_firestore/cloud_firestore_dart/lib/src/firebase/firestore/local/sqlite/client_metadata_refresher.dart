import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:firebase_app_dart/internal.dart';

/// Refreshes the metadata and the primary lease of a client of a SQLite cache every
/// [SQLiteClientMetadata.refreshInterval] (the `ClientMetadataRefresh` timer of the JS SDK).
class ClientMetadataRefresher {
  /// [run] performs a refresh; the client passes a function that puts it on its serial queue.
  ClientMetadataRefresher(
    this._scheduler, {
    required Future<void> Function() run,
  }) : _run = run;

  static const String _tag = 'ClientMetadataRefresher';

  final TaskScheduler _scheduler;
  final Future<void> Function() _run;

  bool _stopped = false;
  TimerTask? _task;

  void start() => _schedule();

  void stop() {
    _stopped = true;
    _task?.cancel();
  }

  void _schedule() {
    _task = _scheduler.add(
      TaskId.clientMetadataRefresh,
      SQLiteClientMetadata.refreshInterval,
      () async {
        try {
          await _run();
        } catch (e) {
          Log.w(_tag, 'Refreshing the client metadata failed: $e');
        }
        if (!_stopped) {
          _schedule();
        }
      },
    );
  }
}

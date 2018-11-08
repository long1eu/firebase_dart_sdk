// File created by
// Lung Razvan <long1eu>
// on 22/10/2018
import 'dart:async';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage/src/internal/task_events.dart';

@publicApi
abstract class Task<TState extends StorageTaskState> {
  /// Attempts to cancel the task. A canceled task cannot be resumed later. A
  /// canceled task throws an exception that indicates the task was canceled.
  ///
  /// Returns true if this task was successfully canceled or is in the process
  /// of being canceled. Returns false if the task is already completed or in a
  /// state that cannot be canceled.
  @publicApi
  Future<bool> cancel();

  /// Attempts to pause the task. A paused task can later be resumed.
  ///
  /// Returns true if this task was successfully paused or is in the process of
  /// being paused. Returns false if the task is already completed or in a state
  /// that cannot be paused.
  @publicApi
  Future<bool> pause();

  /// Attempts to resume this task.
  ///
  /// Returns true if the task is successfully resumed or is in the process of
  /// being resumed. Returns false if the task is already completed or in a
  /// state that cannot be resumed.
  @publicApi
  Future<bool> resume();

  /// Return true if the task has been canceled.
  @publicApi
  Future<bool> get isCanceled;

  /// Return true if the task is currently running.
  @publicApi
  Future<bool> get isInProgress;

  /// Returns true if the task has been paused.
  @publicApi
  Future<bool> get isPaused;

  /// Return this task as a future so you can wait for it to complete.
  Future<void> get future;

  /// Return a stream witch emits events related to the state of this task
  Stream<TaskEvent<TState>> get events;
}

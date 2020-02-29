// File created by
// Lung Razvan <long1eu>
// on 21/10/2018
import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage/src/cancellable_future.dart';

/// Represents an asynchronous operation that can be paused, resumed and
/// canceled.
abstract class ControllableFuture<TState> extends CancellableFuture<TState> {
  /// Attempts to pause the task. A paused task can later be resumed.
  ///
  /// Returns true if this task was successfully paused or is in the process of
  /// being paused. Returns false if the task is already completed or in a state
  /// that cannot be paused.
  bool pause();

  /// Attempts to resume this task.
  ///
  /// Returns true if the task is successfully resumed or is in the process of
  /// being resumed. Returns false if the task is already completed or in a
  /// state that cannot be resumed.
  bool resume();

  /// Returns true if the task has been paused.
  bool get isPaused;
}

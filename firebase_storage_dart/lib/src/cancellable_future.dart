// File created by
// Lung Razvan <long1eu>
// on 21/10/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage/src/util/wrapped_future.dart';

/// Represents an asynchronous operation that can be canceled.
@publicApi
abstract class CancellableFuture<TState> extends WrappedFuture<TState> {
  /// Attempts to cancel the task. A canceled task cannot be resumed later. A
  /// canceled task throws an exception that indicates the task was canceled.
  ///
  /// Returns true if this task was successfully canceled or is in the process
  /// of being canceled. Returns false if the task is already completed or in a
  /// state that cannot be canceled.
  @publicApi
  bool cancel();

  /// Return true if the task has been canceled.
  @publicApi
  bool get isCanceled;

  /// Return true if the task is currently running.
  @publicApi
  bool get isInProgress;
}

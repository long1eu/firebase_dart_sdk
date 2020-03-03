// File created by
// Lung Razvan <long1eu>
// on 21/10/2018

import 'dart:async';
import 'dart:isolate';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage_vm/src/internal/task_events.dart';
import 'package:firebase_storage_vm/src/storage_reference.dart';
import 'package:firebase_storage_vm/src/storage_task_manager.dart';
import 'package:meta/meta.dart';

/// A controllable Task that has a synchronized state machine.
abstract class StorageTask<TResult extends StorageTaskState> {
  StorageTask(this._sendPort) : _completer = Completer<void>();

  static const String _tag = 'StorageTask';

  static const int kInternalStateNotStarted = 1;
  static const int kInternalStateQueued = 2;
  static const int kInternalStateInProgress = 4;
  static const int kInternalStatePausing = 8;
  static const int kInternalStatePaused = 16;
  static const int kInternalStateCanceling = 32;
  static const int kInternalStateFailure = 64;
  static const int kInternalStateSuccess = 128;
  static const int kInternalStateCanceled = 256;
  static const int kStatesSuccess = kInternalStateSuccess;
  static const int kStatesPaused = kInternalStatePaused;
  static const int kStatesFailure = kInternalStateFailure;
  static const int kStatesCanceled = kInternalStateCanceled;
  static const int kStateComplete =
      kStatesSuccess | kStatesFailure | kStatesCanceled;
  static const int kStatesInprogress = ~(kStateComplete | kStatesPaused);

  static final Map<int, Set<int>> _validUserInitiatedStateChanges =
      <int, Set<int>>{
    kInternalStateNotStarted: <int>{
      kInternalStatePaused,
      kInternalStateCanceled
    },
    kInternalStateQueued: <int>{kInternalStatePausing, kInternalStateCanceling},
    kInternalStateInProgress: <int>{
      kInternalStatePausing,
      kInternalStateCanceling
    },
    kInternalStatePaused: <int>{kInternalStateQueued, kInternalStateCanceled},
    kInternalStateFailure: <int>{kInternalStateQueued, kInternalStateCanceled},
  };

  static final Map<int, Set<int>> _validTaskInitiatedStateChanges =
      <int, Set<int>>{
    kInternalStateNotStarted: <int>{
      kInternalStateQueued,
      kInternalStateFailure
    },
    kInternalStateQueued: <int>{
      kInternalStateInProgress,
      kInternalStateFailure,
      kInternalStateSuccess
    },
    kInternalStateInProgress: <int>{
      kInternalStateInProgress,
      kInternalStateFailure,
      kInternalStateSuccess
    },
    kInternalStatePausing: <int>{
      kInternalStatePaused,
      kInternalStateFailure,
      kInternalStateSuccess
    },
    kInternalStateCanceling: <int>{
      kInternalStateCanceled,
      kInternalStateFailure,
      kInternalStateSuccess
    },
  };

  final SendPort _sendPort;
  final Completer<void> _completer;
  int _currentState = kInternalStateNotStarted;
  TResult _finalResult;

  Future<void> get future => _completer.future;

  int get internalState => _currentState;

  /// Returns true if successful or false if the [internalState] is one which
  /// does not allow the task to be queued.
  //@visibleForTesting
  bool queue() {
    if (tryChangeState(state: kInternalStateQueued, userInitiated: false)) {
      scheduleTask();
      return true;
    }
    return false;
  }

  //@visibleForTesting
  void resetState() {}

  //@visibleForTesting
  StorageReference get reference;

  //@visibleForTesting
  Future<void> scheduleTask();

  /// Attempts to resume a paused task.
  ///
  /// Returns true if the task is successfully resumed, false if the task has an
  /// unrecoverable error or has entered another state that precludes resume.
  bool resume() {
    if (tryChangeState(state: kInternalStateQueued, userInitiated: true)) {
      resetState();
      scheduleTask();
      return true;
    }
    return false;
  }

  /// Attempts to pause the task. A paused task can later be resumed.
  ///
  /// Returns true if this task is successfully being paused. Note that a task
  /// may not be immediately paused if it was executing another action and can
  /// still fail or complete.
  bool pause() {
    return tryChangeState(
        states: <int>[kInternalStatePaused, kInternalStatePausing],
        userInitiated: true);
  }

  /// Attempts to cancel the task. A canceled task cannot be resumed later.
  ///
  /// Returns true if this task is successfully being canceled.
  bool cancel() {
    return tryChangeState(
        states: <int>[kInternalStateCanceled, kInternalStateCanceling],
        userInitiated: true);
  }

  /// Returns true if the Task is complete, false otherwise.
  bool get isComplete => (_currentState & kStateComplete) != 0;

  /// Returns true if the Task has completed successfully, false otherwise.
  bool get isSuccessful => (_currentState & kStatesSuccess) != 0;

  /// Returns true if the task has been canceled.
  bool get isCanceled => _currentState == kInternalStateCanceled;

  /// Returns true if the task is currently running.
  bool get isInProgress => (_currentState & kStatesInprogress) != 0;

  /// Returns true if the task has been paused.
  bool get isPaused => (_currentState & kStatesPaused) != 0;

  /// Returns the current state of the task. This method will return state at
  /// any point of the tasks execution and may not be the final result..
  TResult get snapshot => snapState;

  //@visibleForTesting
  TResult get snapState => snapStateImpl;

  //@visibleForTesting
  TResult get snapStateImpl;

  /// Tries to change the current state into one of the requested states. State
  /// transitions are attempted in order (index 0 is first).
  ///
  /// Returns whether at least one state transition was successful.
  //@visibleForTesting
  bool tryChangeState(
      {@required bool userInitiated, int state, List<int> states}) {
    final List<int> _states = state != null ? <int>[state] : states;
    final Map<int, Set<int>> table = userInitiated
        ? _validUserInitiatedStateChanges
        : _validTaskInitiatedStateChanges;

    for (int newState in _states) {
      final Set<int> validStates = table[_currentState];
      if (validStates != null && validStates.contains(newState)) {
        final int oldState = _currentState;
        _currentState = newState;
        switch (_currentState) {
          case kInternalStateQueued:
            StorageTaskManager.instance.ensureRegistered(this);
            onQueued();
            break;
          case kInternalStateInProgress:
            onProgress();
            break;
          case kInternalStatePaused:
            onPaused();
            break;
          case kInternalStateFailure:
            onFailure();
            break;
          case kInternalStateSuccess:
            onSuccess();
            break;
          case kInternalStateCanceled:
            onCanceled();
            break;
        }
        _onInternalStateChanged();

        Log.d(
            _tag,
            'changed internal state to: ${_getStateString(state: newState)} '
            'isUser: $userInitiated from state: '
            '${_getStateString(state: oldState)}');

        return true;
      }
    }

    Log.w(
        _tag,
        'unable to change internal state to: '
        '${_getStateString(states: _states)} isUser: $userInitiated from '
        'state: ${_getStateString(state: _currentState)}');

    return false;
  }

  void _onInternalStateChanged() {
    TaskEvent<TResult> event;
    if ((internalState & kStatesSuccess) != 0) {
      event = TaskEvent<TResult>.success(_getFinalResult());
      _sendPort.send(event.serialize);
    }

    if ((internalState & kStatesFailure) != 0) {
      event = TaskEvent<TResult>.error(_getFinalResult());
      _sendPort.send(event.serialize);
    }

    if ((internalState & kStatesCanceled) != 0) {
      event = TaskEvent<TResult>.error(_getFinalResult());
      _sendPort.send(event.serialize);
    }

    if ((internalState & kStateComplete) != 0) {
      StorageTaskManager.instance.unRegister(this);
      event = TaskEvent<TResult>.complete();
      _sendPort.send(event.serialize);
      _completer.complete();
    }

    if ((internalState & kStatesInprogress) != 0) {
      event = TaskEvent<TResult>.progressed(snapStateImpl);
      _sendPort.send(event.serialize);
    }

    if ((internalState & kStatesPaused) != 0) {
      event = TaskEvent<TResult>.paused();
      _sendPort.send(event.serialize);
    }

    Log.d(_tag, 'Event sent: ${event.type}');
  }

  void onQueued() {}

  void onProgress() {}

  void onPaused() {}

  void onFailure() {}

  void onSuccess() {}

  void onCanceled() {}

  TResult _getFinalResult() {
    if (_finalResult != null) {
      return _finalResult;
    }

    if (!isComplete) {
      return null;
    }

    return _finalResult ??= snapState;
  }

  @visibleForTesting
  Future<void> run();

  @visibleForTesting
  Future<void> Function() getRunnable() {
    return () async {
      try {
        await run();
      } finally {
        ensureFinalState();
      }
    };
  }

  void ensureFinalState() {
    // Ensure that we have entered into a final state.
    // Worst case, we enter a failure final state to indicate something bad
    // happened but we need to ensure the user was notified that we are no
    // longer running. There is also a chance the task was re-queued before
    // run() finished. This might be ok -- so we allow queued. Tasks should
    // immediately switch to 'in progress' as their first action to ensure this
    // doesn't cause an issue.
    if (!isComplete && !isPaused && _currentState != kInternalStateQueued) {
      // We first try to complete a cancel operation and if that fails, we just
      // fail the operation.
      if (!tryChangeState(
          state: kInternalStateCanceled, userInitiated: false)) {
        tryChangeState(state: kInternalStateFailure, userInitiated: false);
      }
    }
  }

  String _getStateString({int state, List<int> states}) {
    if (state != null) {
      switch (state) {
        case kInternalStateNotStarted:
          return 'INTERNAL_STATE_NOT_STARTED';
        case kInternalStateQueued:
          return 'INTERNAL_STATE_QUEUED';
        case kInternalStateInProgress:
          return 'INTERNAL_STATE_IN_PROGRESS';
        case kInternalStatePausing:
          return 'INTERNAL_STATE_PAUSING';
        case kInternalStatePaused:
          return 'INTERNAL_STATE_PAUSED';
        case kInternalStateCanceling:
          return 'INTERNAL_STATE_CANCELING';
        case kInternalStateFailure:
          return 'INTERNAL_STATE_FAILURE';
        case kInternalStateSuccess:
          return 'INTERNAL_STATE_SUCCESS';
        case kInternalStateCanceled:
          return 'INTERNAL_STATE_CANCELED';
        default:
          return 'Unknown Internal State!';
      }
    } else {
      if (states.isEmpty) {
        return '';
      }

      final StringBuffer builder = StringBuffer();

      for (int state in states) {
        builder..write(_getStateString(state: state))..write(', ');
      }

      return builder.toString().substring(0, builder.length - 2);
    }
  }
}

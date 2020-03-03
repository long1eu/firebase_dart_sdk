// File created by
// Lung Razvan <long1eu>
// on 24/09/2018

import 'dart:async';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/online_state.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_store.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:grpc/grpc.dart';

/// Called whenever the online state of the client changes. This is based on the watch stream for
/// now.
typedef OnlineStateCallback = Future<void> Function(OnlineState onlineState);

/// A component used by the [RemoteStore] to track the [OnlineState] (that is, whether or not the
/// client as a whole should be considered to be online or offline), implementing the appropriate
/// heuristics.
///
/// In particular, when the client is trying to connect to the backend, we allow up to
/// [_maxWatchStreamFailures] within [_onlineStateTimeoutMs] for a connection to succeed. If we have
/// too many failures or the timeout elapses, then we set the [OnlineState] to
/// [OnlineState.offline], and the client will behave as if it is offline (get() calls will return
/// cached data, etc.).
class OnlineStateTracker {
  OnlineStateTracker(this._workerQueue, this._onlineStateCallback)
      : _state = OnlineState.unknown,
        _shouldWarnClientIsOffline = false;

  /// To deal with transient failures, we allow multiple stream attempts before giving up and
  /// transitioning from [OnlineState.unknown] to [OnlineState.offline].
  ///
  // TODO(mikelehen): This used to be set to 2 as a mitigation for b/66228394. @jdimond thinks that
  //  bug is sufficiently fixed so that we can set this back to 1. If that works okay, we could
  //  potentially remove this logic entirely.
  static const int _maxWatchStreamFailures = 1;

  /// To deal with stream attempts that don't succeed or fail in a timely manner, we have a timeout
  /// for [OnlineState] to reach [OnlineState.online] or [OnlineState.offline]. If the timeout is
  /// reached, we transition to [OnlineState.offline] rather than waiting indefinitely.
  static const int _onlineStateTimeoutMs = 10 * 1000;

  /// The log tag to use for this class.
  static const String _tag = 'OnlineStateTracker';

  /// The current OnlineState.
  OnlineState _state;

  /// A count of consecutive failures to open the stream. If it reaches the maximum defined by
  /// [_maxWatchStreamFailures], we'll revert to [OnlineState.offline].
  int _watchStreamFailures;

  /// A timer that elapses after [_onlineStateTimeoutMs], at which point we transition from
  /// [OnlineState.unknown] to [OnlineState.offline] without waiting for the stream to actually fail
  /// ([_maxWatchStreamFailures] times).
  DelayedTask<void> _onlineStateTimer;

  /// Whether the client should log a warning message if it fails to connect to the backend
  /// (initially true, cleared after a successful stream, or if we've logged the message already).
  bool _shouldWarnClientIsOffline;

  /// The AsyncQueue to use for running timers (and calling [OnlineStateCallback] methods).
  final AsyncQueue _workerQueue;

  /// The callback to notify on OnlineState changes.
  final OnlineStateCallback _onlineStateCallback;

  /// Called by [RemoteStore] when a watch stream is started (including on each backoff attempt).
  ///
  /// If this is the first attempt, it sets the [OnlineState] to [OnlineState.unknown] and starts
  /// the [_onlineStateTimer].
  Future<void> handleWatchStreamStart() async {
    if (_watchStreamFailures == 0) {
      await _setAndBroadcastState(OnlineState.unknown);

      hardAssert(_onlineStateTimer == null, 'onlineStateTimer shouldn\'t be started yet');
      _onlineStateTimer = _workerQueue.enqueueAfterDelay<void>(
        TimerId.onlineStateTimeout,
        const Duration(milliseconds: _onlineStateTimeoutMs),
        () async {
          _onlineStateTimer = null;
          hardAssert(_state == OnlineState.unknown,
              'Timer should be canceled if we transitioned to a different state.');
          _logClientOfflineWarningIfNecessary(
              'Backend didn\'t respond within ${_onlineStateTimeoutMs / 1000} seconds\n');
          await _setAndBroadcastState(OnlineState.offline);

          // NOTE: [handleWatchStreamFailure] will continue to increment [watchStreamFailures] even
          // though we are already marked [OnlineState.offline] but this is non-harmful.
        },
        'OnlineStateTracker handleWatchStreamStart',
      );
    }
  }

  /// Called by [RemoteStore] when a watch stream fails.
  ///
  /// Updates our [OnlineState] as appropriate. The first failure moves us to [OnlineState.unknown].
  /// We then may allow multiple failures (based on [_maxWatchStreamFailures]) before we actually
  /// transition to [OnlineState.offline].
  Future<void> handleWatchStreamFailure(GrpcError status) async {
    if (_state == OnlineState.online) {
      await _setAndBroadcastState(OnlineState.unknown);

      // To get to [OnlineState.online], [updateState] must have been called which would have reset
      // our heuristics.
      hardAssert(_watchStreamFailures == 0, 'watchStreamFailures must be 0');
      hardAssert(_onlineStateTimer == null, 'onlineStateTimer must be null');
    } else {
      _watchStreamFailures++;
      if (_watchStreamFailures >= _maxWatchStreamFailures) {
        _clearOnlineStateTimer();
        _logClientOfflineWarningIfNecessary(
            'Connection failed $_maxWatchStreamFailures times. Most recent error: $status');
        await _setAndBroadcastState(OnlineState.offline);
      }
    }
  }

  /// Explicitly sets the [OnlineState] to the specified state.
  ///
  /// Note that this resets the timers / failure counters, etc. used by our offline heuristics, so
  /// it must not be used in place of [handleWatchStreamStart] and [handleWatchStreamFailure].
  Future<void> updateState(OnlineState newState) async {
    _clearOnlineStateTimer();
    _watchStreamFailures = 0;

    if (newState == OnlineState.online) {
      // We've connected to watch at least once. Don't warn the developer about being offline going
      // forward.
      _shouldWarnClientIsOffline = false;
    }

    await _setAndBroadcastState(newState);
  }

  Future<void> _setAndBroadcastState(OnlineState newState) async {
    if (newState != _state) {
      _state = newState;
      await _onlineStateCallback(newState);
    }
  }

  void _logClientOfflineWarningIfNecessary(String reason) {
    final String message = 'Could not reach Cloud Firestore backend. $reason\nThis typically '
        'indicates that your device does not have a healthy Internet connection at the moment. The '
        'client will operate in offline mode until it is able to successfully connect to the '
        'backend.';

    if (_shouldWarnClientIsOffline) {
      Log.w(_tag, message);
      _shouldWarnClientIsOffline = false;
    } else {
      Log.d(_tag, message);
    }
  }

  void _clearOnlineStateTimer() {
    if (_onlineStateTimer != null) {
      _onlineStateTimer.cancel();
      _onlineStateTimer = null;
    }
  }
}

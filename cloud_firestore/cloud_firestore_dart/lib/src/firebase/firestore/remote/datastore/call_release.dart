// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';

/// The part of a call that [CallReleaser] needs: a way to cancel it.
typedef CancelCall = Future<void> Function();

/// Lets go of calls that the client is done with, without resetting them while the backend may be finishing them.
///
/// Cancelling a call (or the subscription of its responses) sends an HTTP/2 RST_STREAM. If the backend is ending the
/// call at that moment, its trailers arrive for a stream the client already forgot, and package:http2 (2.3.1) answers
/// that HEADERS frame with a connection error that terminates the whole connection. Every other call on the channel
/// then fails with UNKNOWN, including a commit that the backend already applied. See
/// test/unit/firebase/firestore/remote/http2_reset_race_test.dart.
///
/// So a call whose outcome is known is not cancelled: its remaining responses are ignored and it is left to close by
/// itself. Only a call that the backend really keeps open is cancelled, after [gracePeriod].
class CallReleaser {
  CallReleaser({this.gracePeriod = const Duration(seconds: 10)});

  /// How long a released call may stay open before it is cancelled.
  final Duration gracePeriod;

  final Set<_ReleasedCall> _released = <_ReleasedCall>{};

  /// The number of released calls that neither closed nor were cancelled yet.
  int get pendingCount => _released.length;

  /// Releases a call the client no longer needs. [subscription] is the (only) listener of its responses and must not
  /// be used by the caller afterwards; [cancel] cancels the call.
  ///
  /// The caller should have closed its request stream, if it has one, so that the backend knows the client is done.
  void release<R>(StreamSubscription<R> subscription, CancelCall cancel) {
    late final _ReleasedCall released;
    released = _ReleasedCall(
      Timer(gracePeriod, () {
        _released.remove(released);
        released.cancelNow();
      }),
      () {
        // Completes with an error when the call already failed.
        subscription.cancel().catchError((Object _) {});
        cancel().catchError((Object _) {});
      },
    );
    _released.add(released);

    void closed() {
      released.timer.cancel();
      _released.remove(released);
    }

    subscription
      ..onData((R _) {})
      // An error ends the call; nothing is left to cancel.
      ..onError((Object _) => closed())
      ..onDone(closed);
  }

  /// Returns the first response of [responses] and then [release]s the call, for calls whose first response carries
  /// the whole result. Completes with the error of the call, or with a [StateError] if the call ends without a
  /// response (as [Stream.first]).
  Future<R> first<R>(Stream<R> responses, CancelCall cancel) {
    final Completer<R> completer = Completer<R>();
    late final StreamSubscription<R> subscription;
    subscription = responses.listen(
      (R response) {
        completer.complete(response);
        release<R>(subscription, cancel);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(StateError('No element'));
        }
      },
    );
    return completer.future;
  }

  /// Cancels every released call right away. For when the transport goes away: nothing can race on a connection that
  /// is being closed, and no timer should outlive the client.
  void cancelAll() {
    final List<_ReleasedCall> released = _released.toList();
    _released.clear();
    for (final _ReleasedCall call in released) {
      call.timer.cancel();
      call.cancelNow();
    }
  }
}

class _ReleasedCall {
  _ReleasedCall(this.timer, this.cancelNow);

  final Timer timer;
  final void Function() cancelNow;
}

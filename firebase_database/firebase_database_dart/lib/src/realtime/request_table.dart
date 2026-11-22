/// Request numbers, their response callbacks and their timeouts (owner P): `rtdb_protocol.md` 4
/// (envelope).
library;

import 'dart:async';

/// The requests of one `PersistentConnection` that were sent on the current connection and wait
/// for an answer, keyed by request number.
///
/// Numbers start at 1 and are never reset, also across reconnects
/// (PersistentConnection.ts:175-192); the entries are dropped on every disconnect (:783). A request
/// is added at the moment it is written to a connected socket, never while it waits offline, so
/// its timer only runs on a live connection.
///
/// Every request that expects an answer has a timeout: a request the server cannot parse gets a
/// control error `e` with no request id, or nothing at all (emulator probe, measured). The table
/// only reports a timeout; the owner keeps the count per logical request across reconnects
/// (`ConnectionTimings.maxRequestTimeouts`): below it, close the connection and replay; at it,
/// complete the request with `network_error` and drop it from the replay. Timers are plain
/// `Timer`s (`fakeAsync` drives them).
final class RequestTable {
  /// Creates an empty table whose first number is 1; [timeout] is
  /// `ConnectionTimings.requestTimeout`.
  RequestTable({required Duration timeout}) : _timeout = timeout;

  final Duration _timeout;
  final Map<int, _Entry> _entries = <int, _Entry>{};
  int _lastNumber = 0;

  /// Takes the next request number for a request being sent now on a connected socket. With
  /// [onResponse] the request waits for an answer: [onResponse] gets the response body
  /// `{"s":..,"d":..}`, or [onTimeout] runs (once, and the entry is removed) when no answer came
  /// within the timeout. Without [onResponse] nothing is recorded or timed (`n`, `unauth`).
  int add(
    void Function(Map<String, Object?> body)? onResponse, {
    void Function()? onTimeout,
  }) {
    final int number = ++_lastNumber;
    if (onResponse == null) {
      return number;
    }
    final Timer timer = Timer(_timeout, () {
      if (_entries.remove(number) != null) {
        onTimeout?.call();
      }
    });
    _entries[number] = _Entry(onResponse, timer);
    return number;
  }

  /// Runs and removes the callback of request [r] with [body], cancelling its timer. Returns false
  /// when [r] is unknown (the response is ignored, iOS U-I09).
  bool complete(int r, Map<String, Object?> body) {
    final _Entry? entry = _entries.remove(r);
    if (entry == null) {
      return false;
    }
    entry.timer.cancel();
    entry.onResponse(body);
    return true;
  }

  /// Drops every entry and cancels every timer (the connection is gone). No callback runs.
  void clear() {
    for (final _Entry entry in _entries.values) {
      entry.timer.cancel();
    }
    _entries.clear();
  }

  /// How many requests wait for a response.
  int get pending => _entries.length;
}

final class _Entry {
  _Entry(this.onResponse, this.timer);

  final void Function(Map<String, Object?> body) onResponse;
  final Timer timer;
}

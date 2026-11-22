/// Request numbers, their response callbacks and the link-silence timer (owner P):
/// `rtdb_protocol.md` 4 (envelope); the lead's replaced timeout rule (review H1).
library;

import 'dart:async';

/// The requests of one `PersistentConnection` that were sent on the current connection and wait
/// for an answer, keyed by request number.
///
/// Numbers start at 1 and are never reset, also across reconnects
/// (PersistentConnection.ts:175-192); the entries are dropped on every disconnect (:783).
///
/// Timeout (review H1, replacing the rule of the brief): the table measures **silence of the
/// link**, not the age of a request. While at least one request waits, one timer runs; every
/// inbound frame ([linkActivity], including the pieces the assembler is still buffering) re-arms
/// it, so a long download never times anything out. When the link has been silent for the timeout
/// with requests waiting, `onSilence` runs: the server dropped a request without an answer (it
/// answers an unparseable request with a control error that has no request id, or not at all,
/// measured) or the link is dead. The owner closes the connection and replays. The timer is a
/// plain `Timer` (`fakeAsync` drives it).
final class RequestTable {
  /// Creates an empty table whose first number is 1; [timeout] is
  /// `ConnectionTimings.requestTimeout`.
  RequestTable({required Duration timeout, required void Function() onSilence})
    : _timeout = timeout,
      _onSilence = onSilence;

  final Duration _timeout;
  final void Function() _onSilence;
  final Map<int, void Function(Map<String, Object?> body)> _entries =
      <int, void Function(Map<String, Object?> body)>{};
  int _lastNumber = 0;
  Timer? _silence;

  /// Takes the next request number for a request being sent now on a connected socket. With
  /// [onResponse] the request waits for an answer ([onResponse] gets the response body
  /// `{"s":..,"d":..}`) and the silence timer runs while any request waits. Without
  /// [onResponse] nothing is recorded (`n`, `unauth`).
  int add(void Function(Map<String, Object?> body)? onResponse) {
    final int number = ++_lastNumber;
    if (onResponse == null) {
      return number;
    }
    _entries[number] = onResponse;
    // Silence is measured from the last inbound frame, or from now when nothing was waiting.
    _silence ??= Timer(_timeout, _fire);
    return number;
  }

  /// Runs and removes the callback of request [r] with [body]. Returns false when [r] is unknown
  /// (the response is ignored, iOS U-I09). The timer stops when nothing waits any more.
  bool complete(int r, Map<String, Object?> body) {
    final void Function(Map<String, Object?> body)? onResponse = _entries
        .remove(r);
    if (onResponse == null) {
      return false;
    }
    if (_entries.isEmpty) {
      _cancel();
    }
    onResponse(body);
    return true;
  }

  /// An inbound frame arrived: the link is not silent. Re-arms the timer while requests wait.
  void linkActivity() {
    if (_entries.isEmpty) {
      return;
    }
    _cancel();
    _silence = Timer(_timeout, _fire);
  }

  /// Drops every entry and stops the timer (the connection is gone). No callback runs.
  void clear() {
    _cancel();
    _entries.clear();
  }

  /// How many requests wait for a response.
  int get pending => _entries.length;

  void _fire() {
    _silence = null;
    if (_entries.isNotEmpty) {
      _onSilence();
    }
  }

  void _cancel() {
    _silence?.cancel();
    _silence = null;
  }
}

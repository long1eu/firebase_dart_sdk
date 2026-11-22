/// Request numbers and their response callbacks (owner P): `rtdb_protocol.md` 4 (envelope).
library;

/// The response callbacks of one `PersistentConnection`, keyed by request number.
///
/// Numbers start at 1 and are never reset, also across reconnects
/// (PersistentConnection.ts:175-192); the callbacks are dropped on every disconnect (:783).
final class RequestTable {
  /// Creates an empty table whose first number is 1.
  RequestTable() {
    throw UnimplementedError();
  }

  /// Takes the next request number and records [onResponse] for it, when given. [onResponse] gets
  /// the response body `{"s":..,"d":..}`.
  int add(void Function(Map<String, Object?> body)? onResponse) {
    throw UnimplementedError();
  }

  /// Runs and removes the callback of request [r] with [body]. Returns false when [r] is unknown
  /// (the response is ignored, iOS U-I09).
  bool complete(int r, Map<String, Object?> body) {
    throw UnimplementedError();
  }

  /// Drops every callback (the connection is gone).
  void clear() {
    throw UnimplementedError();
  }

  /// How many requests wait for a response.
  int get pending => throw UnimplementedError();
}

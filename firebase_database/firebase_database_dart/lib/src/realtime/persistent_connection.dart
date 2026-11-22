/// The connection that survives disconnects (owner P): requests, the listen table, puts, gets,
/// the onDisconnect queue, replay after reconnect, `.info` callbacks and interrupt/resume
/// (`rtdb_protocol.md` 4, 5 and 8).
library;

import 'package:firebase_database_dart/src/realtime/auth_session.dart';
import 'package:firebase_database_dart/src/realtime/connection.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/realtime/listen_spec.dart';
import 'package:firebase_database_dart/src/realtime/reconnect_backoff.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';

/// Creates the [RealtimeConnection] of the next attempt for [delegate] (test plan section 5).
/// Production passes a closure over `RealtimeConnection` and the platform connector; tests return a
/// connection over the fake connector, or a stub.
typedef RealtimeConnectionFactory =
    RealtimeConnection Function(
      RealtimeDelegate delegate, {
      String? lastSessionId,
      String? appId,
      String? appCheckToken,
    });

/// The completion of a write: [status] `ok` or an error code (9), [reason] the server's text.
typedef WriteCallback = void Function(String status, String? reason);

/// The completion of a listen: [status] `ok` or an error code; [payload] the response `d` (may
/// hold the `w` warnings, 4.1).
typedef ListenCallback = void Function(String status, Object? payload);

/// What the persistent connection tells the data half.
abstract interface class PersistentConnectionDelegate {
  /// The server sent [data] for [path] (5): an overwrite, or a merge when [isMerge]; [tag] is the
  /// query tag or null.
  void onDataUpdate(String path, Object? data, bool isMerge, int? tag);

  /// `.info/connected` changed to [connected]: true only after the replay was sent (8.4).
  void onConnectStatus(bool connected);

  /// Values of `.info` changed, for example `serverTimeOffset` at each hello (3.2, 8.8).
  void onServerInfoUpdate(Map<String, Object?> updates);
}

/// The server actions of one database instance (test plan section 5, P gives the Repo half).
///
/// Connects at construction (test plan B-8.1a). Before each attempt it fetches the tokens through
/// an [AuthSession] it builds over the given [RealtimeTokenSource] (8.1). After each hello it
/// replays, in order: auth, App Check, listens, unacknowledged puts and merges, queued
/// onDisconnects, outstanding gets (8.4), then reports connected. Sent transaction puts (with a
/// hash) are failed with `disconnect` on a disconnect (8.5). A `c` push cancels every listen at its
/// path with `permission_denied` (lead's decision). The only external reconnect trigger is
/// `connectivityHints` (test plan B-8.7).
final class PersistentConnection {
  /// Creates the connection and starts the first attempt.
  ///
  /// [now] and [random] replace the clock and the random source (test plan 2.4); [appId] goes to
  /// every connection (2.3).
  PersistentConnection({
    required ConnectionTarget target,
    required RealtimeConnectionFactory connectionFactory,
    required ReconnectBackoff backoff,
    required RealtimeTokenSource tokens,
    required PersistentConnectionDelegate delegate,
    ConnectionTimings timings = const ConnectionTimings(),
    String? appId,
    required DateTime Function() now,
    required double Function() random,
    Stream<void>? connectivityHints,
  }) {
    throw UnimplementedError();
  }

  /// Reads [query] once with `g` (4.3): `q` always, no tag, no hash. Kept across disconnects and
  /// re-sent once after reconnect (iOS U-I03, U-I04). Completes with the `d` of an `ok` response,
  /// fails with a `FirebaseDatabaseException` otherwise.
  Future<Object?> get(ListenSpec query) {
    throw UnimplementedError();
  }

  /// Listens to [query] with `q` (4.1). [tag] is non-null only for a query that does not load all
  /// data; [hash] gives the `h` of the current server cache (`""` when empty) at send time, also on
  /// replay; [onComplete] gets the response. A second listen of the same path and query id is a
  /// [StateError] (4.1).
  void listen(
    ListenSpec query,
    int? tag,
    String Function() hash,
    ListenCallback onComplete,
  ) {
    throw UnimplementedError();
  }

  /// Stops the listen of [query] with `n` (4.2); sent only if connected and the listen exists.
  void unlisten(ListenSpec query, int? tag) {
    throw UnimplementedError();
  }

  /// Writes [data] (unresolved, export format) at [path] with `p` (4.4). [hash] makes it a
  /// transaction put (4.4, 8.5).
  void put(
    String path,
    Object? data,
    WriteCallback? onComplete, {
    String? hash,
  }) {
    throw UnimplementedError();
  }

  /// Merges [data] at [path] with `m` (4.4a). Keys may be relative paths.
  void merge(
    String path,
    Map<String, Object?> data,
    WriteCallback? onComplete,
  ) {
    throw UnimplementedError();
  }

  /// Registers an onDisconnect set of [data] at [path] (`o`, 4.5); queued while offline.
  void onDisconnectPut(String path, Object? data, WriteCallback? onComplete) {
    throw UnimplementedError();
  }

  /// Registers an onDisconnect update of [data] at [path] (`om`, 4.5).
  void onDisconnectMerge(
    String path,
    Map<String, Object?> data,
    WriteCallback? onComplete,
  ) {
    throw UnimplementedError();
  }

  /// Cancels the onDisconnect operations at [path] (`oc` with `d: null`, 4.5).
  void onDisconnectCancel(String path, WriteCallback? onComplete) {
    throw UnimplementedError();
  }

  /// The auth [token] changed (8.3): forwarded to the [AuthSession].
  void refreshAuthToken(String? token) {
    throw UnimplementedError();
  }

  /// The App Check [token] changed (8.3): forwarded to the [AuthSession].
  void refreshAppCheckToken(String? token) {
    throw UnimplementedError();
  }

  /// Adds the interrupt [reason] (8.6): closes the connection, or cancels the pending attempt and
  /// drops a token fetch in flight.
  void interrupt(String reason) {
    throw UnimplementedError();
  }

  /// Removes the interrupt [reason] (8.6); when none is left, resets the backoff and connects at
  /// once. `server_kill` is never removed.
  void resume(String reason) {
    throw UnimplementedError();
  }

  /// Whether [reason] is among the current interrupt reasons.
  bool isInterrupted(String reason) {
    throw UnimplementedError();
  }

  /// Closes the connection for good: no reconnect, timers cancelled, the hint stream released.
  Future<void> close() {
    throw UnimplementedError();
  }
}

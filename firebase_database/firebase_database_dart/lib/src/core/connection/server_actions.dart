/// The seam between Repo and the connection. JS: `core/ServerActions.ts` (implemented by
/// `core/PersistentConnection.ts`) and the callbacks Repo passes to it (`core/Repo.ts` `repoStart`,
/// ~line 230-330); Android: `connection/PersistentConnection.java` and its `Delegate`.
///
/// Cross-team seam: JSON only. Paths cross as wire strings (`/a/b`, `/` for the root); data
/// crosses as decoded JSON (`Map<String, Object?>`, `List<Object?>`, `String`, `num`, `bool`,
/// null), in the export form for writes (`.priority`, `.value`, server values `{'.sv': ...}` left
/// unresolved). No `Path`, `Node` or `QuerySpec` crosses it. The protocol is specified in
/// `rtdb/from_boss/rtdb_protocol.md`.
///
/// Errors: the only error vocabulary is the core's `DatabaseErrorCode` / `DatabaseError`; the
/// connection hands over wire status strings and declares no exception class of its own for
/// server statuses, except [ServerActionsException] for a failed [ServerActions.get]. The public
/// `FirebaseDatabaseException` is defined once, in the public API layer.
library;

import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';
import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';

/// The `s` status of a successful response.
const String statusOk = 'ok';

/// The status a sent transaction put (a put with a hash) is cancelled with when the connection
/// drops; produced locally by the connection, never by the server.
const String statusDisconnect = 'disconnect';

/// The status a `get` fails with after two connections in a row were closed for silence while it
/// waited; produced locally by the connection, never by the server. Only a get ends this way: a
/// write, an onDisconnect request or a listen is never failed by a timeout (a silent link is
/// closed and the request replayed). Maps to `DatabaseErrorCode.networkError`.
const String statusNetworkError = 'network_error';

/// The status a read-only [ServerActions] (the REST client) completes every write and
/// onDisconnect request with; maps to `DatabaseErrorCode.readOnly`.
const String statusReadOnly = 'read_only';

/// The failure of [ServerActions.get]: the wire [status] (`permission_denied`, ...) and the
/// server's optional [reason]. JS: the `Error` `PersistentConnection.get` rejects with; Android:
/// `PersistentConnection.get`'s failed task.
final class ServerActionsException implements Exception {
  /// Creates the exception.
  const ServerActionsException(this.status, [this.reason]);

  /// The wire status.
  final String status;

  /// The server's human-readable reason, if any.
  final String? reason;

  /// Shows [status] and [reason] only.
  @override
  String toString() =>
      'ServerActionsException($status${reason == null ? '' : ': $reason'})';
}

/// Completion of a request: [status] is `ok`, a server error status (`permission_denied`,
/// `datastale`, `too_big`, `unavailable`, ...) or the local [statusDisconnect] or
/// [statusNetworkError]; [data] is the
/// response `d`: on error the human-readable reason (`String?`), on a successful listen the
/// payload (which may hold warnings `{'w': ['no_index']}`), otherwise usually null.
///
/// Called once per request, on the caller's event loop, never synchronously from inside the call
/// that sent the request. A listen is the exception: after its `ok` the same callback is called
/// once more if the server cancels the listen later (for example `permission_denied` after a
/// rules or auth change), and never again after that. A sent onDisconnect request whose
/// connection drops before the answer completes with [statusDisconnect].
typedef RequestResultCallback = void Function(String status, Object? data);

/// What Repo asks of the connection. One instance per Repo; the connection owns the socket,
/// handshake, framing, tokens, backoff and replay.
///
/// Tokens belong to the connection: each implementation gets its token source in its
/// constructor (`PersistentConnection` takes a `RealtimeTokenSource`, an adapter over the app's
/// `AuthTokenProvider` and `AppCheckTokenProvider`, and builds its own `AuthSession`; the REST
/// client takes the same source) and subscribes to token changes itself. Repo never pushes
/// tokens, so no token is sent twice.
///
/// Paths cross this seam as `/a/b`, root `/`, in both directions. The server pushes `a/b` and
/// `""` for the root; the connection normalises before calling the delegate.
///
/// A read-only implementation (the REST client) completes every write and onDisconnect request
/// ([put], [merge], [onDisconnectPut], [onDisconnectMerge], [onDisconnectCancel]) with
/// [statusReadOnly].
///
/// Reconnect contract: after a reconnect the connection replays by itself, in this order: `auth`,
/// `appcheck`, every listen still registered (with a freshly computed hash), every put and merge
/// not yet acknowledged, onDisconnect requests not yet sent, and every outstanding [get]. Only then
/// does it call [ServerActionsDelegate.onConnect]. Exception: a put sent with a `hash` (a
/// transaction put) that was already sent is NOT replayed; its [RequestResultCallback] is called
/// with [statusDisconnect] and Repo aborts the transaction with `disconnected` (as JS and Android
/// do). Acknowledged onDisconnect requests are not replayed (the server forgot them with the old
/// connection).
abstract interface class ServerActions {
  /// Starts connecting (the first connection starts when Repo is created, not on first use).
  void initialize();

  /// Closes the connection for good and drops every pending callback; later calls are ignored.
  /// Completes when the socket is closed; `Repo.close()` awaits it.
  Future<void> shutdown();

  /// Sends `q`: listen at [spec]. The listen always carries `h` = [ListenHashProvider.simpleHash]
  /// (and `ch` when [ListenHashProvider.shouldIncludeCompoundHash]). [tag] is non-null only for
  /// queries that do not load all data (tags start at 1); only then are `q` (the query object)
  /// and `t` sent. A query that loads all data is passed as its default form, untagged.
  ///
  /// The data arrives through [ServerActionsDelegate.onDataUpdate] (tagged with [tag]) before
  /// [onComplete] reports `ok`. A failed listen, or a listen the server revokes later with a `c`
  /// push (rules changed), completes with its status (`permission_denied`) and is removed from
  /// the listen table. Listening twice to the same [spec] is an error.
  void listen(
    ListenSpec spec, {
    required ListenHashProvider hashProvider,
    int? tag,
    required RequestResultCallback onComplete,
  });

  /// Sends `n` (with `q` and `t` when [tag] is non-null) if the listen is registered and the
  /// connection is up; always removes it from the listen table. No callback.
  void unlisten(ListenSpec spec, {int? tag});

  /// Sends `g` with `p` and `q` (always, `{}` for the default query) and completes with the
  /// decoded `d`, or fails with a [ServerActionsException] carrying the error status and
  /// reason. Not cancelled by a disconnect: it is re-sent after the reconnect. Fails
  /// with `ServerActionsException(statusNetworkError)` after two connections in a row were
  /// closed for silence while it waited, and with status `database_closed` when the connection
  /// is shut down; Repo sets no timer of its own while connected.
  Future<Object?> get(ListenSpec spec);

  /// Sends `p`: overwrite [path] with [data] (export form, null removes). With [hash] it is a
  /// transaction put (`h` = hash of the data the transaction read): the server answers
  /// `datastale` when the data changed, and a dropped connection completes it with
  /// [statusDisconnect]. Without [hash] it is replayed after a reconnect until acknowledged.
  void put(
    String path,
    Object? data, {
    String? hash,
    RequestResultCallback? onComplete,
  });

  /// Sends `m`: merge [data] (keys are child keys or relative paths) into [path]. Replayed after
  /// a reconnect until acknowledged.
  void merge(
    String path,
    Map<String, Object?> data, {
    String? hash,
    RequestResultCallback? onComplete,
  });

  /// Sends `o`: on disconnect, overwrite [path] with [data]. Queued while offline.
  void onDisconnectPut(
    String path,
    Object? data, {
    RequestResultCallback? onComplete,
  });

  /// Sends `om`: on disconnect, merge [data] into [path]. Queued while offline.
  void onDisconnectMerge(
    String path,
    Map<String, Object?> data, {
    RequestResultCallback? onComplete,
  });

  /// Sends `oc`: cancel the onDisconnect operations at and below [path]. Queued while offline.
  void onDisconnectCancel(String path, {RequestResultCallback? onComplete});

  /// Drops every put and merge not yet acknowledged, completing each with `write_canceled`
  /// (Repo's `purgeOutstandingWrites`).
  ///
  /// Every write gets exactly one completion. The connection completes each write it still holds
  /// unanswered with `write_canceled` and from then on drops any answer the server sends for it.
  /// One case remains by design: an answer the connection had already received, whose completion
  /// is already queued when the core purges, is delivered after the purge, as ok or as the
  /// server's error, because the server did apply or refuse that write. So the core must tolerate
  /// a completion for a write its own purge removed. The connection never delivers two completions
  /// for one write, and never a `write_canceled` followed by an answer.
  void purgeOutstandingWrites();

  /// Adds [reason] (`repo_interrupt` for goOffline) and closes the connection; no reconnect while
  /// any reason is set.
  void interrupt(String reason);

  /// Removes [reason]; when none is left, resets the backoff and reconnects at once.
  void resume(String reason);

  /// Whether [reason] is set.
  bool isInterrupted(String reason);
}

/// What the connection tells Repo. Every call arrives on the event loop, never synchronously from
/// inside a [ServerActions] call.
abstract interface class ServerActionsDelegate {
  /// A `d` (overwrite, [isMerge] false) or `m` (merge, [isMerge] true) push at [path]. For a
  /// merge, [data] is a map of child keys or relative paths to values, null meaning delete.
  ///
  /// [path] is always `/a/b` (`/` for the root), normalised by the connection from the server's
  /// `a/b` (`""` for the root). Merge maps are handed over with their keys as the server sent
  /// them.
  /// [tag] is the listen tag for data of a filtered query, else null.
  void onDataUpdate(
    String path,
    Object? data, {
    required bool isMerge,
    int? tag,
  });

  /// An `rm` push at [path] (only after a listen sent a compound hash); [merges] is never empty.
  /// [path] is normalised to `/a/b` (`/` for the root) as for [onDataUpdate].
  void onRangeMergeUpdate(String path, List<WireRangeMerge> merges, {int? tag});

  /// The connection is up and the replay (see [ServerActions]) has been sent:
  /// `.info/connected` becomes true.
  void onConnect();

  /// The connection was lost: `.info/connected` becomes false and Repo applies the local
  /// onDisconnect tree. Sent transaction puts have already been completed with
  /// [statusDisconnect].
  void onDisconnect();

  /// The result of an `auth`/`gauth` request or an `ac` push: [status] `ok` when authenticated,
  /// else the revoke status (`invalid_token`, `permission_denied`, `expired_token`) and the
  /// server's [explanation]. On a revoke the connection has closed itself and will reconnect with
  /// a freshly forced token.
  void onAuthStatus(String status, {String? explanation});

  /// The result of an `appcheck` request or an `apc` push; on a revoke the connection stays open
  /// and the next token fetch is forced.
  void onAppCheckStatus(String status, {String? explanation});

  /// The server shut this client down (control message `s`) with [reason]; the connection does not
  /// reconnect. Repo fails nothing by itself but logs and reports the reason.
  void onServerShutdown(String reason);

  /// Server info changed; today only `serverTimeOffset` (server time minus local time in ms),
  /// written to `.info/serverTimeOffset`.
  void onServerInfoUpdate(Map<String, Object?> updates);
}

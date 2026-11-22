/// The read-only REST implementation of [ServerActions] (owner R): reads as the JS
/// `ReadonlyRestClient` does (`rtdb_protocol.md` 10, 6.4); threat model T7, T8, T23.
library;

import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/util/logger.dart';
import 'package:firebase_database_dart/src/realtime/auth_session.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';
import 'package:http/http.dart' as http;

/// Reads a database over HTTPS (or HTTP to the emulator); the second implementation of
/// [ServerActions] (JS uses it for `forceRestClient` and crawlers, 10).
///
/// [get] and [listen] send `GET <path>.json?ns=..&format=export[&query params][&auth=..]`. The
/// query parameters are `ListenSpec.restParams` (the core's
/// `QueryParams.toRestQueryStringParameters()`, `rtdb_seam_changes.md` A.4). A listen is one
/// read: the data goes to [ServerActionsDelegate.onDataUpdate] at the spec's path, then
/// `onComplete` gets `ok`. 401 is
/// `permission_denied`, 404 is null data, other non-2xx are `rest_error:<status>` for a listen and
/// a [ServerActionsException] carrying the status for a get (A.2; 9, 10; JS drops it,
/// ReadonlyRestClient.ts:168).
///
/// Writes and onDisconnect operations complete with the status `read_only` ([statusReadOnly],
/// A.7) on the event loop, never synchronously. URLs come from [RealtimeTarget.restUri]. The ID
/// token goes in `auth=` (until the probe of threat model open item 2 says a header works), the
/// App Check token in `X-Firebase-AppCheck`; both only when non-empty and where
/// [RealtimeTarget.mayReceiveTokens] allows (T3). Redirects are not followed (a 3xx is an
/// error), error bodies are read up to 16 KiB, success bodies up to `maxResponseBytes` (T23). No
/// error message or log line holds a URL query (T7, T8): `ClientException.uri` is dropped.
final class RestClient implements ServerActions {
  /// Creates a client of [target] reading tokens from [tokens] (A.1) and reporting to [delegate];
  /// [logger] gets the warnings of 10 (parse failures, `rest_error`), never a URL query (T7);
  /// null drops them.
  /// [httpClient] defaults to a new `http.Client` that [shutdown] closes; a given one is left
  /// open. [maxResponseBytes] bounds a success body (`ConnectionTimings.maxMessageBytes`).
  RestClient({
    required RealtimeTarget target,
    required RealtimeTokenSource tokens,
    required ServerActionsDelegate delegate,
    DatabaseLogger? logger,
    http.Client? httpClient,
    required int maxResponseBytes,
  }) {
    throw UnimplementedError();
  }

  /// Nothing to connect; reports nothing (the REST client never calls
  /// [ServerActionsDelegate.onConnect]).
  @override
  void initialize() {
    throw UnimplementedError();
  }

  /// Closes the HTTP client when this client created it; later reads complete nothing.
  @override
  Future<void> shutdown() {
    throw UnimplementedError();
  }

  /// One read of [spec]; [hashProvider] is not used.
  @override
  void listen(
    ListenSpec spec, {
    required ListenHashProvider hashProvider,
    int? tag,
    required RequestResultCallback onComplete,
  }) {
    throw UnimplementedError();
  }

  /// Forgets the listen; a read in flight is dropped.
  @override
  void unlisten(ListenSpec spec, {int? tag}) {
    throw UnimplementedError();
  }

  @override
  Future<Object?> get(ListenSpec spec) {
    throw UnimplementedError();
  }

  /// Completes with `read_only`: the REST client is read-only.
  @override
  void put(
    String path,
    Object? data, {
    String? hash,
    RequestResultCallback? onComplete,
  }) {
    throw UnimplementedError();
  }

  /// Completes with `read_only`: the REST client is read-only.
  @override
  void merge(
    String path,
    Map<String, Object?> data, {
    String? hash,
    RequestResultCallback? onComplete,
  }) {
    throw UnimplementedError();
  }

  /// Completes with `read_only`.
  @override
  void onDisconnectPut(
    String path,
    Object? data, {
    RequestResultCallback? onComplete,
  }) {
    throw UnimplementedError();
  }

  /// Completes with `read_only`.
  @override
  void onDisconnectMerge(
    String path,
    Map<String, Object?> data, {
    RequestResultCallback? onComplete,
  }) {
    throw UnimplementedError();
  }

  /// Completes with `read_only`.
  @override
  void onDisconnectCancel(String path, {RequestResultCallback? onComplete}) {
    throw UnimplementedError();
  }

  /// Nothing to do: there are no outstanding writes.
  @override
  void purgeOutstandingWrites() {
    throw UnimplementedError();
  }

  /// Records [reason]; reads wait while any reason is set.
  @override
  void interrupt(String reason) {
    throw UnimplementedError();
  }

  @override
  void resume(String reason) {
    throw UnimplementedError();
  }

  @override
  bool isInterrupted(String reason) {
    throw UnimplementedError();
  }
}

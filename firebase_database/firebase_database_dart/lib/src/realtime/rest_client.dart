/// The REST client (owner R): reads as the JS read-only client does (`rtdb_protocol.md` 10, 6.4)
/// and writes from the public REST documentation (outside the JS source); threat model T7, T8, T23.
library;

import 'package:firebase_database_dart/src/realtime/auth_session.dart';
import 'package:firebase_database_dart/src/realtime/listen_spec.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';
import 'package:http/http.dart' as http;

/// Reads and writes a database over HTTPS (or HTTP to the emulator).
///
/// URLs come from [RepoInfo.restUri]. The ID token goes in `auth=` (until the probe of threat model
/// open item 2 says a header works), the App Check token in `X-Firebase-AppCheck`; both only when
/// non-empty and only where [RepoInfo.mayReceiveTokens] allows (T3). Redirects are not followed (a
/// 3xx is an error), error bodies are read up to 16 KiB, success bodies up to `maxResponseBytes`
/// (T23). No error message or log line holds a URL query (T7, T8): `ClientException.uri` is
/// dropped.
///
/// Failures are `FirebaseDatabaseException`s: 401 -> `permission-denied`, other non-2xx ->
/// `rest-error` carrying the status (9, 10; JS drops it, ReadonlyRestClient.ts:168).
final class RestClient {
  /// Creates a client of [repoInfo] reading tokens from [tokens]. [httpClient] defaults to a new
  /// `http.Client` that [close] closes; a given one is left open. [maxResponseBytes] bounds a
  /// success body (`ConnectionTimings.maxMessageBytes`).
  RestClient({
    required RepoInfo repoInfo,
    required RealtimeTokenSource tokens,
    http.Client? httpClient,
    required int maxResponseBytes,
  }) {
    throw UnimplementedError();
  }

  /// Reads [query] (`GET <path>.json?ns=..&format=export[&query params]`, 10). 404 gives null; a
  /// body that is not JSON gives null and a warning (10).
  Future<Object?> get(ListenSpec query) {
    throw UnimplementedError();
  }

  /// Writes [data] at [path] (`PUT`, public REST docs).
  Future<void> put(String path, Object? data) {
    throw UnimplementedError();
  }

  /// Adds [data] under [path] with a server-generated key (`POST`); returns the key (`name` of the
  /// response).
  Future<String> post(String path, Object? data) {
    throw UnimplementedError();
  }

  /// Updates the children of [path] named by the keys of [data] (`PATCH`).
  Future<void> patch(String path, Map<String, Object?> data) {
    throw UnimplementedError();
  }

  /// Deletes [path] (`DELETE`).
  Future<void> delete(String path) {
    throw UnimplementedError();
  }

  /// Closes the HTTP client when this client created it.
  void close() {
    throw UnimplementedError();
  }
}

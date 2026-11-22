/// Parsing and validating a database URL (owner U): `rtdb_protocol.md` 2.1 with the stricter
/// rules of threat model T3 and T6.
library;

import 'package:firebase_database_dart/src/realtime/realtime_error.dart';

/// A validated production database URL.
final class DatabaseUrl {
  /// Creates the value; use [parseDatabaseUrl] for text from the app.
  const DatabaseUrl({
    required this.host,
    required this.namespace,
    required this.namespaceInQuery,
  });

  /// The host, lowercased, without port (`<ns>.firebaseio.com`,
  /// `<ns>.<region>.firebasedatabase.app` or a custom domain).
  final String host;

  /// The namespace: the `ns` parameter when given, else the first label of the host (2.1 steps 4,
  /// 5). Matches `^[a-z0-9-]{1,63}$` (T6).
  final String namespace;

  /// Whether `ns` was given explicitly and differs from the first label
  /// (`includeNamespaceInQueryParams`, 2.1 step 6).
  final bool namespaceInQuery;

  /// The URL as `https://<host>`, plus `?ns=` when [namespaceInQuery]. No secret can be in it.
  @override
  String toString() => namespaceInQuery
      ? 'https://$host?ns=${Uri.encodeQueryComponent(namespace)}'
      : 'https://$host';
}

/// Parses [url] as a production database URL (2.1, threat model T6).
///
/// Accepts `https://` and `wss://` (and a bare host, read as `https`). Refuses, with a
/// [FirebaseDatabaseException] of code `invalid-argument`: `http`/`ws` (pointing to `useEmulator`,
/// T3), userinfo, a fragment, any query key but `ns`, a non-root path, an empty host, IP literals
/// other than loopback, a port other than 443, a custom domain without `ns`, a namespace that does
/// not match `^[a-z0-9-]{1,63}$` after lowercasing, and the domain `firebase.com` (2.1 step 6). The
/// message never quotes a query value.
DatabaseUrl parseDatabaseUrl(String url) {
  throw UnimplementedError();
}

/// The default database host of [projectId]: `<projectId>-default-rtdb.firebaseio.com` (1.1,
/// api/Database.ts:135).
String defaultDatabaseHost(String projectId) {
  throw UnimplementedError();
}

/// Parses an emulator address `host:port`, the value of `FIREBASE_DATABASE_EMULATOR_HOST` (2.4).
///
/// Reading the variable is the caller's explicit step, never a default (threat model T3). Throws a
/// [FirebaseDatabaseException] of code `invalid-argument` for anything but a host and a port in
/// `1..65535`.
({String host, int port}) parseEmulatorHost(String value) {
  throw UnimplementedError();
}

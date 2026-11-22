/// Parsing and validating a database URL into the core's [RepoInfo] (owner U):
/// `rtdb_protocol.md` 2.1 and 2.4 with the stricter rules of threat model T3 and T6.
///
/// A bad URL is a programmer error: these functions throw [FormatException] (text that is not a
/// database URL) or [ArgumentError] (a value out of range), never a database error.
library;

import 'package:firebase_database_dart/src/core/repo_info.dart';

/// Parses [url] as a production database URL (2.1, threat model T6) into a [RepoInfo] with
/// `secure` true and `isUsingEmulator` false.
///
/// Accepts `https://` and `wss://` (and a bare host, read as `https`); the host is lowercased.
/// Namespace: the `ns` parameter when given, else the first label of a `firebaseio.com` /
/// `firebasedatabase.app` host. Throws [FormatException] for: `http`/`ws` (the message points to
/// `useEmulator`, T3), userinfo, a fragment, any query key but `ns`, a non-root path, an empty
/// host, IP literals other than loopback, a port other than 443, a custom domain without `ns`, a
/// namespace that does not match `^[a-z0-9-]{1,63}$` after lowercasing, and the domain
/// `firebase.com` (2.1 step 6). The message never quotes a query value.
RepoInfo parseDatabaseUrl(String url) {
  throw UnimplementedError();
}

/// The [RepoInfo] of the default database of [projectId]:
/// `<projectId>-default-rtdb.firebaseio.com`, namespace `<projectId>-default-rtdb` (1.1,
/// api/Database.ts:135). Throws [ArgumentError] when [projectId] is not a valid label.
RepoInfo defaultDatabase(String projectId) {
  throw UnimplementedError();
}

/// The [RepoInfo] of the emulator at [host]:[port] with [namespace] (2.4): `secure` only for
/// `*.cloudworkstations.dev`. Throws [ArgumentError] for an empty host, a port outside
/// `1..65535` or an invalid namespace.
RepoInfo emulatorDatabase(String host, int port, {required String namespace}) {
  throw UnimplementedError();
}

/// Parses an emulator address `host:port`, the value of `FIREBASE_DATABASE_EMULATOR_HOST` (2.4).
///
/// Reading the variable is the caller's explicit step, never a default (threat model T3). Throws
/// [FormatException] for anything but a host and a port in `1..65535`.
({String host, int port}) parseEmulatorHost(String value) {
  throw UnimplementedError();
}

/// Where the database is. JS: `core/RepoInfo.ts` (the part Repo needs); Android:
/// `core/RepoInfo.java`.
///
/// The core owns the identity (host, namespace, secure, emulator). The realtime half builds its
/// `ConnectionTarget` (`realtime/connection_target.dart`: `connectionUri`, `connectionHeaders`,
/// `acceptServerHost`, `forgetServerHost`, `restUri`, `mayReceiveTokens`) from a [RepoInfo].
library;

/// The host, namespace and transport security of one database.
final class RepoInfo {
  /// Creates the info.
  const RepoInfo({
    required this.host,
    required this.namespace,
    required this.secure,
    this.isUsingEmulator = false,
  });

  /// The host with port, such as `my-project-default-rtdb.firebaseio.com` or `127.0.0.1:9000`.
  final String host;

  /// The namespace (database name), sent as `ns`.
  final String namespace;

  /// Whether to use `wss`/`https`.
  final bool secure;

  /// Whether [host] is the emulator.
  final bool isUsingEmulator;

  /// Whether [host] is a demo host (`*.firebaseio-demo.com`), which warns about data loss.
  bool get isDemoHost => throw UnimplementedError();

  /// The database URL: `https://host` (plus `?ns=` for the emulator); the persistence key
  /// (`PersistenceKey.databaseUrl`) uses it.
  Uri get databaseUrl => throw UnimplementedError();

  /// [databaseUrl] as a string.
  String toUrlString() => throw UnimplementedError();

  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}

/// Where the database is. JS: `core/RepoInfo.ts` (the part Repo needs); Android:
/// `core/RepoInfo.java`.
///
/// The core owns the identity (host, namespace, secure, emulator). The realtime half builds its
/// `ConnectionTarget` (`realtime/connection_target.dart`: `connectionUri`, `connectionHeaders`,
/// `acceptServerHost`, `forgetServerHost`, `mayReceiveTokens`) from a [RepoInfo].
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
  /// JS `RepoInfo.isDemoHost`; Android `RepoInfo.isDemoHost`.
  bool get isDemoHost => host.contains('.firebaseio-demo.com');

  /// The database URL: `https://host` (plus `?ns=` for the emulator); the persistence key
  /// (`PersistenceKey.databaseUrl`) uses it.
  /// JS `RepoInfo.toURLString`; Android `RepoInfo.toString`.
  Uri get databaseUrl => Uri.parse(toUrlString());

  /// [databaseUrl] as a string. JS `RepoInfo.toURLString` (without its trailing `/`).
  String toUrlString() {
    final String scheme = secure ? 'https' : 'http';
    final String query = isUsingEmulator
        ? '?ns=${Uri.encodeQueryComponent(namespace)}'
        : '';
    return '$scheme://$host$query';
  }

  /// Equal when host, namespace, security and emulator flag are (Android `RepoInfo.equals`).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepoInfo &&
          other.host == host &&
          other.namespace == namespace &&
          other.secure == secure &&
          other.isUsingEmulator == isUsingEmulator;

  /// Android `RepoInfo.hashCode`.
  @override
  int get hashCode => Object.hash(host, namespace, secure, isUsingEmulator);

  /// [toUrlString] (Android `RepoInfo.toString`).
  @override
  String toString() => toUrlString();
}

/// Where the database is and how to reach it (owner U): the WebSocket and REST URLs, the upgrade
/// headers, and the server-chosen host (`rtdb_protocol.md` 2.2 to 2.4, threat model T1, T3, T6).
library;

import 'package:firebase_database_dart/src/realtime/database_url.dart';

/// What a connection needs from the database location (test plan section 5, U gives C and P).
abstract interface class ConnectionTarget {
  /// The WebSocket URL of the next attempt (2.3):
  /// `wss://<internalHost>/.ws?v=5[&ls=..][&ac=..][&p=..][&ns=..]`, built with
  /// `Uri(queryParameters:)` (values percent-encoded, T6). `ac` and
  /// `p` are added only when the platform cannot send headers (the web). Never has userinfo.
  Uri connectionUri({
    String? lastSessionId,
    String? appId,
    String? appCheckToken,
  });

  /// The upgrade headers (2.3, Android style): `User-Agent`, `X-Firebase-GMPID`,
  /// `X-Firebase-AppCheck`. Empty when the platform cannot send headers.
  Map<String, String> connectionHeaders({String? appId, String? appCheckToken});

  /// Offers [host], from a hello `h` or a reset `r`, as the host of the next attempts (3.2, 3.3).
  ///
  /// Accepted only when it is a bare lowercase DNS name (no port, userinfo, path, query, fragment,
  /// no trailing dot, at most 253 chars) equal to the configured host or ending in
  /// `.firebaseio.com` / `.firebasedatabase.app` on a label boundary; never with an emulator
  /// (threat model T1). Upper case is lowercased first. Returns whether it was stored; kept in
  /// memory only.
  bool acceptServerHost(String host);

  /// Goes back to the configured host: an attempt to a server-chosen host failed before its hello,
  /// or a reset named an invalid host (3.5; iOS U-I21).
  void forgetServerHost();

  /// The host the app configured, lowercased (with `:port` for the emulator).
  String get configuredHost;

  /// Whether this is the emulator set with `useEmulator` (2.4).
  bool get isUsingEmulator;

  /// Whether the URLs use TLS (`wss`/`https`). False only for the emulator (T3).
  bool get secure;
}

/// The location of one database as the connection half sees it (2.2): the configured host, the
/// server-chosen host, the namespace and the emulator settings, and the URLs built from them.
///
/// Not the core's `RepoInfo` (`lib/src/core/repo_info.dart`, the configured host, namespace,
/// `secure` and emulator flag Repo keeps): whoever creates the connection builds this from it.
///
/// Tokens can only reach the configured host over TLS, a server host accepted by
/// [acceptServerHost], or the emulator's exact `host:port` (threat model T3).
final class RealtimeTarget implements ConnectionTarget {
  /// A production database at [url]. [useHeaders] says whether the platform's connector sends
  /// upgrade headers (`wsConnectorSendsHeaders`); [userAgent] is the `User-Agent` header value.
  RealtimeTarget.production(
    DatabaseUrl url, {
    required bool useHeaders,
    String? userAgent,
  }) {
    throw UnimplementedError();
  }

  /// The emulator at [host]:[port] with [namespace] (2.4): `ws://` and `http://`, except `wss://`
  /// for `*.cloudworkstations.dev`. The hello `h` and a reset `r` never change the host.
  RealtimeTarget.emulator({
    required String host,
    required int port,
    required String namespace,
    required bool useHeaders,
    String? userAgent,
  }) {
    throw UnimplementedError();
  }

  /// The namespace, sent as `ns` when needed (2.2).
  String get namespace => throw UnimplementedError();

  /// The host of the next WebSocket attempt: the configured host or an accepted server host (2.2).
  String get internalHost => throw UnimplementedError();

  /// Whether the domain is neither `firebaseio.com` nor `firebaseio-demo.com` (2.2,
  /// RepoInfo.ts:66-71); every emulator and `*.firebasedatabase.app` host is custom.
  bool get isCustomHost => throw UnimplementedError();

  /// The REST URL of [path] (`/a/b`) with [params] (10): configured host (never the internal one),
  /// path segments percent-encoded one by one, `.json` appended, `ns` first, then [params] in
  /// order.
  Uri restUri(String path, Map<String, String> params) {
    throw UnimplementedError();
  }

  /// Whether a credential may be sent to [uri]: TLS to the configured or an accepted host, or the
  /// emulator's exact host and port (threat model T3).
  bool mayReceiveTokens(Uri uri) {
    throw UnimplementedError();
  }

  @override
  Uri connectionUri({
    String? lastSessionId,
    String? appId,
    String? appCheckToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Map<String, String> connectionHeaders({
    String? appId,
    String? appCheckToken,
  }) {
    throw UnimplementedError();
  }

  @override
  bool acceptServerHost(String host) {
    throw UnimplementedError();
  }

  @override
  void forgetServerHost() {
    throw UnimplementedError();
  }

  @override
  String get configuredHost => throw UnimplementedError();

  @override
  bool get isUsingEmulator => throw UnimplementedError();

  @override
  bool get secure => throw UnimplementedError();

  /// `https://<configuredHost>` (or `http://` for the emulator), never a query (threat model T8).
  @override
  String toString() => throw UnimplementedError();
}

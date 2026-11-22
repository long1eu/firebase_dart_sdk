/// How to reach the database (owner U): the WebSocket and REST URLs, the upgrade headers and the
/// server-chosen host (`rtdb_protocol.md` 2.2 to 2.4, 10; threat model T1, T3, T6).
library;

import 'package:firebase_database_dart/src/core/repo_info.dart';

/// The connection-specific side of one database, built from the core's [RepoInfo] (identity:
/// host, namespace, `secure`, emulator flag; `rtdb_seam_changes.md` A.5, where this class is
/// called `ConnectionTarget`).
///
/// It owns the one piece of mutable connection state about the location: the server-chosen host
/// ([internalHost]), kept in memory only (T1, T27). Tokens can only reach the configured host over
/// TLS, a server host accepted by [acceptServerHost], or the emulator's exact `host:port` (T3).
final class RealtimeTarget {
  /// Creates the target of [repoInfo]. [useHeaders] says whether the platform's connector sends
  /// upgrade headers (`wsConnectorSendsHeaders`); [userAgent] is the `User-Agent` header value.
  ///
  /// For the emulator ([RepoInfo.isUsingEmulator]) the hello `h` and a reset `r` never change the
  /// host, and the scheme is `ws`/`http` unless [RepoInfo.secure] (`*.cloudworkstations.dev`, 2.4).
  RealtimeTarget(
    RepoInfo repoInfo, {
    required bool useHeaders,
    String? userAgent,
  }) {
    throw UnimplementedError();
  }

  /// The identity this target was built from.
  RepoInfo get repoInfo => throw UnimplementedError();

  /// The host of the next WebSocket attempt: the configured host or an accepted server host
  /// (2.2).
  String get internalHost => throw UnimplementedError();

  /// The WebSocket URL of the next attempt (2.3):
  /// `wss://<internalHost>/.ws?v=5[&ls=..][&ac=..][&p=..][&ns=..]`, built with
  /// `Uri(queryParameters:)` (values percent-encoded, T6). `ac` and `p` are added only when the
  /// platform cannot send headers (the web). `ns` is added unless the host is a plain
  /// `<ns>.firebaseio.com` reached before any server redirect (RepoInfo.ts:103-109). Never has
  /// userinfo.
  Uri connectionUri({
    String? lastSessionId,
    String? appId,
    String? appCheckToken,
  }) {
    throw UnimplementedError();
  }

  /// The upgrade headers (2.3, Android style): `User-Agent`, `X-Firebase-GMPID`,
  /// `X-Firebase-AppCheck`. Empty when the platform cannot send headers.
  Map<String, String> connectionHeaders({
    String? appId,
    String? appCheckToken,
  }) {
    throw UnimplementedError();
  }

  /// Offers [host], from a hello `h` or a reset `r`, as the host of the next attempts (3.2, 3.3).
  ///
  /// Accepted only when it is a bare DNS name (no port, userinfo, path, query, fragment, no
  /// trailing dot, at most 253 chars) equal to the configured host or ending in `.firebaseio.com`
  /// / `.firebasedatabase.app` on a label boundary; never with an emulator (threat model T1).
  /// Upper case is lowercased first. Returns whether it was stored.
  bool acceptServerHost(String host) {
    throw UnimplementedError();
  }

  /// Goes back to the configured host: an attempt to a server-chosen host failed before its hello,
  /// or a reset named an invalid host (3.5; iOS U-I21).
  void forgetServerHost() {
    throw UnimplementedError();
  }

  /// The REST URL of [path] (`/a/b`) with [params] (10): the configured host (never the internal
  /// one), path segments percent-encoded one by one, `.json` appended, `ns` first, then [params]
  /// in order.
  Uri restUri(String path, Map<String, String> params) {
    throw UnimplementedError();
  }

  /// Whether a credential may be sent to [uri]: TLS to the configured or an accepted host, or the
  /// emulator's exact host and port (threat model T3).
  bool mayReceiveTokens(Uri uri) {
    throw UnimplementedError();
  }

  /// `RealtimeTarget(<scheme>://<configured host>)`: no query, no server host (T8).
  @override
  String toString() => throw UnimplementedError();
}

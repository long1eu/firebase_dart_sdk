/// How to reach the database (owner U): the WebSocket URL, the upgrade headers and the
/// server-chosen host (`rtdb_protocol.md` 2.2 to 2.4; threat model T1, T3, T6).
library;

import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/realtime/database_url.dart';

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
  ///
  /// Throws [ArgumentError] when [repoInfo] is neither secure nor the emulator (a
  /// misconfiguration that [parseDatabaseUrl] never produces: the WebSocket path would send the ID
  /// and App Check tokens over `ws://`, threat model T3; review M1 (a)) or when its host is not
  /// `host[:port]`.
  RealtimeTarget(this.repoInfo, {required bool useHeaders, String? userAgent})
    : _useHeaders = useHeaders,
      _userAgent = userAgent,
      _address = _configuredAddress(repoInfo) {
    if (!repoInfo.secure && !repoInfo.isUsingEmulator) {
      // Scheme and host only: a RepoInfo holds no query and no credential (threat model T8).
      throw ArgumentError(
        'http://${joinHostPort(_address.host, _address.port)} is plain text, which only the '
        'Realtime Database emulator accepts. Use an https:// database URL, or select the '
        "emulator with the emulatorHost argument ('host:port') of FirebaseDatabase.",
      );
    }
  }

  /// The identity this target was built from.
  final RepoInfo repoInfo;

  final bool _useHeaders;
  final String? _userAgent;

  /// The configured host (lowercase, no brackets) and its explicit port.
  final ({String host, int? port}) _address;

  /// The host accepted from the server, without a port; null while the configured host is used.
  String? _serverHost;

  /// The host of the next WebSocket attempt: the configured host or an accepted server host
  /// (2.2).
  String get internalHost =>
      _serverHost ?? joinHostPort(_address.host, _address.port);

  /// The WebSocket URL of the next attempt (2.3):
  /// `wss://<internalHost>/.ws?v=5[&ls=..][&ac=..][&p=..][&ns=..]`, built with
  /// `Uri(queryParameters:)` (values percent-encoded, T6). `ac` and `p` are added only when the
  /// platform cannot send headers (the web). `ns` is added unless the host is a plain
  /// `<ns>.firebaseio.com` reached before any server redirect (RepoInfo.ts:103-109). Never has
  /// userinfo.
  ///
  /// Empty values are left out (JS websocketconnection.test.ts:35: no `p` for an empty app id).
  Uri connectionUri({
    String? lastSessionId,
    String? appId,
    String? appCheckToken,
  }) {
    final String? serverHost = _serverHost;
    final Map<String, String> query = <String, String>{
      RealtimeProtocol.versionParam: RealtimeProtocol.protocolVersion,
    };
    if (lastSessionId != null && lastSessionId.isNotEmpty) {
      query[RealtimeProtocol.lastSessionParam] = lastSessionId;
    }
    if (!_useHeaders) {
      if (appCheckToken != null && appCheckToken.isNotEmpty) {
        query[RealtimeProtocol.appCheckTokenParam] = appCheckToken;
      }
      if (appId != null && appId.isNotEmpty) {
        query[RealtimeProtocol.applicationIdParam] = appId;
      }
    }
    if (_sendsNamespace) {
      query[RealtimeProtocol.namespaceParam] = repoInfo.namespace;
    }
    return Uri(
      scheme: repoInfo.secure ? 'wss' : 'ws',
      host: serverHost ?? _address.host,
      port: serverHost == null ? _address.port : null,
      path: RealtimeProtocol.webSocketPath,
      queryParameters: query,
    );
  }

  /// The upgrade headers (2.3, Android style): `User-Agent`, `X-Firebase-GMPID`,
  /// `X-Firebase-AppCheck`. Empty when the platform cannot send headers.
  ///
  /// A null or empty value leaves its header out.
  Map<String, String> connectionHeaders({
    String? appId,
    String? appCheckToken,
  }) {
    final Map<String, String> headers = <String, String>{};
    if (!_useHeaders) {
      return headers;
    }
    final String? userAgent = _userAgent;
    if (userAgent != null && userAgent.isNotEmpty) {
      headers['User-Agent'] = userAgent;
    }
    if (appId != null && appId.isNotEmpty) {
      headers[RealtimeProtocol.appIdHeader] = appId;
    }
    if (appCheckToken != null && appCheckToken.isNotEmpty) {
      headers[RealtimeProtocol.appCheckHeader] = appCheckToken;
    }
    return headers;
  }

  /// Offers [host], from a hello `h` or a reset `r`, as the host of the next attempts (3.2, 3.3).
  ///
  /// Accepted only when it is a bare DNS name (no port, userinfo, path, query, fragment, no
  /// trailing dot, at most 253 chars) equal to the configured host or ending in `.firebaseio.com`
  /// / `.firebasedatabase.app` on a label boundary; never with an emulator (threat model T1).
  /// Upper case is lowercased first. Returns whether it was stored.
  ///
  /// The configured host itself is accepted by going back to it (with its configured port).
  /// A refused host leaves the current one in place; the caller decides whether to call
  /// [forgetServerHost] (a reset to an invalid host does, iOS U-I21).
  bool acceptServerHost(String host) {
    if (repoInfo.isUsingEmulator) {
      return false;
    }
    final String name = host.toLowerCase();
    if (!isDnsHostName(name)) {
      return false;
    }
    if (name == _address.host) {
      _serverHost = null;
      return true;
    }
    if (!name.endsWith('.firebaseio.com') &&
        !name.endsWith('.firebasedatabase.app')) {
      return false;
    }
    _serverHost = name;
    return true;
  }

  /// Goes back to the configured host: an attempt to a server-chosen host failed before its hello,
  /// or a reset named an invalid host (3.5; iOS U-I21).
  void forgetServerHost() {
    _serverHost = null;
  }

  /// Whether a credential may be sent to [uri]: TLS to the configured or an accepted host, or the
  /// emulator's exact host and port (threat model T3).
  ///
  /// The scheme must be the configured one's family (`wss`/`https` when secure, `ws`/`http` for a
  /// plain-text emulator); a URL with user info never qualifies. The port compared is the
  /// explicit one or the scheme's default (443 for `wss`/`https`, 80 for `ws`/`http`). A configured
  /// host without a port stands for port 443 in both families, so a plain-text emulator receives
  /// tokens only when its port is named: `emulatorHost: 'localhost'` gets no token (the
  /// persistent connection's second gate, review M1 (b)).
  bool mayReceiveTokens(Uri uri) {
    final bool secure = repoInfo.secure;
    final String scheme = uri.scheme.toLowerCase();
    final bool schemeMatches = secure
        ? scheme == 'https' || scheme == 'wss'
        : scheme == 'http' || scheme == 'ws';
    if (!schemeMatches || uri.userInfo.isNotEmpty) {
      return false;
    }
    final String host = uri.host.toLowerCase();
    final int port = uri.hasPort ? uri.port : (secure ? 443 : 80);
    if (host == _address.host && port == (_address.port ?? 443)) {
      return true;
    }
    return !repoInfo.isUsingEmulator && host == _serverHost && port == 443;
  }

  /// `RealtimeTarget(<scheme>://<configured host>)`: no query, no server host (T8).
  @override
  String toString() =>
      'RealtimeTarget(${repoInfo.secure ? 'https' : 'http'}://'
      '${joinHostPort(_address.host, _address.port)})';

  /// `ns` is left out only for a plain `<ns>.firebaseio.com` reached directly, as JS does
  /// (RepoInfo.ts:103-109); the measured emulator rule (no `ns` makes the first Host label the
  /// namespace, `127.0.0.1` gives `fake-server`) makes it required for every other host.
  bool get _sendsNamespace {
    if (repoInfo.isUsingEmulator ||
        _serverHost != null ||
        _address.port != null) {
      return true;
    }
    final String host = _address.host;
    final List<String> labels = host.split('.');
    return labels.length != 3 ||
        !host.endsWith('.firebaseio.com') ||
        labels.first != repoInfo.namespace;
  }

  static ({String host, int? port}) _configuredAddress(RepoInfo repoInfo) {
    final ({String host, int? port}) address;
    try {
      address = splitHostPort(repoInfo.host);
    } on FormatException catch (e) {
      throw ArgumentError.value(repoInfo.host, 'repoInfo', e.message);
    }
    return (host: address.host.toLowerCase(), port: address.port);
  }
}

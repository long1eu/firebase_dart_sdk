/// The `dart:io` WebSocket channel (owner T). Selected by `ws_connector.dart` on the VM.
///
/// The upgrade is done by hand (threat model T4): `HttpClient.openUrl` with
/// `followRedirects = false`, a check of 101 and `Sec-WebSocket-Accept`, `detachSocket()`, then
/// `WebSocket.fromUpgradedSocket` with compression off (T5) and no `pingInterval` (liveness is the
/// protocol's ping, `rtdb_protocol.md` 3.4). The bytes of one message are counted on the detached
/// socket and the channel closes past `maxMessageBytes` (T9).
///
/// A `wss` attempt goes through the HTTP proxy that the environment names for it, as
/// `HttpClient.findProxyFromEnvironment` reads it (`HTTPS_PROXY`, `NO_PROXY` and their lower-case
/// forms); a loopback target and every `ws` target are always direct (see [ioWsConnector]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:firebase_database_dart/src/realtime/framing.dart';
import 'package:firebase_database_dart/src/realtime/transport/ws_channel.dart';

/// Whether this platform's connector sends upgrade headers. True on the VM: the app id and the App
/// Check token travel as `X-Firebase-GMPID` and `X-Firebase-AppCheck` (`rtdb_protocol.md` 2.3,
/// Android style, section 11 last row).
const bool platformSendsHeaders = true;

/// The connector of this platform, for `ws_connector.dart`.
WsConnector createWsConnector({required int maxMessageBytes}) =>
    ioWsConnector(maxMessageBytes: maxMessageBytes);

/// A connector over `dart:io`.
///
/// [httpClient] is used for the upgrade when given, with its own `findProxy` (a new `HttpClient`
/// reads the environment); otherwise a new one is created per attempt, with [upgradeTimeout] as
/// its `connectionTimeout`, and closed after it. No `badCertificateCallback` is ever set.
///
/// Proxy, for a client of its own: a `wss` target uses the proxy that
/// `HttpClient.findProxyFromEnvironment` finds in [environment] (null: the process environment),
/// that is `https_proxy` or `HTTPS_PROXY` unless `no_proxy` or `NO_PROXY` lists a suffix of the
/// host. A proxy URL may hold `user:password@`, sent as `Proxy-Authorization: Basic` on the
/// CONNECT. Always direct: a loopback target (`localhost` or a loopback IP literal), and every
/// `ws` target, because plain text is only ever the emulator (`RealtimeTarget` refuses it for any
/// other database) and a proxy would read its frames. Through a proxy, `HttpClient` sends
/// `CONNECT host:port` and runs TLS over the tunnel; the upgrade request, its headers and every
/// frame travel inside that TLS. [environment] exists for tests.
///
/// An attempt that has no open channel after [upgradeTimeout] (TCP, CONNECT, TLS and the upgrade
/// answer together), or whose `abort` future completes first, aborts its pending request, closes
/// a client of its own with force and fails with [WsConnectFailure.other]: a server or a proxy
/// that accepts and stays silent leaves no socket behind (review M2), with one limit of dart:io: an
/// attempt that stalls inside the TLS handshake keeps its socket until the peer or the OS closes
/// it, because dart:io offers no handle before the handshake completes (`SecureSocket.secure`
/// detaches the socket, after which `Socket.destroy` is a no-op); the socket is destroyed as soon
/// as the handshake ends. Through a proxy the same holds for the TLS handshake inside the tunnel.
WsConnector ioWsConnector({
  HttpClient? httpClient,
  required int maxMessageBytes,
  Duration upgradeTimeout = const Duration(seconds: 30),
  Map<String, String>? environment,
}) {
  final _IoConnector connector = _IoConnector(
    httpClient,
    maxMessageBytes,
    upgradeTimeout,
    environment,
  );
  return (
    Uri url, {
    Map<String, String> headers = const <String, String>{},
    Future<void>? abort,
  }) => connector.connect(url, headers, abort);
}

/// The GUID of RFC 6455 section 1.3, appended to the key for `Sec-WebSocket-Accept`.
const String _acceptGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

/// The `Sec-WebSocket-Accept` value the server must answer to [key] (RFC 6455 section 4.2.2).
String _expectedAccept(String key) =>
    base64Encode(sha1.convert(ascii.encode('$key$_acceptGuid')).bytes);

final class _IoConnector {
  _IoConnector(
    this._httpClient,
    this._maxMessageBytes,
    this._upgradeTimeout,
    this._environment,
  );

  final HttpClient? _httpClient;
  final int _maxMessageBytes;
  final Duration _upgradeTimeout;
  final Map<String, String>? _environment;

  Future<WsChannel> connect(
    Uri url,
    Map<String, String> headers,
    Future<void>? abort,
  ) async {
    final String httpScheme = switch (url.scheme) {
      'ws' => 'http',
      'wss' => 'https',
      _ => throw const WsConnectException(
        WsConnectFailure.badScheme,
        'only ws and wss URLs are accepted',
      ),
    };
    if (url.userInfo.isNotEmpty) {
      // dart:io would turn it into an `Authorization: Basic` header (threat model T4).
      throw const WsConnectException(
        WsConnectFailure.other,
        'a URL with user info is refused',
      );
    }
    final Uri httpUrl = url.replace(scheme: httpScheme);
    final HttpClient? shared = _httpClient;
    final _UpgradeAttempt attempt = shared != null
        ? _UpgradeAttempt.shared(shared)
        : _UpgradeAttempt.owned(
            _upgradeTimeout,
            _proxyRoute(httpUrl, _environment),
          );
    final Timer timer = Timer(
      _upgradeTimeout,
      () => attempt.stop('the WebSocket upgrade timed out'),
    );
    if (abort != null) {
      void stop() => attempt.stop('the connect attempt was aborted');
      unawaited(abort.then((_) => stop(), onError: (Object _) => stop()));
    }
    try {
      // A shared client may keep connecting until its own connectionTimeout: the attempt fails at
      // once when stopped, and a request that opens later is dropped by `upgrade`.
      final Socket socket = await Future.any(<Future<Socket>>[
        attempt.upgrade(httpUrl, headers),
        attempt.whenStopped,
      ]);
      final _MeteredSocket metered = _MeteredSocket(socket, _maxMessageBytes);
      final WebSocket webSocket = WebSocket.fromUpgradedSocket(
        metered,
        serverSide: false,
        compression: CompressionOptions.compressionOff,
      );
      return IoWsChannel._(webSocket, _maxMessageBytes, metered);
    } on Object catch (e) {
      final WsConnectException? failure =
          attempt.stopped ??
          _tunnelRefused(e, attempt.proxy) ??
          _connectFailure(e);
      if (failure == null) {
        rethrow;
      }
      throw failure;
    } finally {
      timer.cancel();
      attempt.finish();
    }
  }
}

/// The connect failure of an error raised by the upgrade, without URL or header in the message;
/// null for an error that is not a connect failure (rethrown as it is).
WsConnectException? _connectFailure(Object e) => switch (e) {
  WsConnectException() => e,
  SocketException() => _socketFailure(e),
  TlsException() => WsConnectException(
    WsConnectFailure.tls,
    'the TLS handshake failed',
    cause: e,
  ),
  IOException() => WsConnectException(
    WsConnectFailure.other,
    'the WebSocket upgrade failed',
    cause: e,
  ),
  _ => null,
};

/// The proxy of one `wss` attempt: its `host:port` for messages (never the credentials) and the
/// configuration string for `HttpClient.findProxy`.
typedef _ProxyRoute = ({String address, String configuration});

/// The proxy that the environment names for [httpUrl], or null for a direct connection: always
/// null for `http` (a `ws` target) and for a loopback host (see [ioWsConnector]).
///
/// Throws [WsConnectException] for a proxy setting that `HttpClient` would refuse, with a message
/// that does not repeat the setting (it may hold a password).
_ProxyRoute? _proxyRoute(Uri httpUrl, Map<String, String>? environment) {
  if (httpUrl.scheme != 'https' || _isLoopback(httpUrl.host)) {
    return null;
  }
  final String configuration = HttpClient.findProxyFromEnvironment(
    httpUrl,
    environment: environment,
  );
  const String prefix = 'PROXY ';
  if (!configuration.startsWith(prefix)) {
    return null;
  }
  // `PROXY [user:password@]host:port`, checked as `HttpClient` parses it (_ProxyConfiguration).
  final String proxy = configuration.substring(prefix.length).trim();
  final int at = proxy.lastIndexOf('@');
  final String userInfo = at == -1 ? '' : proxy.substring(0, at).trim();
  final int userColon = userInfo.indexOf(':');
  final String address = proxy.substring(at + 1).trim();
  final int colon = address.lastIndexOf(':');
  final bool valid =
      (at == -1 || (userColon > 0 && userColon < userInfo.length - 1)) &&
      colon > 0 &&
      int.tryParse(address.substring(colon + 1).trim()) != null;
  if (!valid) {
    throw const WsConnectException(
      WsConnectFailure.other,
      'the proxy in HTTPS_PROXY (or https_proxy) is not valid: '
      'use http://host:port or http://user:password@host:port',
    );
  }
  return (address: address, configuration: configuration);
}

/// Whether [host] is `localhost` or a loopback IP literal (`127.0.0.0/8`, `::1`).
bool _isLoopback(String host) {
  final String name = host.toLowerCase();
  return name == 'localhost' ||
      (InternetAddress.tryParse(name)?.isLoopback ?? false);
}

/// The failure of a proxy that answered CONNECT with another status than 200, or null when [e] is
/// not that. `HttpClient` reports it as an [HttpException] whose message starts with
/// `Proxy failed to establish tunnel (<status> <reason>)`.
WsConnectException? _tunnelRefused(Object e, _ProxyRoute? proxy) {
  if (proxy == null || e is! HttpException) {
    return null;
  }
  final Match? match = RegExp(
    r'^Proxy failed to establish tunnel \((\d{3})',
  ).firstMatch(e.message);
  if (match == null) {
    return null;
  }
  return WsConnectException(
    WsConnectFailure.other,
    'the proxy ${proxy.address} answered CONNECT with HTTP ${match.group(1)}: check the proxy '
    'address and credentials in HTTPS_PROXY (or https_proxy), or list the host in NO_PROXY',
    cause: e,
  );
}

/// One upgrade in flight: its client and pending request, and whether it was stopped (review M2).
///
/// With a client of its own, the attempt opens the TCP socket (to the target or to the proxy) and,
/// when direct, runs the TLS handshake itself (through `HttpClient.connectionFactory`), so a stop
/// cancels the TCP connect, destroys the socket while it waits for TLS, for the proxy's CONNECT
/// answer or for the upgrade answer, and destroys a socket whose direct handshake ends after the
/// stop. Inside a handshake dart:io gives no handle (see [ioWsConnector]). With a shared client it
/// can only abort the request once `openUrl` has returned one; the client's own
/// `connectionTimeout` bounds the rest.
final class _UpgradeAttempt {
  _UpgradeAttempt.shared(HttpClient client)
    : _client = client,
      _ownsClient = false,
      proxy = null;

  _UpgradeAttempt.owned(Duration timeout, this.proxy)
    : _client = HttpClient(),
      _ownsClient = true {
    final String route = proxy?.configuration ?? 'DIRECT';
    _client
      ..connectionTimeout = timeout
      ..findProxy = ((Uri _) => route)
      ..connectionFactory = _connectSocket;
  }

  final HttpClient _client;
  final bool _ownsClient;

  /// The proxy of a client of its own, or null when the attempt is direct or the client shared.
  final _ProxyRoute? proxy;
  final List<ConnectionTask<Socket>> _tcpTasks = <ConnectionTask<Socket>>[];
  final List<Socket> _rawSockets = <Socket>[];
  HttpClientRequest? _request;
  bool _finished = false;
  final Completer<Socket> _stopSignal = Completer<Socket>();

  /// Fails with [stopped] when the attempt is stopped; never completes otherwise.
  Future<Socket> get whenStopped => _stopSignal.future;

  /// The failure of a stopped attempt (timed out or aborted), or null while it runs.
  WsConnectException? stopped;

  /// The connection factory of a client of its own: a TCP connect, then TLS for a direct `https`
  /// target, with the raw socket kept for [stop] (until TLS takes it over, see [ioWsConnector]).
  ///
  /// With [proxyHost] and [proxyPort] (only for the [proxy] of this attempt) it connects to the
  /// proxy and returns the plain socket: `HttpClient` sends CONNECT on it and runs TLS over the
  /// tunnel itself.
  Future<ConnectionTask<Socket>> _connectSocket(
    Uri url,
    String? proxyHost,
    int? proxyPort,
  ) async {
    final ConnectionTask<Socket> tcp = switch ((proxyHost, proxyPort)) {
      (final String host, final int port) => await Socket.startConnect(
        host,
        port,
      ),
      _ => await Socket.startConnect(url.host, url.port),
    };
    final bool viaProxy = proxyHost != null;
    final _ProxyRoute? route = proxy;
    _tcpTasks.add(tcp);
    if (stopped != null) {
      tcp.cancel();
    }
    final Future<Socket> connected = tcp.socket.then(
      (Socket raw) {
        _rawSockets.add(raw);
        final WsConnectException? stoppedMeanwhile = stopped;
        if (stoppedMeanwhile != null) {
          raw.destroy();
          throw stoppedMeanwhile;
        }
        if (viaProxy || url.scheme != 'https') {
          return raw;
        }
        // After this call `raw.destroy()` does nothing: dart:io moves the native socket into the
        // RawSecureSocket it builds and returns no handle before the handshake ends. So a socket
        // stalled in the handshake can only be dropped when the handshake completes or fails.
        return SecureSocket.secure(raw, host: url.host).then((
          SecureSocket secured,
        ) {
          _rawSockets.add(secured);
          final WsConnectException? stoppedLate = stopped;
          if (stoppedLate != null) {
            secured.destroy();
            throw stoppedLate;
          }
          return secured;
        });
      },
      onError: viaProxy && route != null
          ? (Object e, StackTrace s) => _proxyUnreachable(e, s, route)
          : null,
    );
    return ConnectionTask.fromSocket(connected, _dropSockets);
  }

  void _dropSockets() {
    for (final ConnectionTask<Socket> task in _tcpTasks) {
      task.cancel();
    }
    for (final Socket socket in _rawSockets) {
      socket.destroy();
    }
  }

  /// Stops the attempt with [why] unless it already ended: aborts the pending request and, with a
  /// client of its own, cancels the TCP connect, destroys the socket (a socket inside the TLS
  /// handshake as soon as the handshake ends) and closes the client with force.
  void stop(String why) {
    if (_finished || stopped != null) {
      return;
    }
    final WsConnectException failure = WsConnectException(
      WsConnectFailure.other,
      why,
    );
    stopped = failure;
    _stopSignal.completeError(failure);
    _request?.abort(failure);
    if (_ownsClient) {
      _dropSockets();
      _client.close(force: true);
    }
  }

  /// Ends the attempt: a client of its own is closed (gently when it succeeded).
  void finish() {
    if (_finished) {
      return;
    }
    _finished = true;
    if (_ownsClient && stopped == null) {
      _client.close();
    }
  }

  /// Sends the upgrade request to [httpUrl] and checks the answer; returns the detached socket.
  Future<Socket> upgrade(Uri httpUrl, Map<String, String> headers) async {
    final Random random = Random.secure();
    final String key = base64Encode(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final HttpClientRequest request = await _client.openUrl('GET', httpUrl);
    final WsConnectException? stoppedEarly = stopped;
    if (stoppedEarly != null) {
      // A shared client is not closed: the request it opened meanwhile is dropped here.
      request.abort(stoppedEarly);
      throw stoppedEarly;
    }
    _request = request;
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    request.headers
      ..set(HttpHeaders.connectionHeader, 'Upgrade')
      ..set(HttpHeaders.upgradeHeader, 'websocket')
      ..set('Sec-WebSocket-Key', key)
      ..set('Sec-WebSocket-Version', '13')
      ..removeAll('Sec-WebSocket-Extensions');
    final HttpClientResponse response = await request.close();
    final int status = response.statusCode;
    final String? problem = status != HttpStatus.switchingProtocols
        ? 'the server refused the WebSocket upgrade'
        : _upgradeProblem(response.headers, key);
    if (problem != null || stopped != null) {
      (await response.detachSocket()).destroy();
      throw stopped ??
          WsConnectException(
            WsConnectFailure.upgradeRejected,
            problem!,
            httpStatus: status,
          );
    }
    final Socket socket = await response.detachSocket();
    if (stopped != null) {
      socket.destroy();
      throw stopped!;
    }
    _finished = true;
    if (_ownsClient) {
      _client.close();
    }
    return socket;
  }
}

/// What is wrong with the headers of a 101 answer to [key], or null.
String? _upgradeProblem(HttpHeaders headers, String key) {
  final List<String> connection = <String>[
    for (final String value
        in headers[HttpHeaders.connectionHeader] ?? <String>[])
      for (final String token in value.split(',')) token.trim().toLowerCase(),
  ];
  if (!connection.contains('upgrade')) {
    return 'the upgrade answer has no Connection: Upgrade';
  }
  if (headers.value(HttpHeaders.upgradeHeader)?.toLowerCase() != 'websocket') {
    return 'the upgrade answer has no Upgrade: websocket';
  }
  if (headers.value('Sec-WebSocket-Accept') != _expectedAccept(key)) {
    return 'the upgrade answer has a wrong Sec-WebSocket-Accept';
  }
  if (headers.value('Sec-WebSocket-Extensions') != null) {
    // None was offered; a server that picks one anyway may compress (threat model T5).
    return 'the upgrade answer selects an extension that was not offered';
  }
  return null;
}

/// Rethrows [e], an error of the TCP connect to [proxy], with the proxy named in the message.
Never _proxyUnreachable(Object e, StackTrace stackTrace, _ProxyRoute proxy) {
  if (e is! SocketException) {
    Error.throwWithStackTrace(e, stackTrace);
  }
  final WsConnectException failure = _socketFailure(e);
  throw WsConnectException(
    failure.kind,
    '${failure.message} (the proxy ${proxy.address}): check HTTPS_PROXY (or https_proxy), '
    'or list the host in NO_PROXY',
    cause: e,
  );
}

/// The connect failure of a [SocketException], without its address in the message.
WsConnectException _socketFailure(SocketException e) {
  final String text = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();
  final int? code = e.osError?.errorCode;
  if (text.contains('host lookup') || text.contains('nodename nor servname')) {
    return WsConnectException(
      WsConnectFailure.dns,
      'the host name did not resolve',
      cause: e,
    );
  }
  // ECONNREFUSED: 61 on macOS, 111 on Linux, 10061 on Windows.
  if (code == 61 || code == 111 || code == 10061 || text.contains('refused')) {
    return WsConnectException(
      WsConnectFailure.refused,
      'the connection was refused',
      cause: e,
    );
  }
  return WsConnectException(
    WsConnectFailure.other,
    'the connection failed',
    cause: e,
  );
}

/// How long [IoWsChannel.close] waits for the close handshake before it drops the socket.
const Duration _closeBound = Duration(seconds: 5);

/// A [WsChannel] over a `dart:io` [WebSocket].
final class IoWsChannel implements WsChannel {
  /// Wraps [socket], which must already be open. [maxMessageBytes] bounds one inbound message.
  ///
  /// A socket opened elsewhere is checked after dart:io has assembled each message; the channel of
  /// [ioWsConnector] counts the bytes on the wire instead, before the message is held whole.
  IoWsChannel(WebSocket socket, {required int maxMessageBytes})
    : this._(socket, maxMessageBytes, null);

  IoWsChannel._(this._socket, this._maxMessageBytes, this._raw) {
    _subscription = _socket.listen(
      _onMessage,
      onError: _onError,
      onDone: _onDone,
    );
  }

  final WebSocket _socket;
  final int _maxMessageBytes;
  final _MeteredSocket? _raw;
  final StreamController<WsEvent> _events = StreamController<WsEvent>();
  late final StreamSubscription<Object?> _subscription;
  bool _closed = false;
  bool _ended = false;
  Future<void>? _closing;

  @override
  Stream<WsEvent> get events => _events.stream;

  @override
  void sendText(String frame) {
    if (_closed) {
      throw StateError('sendText on a closed WebSocket channel');
    }
    _socket.add(frame);
  }

  @override
  Future<void> close([int code = 1000, String? reason]) {
    return _closing ??= _close(code, reason);
  }

  Future<void> _close(int code, String? reason) async {
    _closed = true;
    try {
      await _socket.close(code, reason).timeout(_closeBound);
    } on TimeoutException {
      _raw?.destroy();
    } on Object {
      // An invalid code or a socket already gone: the stream ends either way.
      _raw?.destroy();
    }
  }

  @override
  void abandon() {
    if (_ended) {
      return;
    }
    _closed = true;
    unawaited(_subscription.cancel());
    final _MeteredSocket? raw = _raw;
    if (raw != null) {
      raw.destroy();
    } else {
      unawaited(_socket.close().catchError((Object _) {}));
    }
    _end(const WsClosed(null, null));
  }

  void _onMessage(Object? data) {
    if (_ended) {
      return;
    }
    if (data is String) {
      if (_raw == null && utf8Length(data) > _maxMessageBytes) {
        _tooLarge();
        unawaited(_socket.close(1009).catchError((Object _) {}));
        return;
      }
      _events.add(WsText(data));
    } else if (data is List<int>) {
      if (_raw == null && data.length > _maxMessageBytes) {
        _tooLarge();
        unawaited(_socket.close(1009).catchError((Object _) {}));
        return;
      }
      _events.add(
        WsBinary(data is Uint8List ? data : Uint8List.fromList(data)),
      );
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (!_ended) {
      _events.add(WsError(error, stackTrace));
    }
  }

  void _onDone() {
    _closed = true;
    if (_raw?.overflowed ?? false) {
      _tooLarge();
      return;
    }
    _end(WsClosed(_socket.closeCode, _socket.closeReason));
  }

  void _tooLarge() {
    if (_ended) {
      return;
    }
    _closed = true;
    _events.add(
      WsError(
        StateError('inbound message larger than $_maxMessageBytes bytes'),
        StackTrace.current,
      ),
    );
    _end(const WsClosed(1009, null));
  }

  void _end(WsClosed event) {
    if (_ended) {
      return;
    }
    _ended = true;
    _events.add(event);
    unawaited(_events.close());
  }
}

/// The detached socket of an upgrade, with the size of each inbound message counted from the
/// frame headers as the bytes arrive (threat model T9): a message whose frames announce more than
/// `maxMessageBytes` of payload destroys the socket before dart:io buffers it.
final class _MeteredSocket extends StreamView<Uint8List> implements Socket {
  factory _MeteredSocket(Socket socket, int maxMessageBytes) {
    final _FrameMeter meter = _FrameMeter(maxMessageBytes);
    late final _MeteredSocket metered;
    final Stream<Uint8List> counted = socket.where((Uint8List chunk) {
      if (metered.overflowed) {
        return false;
      }
      if (!meter.add(chunk)) {
        metered.overflowed = true;
        socket.destroy();
        return false;
      }
      return true;
    });
    return metered = _MeteredSocket._(socket, counted);
  }

  _MeteredSocket._(this._socket, Stream<Uint8List> counted) : super(counted);

  final Socket _socket;

  /// Whether a message passed the limit and the socket was destroyed.
  bool overflowed = false;

  @override
  InternetAddress get address => _socket.address;

  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;

  @override
  int get port => _socket.port;

  @override
  int get remotePort => _socket.remotePort;

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _socket.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) =>
      _socket.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _socket.setRawOption(option);

  @override
  void destroy() => _socket.destroy();

  @override
  Encoding get encoding => _socket.encoding;

  @override
  set encoding(Encoding value) => _socket.encoding = value;

  @override
  void add(List<int> data) => _socket.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _socket.addStream(stream);

  @override
  Future<void> close() => _socket.close();

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> flush() => _socket.flush();

  @override
  void write(Object? object) => _socket.write(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _socket.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _socket.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _socket.writeln(object);
}

/// Follows the frame headers of the server-to-client byte stream (RFC 6455 section 5.2) and sums
/// the payload lengths of the data frames of one message.
final class _FrameMeter {
  _FrameMeter(this._maxMessageBytes);

  final int _maxMessageBytes;
  final List<int> _header = <int>[];
  int _payloadLeft = 0;
  int _messageBytes = 0;

  /// Feeds [chunk]; false when a message announced more than the limit.
  bool add(Uint8List chunk) {
    int i = 0;
    while (i < chunk.length) {
      if (_payloadLeft > 0) {
        final int skip = min(_payloadLeft, chunk.length - i);
        _payloadLeft -= skip;
        i += skip;
        continue;
      }
      _header.add(chunk[i]);
      i++;
      final int? length = _headerLength();
      if (length == null || _header.length < length) {
        continue;
      }
      if (!_frameStarted()) {
        return false;
      }
      _header.clear();
    }
    return true;
  }

  int? _headerLength() {
    if (_header.length < 2) {
      return null;
    }
    final int length7 = _header[1] & 0x7F;
    final int extended = length7 == 126 ? 2 : (length7 == 127 ? 8 : 0);
    final int mask = (_header[1] & 0x80) != 0 ? 4 : 0;
    return 2 + extended + mask;
  }

  bool _frameStarted() {
    final bool fin = (_header[0] & 0x80) != 0;
    final int opcode = _header[0] & 0x0F;
    int length = _header[1] & 0x7F;
    if (length == 126) {
      length = (_header[2] << 8) | _header[3];
    } else if (length == 127) {
      length = 0;
      for (int k = 2; k < 10; k++) {
        length = (length << 8) | _header[k];
      }
      if (length < 0) {
        return false;
      }
    }
    _payloadLeft = length;
    if (opcode >= 8) {
      // A control frame (close, ping, pong) may come between the fragments of a message.
      return true;
    }
    _messageBytes += length;
    if (_messageBytes > _maxMessageBytes) {
      return false;
    }
    if (fin) {
      _messageBytes = 0;
    }
    return true;
  }
}

/// The `dart:io` WebSocket channel (owner T). Selected by `ws_connector.dart` on the VM.
///
/// The upgrade is done by hand (threat model T4): `HttpClient.openUrl` with
/// `followRedirects = false`, a check of 101 and `Sec-WebSocket-Accept`, `detachSocket()`, then
/// `WebSocket.fromUpgradedSocket` with compression off (T5) and no `pingInterval` (liveness is the
/// protocol's ping, `rtdb_protocol.md` 3.4). The bytes of one message are counted on the detached
/// socket and the channel closes past `maxMessageBytes` (T9).
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
/// [httpClient] is used for the upgrade when given (for a proxy through `HttpClient.findProxy`;
/// none is read from the environment, threat model T4); otherwise a new one is created per attempt.
/// No `badCertificateCallback` is ever set.
WsConnector ioWsConnector({
  HttpClient? httpClient,
  required int maxMessageBytes,
}) {
  return (Uri url, {Map<String, String> headers = const <String, String>{}}) =>
      _connect(url, headers, httpClient, maxMessageBytes);
}

/// The GUID of RFC 6455 section 1.3, appended to the key for `Sec-WebSocket-Accept`.
const String _acceptGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

/// The `Sec-WebSocket-Accept` value the server must answer to [key] (RFC 6455 section 4.2.2).
String _expectedAccept(String key) =>
    base64Encode(sha1.convert(ascii.encode('$key$_acceptGuid')).bytes);

Future<WsChannel> _connect(
  Uri url,
  Map<String, String> headers,
  HttpClient? httpClient,
  int maxMessageBytes,
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
  final HttpClient client = httpClient ?? HttpClient();
  try {
    final Socket socket = await _upgrade(
      client,
      url.replace(scheme: httpScheme),
      headers,
    );
    final _MeteredSocket metered = _MeteredSocket(socket, maxMessageBytes);
    final WebSocket webSocket = WebSocket.fromUpgradedSocket(
      metered,
      serverSide: false,
      compression: CompressionOptions.compressionOff,
    );
    return IoWsChannel._(webSocket, maxMessageBytes, metered);
  } on WsConnectException {
    rethrow;
  } on SocketException catch (e) {
    throw _socketFailure(e);
  } on TlsException catch (e) {
    throw WsConnectException(
      WsConnectFailure.tls,
      'the TLS handshake failed',
      cause: e,
    );
  } on IOException catch (e) {
    throw WsConnectException(
      WsConnectFailure.other,
      'the WebSocket upgrade failed',
      cause: e,
    );
  } finally {
    if (httpClient == null) {
      client.close();
    }
  }
}

/// Sends the upgrade request and checks the answer; returns the detached socket.
Future<Socket> _upgrade(
  HttpClient client,
  Uri httpUrl,
  Map<String, String> headers,
) async {
  final Random random = Random.secure();
  final String key = base64Encode(
    List<int>.generate(16, (_) => random.nextInt(256)),
  );
  final HttpClientRequest request = await client.openUrl('GET', httpUrl);
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
  if (status != HttpStatus.switchingProtocols) {
    (await response.detachSocket()).destroy();
    throw WsConnectException(
      WsConnectFailure.upgradeRejected,
      'the server refused the WebSocket upgrade',
      httpStatus: status,
    );
  }
  final String? problem = _upgradeProblem(response.headers, key);
  if (problem != null) {
    (await response.detachSocket()).destroy();
    throw WsConnectException(
      WsConnectFailure.upgradeRejected,
      problem,
      httpStatus: status,
    );
  }
  return response.detachSocket();
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

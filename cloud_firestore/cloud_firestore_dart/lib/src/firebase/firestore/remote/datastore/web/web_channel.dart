// A client for the WebChannel protocol (version 8), the HTTP based transport
// the Firestore backend and emulator offer for the bidirectional Listen and
// Write RPCs. Browsers cannot use gRPC, and gRPC-Web has no bidirectional
// streams.
//
// The JS SDK uses the closure library implementation
// (packages/firestore/src/platform/browser/webchannel_connection.ts). This is
// an independent implementation of the subset Firestore needs:
//
//  * The session starts with a "forward channel" POST to `<rpc>/channel` that
//    also carries the first messages. The request headers (credentials) travel
//    in the form body, so the request needs no CORS preflight. The response
//    names the session: `[[0,["c","<SID>","",8,<server version>,<timeout>]]]`.
//  * Further client messages are POSTed with `SID`, an incrementing `RID` and
//    `ofs`, the index of the first message in the body.
//  * Server messages arrive on the "back channel", a long lived GET with
//    `RID=rpc`. Its body is a sequence of chunks `<length>\n<json>`, where
//    length counts UTF-16 code units and the JSON is a list of
//    `[arrayId, payload]`. A payload is `[message]`, a control message
//    (`["noop"]`, `["stop"]`, `["close"]`) or a `{"__sm__": ...}` envelope
//    with a status. When the GET ends it is issued again with `AID`, the last
//    array id that was received.
//  * `TYPE=terminate` ends the session.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rpc_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_http_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';

/// Splits a WebChannel response body into its JSON chunks.
class WebChannelChunkParser {
  String _buffer = '';

  /// The longest chunk that is accepted, in UTF-16 code units. The framing
  /// comes from the network: a larger (or negative) length is not buffered
  /// for but reported as a malformed body. Far above what the backend sends
  /// (a chunk holds a few messages; a message is a document of at most 1 MiB
  /// as JSON).
  static const int maxChunkLength = 64 * 1024 * 1024;

  static final RegExp _decimal = RegExp(r'^[0-9]+$');

  /// Adds [text] and returns the chunks that are complete, decoded.
  ///
  /// Throws a [FormatException] if the body is not chunked as expected.
  List<Object?> add(String text) {
    _buffer += text;
    final List<Object?> chunks = <Object?>[];
    while (true) {
      final int newline = _buffer.indexOf('\n');
      if (newline < 0) {
        if (_buffer.length > 20) {
          throw FormatException('Missing chunk length', _buffer);
        }
        break;
      }
      final String prefix = _buffer.substring(0, newline).trim();
      final int? length =
          _decimal.hasMatch(prefix) ? int.tryParse(prefix) : null;
      if (length == null || length > maxChunkLength) {
        throw FormatException('Invalid chunk length', prefix);
      }
      final int end = newline + 1 + length;
      if (_buffer.length < end) {
        break;
      }
      chunks.add(jsonDecode(_buffer.substring(newline + 1, end)));
      _buffer = _buffer.substring(end);
    }
    return chunks;
  }

  /// Whether there is text that is not a complete chunk yet.
  bool get hasPartialChunk => _buffer.trim().isNotEmpty;
}

/// One WebChannel session: a bidirectional stream of JSON messages.
class WebChannelStream {
  WebChannelStream(
    this._http,
    this._channelUrl,
    this._database,
    this._initHeaders, {
    Random? random,
  }) : _random = random ?? Random() {
    _requestId = _random.nextInt(100000);
  }

  final WebHttpClient _http;

  /// `<base>/google.firestore.v1.Firestore/<Rpc>/channel`.
  final String _channelUrl;

  /// `projects/<p>/databases/<d>`: sent with every request, the backend routes
  /// on it.
  final String _database;

  /// Sent once, with the handshake.
  final Map<String, String> _initHeaders;
  final Random _random;

  static const String _protocolVersion = '8';
  static const String _clientVersion = '22';

  /// How many back channel requests in a row may end without any data before
  /// the session is given up.
  static const int _maxEmptyBackChannelRequests = 3;

  final StreamController<Map<String, Object?>> _messages =
      StreamController<Map<String, Object?>>();
  final Completer<Map<String, String>> _handshakeHeaders =
      Completer<Map<String, String>>();

  final List<String> _outgoing = <String>[];
  int _sentCount = 0;
  bool _sending = false;
  bool _opened = false;
  bool _closed = false;
  bool _closeWhenFlushed = false;

  late int _requestId;
  String? _sessionId;
  String? _httpSessionId;
  int _lastArrayId = 0;
  Duration _backChannelTimeout = const Duration(seconds: 45);

  WebHttpRequest? _forwardRequest;
  WebHttpRequest? _backRequest;
  Timer? _backChannelTimer;

  /// The messages of the server. Fails with a [GrpcError] when the session
  /// breaks or the server reports an error; the stream ends after that, and
  /// after [close].
  Stream<Map<String, Object?>> get messages => _messages.stream;

  /// The response headers of the handshake (empty if it never succeeded).
  Future<Map<String, String>> get handshakeHeaders => _handshakeHeaders.future;

  /// Queues [json], one encoded message, for the server. The session is
  /// opened by the first message, which travels with the handshake.
  void send(String json) {
    if (_closed) {
      return;
    }
    _outgoing.add(json);
    unawaited(_flush());
  }

  /// Ends the session.
  Future<void> close() => _shutdown();

  /// Closes the stream once everything that was passed to [send] has been delivered. WebChannel has no half-close:
  /// this is what the end of the client's requests means for it.
  void closeWhenFlushed() {
    _closeWhenFlushed = true;
    if (!_sending && _outgoing.isEmpty) {
      unawaited(_shutdown());
    }
  }

  Uri _url(Map<String, String> params) {
    final Map<String, String> all = <String, String>{
      'database': _database,
      if (_httpSessionId != null) 'gsessionid': _httpSessionId!,
      'VER': _protocolVersion,
      ...params,
      // Defeats caches.
      'zx': _random.nextInt(0x7fffffff).toRadixString(36),
      't': '1',
    };
    final String query = all.entries
        .map((MapEntry<String, String> e) =>
            '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return Uri.parse('$_channelUrl?$query');
  }

  Future<void> _flush() async {
    if (_sending || _closed || _outgoing.isEmpty) {
      return;
    }
    _sending = true;
    final List<String> batch = List<String>.of(_outgoing);
    _outgoing.clear();

    final bool handshake = !_opened;
    _opened = true;
    final List<String> form = <String>[
      if (handshake && _initHeaders.isNotEmpty)
        'headers=${Uri.encodeComponent(_encodeHeaders(_initHeaders))}',
      'count=${batch.length}',
      'ofs=$_sentCount',
      for (int i = 0; i < batch.length; i++)
        'req${i}___data__=${Uri.encodeComponent(batch[i])}',
    ];
    final Uri url = handshake
        ? _url(<String, String>{
            'RID': '${_requestId++}',
            'CVER': _clientVersion,
            // Asks for the session id of the HTTP layer in this header, to be
            // echoed as `gsessionid` (backend stickiness).
            'X-HTTP-Session-Id': 'gsessionid',
          })
        : _url(<String, String>{
            'SID': _sessionId!,
            'RID': '${_requestId++}',
            'AID': '$_lastArrayId',
          });

    try {
      final WebHttpRequest request = _http.send(
        'POST',
        url,
        headers: const <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: form.join('&'),
      );
      _forwardRequest = request;
      final WebHttpResponse response = await request.response;
      final String text = await response.readAll();
      _forwardRequest = null;
      if (_closed) {
        return;
      }
      if (response.statusCode != 200) {
        _fail(_httpError(response.statusCode, text));
        return;
      }
      if (handshake) {
        if (!_onHandshake(response, text)) {
          return;
        }
      }
      _sentCount += batch.length;
    } catch (e) {
      _forwardRequest = null;
      if (!_closed) {
        _fail(GrpcError.unavailable('The stream request failed: $e'));
      }
      return;
    } finally {
      _sending = false;
    }
    if (_closeWhenFlushed && _outgoing.isEmpty) {
      unawaited(_shutdown());
      return;
    }
    unawaited(_flush());
  }

  static String _encodeHeaders(Map<String, String> headers) {
    final StringBuffer buffer = StringBuffer();
    headers.forEach((String name, String value) {
      buffer.write('$name:$value\r\n');
    });
    return buffer.toString();
  }

  static GrpcError _httpError(int status, String body) {
    try {
      final Map<String, Object?>? error = findErrorJson(jsonDecode(body));
      if (error != null) {
        return grpcErrorFromJson(error);
      }
    } on FormatException {
      // Not JSON, fall through.
    }
    return GrpcError.unavailable(
        'The stream request failed with HTTP status $status');
  }

  /// Reads the session out of the handshake response. Returns false if the
  /// session failed.
  bool _onHandshake(WebHttpResponse response, String text) {
    final List<Object?> chunks;
    try {
      chunks = WebChannelChunkParser().add(text);
    } on FormatException catch (e) {
      _fail(GrpcError.unavailable('Malformed handshake response: $e'));
      return false;
    }
    for (final Object? chunk in chunks) {
      if (chunk is! List) {
        continue;
      }
      for (final Object? array in chunk) {
        if (array is List &&
            array.length >= 2 &&
            array[1] is List &&
            (array[1] as List<Object?>).length >= 2 &&
            (array[1] as List<Object?>)[0] == 'c') {
          final List<Object?> open = array[1] as List<Object?>;
          _sessionId = open[1] as String?;
          if (open.length > 5 && open[5] is int && (open[5] as int) > 0) {
            _backChannelTimeout =
                Duration(milliseconds: ((open[5] as int) * 1.5).round());
          }
        } else {
          _onArray(array);
          if (_closed) {
            return false;
          }
        }
      }
    }
    if (_sessionId == null) {
      _fail(const GrpcError.unavailable(
          'The handshake response has no session id'));
      return false;
    }
    final String? httpSessionId = response.headers['x-http-session-id'];
    if (httpSessionId != null && httpSessionId.isNotEmpty) {
      _httpSessionId = httpSessionId;
    }
    if (!_handshakeHeaders.isCompleted) {
      _handshakeHeaders.complete(response.headers);
    }
    unawaited(_runBackChannel());
    return true;
  }

  Future<void> _runBackChannel() async {
    int emptyRequests = 0;
    while (!_closed) {
      bool receivedData = false;
      final WebHttpRequest request = _http.send(
        'GET',
        _url(<String, String>{
          'RID': 'rpc',
          'SID': _sessionId!,
          'AID': '$_lastArrayId',
          // 0: the response may be streamed in chunks.
          'CI': '0',
          'TYPE': 'xmlhttp',
        }),
      );
      _backRequest = request;
      _armBackChannelTimer(request);
      try {
        final WebHttpResponse response = await request.response;
        if (_closed) {
          return;
        }
        if (response.statusCode != 200) {
          // 400 is "Unknown SID": the server no longer has the session.
          final String text = await response.readAll();
          _fail(_httpError(response.statusCode, text));
          return;
        }
        final WebChannelChunkParser parser = WebChannelChunkParser();
        await for (final String text in response.body) {
          if (_closed) {
            return;
          }
          _armBackChannelTimer(request);
          for (final Object? chunk in parser.add(text)) {
            if (chunk is! List) {
              continue;
            }
            for (final Object? array in chunk) {
              receivedData = true;
              _onArray(array);
              if (_closed) {
                return;
              }
            }
          }
        }
      } on FormatException catch (e) {
        if (!_closed) {
          _fail(GrpcError.unavailable('Malformed stream response: $e'));
        }
        return;
      } catch (_) {
        // A network error or the timeout below: counted as an empty request.
      }
      if (_closed) {
        return;
      }
      emptyRequests = receivedData ? 0 : emptyRequests + 1;
      if (emptyRequests >= _maxEmptyBackChannelRequests) {
        _fail(const GrpcError.unavailable('The stream connection was lost'));
        return;
      }
    }
  }

  /// Aborts [request] if the server stays silent for too long (it sends a
  /// `noop` now and then, so silence means the connection is dead).
  void _armBackChannelTimer(WebHttpRequest request) {
    _backChannelTimer?.cancel();
    _backChannelTimer = Timer(_backChannelTimeout, request.abort);
  }

  /// Handles one `[arrayId, payload]` of the server.
  void _onArray(Object? array) {
    if (array is! List || array.length < 2 || array[0] is! int) {
      return;
    }
    _lastArrayId = array[0] as int;
    final Object? payload = array[1];

    Object? message;
    if (payload is List) {
      if (payload.isEmpty) {
        return;
      }
      final Object? first = payload[0];
      if (first == 'noop' || first == 'c') {
        return;
      }
      if (first == 'stop' || first == 'close') {
        _fail(const GrpcError.unavailable('The server closed the stream'));
        return;
      }
      message = first;
    } else if (payload is Map) {
      // A "server message" envelope, for example
      // {"__sm__": {"status": [[{"error": {...}}]]}}.
      final Object? envelope = payload['__sm__'];
      if (envelope is Map && envelope.isNotEmpty) {
        final Object? data = envelope.values.first;
        message = data is List && data.isNotEmpty ? data.first : data;
      } else {
        message = payload;
      }
    }

    final Map<String, Object?>? error = findErrorJson(message);
    if (error != null) {
      _fail(grpcErrorFromJson(error));
      return;
    }
    if (message is Map) {
      _messages.add(message.cast<String, Object?>());
    }
  }

  void _fail(GrpcError error) {
    if (_closed) {
      return;
    }
    _messages.addError(error);
    unawaited(_shutdown());
  }

  Future<void> _shutdown() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _backChannelTimer?.cancel();
    _outgoing.clear();
    if (!_handshakeHeaders.isCompleted) {
      _handshakeHeaders.complete(const <String, String>{});
    }

    final String? sessionId = _sessionId;
    if (sessionId != null) {
      // Best effort: the server also drops sessions that go silent.
      try {
        final WebHttpRequest terminate = _http.send(
          'GET',
          _url(<String, String>{
            'SID': sessionId,
            'RID': '${_requestId++}',
            'TYPE': 'terminate',
          }),
        );
        unawaited(terminate.response
            .then((WebHttpResponse response) => response.body.drain<void>())
            .catchError((Object _) {}));
      } catch (_) {
        // The client may already be closed.
      }
    }
    _backRequest?.abort();
    _forwardRequest?.abort();
    await _messages.close();
  }
}

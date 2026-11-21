import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes.dart';

/// What a chunk hook can do with a chunk upload: return a response that replaces the normal one (the chunk is
/// then not stored, unless [FakeUploadServer.store] is called), throw (a network error), or return null to
/// let the server handle it.
typedef ChunkHook =
    FutureOr<http.Response?> Function(int index, Recorded request);

/// An in-memory resumable upload server (one bucket `b`), strict about offsets like production.
final class FakeUploadServer {
  FakeUploadServer({this.chunkHook, this.queryHook});

  /// Called for each chunk request (index from 0) before it is handled.
  ChunkHook? chunkHook;

  /// Called for each query; a non-null response replaces the normal one.
  FutureOr<http.Response?> Function(Recorded request)? queryHook;

  final List<Recorded> requests = <Recorded>[];
  final BytesBuilder _received = BytesBuilder();
  Map<String, Object?> startMetadata = const <String, Object?>{};
  bool finalized = false;
  int _chunks = 0;

  /// The bytes the server has.
  Uint8List get received => _received.toBytes();

  /// The chunk requests so far.
  List<Recorded> get chunks => <Recorded>[
    for (final Recorded r in requests)
      if (_command(r) case final String c
          when c.contains('upload') || c == 'finalize')
        r,
  ];

  /// Stores [bytes] as if part of a chunk had arrived.
  void store(List<int> bytes) => _received.add(bytes);

  static const String sessionUrl =
      'https://firebasestorage.googleapis.com/v0/b/b/o?name=f&upload_id=u1&upload_protocol=resumable';

  Future<http.Response> handle(Recorded request) async {
    requests.add(request);
    final String? command = _command(request);
    if (request.url.queryParameters.containsKey('upload_id')) {
      return switch (command) {
        'query' => await _query(request),
        'cancel' => http.Response('OK', 200),
        _ => await _chunk(request, command ?? ''),
      };
    }
    if (request.method == 'GET') {
      return _resource();
    }
    final String? protocol = request.headers['x-goog-upload-protocol'];
    if (protocol == 'multipart') {
      _received.add(_multipartData(request));
      finalized = true;
      return _resource();
    }
    if (protocol == 'resumable' && command == 'start') {
      startMetadata = jsonDecode(request.body) as Map<String, Object?>;
      return http.Response(
        'OK',
        200,
        headers: <String, String>{
          'x-goog-upload-status': 'active',
          'x-goog-upload-url': sessionUrl,
        },
      );
    }
    return http.Response('Bad Request', 400);
  }

  Future<http.Response> _query(Recorded request) async {
    final http.Response? replaced = await queryHook?.call(request);
    if (replaced != null) {
      return replaced;
    }
    return http.Response(
      'OK',
      200,
      headers: <String, String>{
        'x-goog-upload-status': finalized ? 'final' : 'active',
        'x-goog-upload-size-received': '${_received.length}',
      },
    );
  }

  Future<http.Response> _chunk(Recorded request, String command) async {
    final int index = _chunks++;
    final http.Response? replaced = await chunkHook?.call(index, request);
    if (replaced != null) {
      return replaced;
    }
    if (finalized) {
      return http.Response('Bad Request', 400);
    }
    final int offset = int.parse(request.headers['x-goog-upload-offset']!);
    if (offset != _received.length) {
      return http.Response('offset $offset, have ${_received.length}', 400);
    }
    _received.add(request.bodyBytes);
    if (command.contains('finalize')) {
      finalized = true;
      return _resource(
        headers: <String, String>{'x-goog-upload-status': 'final'},
      );
    }
    return http.Response(
      'OK',
      200,
      headers: <String, String>{'x-goog-upload-status': 'active'},
    );
  }

  http.Response _resource({Map<String, String>? headers}) {
    return http.Response(
      jsonEncode(<String, Object?>{
        'bucket': 'b',
        'name': 'f',
        'generation': '1',
        'metageneration': '1',
        'size': '${_received.length}',
        'contentType':
            startMetadata['contentType'] ?? 'application/octet-stream',
      }),
      200,
      headers: <String, String>{
        'content-type': 'application/json',
        ...?headers,
      },
    );
  }

  static List<int> _multipartData(Recorded request) {
    final String type = request.headers['content-type']!;
    final String boundary = type.substring(type.indexOf('boundary=') + 9);
    final String body = latin1.decode(request.bodyBytes);
    final int start =
        body.indexOf('\r\n\r\n', body.indexOf('--$boundary', 10)) + 4;
    final int end = body.lastIndexOf('\r\n--$boundary--');
    return request.bodyBytes.sublist(start, end);
  }

  static String? _command(Recorded request) =>
      request.headers['x-goog-upload-command'];
}

/// A [FakeTime] whose waits can be held open, to act during them.
final class GatedTime extends FakeTime {
  Completer<void>? gate;
  final Completer<void> waiting = Completer<void>();

  @override
  Future<void> delay(Duration duration) async {
    await super.delay(duration);
    final Completer<void>? g = gate;
    if (g != null) {
      if (!waiting.isCompleted) {
        waiting.complete();
      }
      await g.future;
    }
  }
}

/// [length] bytes of a repeating pattern.
Uint8List patternBytes(int length) => Uint8List.fromList(
  List<int>.generate(length, (int i) => (i * 7 + i ~/ 251) & 0xff),
);

/// A [FirebaseStorage] whose client reads each request body slowly: every piece of it advances [time] by
/// [perPiece], then waits for [onConsumed] (with the bytes read so far), before [server] handles the request.
FirebaseStorage slowStorage(
  FirebaseApp app,
  FakeUploadServer server,
  FakeTime time, {
  Duration perPiece = const Duration(milliseconds: 200),
  Future<void> Function(Recorded request, int consumed)? onConsumed,
}) {
  return FirebaseStorage(
    app,
    httpClient: MockClient.streaming((
      http.BaseRequest request,
      http.ByteStream body,
    ) async {
      final BytesBuilder builder = BytesBuilder();
      final Recorded partial = Recorded(
        request.method,
        request.url,
        request.headers,
        const <int>[],
      );
      await for (final List<int> piece in body) {
        builder.add(piece);
        time.now = time.now.add(perPiece);
        await onConsumed?.call(partial, builder.length);
        await Future<void>.delayed(Duration.zero);
      }
      final http.Response response = await server.handle(
        Recorded(
          request.method,
          request.url,
          request.headers,
          builder.takeBytes(),
        ),
      );
      return http.StreamedResponse(
        Stream<List<int>>.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
      );
    }),
    clock: time.clock,
    random: () => 0.5,
    delay: time.delay,
  );
}

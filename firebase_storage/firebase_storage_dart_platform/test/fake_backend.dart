// An in-memory Cloud Storage for Firebase REST API behind a MockClient: the
// object, list, media, multipart and resumable upload endpoints the client
// uses, with enough of each for the tests of the mapping.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeObject {
  FakeObject(this.bytes, this.metadata);

  Uint8List bytes;
  Map<String, Object?> metadata;
}

class _Session {
  _Session(this.bucket, this.name, this.metadata, this.size);

  final String bucket;
  final String name;
  final Map<String, Object?> metadata;
  final int size;
  final BytesBuilder received = BytesBuilder();
}

class FakeBackend {
  FakeBackend() {
    client = MockClient(_handle);
  }

  late final http.Client client;

  /// The objects, by `bucket/name`.
  final Map<String, FakeObject> objects = <String, FakeObject>{};

  /// Every request, in order.
  final List<http.Request> requests = <http.Request>[];

  /// A status to answer every request with, instead of handling it.
  int? failWith;

  /// The metadata JSON of the last upload (multipart or resumable start).
  Map<String, Object?>? uploadMetadata;

  /// A status to answer the media (download) requests with.
  int? failMediaWith;

  /// Completes the response of each resumable upload chunk; null answers at
  /// once. A test sets it to hold an upload in the middle.
  Completer<void>? chunkGate;

  /// Completes the response of each media (download) request; null answers at
  /// once. A test sets it to hold a download before its body.
  Completer<void>? mediaGate;

  /// The `x-goog-generation` of the media responses instead of the object's,
  /// as if the object had been overwritten since its metadata was read.
  String? mediaGeneration;

  final Map<String, _Session> _sessions = <String, _Session>{};
  int _generation = 1;

  void reset() {
    objects.clear();
    requests.clear();
    _sessions.clear();
    failWith = null;
    failMediaWith = null;
    uploadMetadata = null;
    chunkGate = null;
    mediaGate = null;
    mediaGeneration = null;
  }

  /// Adds an object with [bytes] at [name] of [bucket].
  void put(
    String bucket,
    String name,
    List<int> bytes, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    objects['$bucket/$name'] = FakeObject(
      Uint8List.fromList(bytes),
      _resource(bucket, name, bytes.length, metadata),
    );
  }

  Map<String, Object?> _resource(
    String bucket,
    String name,
    int size,
    Map<String, Object?> fields,
  ) => <String, Object?>{
    'bucket': bucket,
    'name': name,
    'generation': '${_generation++}',
    'metageneration': '1',
    'size': '$size',
    'md5Hash': 'aGFzaA==',
    'timeCreated': '2026-11-20T10:00:00.000Z',
    'updated': '2026-11-21T11:30:00.500Z',
    'downloadTokens': 'token-1',
    ...fields,
  };

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final int? status = failWith;
    if (status != null) {
      return _json(<String, Object?>{
        'error': <String, Object?>{'code': status, 'message': 'Failure'},
      }, status: status);
    }
    final String? session = request.url.queryParameters['upload_id'];
    if (session != null) {
      return _resumable(request, session);
    }
    final List<String> segments = request.url.pathSegments;
    // /v0/b/<bucket>/o[/<name>]
    if (segments.length < 4 || segments[0] != 'v0' || segments[3] != 'o') {
      return http.Response('Not found', 404);
    }
    final String bucket = segments[2];
    if (segments.length == 4) {
      return switch (request.method) {
        'GET' => _list(bucket, request.url.queryParameters),
        'POST' => _upload(bucket, request),
        _ => http.Response('Method', 405),
      };
    }
    final String name = segments[4];
    final FakeObject? object = objects['$bucket/$name'];
    if (object == null) {
      return _json(<String, Object?>{
        'error': <String, Object?>{'code': 404, 'message': 'Not Found.'},
      }, status: 404);
    }
    switch (request.method) {
      case 'GET' when request.url.queryParameters['alt'] == 'media':
        final Completer<void>? gate = mediaGate;
        if (gate != null) {
          await gate.future;
        }
        final int? mediaStatus = failMediaWith;
        if (mediaStatus != null) {
          return http.Response('Failure', mediaStatus);
        }
        return _media(
          object,
          request.headers['range'] ?? request.headers['Range'],
          mediaGeneration ?? '${object.metadata['generation']}',
        );
      case 'GET':
        return _json(object.metadata);
      case 'PATCH':
        final Map<String, Object?> patch =
            jsonDecode(request.body) as Map<String, Object?>;
        object.metadata = <String, Object?>{...object.metadata, ...patch};
        return _json(object.metadata);
      case 'DELETE':
        objects.remove('$bucket/$name');
        return http.Response('', 204);
    }
    return http.Response('Method', 405);
  }

  /// The content of [object], in the [range] when there is one, with the
  /// [generation] header Cloud Storage sends.
  http.Response _media(FakeObject object, String? range, String generation) {
    final Map<String, String> headers = <String, String>{
      'x-goog-generation': generation,
    };
    final Match? match = range == null
        ? null
        : RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
    if (match == null) {
      return http.Response.bytes(object.bytes, 200, headers: headers);
    }
    final int start = int.parse(match[1]!);
    final int end = match[2]!.isEmpty
        ? object.bytes.length
        : (int.parse(match[2]!) + 1).clamp(0, object.bytes.length);
    return http.Response.bytes(
      object.bytes.sublist(start, end),
      206,
      headers: <String, String>{
        ...headers,
        'content-range': 'bytes $start-${end - 1}/${object.bytes.length}',
      },
    );
  }

  http.Response _list(String bucket, Map<String, String> query) {
    final String prefix = query['prefix'] ?? '';
    final Set<String> prefixes = <String>{};
    final List<Map<String, Object?>> items = <Map<String, Object?>>[];
    for (final String key in objects.keys.toList()..sort()) {
      if (!key.startsWith('$bucket/$prefix')) {
        continue;
      }
      final String rest = key.substring('$bucket/$prefix'.length);
      final int slash = rest.indexOf('/');
      if (slash >= 0) {
        prefixes.add('$prefix${rest.substring(0, slash)}/');
      } else {
        items.add(<String, Object?>{'bucket': bucket, 'name': '$prefix$rest'});
      }
    }
    final int max = int.tryParse(query['maxResults'] ?? '') ?? 1000;
    final int start = int.tryParse(query['pageToken'] ?? '') ?? 0;
    final List<Map<String, Object?>> page = items
        .skip(start)
        .take(max)
        .toList();
    final bool more = start + page.length < items.length;
    return _json(<String, Object?>{
      'prefixes': prefixes.toList(),
      'items': page,
      if (more) 'nextPageToken': '${start + page.length}',
    });
  }

  Future<http.Response> _upload(String bucket, http.Request request) async {
    final String name = request.url.queryParameters['name']!;
    final String? protocol = _header(request, 'x-goog-upload-protocol');
    if (protocol == 'resumable') {
      final Map<String, Object?> metadata = uploadMetadata =
          jsonDecode(request.body) as Map<String, Object?>;
      final String id = '${_sessions.length}';
      _sessions[id] = _Session(
        bucket,
        name,
        metadata,
        int.parse(_header(request, 'x-goog-upload-header-content-length')!),
      );
      return http.Response(
        '',
        200,
        headers: <String, String>{
          'x-goog-upload-status': 'active',
          'x-goog-upload-url': request.url
              .replace(
                queryParameters: <String, String>{
                  'name': name,
                  'upload_id': id,
                },
              )
              .toString(),
        },
      );
    }
    // multipart/related: a JSON part, then the data part.
    final String type = request.headers['content-type'] ?? '';
    final String boundary = RegExp(r'boundary=([^;]+)').firstMatch(type)![1]!;
    final List<int> body = request.bodyBytes;
    final String text = latin1.decode(body);
    final List<String> parts = text.split('--$boundary');
    final String jsonPart = parts[1].split('\r\n\r\n').skip(1).join('\r\n\r\n');
    final Map<String, Object?> metadata = uploadMetadata =
        jsonDecode(jsonPart.trim()) as Map<String, Object?>;
    final String dataPart = parts[2];
    final int headerEnd = dataPart.indexOf('\r\n\r\n') + 4;
    final List<int> data = latin1.encode(
      dataPart.substring(headerEnd, dataPart.length - 2),
    );
    return _store(bucket, name, data, metadata);
  }

  Future<http.Response> _resumable(http.Request request, String id) async {
    final _Session? session = _sessions[id];
    if (session == null) {
      return http.Response('No session', 404);
    }
    final String command = _header(request, 'x-goog-upload-command') ?? '';
    if (command.contains('query')) {
      return http.Response(
        '',
        200,
        headers: <String, String>{
          'x-goog-upload-status': 'active',
          'x-goog-upload-size-received': '${session.received.length}',
        },
      );
    }
    if (command.contains('cancel')) {
      _sessions.remove(id);
      return http.Response('', 200);
    }
    final Completer<void>? gate = chunkGate;
    if (gate != null) {
      await gate.future;
    }
    session.received.add(request.bodyBytes);
    if (command.contains('finalize')) {
      _sessions.remove(id);
      return _store(
        session.bucket,
        session.name,
        session.received.toBytes(),
        session.metadata,
        headers: <String, String>{'x-goog-upload-status': 'final'},
      );
    }
    return http.Response(
      '',
      200,
      headers: <String, String>{'x-goog-upload-status': 'active'},
    );
  }

  http.Response _store(
    String bucket,
    String name,
    List<int> data,
    Map<String, Object?> metadata, {
    Map<String, String> headers = const <String, String>{},
  }) {
    final Map<String, Object?> fields = <String, Object?>{
      for (final MapEntry<String, Object?> entry in metadata.entries)
        if (entry.key != 'name' && entry.key != 'fullPath')
          entry.key: entry.value,
    };
    put(bucket, name, data, metadata: fields);
    return _json(objects['$bucket/$name']!.metadata, headers: headers);
  }

  static String? _header(http.Request request, String name) {
    for (final MapEntry<String, String> entry in request.headers.entries) {
      if (entry.key.toLowerCase() == name) {
        return entry.value;
      }
    }
    return null;
  }

  static http.Response _json(
    Object? body, {
    int status = 200,
    Map<String, String> headers = const <String, String>{},
  }) => http.Response(
    jsonEncode(body),
    status,
    headers: <String, String>{'content-type': 'application/json', ...headers},
  );
}

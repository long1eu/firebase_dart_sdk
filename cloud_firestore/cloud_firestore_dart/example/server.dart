// Firestore in a backend process: a small JSON API over HTTP.
//
// What differs from an app:
// - One Firestore instance for the whole process, created at startup and
//   shared by every request. Creating one per request would open a gRPC
//   channel each time.
// - No `openDatabase`, so nothing is written to disk; the memory cache with
//   eager garbage collection drops documents that no listener needs.
// - Reads use `Source.server`, so that a request never answers from a stale
//   cache, and a write is awaited before the response is sent, so that the
//   client only sees writes the backend accepted.
// - `terminate()` on shutdown.
//
// Against a real project, give the app server credentials before the
// instance is created (package:firebase_auth_providers_dart, see the
// Authentication section of the package README):
//
//     app.authProvider = OAuthTokenProvider.serviceAccount(serviceAccountJson);
//
// This program starts the server on a free port of the loopback interface,
// sends it a few requests, prints the responses and shuts down:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/server.dart

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'common.dart';

Future<void> main() async {
  final Firestore firestore = Firestore.instanceFor(
    app: exampleApp(),
    settings: emulatorSettings(
      cacheSettings: const MemoryCacheSettings(
        gcSettings: MemoryEagerGcSettings(),
      ),
    ),
  );
  final TaskApi api = TaskApi(firestore, scratch('tasks'));

  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen(api.handle);
  final Uri base = Uri.http('127.0.0.1:${server.port}');

  final HttpClient client = HttpClient();
  final Map<String, Object?> created = await _send(
    client,
    'POST',
    base.resolve('/tasks'),
    <String, Object?>{'title': 'Write the docs'},
  );
  await _send(client, 'POST', base.resolve('/tasks'), <String, Object?>{
    'title': 'Ship it',
  });
  await _send(client, 'GET', base.resolve('/tasks/${created['id']}'));
  await _send(client, 'POST', base.resolve('/tasks/${created['id']}/done'));
  await _send(client, 'GET', base.resolve('/tasks?done=false'));
  await _send(client, 'GET', base.resolve('/stats'));
  await _send(client, 'GET', base.resolve('/tasks/missing'));
  client.close();

  await server.close();
  await firestore.terminate();
}

/// The request handlers. Every handler runs against the one shared
/// [Firestore] instance.
class TaskApi {
  TaskApi(Firestore firestore, String path)
    : _tasks = firestore.collection(path),
      _stats = firestore.doc('$path-stats/counts'),
      _firestore = firestore;

  final Firestore _firestore;
  final CollectionReference<Map<String, Object?>> _tasks;
  final DocumentReference<Map<String, Object?>> _stats;

  Future<void> handle(HttpRequest request) async {
    final List<String> path = request.uri.pathSegments;
    int status = HttpStatus.ok;
    Object? body;
    try {
      switch ((request.method, path)) {
        case ('POST', <String>['tasks']):
          status = HttpStatus.created;
          body = await _create(await _readJson(request));
        case ('GET', <String>['tasks']):
          body = await _list(request.uri.queryParameters['done'] == 'true');
        case ('GET', <String>['tasks', final String id]):
          body = await _read(id);
          if (body == null) {
            status = HttpStatus.notFound;
            body = <String, Object?>{'error': 'no task $id'};
          }
        case ('POST', <String>['tasks', final String id, 'done']):
          body = await _complete(id);
        case ('GET', <String>['stats']):
          body = (await _stats.get(Source.server)).data;
        default:
          status = HttpStatus.notFound;
          body = <String, Object?>{'error': 'no route'};
      }
    } on FirestoreError catch (e) {
      status = HttpStatus.internalServerError;
      body = <String, Object?>{'error': e.message};
    }
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  /// Adds a task and counts it, atomically, with a batch.
  Future<Map<String, Object?>> _create(Map<String, Object?> input) async {
    final DocumentReference<Map<String, Object?>> task = _tasks.doc();
    await (_firestore.batch()
          ..set(task, <String, Object?>{
            'title': input['title'],
            'done': false,
            'createdAt': FieldValue.serverTimestamp(),
          })
          ..set(_stats, <String, Object?>{
            'open': FieldValue.increment(1),
          }, SetOptions.mergeAllFields))
        .commit();
    return <String, Object?>{'id': task.id};
  }

  Future<Map<String, Object?>?> _read(String id) async {
    final DocumentSnapshot<Map<String, Object?>> snapshot = await _tasks
        .doc(id)
        .get(Source.server);
    return snapshot.exists ? _toJson(snapshot) : null;
  }

  Future<List<Map<String, Object?>>> _list(bool done) async {
    final QuerySnapshot<Map<String, Object?>> snapshot = await _tasks
        .where('done', isEqualTo: done)
        .get(Source.server);
    return <Map<String, Object?>>[
      for (final QueryDocumentSnapshot<Map<String, Object?>> doc
          in snapshot.docs)
        _toJson(doc),
    ];
  }

  /// Marks a task done with a transaction: a concurrent request for the same
  /// task makes one of the two retry and see `done` already set.
  Future<Map<String, Object?>> _complete(String id) {
    final DocumentReference<Map<String, Object?>> task = _tasks.doc(id);
    return _firestore.runTransaction<Map<String, Object?>>((
      Transaction transaction,
    ) async {
      final DocumentSnapshot<Map<String, Object?>> snapshot = await transaction
          .get(task);
      if (!snapshot.exists || snapshot.data!['done'] == true) {
        return <String, Object?>{'changed': false};
      }
      transaction
        ..update(task, <String, Object?>{'done': true})
        ..update(_stats, <String, Object?>{
          'open': FieldValue.increment(-1),
          'done': FieldValue.increment(1),
        });
      return <String, Object?>{'changed': true};
    });
  }

  static Map<String, Object?> _toJson(
    DocumentSnapshot<Map<String, Object?>> doc,
  ) {
    final Map<String, Object?> data = doc.data!;
    final Timestamp createdAt = data['createdAt']! as Timestamp;
    return <String, Object?>{
      'id': doc.id,
      'title': data['title'],
      'done': data['done'],
      'createdAt': createdAt.toDate().toUtc().toIso8601String(),
    };
  }

  static Future<Map<String, Object?>> _readJson(HttpRequest request) async {
    final String text = await utf8.decodeStream(request);
    return jsonDecode(text) as Map<String, Object?>;
  }
}

/// Sends a request, prints the method, the path, the status and the body
/// (with the generated ids and the timestamps left out, so that the output is
/// the same on every run) and returns the decoded body.
Future<Map<String, Object?>> _send(
  HttpClient client,
  String method,
  Uri uri, [
  Map<String, Object?>? body,
]) async {
  final HttpClientRequest request = await client.openUrl(method, uri);
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final HttpClientResponse response = await request.close();
  final Object? decoded = jsonDecode(await utf8.decodeStream(response));
  print(
    '$method ${uri.path.replaceAll(RegExp('/tasks/[A-Za-z0-9]{20}'), '/tasks/<id>')}'
    '${uri.hasQuery ? '?${uri.query}' : ''} -> ${response.statusCode} '
    '${jsonEncode(_withoutVolatile(decoded))}',
  );
  return decoded is Map<String, Object?> ? decoded : <String, Object?>{};
}

Object? _withoutVolatile(Object? json) => switch (json) {
  final Map<String, Object?> map => <String, Object?>{
    for (final MapEntry<String, Object?> entry in map.entries)
      if (entry.key != 'id' && entry.key != 'createdAt')
        entry.key: _withoutVolatile(entry.value),
  },
  final List<Object?> list => list.map(_withoutVolatile).toList(),
  _ => json,
};

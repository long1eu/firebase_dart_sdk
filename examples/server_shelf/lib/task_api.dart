import 'dart:convert';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'change_feed.dart';

/// The routes of the task API on one shared [Firestore] instance:
///
///     GET    /tasks?done=true|false    list (all without `done`)
///     POST   /tasks {"title": "..."}   create; 201 {"id": "..."}
///     GET    /tasks/<id>               one task; 404 if missing
///     PATCH  /tasks/<id> {"done": b}   mark done or open; 404 if missing
///     DELETE /tasks/<id>               delete; 204
///     GET    /events                   server-sent events of every change
///     GET    /healthz                  "ok"
///
/// Reads use `Source.server`: an HTTP response is never served from a stale
/// cache. A write is awaited, so the response only reports writes the backend
/// accepted.
class TaskApi {
  TaskApi(this._firestore, String collection)
    : _tasks = _firestore.collection(collection) {
    _feed = ChangeFeed(_tasks);
  }

  final Firestore _firestore;
  final CollectionReference<Map<String, Object?>> _tasks;
  late final ChangeFeed _feed;

  /// Completes when the real-time listener has its first snapshot.
  Future<void> get ready => _feed.ready;

  /// The number of clients connected to `/events`.
  int get subscribers => _feed.subscribers;

  Handler get handler {
    final Router router = Router()
      ..get('/healthz', (Request request) => Response.ok('ok'))
      ..get('/tasks', _list)
      ..post('/tasks', _create)
      ..get('/tasks/<id>', _read)
      ..patch('/tasks/<id>', _update)
      ..delete('/tasks/<id>', _delete)
      ..get('/events', _events);
    return const Pipeline()
        .addMiddleware(_firestoreErrors)
        .addHandler(router.call);
  }

  Future<Response> _list(Request request) async {
    Query<Map<String, Object?>> query = _tasks.orderBy('createdAt');
    final String? done = request.url.queryParameters['done'];
    if (done != null) {
      // Not ordered: a filter on `done` with an order on `createdAt` needs a
      // composite index on a real project.
      query = _tasks.where('done', isEqualTo: done == 'true');
    }
    final QuerySnapshot<Map<String, Object?>> snapshot = await query.get(
      Source.server,
    );
    return _json(200, <Map<String, Object?>>[
      for (final QueryDocumentSnapshot<Map<String, Object?>> doc
          in snapshot.docs)
        <String, Object?>{'id': doc.id, ...toJson(doc.data)},
    ]);
  }

  Future<Response> _create(Request request) async {
    final Object? body = await _readJson(request);
    final Object? title = body is Map<String, Object?> ? body['title'] : null;
    if (title is! String || title.isEmpty) {
      return _json(400, <String, Object?>{'error': 'title is required'});
    }
    final DocumentReference<Map<String, Object?>> task = await _tasks.add(
      <String, Object?>{
        'title': title,
        'done': false,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
    return _json(201, <String, Object?>{'id': task.id});
  }

  Future<Response> _read(Request request, String id) async {
    final DocumentSnapshot<Map<String, Object?>> snapshot = await _tasks
        .doc(id)
        .get(Source.server);
    if (!snapshot.exists) {
      return _json(404, <String, Object?>{'error': 'no task $id'});
    }
    return _json(200, <String, Object?>{'id': id, ...toJson(snapshot.data!)});
  }

  Future<Response> _update(Request request, String id) async {
    final Object? body = await _readJson(request);
    final Object? done = body is Map<String, Object?> ? body['done'] : null;
    if (done is! bool) {
      return _json(400, <String, Object?>{
        'error': 'done (a bool) is required',
      });
    }
    // `update` fails with not-found for a missing document; see
    // [_firestoreErrors].
    await _tasks.doc(id).update(<String, Object?>{'done': done});
    return _json(200, <String, Object?>{'id': id, 'done': done});
  }

  Future<Response> _delete(Request request, String id) async {
    await _tasks.doc(id).delete();
    return Response(204);
  }

  Response _events(Request request) {
    return Response.ok(
      _feed.subscribe().map(utf8.encode),
      headers: <String, String>{
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
      },
      // Send each event as soon as it is written instead of buffering.
      context: <String, Object>{'shelf.io.buffer_output': false},
    );
  }

  /// Stops the listener and terminates the Firestore instance.
  Future<void> close() async {
    await _feed.close();
    await _firestore.terminate();
  }

  /// Maps the errors of Firestore to HTTP statuses.
  static Handler _firestoreErrors(Handler inner) {
    return (Request request) async {
      try {
        return await inner(request);
      } on FirestoreError catch (e) {
        final int status = switch (e.code) {
          FirestoreErrorCode.notFound => 404,
          FirestoreErrorCode.invalidArgument => 400,
          FirestoreErrorCode.permissionDenied => 403,
          FirestoreErrorCode.unauthenticated => 401,
          FirestoreErrorCode.unavailable ||
          FirestoreErrorCode.deadlineExceeded => 503,
          _ => 500,
        };
        return _json(status, <String, Object?>{'error': e.message});
      }
    };
  }

  static Future<Object?> _readJson(Request request) async {
    try {
      return jsonDecode(await request.readAsString());
    } on FormatException {
      return null;
    }
  }

  static Response _json(int status, Object? body) => Response(
    status,
    body: jsonEncode(body),
    headers: <String, String>{'content-type': 'application/json'},
  );
}

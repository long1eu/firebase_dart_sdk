// A notes API on package:shelf over one shared FirebaseDatabase. See
// README.md for how to run it.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

const int defaultLimit = 20;
const int maxLimit = 200;

/// The `limit` query parameter: [defaultLimit] when absent, else 1..[maxLimit];
/// null when it is not a number in that range.
int? parseLimit(String? raw) {
  if (raw == null) {
    return defaultLimit;
  }
  final int? limit = int.tryParse(raw);
  return limit == null || limit < 1 || limit > maxLimit ? null : limit;
}

/// The JSON object in [body], or null when it is not one.
Map<String, Object?>? parseObject(String body) {
  try {
    final Object? decoded = jsonDecode(body);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// One server-sent event.
String sseEvent(String event, Object? data) =>
    'event: $event\ndata: ${jsonEncode(data)}\n\n';

/// The HTTP status of a database error.
int statusFor(FirebaseDatabaseException e) => switch (e.code) {
  'permission-denied' => 403,
  'unavailable' || 'network-error' || 'disconnected' => 503,
  'database-closed' => 503,
  'too-big' => 413,
  'index-not-defined' => 400,
  _ => 502,
};

/// The routes. One [FirebaseDatabase] serves every request; each event stream
/// holds one listener until its client disconnects or [close] is called.
class NotesApi {
  NotesApi(this.db, {this.collection = 'notes'}) {
    _router
      ..get('/healthz', _health)
      ..get('/notes', _list)
      ..post('/notes', _create)
      ..get('/notes/<id>', _get)
      ..patch('/notes/<id>', _patch)
      ..delete('/notes/<id>', _delete)
      ..get('/events/<path|.*>', _events);
  }

  final FirebaseDatabase db;
  final String collection;
  final Router _router = Router();
  final Set<StreamController<List<int>>> _streams =
      <StreamController<List<int>>>{};
  bool _closed = false;

  Handler get handler => (Request request) async {
    try {
      return await _router(request);
    } on FirebaseDatabaseException catch (e) {
      return _json(statusFor(e), <String, Object?>{
        'error': e.code,
        'message': e.message,
      });
    }
  };

  /// Ends every event stream, which cancels its listener.
  Future<void> close() async {
    _closed = true;
    for (final StreamController<List<int>> stream in _streams.toList()) {
      await stream.close();
    }
  }

  DatabaseReference get _notes => db.ref(collection);

  Future<Response> _health(Request request) async {
    final bool connected = await db.onConnected.first;
    return _json(connected ? 200 : 503, <String, Object?>{
      'connected': connected,
    });
  }

  Future<Response> _list(Request request) async {
    final int? limit = parseLimit(request.url.queryParameters['limit']);
    if (limit == null) {
      return _error(400, 'limit must be a number from 1 to $maxLimit');
    }
    // Push ids sort by creation time: the last ones are the newest.
    final DataSnapshot snapshot = await _notes.limitToLast(limit).get();
    return _json(200, <Object?>[
      for (final DataSnapshot child in snapshot.children) _note(child),
    ]);
  }

  Future<Response> _get(Request request, String id) async {
    final DataSnapshot snapshot = await _notes.child(id).get();
    return snapshot.exists
        ? _json(200, _note(snapshot))
        : _error(404, 'no note $id');
  }

  Future<Response> _create(Request request) async {
    final Map<String, Object?>? body = parseObject(
      await request.readAsString(),
    );
    if (body == null) {
      return _error(400, 'the body must be a JSON object');
    }
    final DatabaseReference ref = _notes.push();
    await ref.set(<String, Object?>{
      ...body,
      'createdAt': ServerValue.timestamp,
    });
    return _json(201, <String, Object?>{'id': ref.key});
  }

  Future<Response> _patch(Request request, String id) async {
    final Map<String, Object?>? body = parseObject(
      await request.readAsString(),
    );
    if (body == null || body.isEmpty) {
      return _error(400, 'the body must be a non-empty JSON object');
    }
    final DatabaseReference ref = _notes.child(id);
    // update() would create the note; a PATCH of a missing note is a 404.
    if (!(await ref.get()).exists) {
      return _error(404, 'no note $id');
    }
    await ref.update(body);
    return _json(200, _note(await ref.get()));
  }

  Future<Response> _delete(Request request, String id) async {
    await _notes.child(id).remove();
    return Response(204);
  }

  /// Streams `onValue` of the path as server-sent events, until the client
  /// disconnects: then the response stream is cancelled, which cancels the
  /// database listener.
  Response _events(Request request, String path) {
    if (_closed) {
      return _error(503, 'shutting down');
    }
    late final StreamController<List<int>> out;
    StreamSubscription<DatabaseEvent>? listener;
    Timer? ping;
    out = StreamController<List<int>>(
      onListen: () {
        void send(String text) {
          if (!out.isClosed) {
            out.add(utf8.encode(text));
          }
        }

        listener = db
            .ref(path)
            .onValue
            .listen(
              (DatabaseEvent event) =>
                  send(sseEvent('value', event.snapshot.value)),
              onError: (Object e) {
                send(sseEvent('error', <String, Object?>{'message': '$e'}));
                out.close();
              },
            );
        ping = Timer.periodic(
          const Duration(seconds: 15),
          (_) => send(': ping\n\n'),
        );
      },
      onCancel: () async {
        ping?.cancel();
        _streams.remove(out);
        await listener?.cancel();
      },
    );
    _streams.add(out);
    return Response.ok(
      out.stream,
      headers: <String, Object>{
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
      },
      context: <String, Object>{'shelf.io.buffer_output': false},
    );
  }
}

Map<String, Object?> _note(DataSnapshot snapshot) {
  final Object? value = snapshot.value;
  return <String, Object?>{
    'id': snapshot.key,
    if (value is Map) ...value.cast<String, Object?>() else 'value': value,
  };
}

Response _json(int status, Object? body) => Response(
  status,
  body: jsonEncode(body),
  headers: <String, Object>{'content-type': 'application/json'},
);

Response _error(int status, String message) =>
    _json(status, <String, Object?>{'error': message});

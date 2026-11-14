import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

/// One real-time listener on a collection, shared by every client of the
/// server: each change is encoded once and sent to all the subscribers.
///
/// Opening a Firestore listener per HTTP client would also work, but each one
/// is a target on the backend and the memory cache keeps its documents; one
/// listener per collection keeps the cost independent of the number of
/// clients.
class ChangeFeed {
  ChangeFeed(Query<Map<String, Object?>> query) {
    _subscription = query.snapshots.listen(
      _onSnapshot,
      onError: (Object error) {
        // The listener ended (for example permission-denied): the subscribers
        // are told, and the server keeps answering the other routes.
        _events.add(_event('error', <String, Object?>{'message': '$error'}));
      },
    );
  }

  late final StreamSubscription<QuerySnapshot<Map<String, Object?>>>
  _subscription;
  final StreamController<String> _events = StreamController<String>.broadcast();
  final Map<String, Map<String, Object?>> _current =
      <String, Map<String, Object?>>{};
  final Completer<void> _ready = Completer<void>();

  /// Completes with the first snapshot of the listener.
  Future<void> get ready => _ready.future;

  /// The number of connected subscribers.
  int get subscribers => _subscribers;
  int _subscribers = 0;

  /// The server-sent events for one client: the current documents first (one
  /// `snapshot` event), then an event per change (`added`, `modified`,
  /// `removed`), and a comment every [keepAlive] so that proxies do not close
  /// an idle connection.
  Stream<String> subscribe({Duration keepAlive = const Duration(seconds: 15)}) {
    late final StreamController<String> controller;
    StreamSubscription<String>? changes;
    Timer? timer;
    controller = StreamController<String>(
      onListen: () {
        _subscribers++;
        controller.add(
          _event('snapshot', <String, Object?>{
            'documents': <Map<String, Object?>>[
              for (final MapEntry<String, Map<String, Object?>> entry
                  in _current.entries)
                <String, Object?>{'id': entry.key, ...entry.value},
            ],
          }),
        );
        changes = _events.stream.listen(controller.add);
        timer = Timer.periodic(keepAlive, (_) => controller.add(': ping\n\n'));
      },
      onCancel: () async {
        // The client disconnected.
        _subscribers--;
        timer?.cancel();
        await changes?.cancel();
      },
    );
    return controller.stream;
  }

  void _onSnapshot(QuerySnapshot<Map<String, Object?>> snapshot) {
    for (final DocumentChange<Map<String, Object?>> change
        in snapshot.docChanges) {
      final String id = change.document.id;
      // A server timestamp that the backend has not filled in yet (a write of
      // this server, before its acknowledgement) is sent as the local
      // estimate; a `modified` event with the real value follows.
      final Map<String, Object?> data = toJson(
        change.document.getData(ServerTimestampBehavior.estimate),
      );
      if (change.type == DocumentChangeType.removed) {
        _current.remove(id);
      } else {
        _current[id] = data;
      }
      // The first snapshot is what a subscriber gets as its `snapshot` event.
      if (_ready.isCompleted) {
        _events.add(
          _event(change.type.name, <String, Object?>{'id': id, ...data}),
        );
      }
    }
    if (!_ready.isCompleted) {
      _ready.complete();
    }
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _events.close();
  }

  static String _event(String name, Object? data) =>
      'event: $name\ndata: ${jsonEncode(data)}\n\n';
}

/// The fields of a document as JSON: timestamps as ISO 8601 strings in UTC.
Map<String, Object?> toJson(Map<String, Object?> data) => <String, Object?>{
  for (final MapEntry<String, Object?> entry in data.entries)
    entry.key: switch (entry.value) {
      final Timestamp timestamp => timestamp.toDate().toUtc().toIso8601String(),
      final Object? value => value,
    },
};

/// `QueryRef.subscribe()` in 0.1.0 (spec 5.10): streams of the results this instance fetches. There
/// is no server push.
library;

import 'dart:async';

import 'package:firebase_data_connect_dart/src/api/refs.dart';
import 'package:firebase_data_connect_dart/src/errors.dart';
import 'package:firebase_data_connect_dart/src/value/json_values.dart';
import 'package:meta/meta.dart';

/// The subscription streams of one `DataConnect` instance, grouped by `operationId`.
///
/// One stream returned by `subscribe` is one listener of its group. The first listener of a group
/// runs the query once; every successful query of that id on the instance then reaches every
/// listener, each decoding its own copy with its own reference. A listener that joins later gets
/// the last data, unless the signed-in user changed since it was stored. When the last listener of
/// a group cancels, the group is dropped with its data.
@internal
final class SubscriptionHub {
  /// A hub that reads the signed-in user's id with [uid] (`app.authProvider.uid`).
  SubscriptionHub({required String? Function() uid}) : _uid = uid;

  final String? Function() _uid;
  final Map<String, _Group> _groups = <String, _Group>{};
  bool _closed = false;

  /// A broadcast stream of [ref]'s results.
  ///
  /// The group is joined when the stream gets its first listener and left when its last one
  /// cancels. Variables that break the value rules end the stream with their [ArgumentError]; after
  /// [close] it ends with `client-closed`.
  Stream<QueryResult<Data, Variables>> subscribe<Data, Variables>(
    QueryRef<Data, Variables> ref,
  ) {
    late final _Listener<Data, Variables> listener;
    final StreamController<QueryResult<Data, Variables>> controller =
        StreamController<QueryResult<Data, Variables>>.broadcast(
          onListen: () => _join(listener),
          onCancel: () => _leave(listener),
        );
    listener = _Listener<Data, Variables>(ref, controller);
    return controller.stream;
  }

  void _join(_Listener<Object?, Object?> listener) {
    if (_closed) {
      listener.end(clientClosedException());
      return;
    }
    final String id;
    try {
      id = listener.ref.operationId;
    } on ArgumentError catch (error) {
      listener.end(error);
      return;
    }
    listener.id = id;
    final _Group group = _groups.putIfAbsent(id, _Group.new);
    final bool first = group.listeners.isEmpty;
    group.listeners.add(listener);
    if (first) {
      unawaited(_fetchFirst(listener));
      return;
    }
    final Map<String, Object?>? last = group.lastData;
    if (last != null && group.lastUid == _uid()) {
      listener.deliver(copyJsonObject(last));
    }
  }

  /// Runs the query of the first listener of a group. Its data reaches the group through [publish];
  /// its error goes to that listener only.
  Future<void> _fetchFirst(_Listener<Object?, Object?> listener) async {
    try {
      await listener.ref.fetchForSubscription();
    } on Object catch (error) {
      listener.fail(error);
    }
  }

  void _leave(_Listener<Object?, Object?> listener) {
    final String? id = listener.id;
    final _Group? group = id == null ? null : _groups[id];
    if (group == null) {
      return;
    }
    group.listeners.remove(listener);
    if (group.listeners.isEmpty) {
      _groups.remove(id);
    }
  }

  /// Hands [data], the data of a successful query with [operationId], to every listener of that id,
  /// each as its own copy, and keeps it for listeners that join later. Does nothing without
  /// listeners.
  void publish(String operationId, Map<String, Object?> data) {
    final _Group? group = _groups[operationId];
    if (group == null || group.listeners.isEmpty) {
      return;
    }
    group
      ..lastData = copyJsonObject(data)
      ..lastUid = _uid();
    for (final _Listener<Object?, Object?> listener
        in group.listeners.toList()) {
      listener.deliver(copyJsonObject(data));
    }
  }

  /// Ends every stream with `client-closed`; later streams end with it as soon as they are listened
  /// to. Idempotent.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    final List<_Listener<Object?, Object?>> listeners =
        <_Listener<Object?, Object?>>[
          for (final _Group group in _groups.values) ...group.listeners,
        ];
    _groups.clear();
    for (final _Listener<Object?, Object?> listener in listeners) {
      listener.end(clientClosedException());
    }
  }
}

/// The listeners of one `operationId` and the last data they received.
final class _Group {
  final List<_Listener<Object?, Object?>> listeners =
      <_Listener<Object?, Object?>>[];
  Map<String, Object?>? lastData;
  String? lastUid;
}

/// One stream returned by [SubscriptionHub.subscribe], with the reference that decodes for it.
final class _Listener<Data, Variables> {
  _Listener(this.ref, this._controller);

  final QueryRef<Data, Variables> ref;
  final StreamController<QueryResult<Data, Variables>> _controller;

  /// The group joined; null before the first listen.
  String? id;

  /// Emits [data] read by [ref], or the `codec-failed` error of its `decode` on this stream only.
  void deliver(Map<String, Object?> data) {
    if (_controller.isClosed) {
      return;
    }
    try {
      _controller.add(ref.resultOf(data));
    } on DataConnectException catch (error) {
      _controller.addError(error);
    }
  }

  /// Emits [error] on this stream.
  void fail(Object error) {
    if (!_controller.isClosed) {
      _controller.addError(error);
    }
  }

  /// Emits [error] and closes the stream.
  void end(Object error) {
    if (_controller.isClosed) {
      return;
    }
    _controller.addError(error);
    unawaited(_controller.close());
  }
}

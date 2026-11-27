/// A sorted, filtered view of a location. JS: `api/Reference_impl.ts` (`QueryImpl`, query constraints);
/// Android: `Query.java`.
library;

import 'dart:async';

import 'package:firebase_database_dart/src/api/data_snapshot.dart';
import 'package:firebase_database_dart/src/api/database_event.dart';
import 'package:firebase_database_dart/src/api/database_event_type.dart';
import 'package:firebase_database_dart/src/api/database_reference.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart';
import 'package:firebase_database_dart/src/api/user_value.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/repo.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/path_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/value_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/util/validation.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:meta/meta.dart';

/// A location with an optional order, range and limit. Immutable: every modifier returns a new query.
///
/// ```dart
/// final Query top = db.ref('scores').orderByValue().limitToLast(10);
/// top.onValue.listen((DatabaseEvent e) {
///   for (final DataSnapshot s in e.snapshot.children) print('${s.key}: ${s.value}');
/// });
/// ```
///
/// Validation. The client checks a query when you build it, in release builds too, with the JS SDK's rules:
/// one `orderBy*`; at most one start bound and one end bound; [equalTo] excludes both; a `key:` argument only
/// where the order allows it; a limit above 0. A violation throws an [ArgumentError] (a bad argument) or a
/// [StateError] (a second `orderBy*`, start, end or limit) at the call.
///
/// Streams. Every event getter returns a stream made with `Stream.multi`: not broadcast, and each `listen`,
/// also a second `listen` on the same stream object, is its own registration that gets its own initial
/// events. Equal queries share one listen on the server. Cancelling a subscription removes it at once,
/// without waiting for the server; the last one on a query removes the server listen. A stream ends only
/// when the database closes (error `database-closed`, then done) or when the server cancels the listen
/// (error, for example `permission-denied`, then done). A lost connection is never a stream error.
///
/// Delivery. No listener runs inside the call that caused it, except in [FirebaseDatabase.close],
/// which delivers the `database-closed` error to every open stream before it returns: events go
/// through one queue per database, drained in a microtask. Inside one change, events come child
/// removed, added, moved, changed, then value; deeper locations before shallower ones. Changes are
/// delivered in the order they were applied. Pausing a subscription buffers its events without
/// bound; nothing is dropped. Order across subscriptions holds only for `listen` callbacks that are
/// not paused: `await for` pauses after each event, so it loses order relative to other streams
/// (use [onChildEvents] to keep the order of child events). An exception thrown by a listener goes
/// to that listener's zone; its subscription stays open.
///
/// Cache. A new listener on a location whose data is held complete (by another listener, or by a pending
/// local write) gets its initial events from that data with no round trip. Two queries are equal when they
/// have the same database, path and query parameters.
base class Query {
  /// Creates the query [spec] of [database]. Use `FirebaseDatabase.ref` and the modifiers instead.
  @internal
  const Query.internal(this.database, this.spec);

  /// The database this query reads.
  final FirebaseDatabase database;

  /// The path and parameters of this query.
  @internal
  final QuerySpec spec;

  /// Whether an `orderBy*` was called on this query (JS `_orderByCalled`).
  bool get _orderByCalled => this is _OrderedQuery;

  Query _with(QueryParams params, {bool ordered = false}) {
    final QuerySpec newSpec = QuerySpec(spec.path, params);
    return ordered || _orderByCalled
        ? _OrderedQuery(database, newSpec)
        : Query.internal(database, newSpec);
  }

  /// The reference to this query's location, without order, range or limit.
  DatabaseReference get ref =>
      DatabaseReference.internal(database, QuerySpec.defaultAt(spec.path));

  /// The path of the location: `'/a/b'`, or `'/'` at the root.
  String get path => spec.path.toString();

  /// The scheme, host and percent-encoded [path] of this location, for example
  /// `https://my-project-default-rtdb.firebaseio.com/a/b`. Unlike [FirebaseDatabase.databaseUrl] it
  /// never has the `?ns=` query of an emulator.
  Uri get url => database.urlFor(spec.path);

  /// Orders by the value of the child at [path] (which may have several segments) of each child.
  /// Children without it come first.
  ///
  /// With no range and no limit the client asks the server for all the data at this location and
  /// orders it here, as [get] and the `on<Thing>` streams do, so no `.indexOn` rule is needed. With
  /// [startAt], [startAfter], [endAt], [endBefore], [equalTo] or a limit the query is sent as it
  /// is, and the server fails it with `index-not-defined` when the rules have no `.indexOn` for
  /// [path].
  ///
  /// ```dart
  /// final Query adults = db.ref('users').orderByChild('age').startAt(18);
  /// ```
  Query orderByChild(String path) {
    if (path == r'$key') {
      throw ArgumentError(
        r'orderByChild: "$key" is invalid.  Use orderByKey() instead.',
      );
    } else if (path == r'$priority') {
      throw ArgumentError(
        r'orderByChild: "$priority" is invalid.  Use orderByPriority() instead.',
      );
    } else if (path == r'$value') {
      throw ArgumentError(
        r'orderByChild: "$value" is invalid.  Use orderByValue() instead.',
      );
    }
    validatePathString('orderByChild', 'path', path);
    _validateNoPreviousOrderByCall('orderByChild');
    final Path parsedPath = Path(path);
    if (parsedPath.isEmpty) {
      throw ArgumentError(
        'orderByChild: cannot pass in empty path. Use orderByValue() instead.',
      );
    }
    final QueryParams params = spec.params.orderBy(PathIndex(parsedPath));
    _validateQueryEndpoints(params);
    return _with(params, ordered: true);
  }

  /// Orders by child key: keys that parse as 32-bit integers (leading zeros allowed) come first, by value,
  /// ties going to the shorter string; then all other keys by UTF-16 code units.
  Query orderByKey() {
    _validateNoPreviousOrderByCall('orderByKey');
    final QueryParams params = spec.params.orderBy(keyIndex);
    _validateQueryEndpoints(params);
    return _with(params, ordered: true);
  }

  /// Orders by the children's values: null, then false, true, numbers, strings, then objects by key.
  Query orderByValue() {
    _validateNoPreviousOrderByCall('orderByValue');
    final QueryParams params = spec.params.orderBy(valueIndex);
    _validateQueryEndpoints(params);
    return _with(params, ordered: true);
  }

  /// Orders by the children's priorities.
  Query orderByPriority() {
    _validateNoPreviousOrderByCall('orderByPriority');
    final QueryParams params = spec.params.orderBy(priorityIndex);
    _validateQueryEndpoints(params);
    return _with(params, ordered: true);
  }

  /// Starts the range at [value], included, and at children whose key is at least [key] among those equal
  /// to [value]. A `null` [value] is a real bound (null priority or value). Throws when a start bound is
  /// already set or [key] is not allowed by the order.
  Query startAt(Object? value, {String? key}) {
    validateKey('startAt', 'key', key, optional: true);
    final QueryParams params = spec.params.startAt(
      _boundNode('startAt', value),
      key == null ? null : ChildKey(key),
    );
    _validateLimit(params);
    _validateQueryEndpoints(params);
    if (spec.params.hasStart) {
      throw StateError(
        'startAt: Starting point was already set (by another call to startAt, '
        'startAfter or equalTo).',
      );
    }
    return _with(params);
  }

  /// Starts the range just after [value] (and after [key] among children equal to [value]). A `null`
  /// [value] is a real bound.
  Query startAfter(Object? value, {String? key}) {
    validateKey('startAfter', 'key', key, optional: true);
    final QueryParams params = spec.params.startAfter(
      _boundNode('startAfter', value),
      key == null ? null : ChildKey(key),
    );
    _validateLimit(params);
    _validateQueryEndpoints(params);
    if (spec.params.hasStart) {
      throw StateError(
        'startAfter: Starting point was already set (by another call to startAt, '
        'startAfter, or equalTo).',
      );
    }
    return _with(params);
  }

  /// Ends the range at [value], included (and at [key] among children equal to [value]). A `null` [value]
  /// is a real bound. Throws when an end bound is already set.
  Query endAt(Object? value, {String? key}) {
    validateKey('endAt', 'key', key, optional: true);
    final QueryParams params = spec.params.endAt(
      _boundNode('endAt', value),
      key == null ? null : ChildKey(key),
    );
    _validateLimit(params);
    _validateQueryEndpoints(params);
    if (spec.params.hasEnd) {
      throw StateError(
        'endAt: Ending point was already set (by another call to endAt, '
        'endBefore or equalTo).',
      );
    }
    return _with(params);
  }

  /// Ends the range just before [value] (and before [key] among children equal to [value]). A `null` [value]
  /// is a real bound.
  Query endBefore(Object? value, {String? key}) {
    validateKey('endBefore', 'key', key, optional: true);
    final QueryParams params = spec.params.endBefore(
      _boundNode('endBefore', value),
      key == null ? null : ChildKey(key),
    );
    _validateLimit(params);
    _validateQueryEndpoints(params);
    if (spec.params.hasEnd) {
      throw StateError(
        'endBefore: Ending point was already set (by another call to endAt, '
        'endBefore or equalTo).',
      );
    }
    return _with(params);
  }

  /// Keeps only the children equal to [value] (and with key [key] when given): a start and an end bound at
  /// once, so it throws when either is already set.
  Query equalTo(Object? value, {String? key}) {
    validateKey('equalTo', 'key', key, optional: true);
    validateFirebaseDataArg('equalTo', value, spec.path);
    if (spec.params.hasStart) {
      throw StateError(
        'equalTo: Starting point was already set (by another call to '
        'startAt/startAfter or equalTo).',
      );
    }
    if (spec.params.hasEnd) {
      throw StateError(
        'equalTo: Ending point was already set (by another call to '
        'endAt/endBefore or equalTo).',
      );
    }
    return startAt(value, key: key).endAt(value, key: key);
  }

  /// Keeps the first [limit] children in the order; [limit] must be above 0 and no limit may be set yet.
  Query limitToFirst(int limit) {
    if (limit <= 0) {
      throw ArgumentError.value(
        limit,
        'limit',
        'limitToFirst: First argument must be a positive integer.',
      );
    }
    if (spec.params.hasLimit) {
      throw StateError(
        'limitToFirst: Limit was already set (by another call to limitToFirst '
        'or limitToLast).',
      );
    }
    return _with(spec.params.limitToFirst(limit));
  }

  /// Keeps the last [limit] children in the order; [limit] must be above 0 and no limit may be set yet.
  Query limitToLast(int limit) {
    if (limit <= 0) {
      throw ArgumentError.value(
        limit,
        'limit',
        'limitToLast: First argument must be a positive integer.',
      );
    }
    if (spec.params.hasLimit) {
      throw StateError(
        'limitToLast: Limit was already set (by another call to limitToFirst '
        'or limitToLast).',
      );
    }
    return _with(spec.params.limitToLast(limit));
  }

  /// Reads the query's data once, preferring the server.
  ///
  /// 1. When the client already holds the query's data complete (server data kept for an active listener,
  ///    or pending local writes that cover the query, with pending writes laid over it), it answers from
  ///    that with no round trip.
  /// 2. Otherwise it asks the server and waits, with no client timeout while connected. The answer also
  ///    raises events on the listeners it completes, before this Future completes.
  /// 3. When not connected, it waits up to 3 seconds for a connection, then answers from the persisted
  ///    cache, or fails with `unavailable`. After `FirebaseDatabase.goOffline` it does not wait.
  /// 4. When the connection drops while the request is out, case 3 applies from then.
  /// 5. When the server refuses the read it fails with `permission-denied`, never with a cached answer.
  ///
  /// 6. A `.info` path answers from the local state at once.
  ///
  /// Other failures keep their code: `network-error` after two connections that each fell silent,
  /// `index-not-defined` for a filtered query the rules cannot serve, `database-closed` after
  /// [FirebaseDatabase.close]. Without `persistence` there is no persisted cache, so case 3 ends in
  /// `unavailable`.
  ///
  /// Outside case 1 the answer does not include this client's pending writes.
  ///
  /// A query with an order but no range and no limit asks the server for all the data at its path and
  /// orders the children here, as a listener does, so it needs no `.indexOn` rule (JS sends the ordered
  /// query and the server refuses it without one). A query with a range or a limit is sent as it is and
  /// fails with `index-not-defined` when the rules have no `.indexOn` for its order.
  Future<DataSnapshot> get() {
    final DatabaseReference location = ref;
    return database.request<DataSnapshot>((
      Repo repo,
      void Function(DataSnapshot) complete,
      void Function(Object, [StackTrace?]) fail,
    ) {
      repo
          .getValue(spec)
          .then<void>(
            (Node node) =>
                complete(DataSnapshot.internal(location, node, spec.index)),
            onError: (Object error, StackTrace stackTrace) =>
                fail(toApiError(error), stackTrace),
          );
    });
  }

  /// Completes with the first event of [type] and stops listening.
  ///
  /// This is a listener, not a read. It answers from data the client already holds (pending local
  /// writes included), else it waits for the server with no timeout, also while offline; [get]
  /// fails with `unavailable` after 3 seconds instead. With a child type it completes with the
  /// first child event, so it waits until a child exists or changes. It fails with the error of the
  /// stream (`permission-denied` when the rules refuse the listen, `database-closed` after
  /// [FirebaseDatabase.close]).
  ///
  /// ```dart
  /// final DatabaseEvent e = await db.ref('config').once();
  /// print(e.snapshot.value);
  /// ```
  Future<DatabaseEvent> once([
    DatabaseEventType type = DatabaseEventType.value,
  ]) {
    final Completer<DatabaseEvent> completer = Completer<DatabaseEvent>();
    late final StreamSubscription<DatabaseEvent> subscription;
    subscription = _stream(<EventType>{_coreType(type)}).listen(
      (DatabaseEvent event) {
        if (completer.isCompleted) {
          return;
        }
        unawaited(subscription.cancel());
        completer.complete(event);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('The stream ended before an event of type $type.'),
          );
        }
      },
      cancelOnError: true,
    );
    return completer.future;
  }

  Stream<DatabaseEvent> _stream(Set<EventType> types) =>
      database.eventStream(this, types);

  /// The value of the query: its current data first, then again after every change. An empty
  /// location gives a first event whose snapshot has `exists` false. While offline the first event
  /// comes from data the client already holds, else it waits for the server; the loss of the
  /// connection is not an error of the stream (see [FirebaseDatabase.onConnected]).
  Stream<DatabaseEvent> get onValue => _stream(<EventType>{EventType.value});

  /// A [DatabaseEventType.childAdded] event per child, first for each existing child, then for each new
  /// one. An empty location gives no event until a child appears.
  Stream<DatabaseEvent> get onChildAdded =>
      _stream(<EventType>{EventType.childAdded});

  /// A [DatabaseEventType.childChanged] event each time a child's data changes.
  Stream<DatabaseEvent> get onChildChanged =>
      _stream(<EventType>{EventType.childChanged});

  /// A [DatabaseEventType.childMoved] event each time a child changes place in the order.
  Stream<DatabaseEvent> get onChildMoved =>
      _stream(<EventType>{EventType.childMoved});

  /// A [DatabaseEventType.childRemoved] event each time a child leaves the results.
  Stream<DatabaseEvent> get onChildRemoved =>
      _stream(<EventType>{EventType.childRemoved});

  /// The four child event kinds in one stream, in their true order, with no value events and no batching
  /// per change; switch on [DatabaseEvent.type]. Unlike four separate streams, it keeps the order of child
  /// events under pause and `await for`.
  Stream<DatabaseEvent> get onChildEvents => _stream(<EventType>{
    EventType.childRemoved,
    EventType.childAdded,
    EventType.childMoved,
    EventType.childChanged,
  });

  /// Keeps this query's data synchronised even with no listener when [value] is true, and stops when it is
  /// false.
  ///
  /// It is a flag, not a counter: calling it with true twice and false once turns it off. Without
  /// persistence it keeps the in-memory data and the server listen. The Future completes when the
  /// flag has been applied here, not when the data has arrived; after [FirebaseDatabase.close] it
  /// fails with `database-closed`. A `.info` path throws an [ArgumentError] at the call, not
  /// through the Future.
  ///
  /// ```dart
  /// await db.ref('scores').orderByValue().limitToLast(10).keepSynced(true);
  /// ```
  Future<void> keepSynced(bool value) {
    if (spec.path.front == ChildKey.info) {
      throw ArgumentError("keepSynced() can't be called on .info paths.");
    }
    return database.request<void>((
      Repo repo,
      void Function(void) complete,
      void Function(Object, [StackTrace?]) fail,
    ) {
      repo.keepSynced(spec, keep: value);
      complete(null);
    });
  }

  void _validateNoPreviousOrderByCall(String fnName) {
    if (_orderByCalled) {
      throw StateError("$fnName: You can't combine multiple orderBy calls.");
    }
  }

  /// The node of a cursor [value], validated as data (JS `validateFirebaseDataArg`).
  Node _boundNode(String fnName, Object? value) {
    validateFirebaseDataArg(fnName, value, spec.path);
    return userValueNode(value);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Query && other.database == database && other.spec == spec;

  @override
  int get hashCode => Object.hash(database, spec);
}

/// A query on which an `orderBy*` was called; a second one throws.
final class _OrderedQuery extends Query {
  _OrderedQuery(super.database, super.spec) : super.internal();
}

EventType _coreType(DatabaseEventType type) => switch (type) {
  DatabaseEventType.value => EventType.value,
  DatabaseEventType.childAdded => EventType.childAdded,
  DatabaseEventType.childChanged => EventType.childChanged,
  DatabaseEventType.childMoved => EventType.childMoved,
  DatabaseEventType.childRemoved => EventType.childRemoved,
};

bool _isStringNode(Node node) => node.isLeafNode && node.value is String;

bool _isObjectNode(Node node) => !node.isLeafNode && !node.isEmpty;

bool _isPriorityNode(Node node) =>
    node.isEmpty ||
    (node.isLeafNode && (node.value is num || node.value is String));

/// JS `validateQueryEndpoints` (`api/Reference_impl.ts`).
void _validateQueryEndpoints(QueryParams params) {
  final Node? startNode = params.hasStart ? params.indexStartValue : null;
  final Node? endNode = params.hasEnd ? params.indexEndValue : null;

  if (params.index == keyIndex) {
    const String tooManyArgsError =
        'Query: When ordering by key, you may only pass one argument to '
        'startAt(), endAt(), or equalTo().';
    const String wrongArgTypeError =
        'Query: When ordering by key, the argument passed to startAt(), startAfter(), '
        'endAt(), endBefore(), or equalTo() must be a string.';
    if (startNode != null) {
      if (params.indexStartName != ChildKey.min) {
        throw ArgumentError(tooManyArgsError);
      } else if (!_isStringNode(startNode)) {
        throw ArgumentError(wrongArgTypeError);
      }
    }
    if (endNode != null) {
      if (params.indexEndName != ChildKey.max) {
        throw ArgumentError(tooManyArgsError);
      } else if (!_isStringNode(endNode)) {
        throw ArgumentError(wrongArgTypeError);
      }
    }
  } else if (params.index == priorityIndex) {
    if ((startNode != null && !_isPriorityNode(startNode)) ||
        (endNode != null && !_isPriorityNode(endNode))) {
      throw ArgumentError(
        'Query: When ordering by priority, the first argument passed to startAt(), '
        'startAfter() endAt(), endBefore(), or equalTo() must be a valid priority value '
        '(null, a number, or a string).',
      );
    }
  } else {
    if ((startNode != null && _isObjectNode(startNode)) ||
        (endNode != null && _isObjectNode(endNode))) {
      throw ArgumentError(
        'Query: First argument passed to startAt(), startAfter(), endAt(), endBefore(), or '
        'equalTo() cannot be an object.',
      );
    }
  }
}

/// JS `validateLimit` (`api/Reference_impl.ts`).
void _validateLimit(QueryParams params) {
  if (params.hasStart &&
      params.hasEnd &&
      params.hasLimit &&
      !params.hasAnchoredLimit) {
    throw ArgumentError(
      "Query: Can't combine startAt(), startAfter(), endAt(), endBefore(), and limit(). Use "
      'limitToFirst() or limitToLast() instead.',
    );
  }
}

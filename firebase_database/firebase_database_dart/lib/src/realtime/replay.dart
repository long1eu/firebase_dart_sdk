/// What the persistent connection keeps across disconnects (owner P): the listen table, the
/// unacknowledged writes, the onDisconnect requests queued offline and the outstanding gets, in
/// the order of the replay of `rtdb_protocol.md` 8.4 (PersistentConnection.ts:95-104,
/// 1035-1069).
library;

import 'dart:async';

import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';

/// A request that is replayed after a reconnect and counts its timeouts across connections.
sealed class TimedRequest {
  /// How many timeouts the request has been counted for on live connections.
  int timeouts = 0;

  /// Whether it was written to the current connection and its answer has not arrived.
  bool awaitingAnswer = false;
}

/// One registered listen.
final class ListenRecord extends TimedRequest {
  /// Creates the record of [spec] with [tag], hashed by [hashProvider], completed by
  /// [onComplete].
  ListenRecord(this.spec, this.tag, this.hashProvider, this.onComplete);

  /// The listen.
  final ListenSpec spec;

  /// The tag, non-null only for a query that does not load all data.
  final int? tag;

  /// Gives `h` (and `ch`) when the listen is sent, also again at each replay.
  final ListenHashProvider hashProvider;

  /// Gets the status of the listen response, or of a later revoke.
  final RequestResultCallback onComplete;

  /// The `b` of the `q` request (4.1): `p`, `h` always; `q` and `t` only with a tag; `ch` when
  /// the hash provider asks for it (7.3). The query object is sent as the core built it.
  Map<String, Object?> wireBody() {
    final Map<String, Object?> body = <String, Object?>{
      'p': spec.path,
      'h': hashProvider.simpleHash(),
    };
    final int? tag = this.tag;
    if (tag != null) {
      body['q'] = spec.queryObject;
      body['t'] = tag;
    }
    if (hashProvider.shouldIncludeCompoundHash()) {
      final WireCompoundHash compound = hashProvider.compoundHash();
      body['ch'] = <String, Object?>{
        'ps': compound.posts,
        'hs': compound.hashes,
      };
    }
    return body;
  }
}

/// One put or merge not yet acknowledged.
final class OutstandingWrite extends TimedRequest {
  /// Creates the write of [action] (`p` or `m`) with [body]; [isTransaction] for a put with a
  /// hash.
  OutstandingWrite(
    this.action,
    this.body,
    this.onComplete, {
    required this.isTransaction,
  });

  /// `p` or `m`.
  final String action;

  /// `{p, d[, h]}`.
  final Map<String, Object?> body;

  /// Gets the status of the response.
  final RequestResultCallback? onComplete;

  /// Whether this is a transaction put: once sent, a drop completes it with `disconnect` instead
  /// of a replay (8.5).
  final bool isTransaction;

  /// Whether it was written to the current connection.
  bool sent = false;
}

/// One `g` not yet answered.
final class OutstandingGet extends TimedRequest {
  /// Creates the get with [body] `{p, q}`.
  OutstandingGet(this.body);

  /// `{p, q}`.
  final Map<String, Object?> body;

  /// Completes with the data, or fails with a `ServerActionsException`.
  final Completer<Object?> completer = Completer<Object?>();

  /// Whether it was written to the current connection.
  bool sent = false;
}

/// One onDisconnect request made while offline.
final class QueuedOnDisconnect {
  /// Creates the request of [action] (`o`, `om`, `oc`) with [body].
  QueuedOnDisconnect(this.action, this.body, this.onComplete);

  /// `o`, `om` or `oc`.
  final String action;

  /// `{p, d}`.
  final Map<String, Object?> body;

  /// Gets the status of the response.
  final RequestResultCallback? onComplete;
}

/// The state the persistent connection replays after each hello.
final class ReplayQueues {
  /// Creates empty queues.
  ReplayQueues();

  final Map<String, ListenRecord> _listens = <String, ListenRecord>{};

  /// Unacknowledged puts and merges, in the order they were made.
  final List<OutstandingWrite> writes = <OutstandingWrite>[];

  /// onDisconnect requests made while offline, first in first out.
  final List<QueuedOnDisconnect> onDisconnects = <QueuedOnDisconnect>[];

  /// Gets not yet answered.
  final List<OutstandingGet> gets = <OutstandingGet>[];

  static String _key(String path, String queryIdentifier) =>
      '$path\u0000$queryIdentifier';

  /// The registered listens, in the order they were made.
  Iterable<ListenRecord> get listens => _listens.values.toList();

  /// Registers [record]; false when its path and query identifier are already listened to.
  bool addListen(ListenRecord record) {
    final String key = _key(record.spec.path, record.spec.queryIdentifier);
    if (_listens.containsKey(key)) {
      return false;
    }
    _listens[key] = record;
    return true;
  }

  /// Whether [record] itself (not another listen of the same query) is registered.
  bool hasListen(ListenRecord record) => identical(
    _listens[_key(record.spec.path, record.spec.queryIdentifier)],
    record,
  );

  /// Removes and returns the listen at [path] with [queryIdentifier], if any.
  ListenRecord? removeListen(String path, String queryIdentifier) =>
      _listens.remove(_key(path, queryIdentifier));

  /// Removes and returns every listen at [path], whatever its query.
  List<ListenRecord> removeListensAt(String path) {
    final List<ListenRecord> removed = <ListenRecord>[];
    _listens.removeWhere((String key, ListenRecord record) {
      if (record.spec.path != path) {
        return false;
      }
      removed.add(record);
      return true;
    });
    return removed;
  }

  /// Removes and returns the transaction puts that were sent on the connection that just ended.
  List<OutstandingWrite> takeSentTransactions() {
    final List<OutstandingWrite> taken = writes
        .where((OutstandingWrite write) => write.isTransaction && write.sent)
        .toList();
    writes.removeWhere(taken.contains);
    return taken;
  }

  /// The replayable requests waiting for their answer on the current connection.
  Iterable<TimedRequest> get awaitingAnswer => <TimedRequest>[
    ..._listens.values,
    ...writes,
    ...gets,
  ].where((TimedRequest request) => request.awaitingAnswer);

  /// Whether [request] is still registered (not answered, purged, unlistened or failed).
  bool isQueued(TimedRequest request) => switch (request) {
    ListenRecord() => hasListen(request),
    OutstandingWrite() => writes.contains(request),
    OutstandingGet() => gets.contains(request),
  };

  /// Marks every request as not sent: the connection that carried them is gone.
  void markAllUnsent() {
    for (final ListenRecord listen in _listens.values) {
      listen.awaitingAnswer = false;
    }
    for (final OutstandingWrite write in writes) {
      write
        ..sent = false
        ..awaitingAnswer = false;
    }
    for (final OutstandingGet get in gets) {
      get
        ..sent = false
        ..awaitingAnswer = false;
    }
  }

  /// Drops everything (shutdown).
  void clear() {
    _listens.clear();
    writes.clear();
    onDisconnects.clear();
    gets.clear();
  }
}

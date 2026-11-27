/// What the persistent connection keeps across disconnects (owner P): the listen table, the
/// unacknowledged writes, the onDisconnect requests (queued offline, or sent and not answered)
/// and the outstanding gets, in the order of the replay of `rtdb_protocol.md` 8.4
/// (PersistentConnection.ts:95-104, 1035-1069).
///
/// Timeouts (review H1, the lead's replaced rule): no write, listen or onDisconnect request ever
/// counts a timeout; only a get counts the connections that ended in link silence while it waited
/// ([OutstandingGet.silentConnections]).
library;

import 'dart:async';

import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';

/// One registered listen.
final class ListenRecord {
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

/// One put or merge not yet acknowledged. Never failed by a timeout: it stays in the replay
/// until an answer, a purge or a shutdown (at-least-once, 8.4).
final class OutstandingWrite {
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

  /// Whether it was written to the current connection (set only when the send succeeded).
  bool sent = false;
}

/// One `g` not yet answered.
final class OutstandingGet {
  /// Creates the get with [body] `{p, q}`.
  OutstandingGet(this.body);

  /// `{p, q}`.
  final Map<String, Object?> body;

  /// Completes with the data, or fails with a `ServerActionsException`.
  final Completer<Object?> completer = Completer<Object?>();

  /// Whether it was written to the current connection (set only when the send succeeded).
  bool sent = false;

  /// How many connections ended in link silence while this get waited for its answer on them
  /// (the lead's rule: two give `network_error`). It belongs to this get alone; an answered get
  /// leaves the queue.
  int silentConnections = 0;
}

/// One onDisconnect request (`o`, `om`, `oc`).
final class QueuedOnDisconnect {
  /// Creates the request of [action] with [body].
  QueuedOnDisconnect(this.action, this.body, this.onComplete);

  /// `o`, `om` or `oc`.
  final String action;

  /// `{p, d}`.
  final Map<String, Object?> body;

  /// Gets the status of the response, or `disconnect` when its connection dropped first.
  final RequestResultCallback? onComplete;
}

/// The state the persistent connection replays after each hello.
final class ReplayQueues {
  /// Creates empty queues.
  ReplayQueues();

  final Map<String, ListenRecord> _listens = <String, ListenRecord>{};

  /// Unacknowledged puts and merges, in the order they were made.
  final List<OutstandingWrite> writes = <OutstandingWrite>[];

  /// onDisconnect requests made while offline, first in first out; sent at the next connection.
  final List<QueuedOnDisconnect> onDisconnects = <QueuedOnDisconnect>[];

  /// onDisconnect requests sent on the current connection and not answered yet. Never replayed:
  /// a drop completes each with `disconnect` (review H3).
  final List<QueuedOnDisconnect> sentOnDisconnects = <QueuedOnDisconnect>[];

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

  /// Removes and returns the onDisconnect requests sent on the connection that just ended.
  List<QueuedOnDisconnect> takeSentOnDisconnects() {
    final List<QueuedOnDisconnect> taken = sentOnDisconnects.toList();
    sentOnDisconnects.clear();
    return taken;
  }

  /// Marks every write and get as not sent: the connection that carried them is gone.
  void markAllUnsent() {
    for (final OutstandingWrite write in writes) {
      write.sent = false;
    }
    for (final OutstandingGet get in gets) {
      get.sent = false;
    }
  }

  /// Drops everything (shutdown).
  void clear() {
    _listens.clear();
    writes.clear();
    onDisconnects.clear();
    sentOnDisconnects.clear();
    gets.clear();
  }
}

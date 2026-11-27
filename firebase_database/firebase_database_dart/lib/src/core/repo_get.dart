// `get`: answer locally when the tree has the data, else ask the server, with contract C25's
// rules for a missing connection. JS: `core/Repo.ts` (`repoGetValue`); Android: `core/Repo.java`
// (`getValue`); the wait is iOS's (`FRepo.m:542-565`, `FPersistentConnection.m:919-935`).
part of 'repo.dart';

/// One `get` waiting for the server.
final class _PendingGet {
  _PendingGet(this.query);

  /// The query asked for.
  final QuerySpec query;

  /// Completes with the answer.
  final Completer<Node> completer = Completer<Node>();

  /// The wait for a connection, while disconnected (contract C25 rule 3).
  Timer? timer;
}

extension _RepoGet on Repo {
  /// The body of [Repo.getValue].
  ///
  /// 1. Complete local data (an active complete view, or pending writes covering the query)
  ///    answers at once (JS `syncTreeGetServerValue`).
  /// 2. After goOffline the persisted cache answers at once, else `unavailable`.
  /// 3. Otherwise the request goes out; a query that loads all data asks for the default query
  ///    and is ordered here. While connected there is no timer; while disconnected (or from a
  ///    drop on) a [getPersistedFallbackDelay] wait starts, after which the persisted cache
  ///    answers, else `unavailable`. A connection stops the wait.
  /// 4. A failure (`permission_denied`, `network_error`, ...) fails the get; it never answers
  ///    from the cache.
  Future<Node> _getValue(QuerySpec query) {
    if (_closed) {
      return Future<Node>.error(Repo._closedError());
    }
    if (Repo._isInfo(query.path)) {
      return Future<Node>.value(
        (_infoSyncTree.getServerValue(query) ?? _infoData.getNode(query.path))
            .withIndex(query.index),
      );
    }
    final Node? cached = _serverSyncTree.getServerValue(query);
    if (cached != null) {
      return Future<Node>.value(cached);
    }
    final _PendingGet request = _PendingGet(query);
    _pendingGets.add(request);
    // Android marks the query active so its persisted data is tracked; the keepSynced bracket
    // around the answer makes it inactive again.
    _serverSyncTree.setQueryActive(query);
    if (_connection.isInterrupted(interruptReason)) {
      _answerGetFromCache(request);
      return request.completer.future;
    }
    // A query that loads all data is asked for as the default query and ordered here, as a listen
    // is (sync tree `_queryForListening`): the server refuses an ordered get with `no_index` when
    // the rules have no `.indexOn`, while it answers the default get.
    final QuerySpec wireQuery = query.loadsAllData && !query.isDefault
        ? QuerySpec.defaultAt(query.path)
        : query;
    _connection
        .get(wireQuery.toListenSpec())
        .then<void>(
          (Object? payload) => _onGetResult(request, payload),
          onError: (Object error, StackTrace stackTrace) =>
              _onGetError(request, error),
        );
    if (!_connected) {
      _startGetWait(request);
    }
    return request.completer.future;
  }

  /// Starts the wait for a connection of [request] (or answers at once after goOffline).
  void _startGetWait(_PendingGet request) {
    if (request.completer.isCompleted || request.timer != null) {
      return;
    }
    if (_connection.isInterrupted(interruptReason)) {
      _answerGetFromCache(request);
      return;
    }
    request.timer = Timer(
      getPersistedFallbackDelay,
      () => _answerGetFromCache(request),
    );
  }

  /// Answers [request] from the persisted cache, else fails it with `unavailable`.
  void _answerGetFromCache(_PendingGet request) {
    if (request.completer.isCompleted || _closed) {
      return;
    }
    _finishGet(request);
    _releaseGetQuery(request.query);
    final Node? persisted = _serverSyncTree.persistenceServerCache(
      request.query,
    );
    if (persisted != null) {
      request.completer.complete(persisted);
    } else {
      request.completer.completeError(
        DatabaseError.fromStatus(
          DatabaseErrorCode.unavailable.wireStatus,
          'The client is offline and has no cached data for this query.',
        ),
      );
    }
  }

  void _finishGet(_PendingGet request) {
    request.timer?.cancel();
    request.timer = null;
    _pendingGets.remove(request);
  }

  /// Marks [query], made active by a get that ends without a server overwrite, inactive again
  /// unless another get of it is open or a listener holds it. Otherwise the tracked query stays
  /// active for the session: it is never pruned, and an acknowledged write below it is not
  /// written to the cache (`applyUserWriteToServerCache` takes it for a listened location), so
  /// a later offline get could answer the older value.
  void _releaseGetQuery(QuerySpec query) {
    if (_pendingGets.any((_PendingGet other) => other.query == query)) {
      return;
    }
    _serverSyncTree.releaseQuery(query);
  }

  /// Applies the server's answer as a listen would (a get answer comes with no data update),
  /// raising events on listeners it completes, then answers (JS `repoGetValue`; Android
  /// `getValue`). A filtered query's answer goes to its tagged view only, so it never makes the
  /// default query complete.
  void _onGetResult(_PendingGet request, Object? payload) {
    if (request.completer.isCompleted || _closed) {
      return;
    }
    _finishGet(request);
    final QuerySpec query = request.query;
    final Node node;
    try {
      node = nodeFromJson(payload);
    } on Object catch (e) {
      // The error's text can quote the server's data, so only its type is logged.
      _log(
        DatabaseLogLevel.error,
        'Failed to parse server response for get() at ${query.path}: '
        '${e.runtimeType}',
      );
      _releaseGetQuery(query);
      request.completer.completeError(
        DatabaseError.local(
          DatabaseErrorCode.unknown,
          'The server answer to get() could not be read.',
          cause: e,
        ),
      );
      return;
    }
    final bool bracket = !_keptSynced.contains(query);
    if (bracket) {
      _serverSyncTree.keepSynced(query, keep: true, skipDedup: true);
    }
    final List<Event> events;
    if (query.loadsAllData) {
      events = _serverSyncTree.applyServerOverwrite(query.path, node);
    } else {
      final Tag? tag = _serverSyncTree.tagForQuery(query);
      events = tag == null
          ? const <Event>[]
          : _serverSyncTree.applyTaggedQueryOverwrite(query.path, node, tag);
    }
    _post(events);
    request.completer.complete(node.withIndex(query.index));
    if (bracket) {
      _serverSyncTree.keepSynced(query, keep: false, skipDedup: true);
    }
  }

  void _onGetError(_PendingGet request, Object error) {
    // Also after close: the connection's shutdown fails every outstanding get.
    if (request.completer.isCompleted) {
      return;
    }
    _finishGet(request);
    if (!_closed) {
      _releaseGetQuery(request.query);
    }
    // The query's shape only: its bounds are user values (JS logs the whole query).
    _log(
      DatabaseLogLevel.debug,
      'get for query ${_queryShape(request.query)} failed: '
      '${error is ServerActionsException ? error : error.runtimeType}',
    );
    request.completer.completeError(
      // After close the connection's shutdown fails the get with the status `database_closed`,
      // which the wire mapping reads as `unknown`; the get fails with the local closed error.
      _closed
          ? Repo._closedError()
          : error is ServerActionsException
          ? DatabaseError.fromStatus(error.status, error.reason)
          : DatabaseError.local(
              DatabaseErrorCode.unknown,
              'get() failed with an error the client did not expect.',
              cause: error,
            ),
    );
  }
}

/// The path and shape of [query] for a log line: the index, which bounds are set and whether
/// each is inclusive, and the limit with its side. Never a bound value or a bound key.
String _queryShape(QuerySpec query) {
  final QueryParams params = query.params;
  final List<String> parts = <String>['order ${params.index.queryDefinition}'];
  if (params.hasStart) {
    parts.add(params.startInclusive ? 'start inclusive' : 'start exclusive');
  }
  if (params.hasEnd) {
    parts.add(params.endInclusive ? 'end inclusive' : 'end exclusive');
  }
  if (params.hasLimit) {
    final String side = params.isViewFromLeft ? 'first' : 'last';
    parts.add('limit ${params.limit} $side');
  }
  return '${query.path} (${parts.join(', ')})';
}

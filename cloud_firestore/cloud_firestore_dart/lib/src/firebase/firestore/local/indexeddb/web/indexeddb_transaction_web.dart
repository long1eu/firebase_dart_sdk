part of 'indexeddb_persistence_web.dart';

/// A persistence transaction made a request after its IndexedDB transaction had committed: something inside
/// `runTransaction` awaited a timer, other I/O or anything else that let the event loop run (see the library comment).
/// The writes before that point are committed and the ones after it are not, so the transaction can not be retried:
/// the persistence refuses every later transaction.
///
/// An [Error], not an exception: it is a bug of the code that ran inside the transaction.
class IndexedDbTransactionInactiveError extends Error {
  IndexedDbTransactionInactiveError(this.action, this.operation, [this.cause]);

  /// The persistence transaction.
  final String action;

  /// The request that found the transaction inactive.
  final String operation;

  /// The `TransactionInactiveError` of IndexedDB, if one was thrown.
  final Object? cause;

  @override
  String toString() =>
      'IndexedDbTransactionInactiveError: the IndexedDB transaction of "$action" committed before "$operation" '
      '(${cause ?? 'the transaction had completed'}). Code inside a persistence transaction awaited something other '
      'than a request of the transaction (a timer, other I/O): the writes before this point are committed, the '
      'rest is lost. The IndexedDB cache refuses every further transaction; restart the client.';
}

/// One IndexedDB transaction over every store, with requests that report a broken transaction rule.
class _IdbTransaction {
  _IdbTransaction(this._persistence, this.action, this._idb) {
    _persistence._openTransactions++;
    final Completer<void> done = Completer<void>();
    _done = done.future..ignore();
    _idb.oncomplete = ((web.Event _) {
      _completed = true;
      _persistence._openTransactions--;
      done.complete();
    }).toJS;
    _idb.onabort = ((web.Event _) {
      if (!_aborted && !_completed) {
        _persistence._openTransactions--;
      }
      _aborted = true;
      if (!done.isCompleted) {
        final web.DOMException? error = _idb.error;
        done.completeError(
          TransientDatabaseException(
            'The IndexedDB transaction "$action" aborted: ${idbDescribe(error)}',
            error,
          ),
        );
      }
    }).toJS;
  }

  final WebIndexedDbPersistence _persistence;

  /// The action of the persistence transaction.
  final String action;
  final web.IDBTransaction _idb;
  late final Future<void> _done;
  bool _completed = false;
  bool _aborted = false;

  bool get _finished => _completed || _aborted;

  web.IDBObjectStore store(String name) => _idb.objectStore(name);

  IndexedDbTransactionInactiveError _inactive(String what, [Object? cause]) {
    final IndexedDbTransactionInactiveError error =
        IndexedDbTransactionInactiveError(action, what, cause);
    _persistence._fail(error);
    return error;
  }

  /// Throws an [IndexedDbTransactionInactiveError] when the IndexedDB transaction already committed.
  void checkNotFinished(String what) {
    if (_completed) {
      throw _inactive(what);
    }
  }

  /// Makes the request [make] returns (synchronously), checking that the transaction is still active.
  web.IDBRequest _issue(String what, web.IDBRequest Function() make) {
    if (_completed) {
      throw _inactive(what);
    }
    try {
      return make();
    } catch (error) {
      if (_aborted) {
        // A request failed before and aborted the transaction: that failure is the one to report.
        throw TransientDatabaseException(
          'IndexedDB "$what" in the transaction "$action": the transaction was aborted '
          '(${idbDescribe(_idb.error)})',
          error,
        );
      }
      if (_completed || '$error'.contains('TransactionInactiveError')) {
        throw _inactive(what, error);
      }
      throw StateError(
        'IndexedDB refused "$what" in the transaction "$action": $error',
      );
    }
  }

  TransientDatabaseException _failed(
    String what,
    IdbRequestError error,
  ) => TransientDatabaseException(
    'IndexedDB "$what" failed in the transaction "$action": ${error.name}: ${error.message}',
    error,
  );

  /// The result of the request [make] returns. [what] names the request in errors.
  Future<JSAny?> request(String what, web.IDBRequest Function() make) {
    final web.IDBRequest request = _issue(what, make);
    final Completer<JSAny?> completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) => completer.complete(
      request.result,
    )).toJS;
    request.onerror = ((web.Event _) => completer.completeError(
      _failed(what, IdbRequestError.of(request)),
    )).toJS;
    return completer.future;
  }

  /// The result of the request [make] returns, as a JSON tree (see [idbToDart]).
  Future<Object?> read(String what, web.IDBRequest Function() make) async =>
      idbToDart(await request(what, make));

  /// Visits the cursor the request [open] returns, see [idbForEach].
  Future<void> forEach(
    String what,
    web.IDBRequest Function() open,
    bool Function(web.IDBCursor cursor) visit,
  ) async {
    try {
      await idbForEach(_issue(what, open), visit);
    } on IdbRequestError catch (error) {
      throw _failed(what, error);
    }
  }

  /// Walks the cursor the request [open] returns, see [idbWalk].
  Future<void> walk(
    String what,
    web.IDBRequest Function() open,
    Object Function(web.IDBCursor cursor) visit,
  ) async {
    try {
      await idbWalk(_issue(what, open), visit);
    } on IdbRequestError catch (error) {
      throw _failed(what, error);
    }
  }

  /// Commits the transaction (`commit()` where the browser has it; it commits on its own otherwise) and completes
  /// when it is durable.
  Future<void> commit() {
    if (!_finished) {
      try {
        _idb.commit();
      } catch (_) {
        // A browser without IDBTransaction.commit: the transaction commits when its last request is done.
      }
    }
    return _done;
  }

  /// Rolls the transaction back, if it is still running.
  void abort() {
    if (_finished) {
      return;
    }
    try {
      _idb.abort();
    } catch (_) {
      // It finished in the meantime.
    }
  }
}

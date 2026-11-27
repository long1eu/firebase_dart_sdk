// Transactions: the queue tree, sending, rerunning and aborting. JS: `core/Repo.ts`
// (`repoStartTransaction`, `repoSendReadyTransactions`, `repoRerunTransactions`,
// `repoAbortTransactions`); Android: `core/Repo.java` (the "Transaction code" section).
part of 'repo.dart';

/// The value listener a transaction keeps on its path, so its data is synced and server updates
/// there rerun it (Android's no-op `ValueEventListener` in `startTransaction`; JS
/// `repoStartTransaction`'s `watchRef.on('value', ...)`). It delivers nothing.
final class _TransactionWatch extends EventRegistration {
  _TransactionWatch(this.querySpec, [Object? token])
    : _token = token ?? Object();

  @override
  final QuerySpec querySpec;

  /// Shared by clones, so a clone is the same listener.
  final Object _token;

  @override
  bool respondsTo(EventType type) => type == EventType.value;

  @override
  DataEvent createEvent(Change change, QuerySpec query) =>
      DataEvent(EventType.value, this, query.path, change.node);

  @override
  void fireEvent(DataEvent event) {}

  @override
  void fireCancelEvent(DatabaseError error) {}

  @override
  EventRegistration clone(QuerySpec newQuery) =>
      _TransactionWatch(newQuery, _token);

  @override
  bool isSameListener(EventRegistration other) =>
      other is _TransactionWatch && identical(other._token, _token);
}

/// The transactions whose first run is in progress, per Repo. They are not in the queue tree
/// yet; [_RepoTransactions._abortTransactions] marks one that a write or purge from inside its
/// handler overlaps.
final Expando<List<TransactionData>> _firstRuns =
    Expando<List<TransactionData>>('transaction first runs');

extension _RepoTransactions on Repo {
  /// The body of [Repo.startTransaction] (Android `Repo.startTransaction`).
  void _startTransaction(
    Path path,
    TransactionUpdate update,
    TransactionCompletion? onComplete,
    bool applyLocally,
  ) {
    if (_closed) {
      if (onComplete != null) {
        final DatabaseError error = Repo._closedError();
        scheduleMicrotask(() => onComplete(error, false, null));
      }
      return;
    }
    _log(DatabaseLogLevel.debug, 'transaction: $path');
    if (_persistenceManager is! NoopPersistenceManager &&
        !_loggedTransactionPersistenceWarning) {
      _loggedTransactionPersistenceWarning = true;
      _log(
        DatabaseLogLevel.info,
        'runTransaction() usage detected while persistence is enabled. Please be aware that '
        'transactions *will not* be persisted across database restarts.',
      );
    }
    // The watch is added inside the call, so its listen keeps the order of the user's calls.
    final _TransactionWatch watch = _TransactionWatch(
      QuerySpec.defaultAt(path),
    );
    _post(_serverSyncTree.addEventRegistration(watch));
    final TransactionData transaction = TransactionData(
      path: path,
      update: update,
      onComplete: onComplete,
      order: _transactionOrder++,
      applyLocally: applyLocally,
      unwatcher: () {
        if (!_closed) {
          _post(_serverSyncTree.removeEventRegistration(watch));
        }
      },
    );
    _runTransactionFirstTime(transaction);
  }

  /// The first run, inside [Repo.startTransaction] as in JS: abort, or queue the result, apply it
  /// locally and send what is ready. A write or purge the handler makes that overlaps its path
  /// aborts the transaction (`overridden-by-set`, `write-canceled`), as it does on a rerun.
  void _runTransactionFirstTime(TransactionData transaction) {
    final Path path = transaction.path;
    final Node currentState = _latestState(path);
    transaction.currentInputSnapshot = currentState;
    final List<TransactionData> running = _firstRuns[this] ??=
        <TransactionData>[];
    running.add(transaction);
    final (TransactionOutcome outcome, DatabaseError? error) = _runUpdate(
      transaction,
      currentState,
    );
    running.remove(transaction);
    if (_closed) {
      // The handler closed the database.
      transaction.status = TransactionStatus.completed;
      scheduleMicrotask(
        () => transaction.onComplete?.call(Repo._closedError(), false, null),
      );
      return;
    }
    if (transaction.status == TransactionStatus.completed) {
      transaction.unwatcher();
      final DatabaseError? abortReason = transaction.abortReason;
      _postCallback(
        () => transaction.onComplete?.call(abortReason, false, null),
      );
      return;
    }
    if (outcome is! TransactionSuccess) {
      transaction
        ..currentOutputSnapshotRaw = null
        ..currentOutputSnapshotResolved = null
        ..status = TransactionStatus.completed;
      transaction.unwatcher();
      _postCallback(
        () => transaction.onComplete?.call(error, false, currentState),
      );
      return;
    }
    transaction.status = TransactionStatus.run;
    final Tree<List<TransactionData>> queueNode = _transactionQueueTree.subTree(
      path,
    );
    queueNode.value = <TransactionData>[...?queueNode.value, transaction];
    final Node newNodeUnresolved = _transactionOutput(
      outcome.value,
      currentState,
    );
    final Node newNode = server_values.resolveDeferredValueSnapshot(
      newNodeUnresolved,
      currentState,
      generateServerValues(),
    );
    transaction
      ..currentOutputSnapshotRaw = newNodeUnresolved
      ..currentOutputSnapshotResolved = newNode
      ..currentWriteId = _nextWriteId++;
    _post(
      _serverSyncTree.applyUserOverwrite(
        path,
        newNodeUnresolved,
        newNode,
        transaction.currentWriteId!,
        visible: transaction.applyLocally,
        persist: false,
      ),
    );
    _sendAllReadyTransactions();
  }

  /// The node of a transaction's [value]: normalised, and with the priority of [current] when
  /// [value] gives none (JS `repoStartTransaction`, `repoRerunTransactionQueue`).
  Node _transactionOutput(Object? value, Node current) {
    final Node node = _normalizeUserNode(nodeFromJson(value));
    final bool explicitPriority =
        value is Map<Object?, Object?> && value.containsKey('.priority');
    return explicitPriority ? node : node.updatePriority(current.priority);
  }

  /// Runs the update function on a fresh mutable copy of [current] (without priority, JS
  /// `val()`); a throw aborts with `user_code_exception` (Android `DatabaseError.fromException`),
  /// the thrown object and its stack trace as the error's cause.
  (TransactionOutcome, DatabaseError?) _runUpdate(
    TransactionData transaction,
    Node current,
  ) {
    try {
      return (transaction.update(current.toJson()), null);
    } on Object catch (e, stackTrace) {
      // The log line has the type only: the text may quote the value the handler was given. The
      // exception and its stack trace stay on the error, for the caller.
      _log(DatabaseLogLevel.error, 'Caught Throwable. ${e.runtimeType}');
      return (
        TransactionOutcome.abort,
        DatabaseError.local(
          DatabaseErrorCode.userCodeException,
          'The transaction update function threw an exception.',
          cause: e,
          causeStackTrace: stackTrace,
        ),
      );
    }
  }

  Node _latestState(
    Path path, [
    List<WriteId> excludeSets = const <WriteId>[],
  ]) =>
      _serverSyncTree.calcCompleteEventCache(
        path,
        writeIdsToExclude: excludeSets,
      ) ??
      ChildrenNode.empty;

  /// Android `Repo.sendAllReadyTransactions`.
  void _sendAllReadyTransactions() {
    _pruneCompletedTransactions(_transactionQueueTree);
    _sendReadyTransactions(_transactionQueueTree);
  }

  /// Android `Repo.sendReadyTransactions`: a queue goes out only when all of it is run (none
  /// sent).
  void _sendReadyTransactions(Tree<List<TransactionData>> node) {
    if (node.value != null) {
      final List<TransactionData> queue = _buildTransactionQueue(node);
      assert(queue.isNotEmpty, 'Sending zero length transaction queue');
      final bool allRun = queue.every(
        (TransactionData t) => t.status == TransactionStatus.run,
      );
      if (allRun) {
        _sendTransactionQueue(queue, node.path);
      }
    } else if (node.hasChildren) {
      node.forEachChild(_sendReadyTransactions);
    }
  }

  /// Android `Repo.sendTransactionQueue`: one hashed put of the latest state with every
  /// transaction's output written in.
  void _sendTransactionQueue(List<TransactionData> queue, Path path) {
    final List<WriteId> setsToIgnore = <WriteId>[
      for (final TransactionData t in queue) t.currentWriteId!,
    ];
    final Node latestState = _latestState(path, setsToIgnore);
    Node snapToSend = latestState;
    final String latestHash = _hijackHash ? 'badhash' : latestState.hash();
    for (final TransactionData transaction in queue) {
      assert(transaction.status == TransactionStatus.run);
      transaction
        ..status = TransactionStatus.sent
        ..retryCount += 1;
      final Path relativePath = Path.relative(path, transaction.path);
      snapToSend = snapToSend.updateChild(
        relativePath,
        transaction.currentOutputSnapshotRaw!,
      );
    }
    _connection.put(
      path.toString(),
      snapToSend.toJson(exportFormat: true),
      hash: latestHash,
      onComplete: (String status, Object? data) {
        if (_closed) {
          return;
        }
        final DatabaseError? error = Repo._errorFor(status, data);
        _warnIfWriteFailed('Transaction', path, error);
        if (error == null) {
          final List<Event> events = <Event>[];
          final List<void Function()> callbacks = <void Function()>[];
          for (final TransactionData transaction in queue) {
            transaction.status = TransactionStatus.completed;
            events.addAll(
              _serverSyncTree.ackUserWrite(
                transaction.currentWriteId!,
                revert: false,
                persist: false,
                serverValues: generateServerValues(),
              ),
            );
            final Node? node = transaction.currentOutputSnapshotResolved;
            callbacks.add(() => transaction.onComplete?.call(null, true, node));
            transaction.unwatcher();
          }
          _pruneCompletedTransactions(_transactionQueueTree.subTree(path));
          _sendAllReadyTransactions();
          _post(events);
          callbacks.forEach(_postCallback);
        } else {
          if (error.code == DatabaseErrorCode.dataStale) {
            for (final TransactionData transaction in queue) {
              transaction.status =
                  transaction.status == TransactionStatus.sentNeedsAbort
                  ? TransactionStatus.needsAbort
                  : TransactionStatus.run;
            }
          } else {
            for (final TransactionData transaction in queue) {
              transaction
                ..status = TransactionStatus.needsAbort
                ..abortReason = error;
            }
          }
          _rerunTransactions(path);
        }
      },
    );
  }

  /// Android `Repo.pruneCompletedTransactions`.
  void _pruneCompletedTransactions(Tree<List<TransactionData>> node) {
    final List<TransactionData>? queue = node.value;
    if (queue != null) {
      queue.removeWhere(
        (TransactionData t) => t.status == TransactionStatus.completed,
      );
      node.value = queue.isEmpty ? null : queue;
    }
    node.forEachChild(_pruneCompletedTransactions);
  }

  /// Reruns the transactions at, above and below [changedPath] from the root-most queue, and
  /// returns that queue's path (Android `Repo.rerunTransactions`).
  Path _rerunTransactions(Path changedPath) {
    final Tree<List<TransactionData>> rootMostTransactionNode =
        _ancestorTransactionNode(changedPath);
    final Path path = rootMostTransactionNode.path;
    final List<TransactionData> queue = _buildTransactionQueue(
      rootMostTransactionNode,
    );
    _rerunTransactionQueue(queue, path);
    return path;
  }

  /// Android `Repo.rerunTransactionQueue`, in transaction order; callbacks run once the queue
  /// state is clean, and the unwatch of an aborted transaction waits a microtask (removing a
  /// listener may prune data the rest of the rerun reads).
  void _rerunTransactionQueue(List<TransactionData> queue, Path path) {
    if (queue.isEmpty) {
      return;
    }
    final List<void Function()> callbacks = <void Function()>[];
    for (int i = 0; i < queue.length; i++) {
      final TransactionData transaction = queue[i];
      assert(path.contains(transaction.path));
      bool abortTransaction = false;
      DatabaseError? abortReason;
      final List<Event> events = <Event>[];
      if (transaction.status == TransactionStatus.needsAbort) {
        abortTransaction = true;
        abortReason = transaction.abortReason;
        if (abortReason?.code != DatabaseErrorCode.writeCanceled) {
          events.addAll(_revert(transaction.currentWriteId!));
        }
      } else if (transaction.status == TransactionStatus.run) {
        if (transaction.retryCount >= maxTransactionRetries) {
          abortTransaction = true;
          abortReason = DatabaseError.fromStatus(
            DatabaseErrorCode.maxRetries.wireStatus,
          );
          events.addAll(_revert(transaction.currentWriteId!));
        } else {
          // Every set of this queue is ignored except the new ones this rerun made; counted
          // here, since a handler's own write may have rerun part of the queue already.
          final Node currentNode = _latestState(transaction.path, <WriteId>[
            for (int j = 0; j < queue.length; j++)
              if (j >= i || queue[j].status != TransactionStatus.run)
                ?queue[j].currentWriteId,
          ]);
          transaction.currentInputSnapshot = currentNode;
          final (TransactionOutcome outcome, DatabaseError? error) = _runUpdate(
            transaction,
            currentNode,
          );
          if (transaction.status != TransactionStatus.run) {
            // The handler wrote or purged over its own path: that abort already reverted the
            // write and queued the callback.
            continue;
          }
          if (outcome is TransactionSuccess) {
            final WriteId oldWriteId = transaction.currentWriteId!;
            final Node newDataNode = _transactionOutput(
              outcome.value,
              currentNode,
            );
            final Node newNodeResolved = server_values
                .resolveDeferredValueSnapshot(
                  newDataNode,
                  currentNode,
                  generateServerValues(),
                );
            transaction
              ..currentOutputSnapshotRaw = newDataNode
              ..currentOutputSnapshotResolved = newNodeResolved
              ..currentWriteId = _nextWriteId++;
            events
              ..addAll(
                _serverSyncTree.applyUserOverwrite(
                  transaction.path,
                  newDataNode,
                  newNodeResolved,
                  transaction.currentWriteId!,
                  visible: transaction.applyLocally,
                  persist: false,
                ),
              )
              ..addAll(_revert(oldWriteId));
          } else {
            // The user aborted: not an error unless the update function threw.
            abortTransaction = true;
            abortReason = error;
            events.addAll(_revert(transaction.currentWriteId!));
          }
        }
      }
      _post(events);
      if (abortTransaction) {
        transaction.status = TransactionStatus.completed;
        final Node? lastInput = transaction.currentInputSnapshot;
        scheduleMicrotask(transaction.unwatcher);
        final DatabaseError? callbackError = abortReason;
        callbacks.add(
          () => transaction.onComplete?.call(callbackError, false, lastInput),
        );
      }
    }
    _pruneCompletedTransactions(_transactionQueueTree);
    callbacks.forEach(_postCallback);
    _sendAllReadyTransactions();
  }

  List<Event> _revert(WriteId writeId) => _serverSyncTree.ackUserWrite(
    writeId,
    revert: true,
    persist: false,
    serverValues: generateServerValues(),
  );

  /// The highest node on [path] that holds a queue, else the node at [path] (Android
  /// `Repo.getAncestorTransactionNode`).
  Tree<List<TransactionData>> _ancestorTransactionNode(Path path) {
    Tree<List<TransactionData>> transactionNode = _transactionQueueTree;
    Path rest = path;
    while (!rest.isEmpty && transactionNode.value == null) {
      transactionNode = transactionNode.subTree(
        Path.fromKeys(<ChildKey>[rest.front!]),
      );
      rest = rest.popFront();
    }
    return transactionNode;
  }

  /// Every transaction at and below [transactionNode], in start order (Android
  /// `Repo.buildTransactionQueue`).
  List<TransactionData> _buildTransactionQueue(
    Tree<List<TransactionData>> transactionNode,
  ) {
    final List<TransactionData> queue = <TransactionData>[];
    void aggregate(Tree<List<TransactionData>> node) {
      queue.addAll(node.value ?? const <TransactionData>[]);
      node.forEachChild(aggregate);
    }

    aggregate(transactionNode);
    queue.sort((TransactionData a, TransactionData b) => a.order - b.order);
    return queue;
  }

  /// Aborts the transactions at, above and below [path] with [reason] (`overriddenBySet` or
  /// `writeCanceled`) and returns the path of the root-most queue (Android
  /// `Repo.abortTransactions`).
  Path _abortTransactions(Path path, DatabaseErrorCode reason) {
    for (final TransactionData running
        in _firstRuns[this] ?? const <TransactionData>[]) {
      if (running.status == TransactionStatus.run &&
          (running.path.contains(path) || path.contains(running.path))) {
        running
          ..status = TransactionStatus.completed
          ..abortReason = DatabaseError.fromStatus(reason.wireStatus);
      }
    }
    final Path affectedPath = _ancestorTransactionNode(path).path;
    final Tree<List<TransactionData>> transactionNode = _transactionQueueTree
        .subTree(path);
    transactionNode.forEachAncestor((Tree<List<TransactionData>> tree) {
      _abortTransactionsAtNode(tree, reason);
      return false;
    });
    _abortTransactionsAtNode(transactionNode, reason);
    transactionNode.forEachDescendant(
      (Tree<List<TransactionData>> tree) =>
          _abortTransactionsAtNode(tree, reason),
    );
    return affectedPath;
  }

  /// Android `Repo.abortTransactionsAtNode`: a sent transaction aborts when its answer comes; the
  /// others abort now (reverted unless the purge already removed their write).
  void _abortTransactionsAtNode(
    Tree<List<TransactionData>> node,
    DatabaseErrorCode reason,
  ) {
    final List<TransactionData>? queue = node.value;
    if (queue == null) {
      return;
    }
    final DatabaseError abortError = DatabaseError.fromStatus(
      reason.wireStatus,
    );
    final List<Event> events = <Event>[];
    final List<void Function()> callbacks = <void Function()>[];
    int lastSent = -1;
    for (int i = 0; i < queue.length; i++) {
      final TransactionData transaction = queue[i];
      if (transaction.status == TransactionStatus.sentNeedsAbort) {
        // Already marked: keep waiting for its answer (JS `repoAbortTransactionsOnNode`).
        assert(lastSent == i - 1, 'All sent items should be first');
        lastSent = i;
      } else if (transaction.status == TransactionStatus.sent) {
        assert(lastSent == i - 1, 'All sent items should be first');
        lastSent = i;
        transaction
          ..status = TransactionStatus.sentNeedsAbort
          ..abortReason = abortError;
      } else if (transaction.status != TransactionStatus.completed) {
        transaction.status = TransactionStatus.completed;
        transaction.unwatcher();
        if (reason == DatabaseErrorCode.overriddenBySet) {
          events.addAll(_revert(transaction.currentWriteId!));
        }
        callbacks.add(
          () => transaction.onComplete?.call(abortError, false, null),
        );
      }
    }
    node.value = lastSent == -1 ? null : queue.sublist(0, lastSent + 1);
    _post(events);
    callbacks.forEach(_postCallback);
  }

  /// Completes every running transaction with [error] and forgets them ([Repo.close]).
  void _failAllTransactions(DatabaseError error) {
    final List<TransactionData> all = _buildTransactionQueue(
      _transactionQueueTree,
    );
    _transactionQueueTree.node.children.clear();
    _transactionQueueTree.value = null;
    for (final TransactionData transaction in all) {
      if (transaction.status != TransactionStatus.completed) {
        transaction.status = TransactionStatus.completed;
        transaction.onComplete?.call(error, false, null);
      }
    }
  }
}

/// Read-only views of Repo's write and transaction state, for tests of the transaction code.
@visibleForTesting
extension RepoTransactionDebug on Repo {
  /// The ids of the user writes neither acknowledged nor reverted yet, oldest first.
  List<WriteId> get debugPendingWriteIds {
    final SyncTreeApi tree = _serverSyncTree;
    if (tree is! SyncTree) {
      throw StateError(
        'debugPendingWriteIds needs the SyncTree Repo builds itself.',
      );
    }
    return <WriteId>[
      for (WriteId id = 0; id < _nextWriteId; id++)
        if (tree.pendingWriteTree.getWrite(id) != null) id,
    ];
  }

  /// Whether the transaction queue tree holds no transaction.
  bool get debugTransactionQueueEmpty =>
      _buildTransactionQueue(_transactionQueueTree).isEmpty;

  /// Whether no listener, the user's or a transaction's, is registered in the server sync tree.
  bool get debugServerSyncTreeEmpty => _serverSyncTree.isEmpty;
}

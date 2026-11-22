// onDisconnect: the requests, the local tree of acknowledged writes, and applying it when the
// connection drops. JS: `core/Repo.ts` (`repoOnDisconnectSet`, `repoOnDisconnectUpdate`,
// `repoOnDisconnectCancel`, `repoRunOnDisconnectEvents`); Android: `core/Repo.java`
// (`onDisconnectSetValue`, `onDisconnectUpdate`, `onDisconnectCancel`, `runOnDisconnectEvents`).
part of 'repo.dart';

extension _RepoOnDisconnect on Repo {
  /// Android `Repo.onDisconnectSetValue`: remembered locally only once the server acknowledged
  /// it (JS `Repo.ts:731-732`).
  void _onDisconnectSetValue(
    Path path,
    Node newValue,
    WriteCompletion? onComplete,
  ) {
    if (_closed) {
      return _failClosed(onComplete);
    }
    final Node value = _normalizeUserNode(newValue);
    final int completion = _track(onComplete);
    _connection.onDisconnectPut(
      path.toString(),
      value.toJson(exportFormat: true),
      onComplete: (String status, Object? data) {
        if (_closed) {
          return;
        }
        final DatabaseError? error = Repo._errorFor(status, data);
        _warnIfWriteFailed('onDisconnect().setValue', path, error);
        if (error == null) {
          _onDisconnect.remember(path, value);
        }
        _complete(completion, error);
      },
    );
  }

  /// Android `Repo.onDisconnectUpdate`; an empty update completes at once without a request (JS
  /// `repoOnDisconnectUpdate`).
  void _onDisconnectUpdate(
    Path path,
    Map<Path, Node> newChildren,
    Map<String, Object?> unparsedUpdates,
    WriteCompletion? onComplete,
  ) {
    if (_closed) {
      return _failClosed(onComplete);
    }
    if (newChildren.isEmpty) {
      _log(
        DatabaseLogLevel.debug,
        "onDisconnect().update() called with empty data. Don't do anything.",
      );
      if (onComplete != null) {
        scheduleMicrotask(() => onComplete(null));
      }
      return;
    }
    final Map<Path, Node> children = <Path, Node>{
      for (final MapEntry<Path, Node> entry in newChildren.entries)
        entry.key: _normalizeUserNode(entry.value),
    };
    final int completion = _track(onComplete);
    _connection.onDisconnectMerge(
      path.toString(),
      _normalizeUserJson(unparsedUpdates)! as Map<String, Object?>,
      onComplete: (String status, Object? data) {
        if (_closed) {
          return;
        }
        final DatabaseError? error = Repo._errorFor(status, data);
        _warnIfWriteFailed('onDisconnect().updateChildren', path, error);
        if (error == null) {
          for (final MapEntry<Path, Node> entry in children.entries) {
            _onDisconnect.remember(path.childPath(entry.key), entry.value);
          }
        }
        _complete(completion, error);
      },
    );
  }

  /// Android `Repo.onDisconnectCancel`.
  void _onDisconnectCancel(Path path, WriteCompletion? onComplete) {
    if (_closed) {
      return _failClosed(onComplete);
    }
    final int completion = _track(onComplete);
    _connection.onDisconnectCancel(
      path.toString(),
      onComplete: (String status, Object? data) {
        if (_closed) {
          return;
        }
        final DatabaseError? error = Repo._errorFor(status, data);
        if (error == null) {
          _onDisconnect.forget(path);
        }
        _complete(completion, error);
      },
    );
  }

  /// Applies every remembered write as server data, aborting the transactions it overrides, then
  /// forgets them (Android `Repo.runOnDisconnectEvents`; JS `repoRunOnDisconnectEvents`). Each
  /// write's events are queued before its transactions rerun.
  void _runOnDisconnectEvents() {
    final Map<String, Object?> serverValues = generateServerValues();
    final SparseSnapshotTree tree = _onDisconnect;
    _onDisconnect = SparseSnapshotTree();
    tree.forEachTree(Path.empty, (Path path, Node node) {
      final Node existing =
          _serverSyncTree.calcCompleteEventCache(path) ?? ChildrenNode.empty;
      final Node resolved = server_values.resolveDeferredValueSnapshot(
        node,
        existing,
        serverValues,
      );
      _post(_serverSyncTree.applyServerOverwrite(path, resolved));
      final Path affectedPath = _abortTransactions(
        path,
        DatabaseErrorCode.overriddenBySet,
      );
      _rerunTransactions(affectedPath);
    });
  }
}

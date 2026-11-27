// What the connection tells Repo, and the `.info` data. JS: `core/Repo.ts` (`repoOnDataUpdate`,
// `repoOnConnectStatus`, `repoOnServerInfoUpdate`, `repoUpdateInfo`); Android: `core/Repo.java`
// (the `PersistentConnection.Delegate` methods, `updateInfo`).
part of 'repo.dart';

extension _RepoServerActions on Repo {
  /// Android `Repo.onDataUpdate`; JS `repoOnDataUpdate`. The update's events are queued before
  /// the transactions under the path rerun.
  void _onDataUpdate(
    String wirePath,
    Object? data, {
    required bool isMerge,
    int? tag,
  }) {
    if (_closed) {
      return;
    }
    final Path path = Path(wirePath);
    _log(DatabaseLogLevel.debug, 'onDataUpdate: $path');
    _dataUpdateCount++;
    // Read first, then apply, so the log line can say which failed. Each logs the error's type
    // and a fixed reason only: the error's text can quote the data (Android logs both as an
    // internal error).
    final Map<Path, Node>? children;
    final Node? node;
    try {
      children = isMerge ? _changedChildren(data) : null;
      node = isMerge ? null : nodeFromServerJson(data);
    } on Object catch (e) {
      _log(
        DatabaseLogLevel.error,
        'FIREBASE INTERNAL ERROR at $path: the server sent data the client cannot read '
        '(${e.runtimeType})',
      );
      return;
    }
    final List<Event> events;
    try {
      if (children != null) {
        events = tag == null
            ? _serverSyncTree.applyServerMerge(path, children)
            : _serverSyncTree.applyTaggedQueryMerge(path, children, Tag(tag));
      } else {
        events = tag == null
            ? _serverSyncTree.applyServerOverwrite(path, node!)
            : _serverSyncTree.applyTaggedQueryOverwrite(path, node!, Tag(tag));
      }
    } on Object catch (e) {
      _log(
        DatabaseLogLevel.error,
        'FIREBASE INTERNAL ERROR at $path: applying server data failed, in the local cache '
        'or the client (${e.runtimeType})',
      );
      return;
    }
    _post(events);
    if (events.isNotEmpty) {
      // A transaction keeps a listener on its path, so events are a proxy for a change there.
      _rerunTransactions(path);
    }
  }

  static Map<Path, Node> _changedChildren(Object? data) => <Path, Node>{
    for (final MapEntry<Object?, Object?> entry
        in (data! as Map<Object?, Object?>).entries)
      Path('${entry.key}'): nodeFromServerJson(entry.value),
  };

  /// Android `Repo.onRangeMergeUpdate`.
  void _onRangeMergeUpdate(
    String wirePath,
    List<WireRangeMerge> merges, {
    int? tag,
  }) {
    if (_closed) {
      return;
    }
    final Path path = Path(wirePath);
    _log(DatabaseLogLevel.debug, 'onRangeMergeUpdate: $path');
    _dataUpdateCount++;
    // Read first, then apply, logged as in _onDataUpdate: the error's type and a fixed reason.
    final List<RangeMerge> parsed;
    try {
      parsed = <RangeMerge>[
        for (final WireRangeMerge merge in merges) RangeMerge.fromWire(merge),
      ];
    } on Object catch (e) {
      _log(
        DatabaseLogLevel.error,
        'FIREBASE INTERNAL ERROR at $path: the server sent a range merge the client cannot '
        'read (${e.runtimeType})',
      );
      return;
    }
    final List<Event> events;
    try {
      events = tag != null
          ? _serverSyncTree.applyTaggedRangeMerges(path, parsed, Tag(tag))
          : _serverSyncTree.applyServerRangeMerges(path, parsed);
    } on Object catch (e) {
      _log(
        DatabaseLogLevel.error,
        'FIREBASE INTERNAL ERROR at $path: applying a server range merge failed, in the local '
        'cache or the client (${e.runtimeType})',
      );
      return;
    }
    _post(events);
    if (events.isNotEmpty) {
      _rerunTransactions(path);
    }
  }

  /// Android `Repo.onConnect`; the `get` wait of contract C25 stops while connected.
  void _onConnect() {
    if (_closed) {
      return;
    }
    _connected = true;
    _updateInfo('connected', true);
    for (final _PendingGet request in _pendingGets) {
      request.timer?.cancel();
      request.timer = null;
    }
  }

  /// Android `Repo.onDisconnect` and `runOnDisconnectEvents`; JS `repoOnConnectStatus` and
  /// `repoRunOnDisconnectEvents`. The `.info/connected` false event comes first (rule 4.14).
  void _onDisconnected() {
    if (_closed) {
      return;
    }
    _connected = false;
    _updateInfo('connected', false);
    _runOnDisconnectEvents();
    for (final _PendingGet request in _pendingGets.toList()) {
      _startGetWait(request);
    }
  }

  /// Android `Repo.onConnectionStatus` (`.info/authenticated`); a revoke is logged.
  void _onAuthStatus(String status, String? explanation) {
    if (_closed) {
      return;
    }
    final bool ok = status == statusOk;
    if (!ok) {
      _log(
        DatabaseLogLevel.warning,
        'Authentication failed: $status'
        '${explanation == null ? '' : ' ($explanation)'}',
      );
    }
    _updateInfo('authenticated', ok);
  }

  /// JS `PersistentConnection.onAppCheckRevoked_` logs the revoke.
  void _onAppCheckStatus(String status, String? explanation) {
    if (status != statusOk) {
      _log(
        DatabaseLogLevel.warning,
        'App Check failed: $status'
        '${explanation == null ? '' : ' ($explanation)'}',
      );
    }
  }

  /// Writes [value] to `.info/<key>` and raises its events; `serverTimeOffset` also moves the
  /// server clock. Android `Repo.updateInfo`; JS `repoUpdateInfo`.
  void _updateInfo(String key, Object? value) {
    if (_closed) {
      return;
    }
    if (key == 'serverTimeOffset' && value is num) {
      _serverClock.offsetMillis = value.toInt();
    }
    final Path path = Path.fromKeys(<ChildKey>[ChildKey.info, ChildKey(key)]);
    try {
      final Node node = nodeFromJson(value);
      _infoData.updateSnapshot(path, node);
      _post(_infoSyncTree.applyServerOverwrite(path, node));
    } on Object catch (e) {
      // The type only, as every other parse failure (the values are the client's own).
      _log(
        DatabaseLogLevel.error,
        'Failed to parse info update for $key: ${e.runtimeType}',
      );
    }
  }
}

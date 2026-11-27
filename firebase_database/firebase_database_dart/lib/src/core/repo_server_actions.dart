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
    final List<Event> events;
    try {
      if (tag != null) {
        if (isMerge) {
          events = _serverSyncTree.applyTaggedQueryMerge(
            path,
            _changedChildren(data),
            Tag(tag),
          );
        } else {
          events = _serverSyncTree.applyTaggedQueryOverwrite(
            path,
            nodeFromJson(data),
            Tag(tag),
          );
        }
      } else if (isMerge) {
        events = _serverSyncTree.applyServerMerge(path, _changedChildren(data));
      } else {
        events = _serverSyncTree.applyServerOverwrite(path, nodeFromJson(data));
      }
    } on Object catch (e) {
      // The server sent data the client cannot read; Android logs it as an internal error. The
      // error's text can quote that data, so only its type is logged.
      _log(
        DatabaseLogLevel.error,
        'FIREBASE INTERNAL ERROR at $path: ${e.runtimeType}',
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
      Path('${entry.key}'): nodeFromJson(entry.value),
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
    final List<RangeMerge> parsed = <RangeMerge>[
      for (final WireRangeMerge merge in merges) RangeMerge.fromWire(merge),
    ];
    final List<Event> events = tag != null
        ? _serverSyncTree.applyTaggedRangeMerges(path, parsed, Tag(tag))
        : _serverSyncTree.applyServerRangeMerges(path, parsed);
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
      _log(DatabaseLogLevel.error, 'Failed to parse info update: $e');
    }
  }
}

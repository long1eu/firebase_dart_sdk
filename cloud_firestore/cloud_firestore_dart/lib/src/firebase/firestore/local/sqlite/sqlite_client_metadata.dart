part of 'sqlite_persistence.dart';

/// The current time in milliseconds since the epoch. Injectable so that tests can move it.
typedef Clock = int Function();

int _systemClock() => DateTime.now().millisecondsSinceEpoch;

/// How a client takes the primary lease of a cache that another client holds.
enum PrimaryLeaseMode {
  /// The client takes the lease when it starts, also from a client that still holds it, and logs a warning when it
  /// does. Afterwards it competes for the lease like [multipleClients]. The default while the clients are not
  /// coordinated (stage 1 of the multi-client plan): a second client keeps working as before.
  forceOwnership,

  /// The election of the JS SDK with tab synchronization: a valid lease of another client is respected.
  multipleClients,
}

/// The lease as stored in the `primary_client` table.
class _PrimaryLease {
  const _PrimaryLease(this.ownerId, this.allowSynchronization, this.timestamp);

  final String ownerId;
  final bool allowSynchronization;
  final int timestamp;
}

/// The metadata of one client of a SQLite cache and its part in the election of the primary client: the client
/// that, once clients are coordinated, talks to the backend and does the work that only one client may do.
///
/// A port of the client metadata and primary lease of `IndexedDbPersistence` of the JS SDK, with the same constants.
/// Every client writes its row in the `clients` table at start and every [refreshInterval]. The primary writes its id
/// and the time into the single row of `primary_client`; the lease is valid for [maxPrimaryEligibleAgeMs]. A client
/// that terminates releases the lease and removes its row, so that another client takes over at its next refresh;
/// one that dies keeps the lease until it expires. The primary removes the rows of clients that did not refresh for
/// [maxClientAgeMs].
///
/// PORTING NOTE: the JS SDK also marks a closing tab as "zombied" in LocalStorage, because IndexedDB cannot be used
/// reliably while a page unloads. A Dart client releases the lease in a transaction when it terminates instead; a
/// client that dies without terminating is noticed when its lease expires.
///
/// All methods run inside a transaction of [SQLitePersistence], which holds the write lock.
class SQLiteClientMetadata {
  SQLiteClientMetadata._(
    this._persistence,
    this.clientId,
    this._clock,
    this.mode,
  );

  /// Oldest acceptable age of the metadata of a client before the client is considered gone and its row is removed.
  static const int maxClientAgeMs = 30 * 60 * 1000;

  /// Oldest acceptable age of a lease, and of the metadata of a client that may take part in the election.
  static const int maxPrimaryEligibleAgeMs = 5000;

  /// How often a client writes its metadata and refreshes or tries to take the lease.
  static const Duration refreshInterval = Duration(milliseconds: 4000);

  static const String _tag = 'PrimaryLease';

  final SQLitePersistence _persistence;

  /// The id of this client, unique per instance.
  final String clientId;
  final Clock _clock;
  final PrimaryLeaseMode mode;

  Database get _db => _persistence._db;

  bool _isPrimary = false;

  /// Whether this client held the lease the last time it looked.
  bool get isPrimary => _isPrimary;

  /// Whether the network of this client is enabled: a client without network is a worse primary.
  bool networkEnabled = true;

  /// Whether the application of this client is in the foreground. Always true on the VM so far.
  bool inForeground = true;

  /// Called when [isPrimary] changes.
  void Function(bool isPrimary)? primaryStateListener;

  int _lastGarbageCollectionTime = -maxClientAgeMs;

  bool get _allowSynchronization => mode == PrimaryLeaseMode.multipleClients;

  void _setPrimary(bool isPrimary) {
    if (_isPrimary != isPrimary) {
      Log.d(
        _tag,
        'Client $clientId ${isPrimary ? 'is' : 'is no longer'} primary',
      );
      _isPrimary = isPrimary;
      primaryStateListener?.call(isPrimary);
    }
  }

  /// How often at most the warnings about the rows of the file are logged: a row in the future (or a malformed one)
  /// is seen at every refresh, every 4 s, for as long as it is there.
  static const int _warningIntervalMs = 60 * 1000;

  /// When each kind of warning was last logged, see [_warnRateLimited].
  final Map<String, int> _lastWarnings = <String, int>{};

  /// Logs [message] unless a warning of the same [kind] was logged within [_warningIntervalMs].
  void _warnRateLimited(String kind, String message) {
    final int now = _clock();
    final int? last = _lastWarnings[kind];
    if (last != null && now >= last && now - last < _warningIntervalMs) {
      return;
    }
    _lastWarnings[kind] = now;
    Log.w(_tag, message);
  }

  bool _isWithinAge(int updateTimeMs, int maxAgeMs) {
    final int now = _clock();
    if (updateTimeMs < now - maxAgeMs) {
      return false;
    } else if (updateTimeMs > now) {
      _warnRateLimited(
        'future',
        'Detected an update time that is in the future: $updateTimeMs > $now',
      );
      return false;
    }
    return true;
  }

  /// The lease, or null when there is none. The columns are typed by affinity only, so a row written by something
  /// else than this SDK (or a damaged file) can hold any value: such a row counts as no lease, and is overwritten by
  /// the next client that takes the lease, instead of failing the start of every client.
  Future<_PrimaryLease?> _readLease() async {
    final List<Map<String, dynamic>> rows = await _db.query(
      'SELECT owner_id, allow_synchronization, lease_timestamp_ms FROM primary_client WHERE id = 0',
    );
    if (rows.isEmpty) {
      return null;
    }
    final Map<String, dynamic> row = rows.single;
    final Object? ownerId = row['owner_id'];
    final Object? allowSynchronization = row['allow_synchronization'];
    final Object? timestamp = row['lease_timestamp_ms'];
    if (ownerId is! String ||
        allowSynchronization is! int ||
        timestamp is! int) {
      _warnRateLimited(
        'lease',
        'Ignoring a malformed primary lease: ($ownerId, $allowSynchronization, $timestamp)',
      );
      return null;
    }
    return _PrimaryLease(ownerId, allowSynchronization != 0, timestamp);
  }

  bool _isValid(_PrimaryLease? lease) =>
      lease != null && _isWithinAge(lease.timestamp, maxPrimaryEligibleAgeMs);

  Future<void> _writeOwnMetadata() async {
    await _db.execute(
      'INSERT OR REPLACE INTO clients (client_id, update_time_ms, network_enabled, in_foreground) '
      'VALUES (?, ?, ?, ?)',
      <Object?>[
        clientId,
        _clock(),
        networkEnabled ? 1 : 0,
        inForeground ? 1 : 0,
      ],
    );
  }

  Future<void> _acquireOrExtendLease() async {
    await _db.execute(
      'INSERT OR REPLACE INTO primary_client (id, owner_id, allow_synchronization, lease_timestamp_ms) '
      'VALUES (0, ?, ?, ?)',
      <Object?>[clientId, _allowSynchronization ? 1 : 0, _clock()],
    );
  }

  Future<void> _releaseLeaseIfHeld() async {
    await _db.execute(
      'DELETE FROM primary_client WHERE id = 0 AND owner_id = ?',
      <Object?>[clientId],
    );
  }

  /// Whether this client may hold the lease now (`canActAsPrimary` of the JS SDK).
  ///
  /// PORTING NOTE: the JS SDK fails here when the lease is held by a client that does not allow tab
  /// synchronization. Until the clients are coordinated nobody is refused (decision 6 of the multi-client plan).
  Future<bool> _canActAsPrimary() async {
    final _PrimaryLease? lease = await _readLease();
    if (_isValid(lease)) {
      final bool isLocal = lease!.ownerId == clientId;
      if (isLocal && networkEnabled) {
        return true;
      }
      if (!isLocal) {
        return false;
      }
    }

    if (networkEnabled && inForeground) {
      return true;
    }

    // The lease is free or ours without network: keep or take it unless another active client is a better choice.
    final int minimum = _clock() - maxPrimaryEligibleAgeMs;
    final List<Map<String, dynamic>> others = await _db.query(
      'SELECT update_time_ms, network_enabled, in_foreground FROM clients WHERE client_id != ? AND update_time_ms >= ?',
      <Object?>[clientId, minimum],
    );
    for (final Map<String, dynamic> other in others) {
      final Object? updateTime = other['update_time_ms'];
      final Object? network = other['network_enabled'];
      final Object? foreground = other['in_foreground'];
      // A malformed row is not a client that takes part in the election.
      if (updateTime is! int ||
          network is! int ||
          foreground is! int ||
          !_isWithinAge(updateTime, maxPrimaryEligibleAgeMs)) {
        continue;
      }
      final bool otherNetwork = network != 0;
      final bool otherForeground = foreground != 0;
      final bool betterNetwork = !networkEnabled && otherNetwork;
      final bool betterVisibility =
          !inForeground && otherForeground && networkEnabled == otherNetwork;
      if (betterNetwork || betterVisibility) {
        return false;
      }
    }
    return true;
  }

  /// Writes the metadata of this client and refreshes, takes or releases the lease
  /// (`updateClientMetadataAndTryBecomePrimary` of the JS SDK). With [atStart] in [PrimaryLeaseMode.forceOwnership]
  /// the lease is taken whoever holds it.
  Future<void> _update({bool atStart = false}) async {
    await _writeOwnMetadata();

    if (_isPrimary) {
      final _PrimaryLease? lease = await _readLease();
      if (lease?.ownerId != clientId) {
        _setPrimary(false);
      }
    }

    bool canActAsPrimary;
    if (atStart && mode == PrimaryLeaseMode.forceOwnership) {
      final _PrimaryLease? lease = await _readLease();
      if (_isValid(lease) && lease!.ownerId != clientId) {
        Log.w(
          _tag,
          'Another client (${lease.ownerId}) is using the persistent cache "${_persistence.databaseName}". This '
          'client takes over as its primary client. Clients that share a cache are not coordinated yet: both work '
          'on the cache, and neither sees the listeners and pending writes of the other until it reads the cache '
          'again. Expected after a hot restart; otherwise use a different app name or database for each client.',
        );
      }
      canActAsPrimary = true;
    } else {
      canActAsPrimary = await _canActAsPrimary();
    }

    if (_isPrimary && !canActAsPrimary) {
      await _releaseLeaseIfHeld();
      _setPrimary(false);
    } else if (canActAsPrimary) {
      await _acquireOrExtendLease();
      _setPrimary(true);
    } else {
      _setPrimary(false);
    }
  }

  /// The check of a primary-only transaction (`verifyPrimaryLease` and `canActAsPrimary` in `runTransaction` of the
  /// JS SDK): passes when this client owns the lease (whatever its age: a lone client whose isolate was paused keeps
  /// working) or may take it now; otherwise this client is not primary any more and the transaction fails.
  Future<void> _verifyPrimaryLease(String action) async {
    final _PrimaryLease? lease = await _readLease();
    if (lease?.ownerId == clientId || await _canActAsPrimary()) {
      return;
    }
    Log.w(_tag, 'Failed to obtain the primary lease for action "$action".');
    _setPrimary(false);
    throw FirestoreError(
      primaryLeaseLostErrorMessage,
      FirestoreErrorCode.failedPrecondition,
    );
  }

  /// Extends the lease after the operation of a primary-only transaction, or takes it when
  /// [_verifyPrimaryLease] found that this client may.
  Future<void> _extendPrimaryLease() async {
    await _acquireOrExtendLease();
    _setPrimary(true);
  }

  /// After another connection committed: notices that this client lost the lease. Taking it is left to the next
  /// refresh.
  Future<void> _onForeignCommit() async {
    if (_isPrimary) {
      final _PrimaryLease? lease = await _readLease();
      if (lease?.ownerId != clientId) {
        _setPrimary(false);
      }
    }
  }

  /// The primary removes the rows of clients that did not refresh for [maxClientAgeMs], at most once per that time
  /// (`maybeGarbageCollectMultiClientState` of the JS SDK).
  Future<int> _maybeGarbageCollect() async {
    if (!_isPrimary ||
        _isWithinAge(_lastGarbageCollectionTime, maxClientAgeMs)) {
      return 0;
    }
    _lastGarbageCollectionTime = _clock();
    final int now = _clock();
    return _db.delete(
      'DELETE FROM clients WHERE client_id != ? AND (update_time_ms < ? OR update_time_ms > ?)',
      <Object?>[clientId, now - maxClientAgeMs, now],
    );
  }

  /// The ids of the clients that refreshed their metadata within [maxClientAgeMs], this one included.
  Future<List<String>> _activeClients() async {
    final List<Map<String, dynamic>> rows = await _db.query(
      'SELECT client_id, update_time_ms FROM clients ORDER BY client_id',
    );
    return <String>[
      for (final Map<String, dynamic> row in rows)
        if (row['client_id'] case final String id
            when row['update_time_ms'] is int &&
                _isWithinAge(row['update_time_ms'] as int, maxClientAgeMs))
          id,
    ];
  }

  /// Releases the lease and removes the row of this client, when it terminates.
  Future<void> _remove() async {
    await _releaseLeaseIfHeld();
    await _db.execute('DELETE FROM clients WHERE client_id = ?', <Object?>[
      clientId,
    ]);
    _setPrimary(false);
  }
}

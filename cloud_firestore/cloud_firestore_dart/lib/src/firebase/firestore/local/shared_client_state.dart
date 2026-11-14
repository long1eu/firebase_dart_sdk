// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/listent_sequence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/shared_client_state_storage.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:meta/meta.dart';

/// The id of a client (a Firestore instance) of a persistence shared by several clients.
typedef ClientId = String;

/// The state of a mutation batch, as the clients of a shared persistence see it.
enum MutationBatchState {
  pending('pending'),
  acknowledged('acknowledged'),
  rejected('rejected');

  const MutationBatchState(this.jsonName);

  /// The name in the stored entries (as the JS SDK).
  final String jsonName;

  static MutationBatchState? fromJsonName(Object? name) {
    for (final MutationBatchState state in values) {
      if (state.jsonName == name) {
        return state;
      }
    }
    return null;
  }
}

/// The state of a query target, as the clients of a shared persistence see it.
enum QueryTargetState {
  notCurrent('not-current'),
  current('current'),
  rejected('rejected');

  const QueryTargetState(this.jsonName);

  /// The name in the stored entries (as the JS SDK).
  final String jsonName;

  static QueryTargetState? fromJsonName(Object? name) {
    for (final QueryTargetState state in values) {
      if (state.jsonName == name) {
        return state;
      }
    }
    return null;
  }
}

/// The callbacks of a [SharedClientState] into the sync engine of its client (the JS `SharedClientStateSyncer`).
abstract class SharedClientStateSyncer {
  /// Applies a mutation state to an existing batch.
  Future<void> applyBatchState(
    int batchId,
    MutationBatchState state,
    FirestoreError? error,
  );

  /// Applies a query target change from a different client.
  Future<void> applyTargetState(
    int targetId,
    QueryTargetState state,
    FirestoreError? error,
  );

  /// Adds or removes Watch targets for queries from different clients.
  Future<void> applyActiveTargetsChange(List<int> added, List<int> removed);

  /// Returns the ids of the clients that are currently active.
  Future<List<ClientId>> getActiveClients();

  /// Retrieves newly changed documents of [collectionGroup] from the remote document cache and raises snapshots if
  /// needed.
  Future<void> synchronizeWithChangedDocuments(String collectionGroup);
}

/// Keeps track of the global state of the mutations and query targets of all the active clients of one persistence,
/// relays the local changes to the other clients and applies theirs (the JS `SharedClientState`).
///
/// [syncEngine] and [onlineStateHandler] have to be set before [start] is called.
abstract class SharedClientState {
  static const String _tag = 'SharedClientState';

  SharedClientStateSyncer? syncEngine;

  void Function(OnlineState onlineState)? onlineStateHandler;

  void Function(int sequenceNumber)? sequenceNumberHandler;

  /// Whether the state is shared with other clients (and a secondary client gets the online state of the primary
  /// client from it).
  bool get sharesState;

  /// Registers the batch id of a newly pending mutation.
  void addPendingMutation(int batchId);

  /// Records that a pending mutation has been acknowledged or rejected. Called by the primary client to notify the
  /// secondary clients of the results of the mutations as they come back from the backend.
  void updateMutationState(
    int batchId,
    MutationBatchState state, [
    FirestoreError? error,
  ]);

  /// Associates a target id with the local client and returns the state of the target (which can be
  /// [QueryTargetState.current] if another client listens to it already).
  ///
  /// A target that is only listened to from the cache is not registered as an active watch target
  /// ([addToActiveTargetIds] false).
  QueryTargetState addLocalQueryTarget(
    int targetId, {
    bool addToActiveTargetIds = true,
  });

  /// Removes the association of the target id with the local client.
  void removeLocalQueryTarget(int targetId);

  /// Whether the target is associated with the local client.
  bool isLocalQueryTarget(int targetId);

  /// Processes an update of a query target. Called by the primary client to notify the secondary clients of document
  /// changes or state transitions of the target.
  void updateQueryState(
    int targetId,
    QueryTargetState state, [
    FirestoreError? error,
  ]);

  /// Removes the metadata entry of the target. Called by the primary client when all clients stopped listening to it.
  void clearQueryState(int targetId);

  /// The ids of the targets that any active client listens to.
  SplayTreeSet<int> getAllActiveQueryTargets();

  /// Whether any active client listens to the target.
  bool isActiveQueryTarget(int targetId);

  /// Starts the shared state: reads the existing client data and starts applying the updates of the other clients.
  Future<void> start();

  /// Shuts the shared state down and unregisters the local client.
  void shutdown();

  /// Changes the active user and removes all user-specific data. Does not call back into the sync engine.
  void handleUserChange(
    User user,
    List<int> removedBatchIds,
    List<int> addedBatchIds,
  );

  /// Changes the shared online state of all clients.
  void setOnlineState(OnlineState onlineState);

  void writeSequenceNumber(int sequenceNumber);

  /// Notifies the other clients that remote documents of [collectionGroups] changed because a bundle was loaded.
  void notifyBundleLoaded(Set<String> collectionGroups);
}

/// The names of the error codes in the state the clients share, indexed by the value of the code: the code strings
/// of the JS SDK. They are stored, so they are spelled out here and do not come from `FirestoreErrorCode.toString()`.
const List<String> _storedErrorCodes = <String>[
  'ok',
  'cancelled',
  'unknown',
  'invalid-argument',
  'deadline-exceeded',
  'not-found',
  'already-exists',
  'permission-denied',
  'resource-exhausted',
  'failed-precondition',
  'aborted',
  'out-of-range',
  'unimplemented',
  'internal',
  'unavailable',
  'data-loss',
  'unauthenticated',
];

Map<String, String> _errorToJson(FirestoreError error) => <String, String>{
  'code': _storedErrorCodes[error.code.value],
  'message': error.message,
};

/// Parses `{code, message}`; returns null if the data is not valid.
FirestoreError? _errorFromJson(Object? json) {
  if (json is! Map<String, dynamic> ||
      json['code'] is! String ||
      json['message'] is! String) {
    return null;
  }
  final int value = _storedErrorCodes.indexOf(json['code'] as String);
  if (value != -1) {
    return FirestoreError(
      json['message'] as String,
      FirestoreErrorCode.values[value],
    );
  }
  return null;
}

Object? _tryDecode(String value) {
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}

/// The state of a mutation batch: its user, batch id and whether it is pending, acknowledged or rejected.
@visibleForTesting
class MutationMetadata {
  MutationMetadata(this.user, this.batchId, this.state, [this.error])
    : assert(
        (error != null) == (state == MutationBatchState.rejected),
        'MutationMetadata must contain an error iff state is rejected',
      );

  final User user;
  final int batchId;
  final MutationBatchState state;
  final FirestoreError? error;

  /// Parses the stored form. Logs and returns null if the data is not valid.
  static MutationMetadata? fromStorageEntry(
    User user,
    int batchId,
    String value,
  ) {
    final Object? json = _tryDecode(value);
    MutationBatchState? state;
    FirestoreError? error;
    bool validData = json is Map<String, dynamic>;
    if (json is Map<String, dynamic>) {
      state = MutationBatchState.fromJsonName(json['state']);
      validData = state != null;
      if (validData && json['error'] != null) {
        error = _errorFromJson(json['error']);
        validData = error != null;
      }
      validData =
          validData &&
          (error != null) == (state == MutationBatchState.rejected);
    }
    if (!validData) {
      Log.e(
        SharedClientState._tag,
        'Failed to parse mutation state for ID \'$batchId\': $value',
      );
      return null;
    }
    return MutationMetadata(user, batchId, state!, error);
  }

  String toStorageJson() {
    return jsonEncode(<String, Object>{
      'state': state.jsonName,
      // Modify the existing value to trigger an update.
      'updateTimeMs': DateTime.now().millisecondsSinceEpoch,
      if (error != null) 'error': _errorToJson(error!),
    });
  }
}

/// The state of a query target: whether it is not current, current or rejected.
@visibleForTesting
class QueryTargetMetadata {
  QueryTargetMetadata(this.targetId, this.state, [this.error])
    : assert(
        (error != null) == (state == QueryTargetState.rejected),
        'QueryTargetMetadata must contain an error iff state is rejected',
      );

  final int targetId;
  final QueryTargetState state;
  final FirestoreError? error;

  /// Parses the stored form. Logs and returns null if the data is not valid.
  static QueryTargetMetadata? fromStorageEntry(int targetId, String value) {
    final Object? json = _tryDecode(value);
    QueryTargetState? state;
    FirestoreError? error;
    bool validData = json is Map<String, dynamic>;
    if (json is Map<String, dynamic>) {
      state = QueryTargetState.fromJsonName(json['state']);
      validData = state != null;
      if (validData && json['error'] != null) {
        error = _errorFromJson(json['error']);
        validData = error != null;
      }
      validData =
          validData && (error != null) == (state == QueryTargetState.rejected);
    }
    if (!validData) {
      Log.e(
        SharedClientState._tag,
        'Failed to parse target state for ID \'$targetId\': $value',
      );
      return null;
    }
    return QueryTargetMetadata(targetId, state!, error);
  }

  String toStorageJson() {
    return jsonEncode(<String, Object>{
      'state': state.jsonName,
      // Modify the existing value to trigger an update.
      'updateTimeMs': DateTime.now().millisecondsSinceEpoch,
      if (error != null) 'error': _errorToJson(error!),
    });
  }
}

/// The query targets a client actively listens to.
abstract class ClientState {
  Set<int> get activeTargetIds;
}

/// The immutable state of another client, read from the storage.
class _RemoteClientState implements ClientState {
  _RemoteClientState(this.clientId, this.activeTargetIds);

  final ClientId clientId;

  @override
  final Set<int> activeTargetIds;

  /// Parses the stored form. Logs and returns null if the data is not valid.
  static _RemoteClientState? fromStorageEntry(ClientId clientId, String value) {
    final Object? json = _tryDecode(value);
    if (json is Map<String, dynamic> && json['activeTargetIds'] is List) {
      final List<dynamic> ids = json['activeTargetIds'] as List<dynamic>;
      if (ids.every((dynamic id) => id is int)) {
        return _RemoteClientState(clientId, SplayTreeSet<int>.of(ids.cast()));
      }
    }
    Log.e(
      SharedClientState._tag,
      'Failed to parse client data for instance \'$clientId\': $value',
    );
    return null;
  }
}

/// The online state of the clients of a persistence. Only written by the primary client, and used by the secondary
/// clients to update their views.
@visibleForTesting
class SharedOnlineState {
  const SharedOnlineState(this.clientId, this.onlineState);

  final ClientId clientId;
  final OnlineState onlineState;

  /// The names in the stored entries (as the JS SDK).
  static const Map<OnlineState, String> _names = <OnlineState, String>{
    OnlineState.unknown: 'Unknown',
    OnlineState.online: 'Online',
    OnlineState.offline: 'Offline',
  };

  /// Parses the stored form. Logs and returns null if the data is not valid.
  static SharedOnlineState? fromStorageEntry(String value) {
    final Object? json = _tryDecode(value);
    if (json is Map<String, dynamic> && json['clientId'] is String) {
      for (final MapEntry<OnlineState, String> entry in _names.entries) {
        if (entry.value == json['onlineState']) {
          return SharedOnlineState(json['clientId'] as String, entry.key);
        }
      }
    }
    Log.e(SharedClientState._tag, 'Failed to parse online state: $value');
    return null;
  }

  String toStorageJson() => jsonEncode(<String, String>{
    'clientId': clientId,
    'onlineState': _names[onlineState]!,
  });
}

/// The mutable state of the local client: the query targets it listens to.
@visibleForTesting
class LocalClientState implements ClientState {
  @override
  final SplayTreeSet<int> activeTargetIds = SplayTreeSet<int>();

  void addQueryTarget(int targetId) => activeTargetIds.add(targetId);

  void removeQueryTarget(int targetId) => activeTargetIds.remove(targetId);

  /// The stored form. The client id is part of the key.
  String toStorageJson() => jsonEncode(<String, Object>{
    'activeTargetIds': activeTargetIds.toList(),
    // Modify the existing value to trigger an update.
    'updateTimeMs': DateTime.now().millisecondsSinceEpoch,
  });
}

/// The [SharedClientState] of a client whose persistence is shared with other clients: the state lives in a
/// [SharedClientStateStorage] that notifies the other clients of every change (the port of the JS
/// `WebStorageSharedClientState`, with the same keys and values).
///
/// The changes of the other clients are applied with [enqueue], which must run them one after the other on the queue
/// of the client (the JS `AsyncQueue.enqueueRetryable`).
class StorageSharedClientState extends SharedClientState {
  @override
  bool get sharesState => true;

  StorageSharedClientState(
    this._storage,
    this._enqueue,
    this._persistenceKey,
    this._localClientId,
    User initialUser,
  ) : assert(
        !_localClientId.contains('_'),
        'Client key cannot contain \'_\', but was \'$_localClientId\'',
      ),
      _currentUser = initialUser {
    final String escapedPersistenceKey = RegExp.escape(_persistenceKey);
    _localClientStorageKey = clientStateKey(_persistenceKey, _localClientId);
    _sequenceNumberKey = '${sequenceNumberKeyPrefix}_$_persistenceKey';
    _onlineStateKey = '${onlineStateKeyPrefix}_$_persistenceKey';
    _bundleLoadedKey = '${bundleLoadedKeyPrefix}_$_persistenceKey';
    _clientStateKeyRe = RegExp(
      '^${clientStateKeyPrefix}_${escapedPersistenceKey}_([^_]*)\$',
    );
    _mutationBatchKeyRe = RegExp(
      '^${mutationBatchKeyPrefix}_${escapedPersistenceKey}_(\\d+)(?:_(.*))?\$',
    );
    _queryTargetKeyRe = RegExp(
      '^${queryTargetKeyPrefix}_${escapedPersistenceKey}_(\\d+)\$',
    );
    _activeClients[_localClientId] = LocalClientState();

    // The listener is added here rather than in start(), so that the events that happen before the other components
    // populated their initial state (during their own start()) are collected and replayed by start().
    _storage.addListener(_handleStorageEvent);
  }

  static const String clientStateKeyPrefix = 'firestore_clients';
  static const String mutationBatchKeyPrefix = 'firestore_mutations';
  static const String queryTargetKeyPrefix = 'firestore_targets';
  static const String onlineStateKeyPrefix = 'firestore_online_state';
  static const String bundleLoadedKeyPrefix = 'firestore_bundle_loaded_v2';
  static const String sequenceNumberKeyPrefix = 'firestore_sequence_number';

  /// The key of the state of [clientId].
  static String clientStateKey(String persistenceKey, ClientId clientId) =>
      '${clientStateKeyPrefix}_${persistenceKey}_$clientId';

  /// The key of the state of a mutation batch; the uid of an authenticated user is last, so that it needs no escaping.
  static String mutationBatchKey(
    String persistenceKey,
    User user,
    int batchId,
  ) =>
      '${mutationBatchKeyPrefix}_${persistenceKey}_$batchId'
      '${user.isAuthenticated ? '_${user.uid}' : ''}';

  /// The key of the state of a query target.
  static String queryTargetKey(String persistenceKey, int targetId) =>
      '${queryTargetKeyPrefix}_${persistenceKey}_$targetId';

  final SharedClientStateStorage _storage;
  final Future<void> Function(Future<void> Function() operation) _enqueue;
  final String _persistenceKey;
  final ClientId _localClientId;

  late final String _localClientStorageKey;
  late final String _sequenceNumberKey;
  late final String _onlineStateKey;
  late final String _bundleLoadedKey;
  late final RegExp _clientStateKeyRe;
  late final RegExp _mutationBatchKeyRe;
  late final RegExp _queryTargetKeyRe;

  /// The state of every active client, this one included, by client id.
  Map<ClientId, ClientState> _activeClients =
      SplayTreeMap<ClientId, ClientState>();
  bool _started = false;
  User _currentUser;

  /// The events received before [start], replayed by it.
  List<SharedClientStateStorageEvent> _earlyEvents =
      <SharedClientStateStorageEvent>[];

  LocalClientState get _localClientState =>
      _activeClients[_localClientId]! as LocalClientState;

  @override
  Future<void> start() async {
    assert(!_started, 'StorageSharedClientState already started');
    assert(
      syncEngine != null,
      'syncEngine property must be set before calling start()',
    );
    assert(
      onlineStateHandler != null,
      'onlineStateHandler property must be set before calling start()',
    );

    // Backfill the state of the clients that exist already.
    final List<ClientId> existingClients = await syncEngine!.getActiveClients();
    for (final ClientId clientId in existingClients) {
      if (clientId == _localClientId) {
        continue;
      }
      final String? item = _getItem(clientStateKey(_persistenceKey, clientId));
      if (item != null) {
        final _RemoteClientState? clientState =
            _RemoteClientState.fromStorageEntry(clientId, item);
        if (clientState != null) {
          _activeClients[clientState.clientId] = clientState;
        }
      }
    }

    _persistClientState();

    // Apply the online state that the primary client stored, if any.
    final String? onlineStateJson = _storage.getItem(_onlineStateKey);
    if (onlineStateJson != null) {
      final SharedOnlineState? onlineState = SharedOnlineState.fromStorageEntry(
        onlineStateJson,
      );
      if (onlineState != null) {
        _handleOnlineStateEvent(onlineState);
      }
    }

    // Set before replaying, so that the replayed events are applied rather than collected again.
    _started = true;
    final List<SharedClientStateStorageEvent> earlyEvents = _earlyEvents;
    _earlyEvents = <SharedClientStateStorageEvent>[];
    earlyEvents.forEach(_handleStorageEvent);
  }

  @override
  void writeSequenceNumber(int sequenceNumber) {
    _setItem(_sequenceNumberKey, jsonEncode(sequenceNumber));
  }

  @override
  SplayTreeSet<int> getAllActiveQueryTargets() =>
      _extractActiveQueryTargets(_activeClients);

  @override
  bool isActiveQueryTarget(int targetId) => _activeClients.values.any(
    (ClientState state) => state.activeTargetIds.contains(targetId),
  );

  @override
  void addPendingMutation(int batchId) {
    _persistMutationState(batchId, MutationBatchState.pending);
  }

  @override
  void updateMutationState(
    int batchId,
    MutationBatchState state, [
    FirestoreError? error,
  ]) {
    _persistMutationState(batchId, state, error);

    // Once a final mutation result is observed by other clients, they no longer access the mutation's metadata entry.
    // Since the storage replays events in order, it is safe to delete the entry right after updating it.
    _removeMutationState(batchId);
  }

  @override
  QueryTargetState addLocalQueryTarget(
    int targetId, {
    bool addToActiveTargetIds = true,
  }) {
    QueryTargetState queryState = QueryTargetState.notCurrent;

    // Look up the state of a target that another client registered already.
    if (isActiveQueryTarget(targetId)) {
      final String? item = _storage.getItem(
        queryTargetKey(_persistenceKey, targetId),
      );
      if (item != null) {
        final QueryTargetMetadata? metadata =
            QueryTargetMetadata.fromStorageEntry(targetId, item);
        if (metadata != null) {
          queryState = metadata.state;
        }
      }
    }

    // A query that only listens to the cache is not an active watch target of the client.
    if (addToActiveTargetIds) {
      _localClientState.addQueryTarget(targetId);
    }

    _persistClientState();
    return queryState;
  }

  @override
  void removeLocalQueryTarget(int targetId) {
    _localClientState.removeQueryTarget(targetId);
    _persistClientState();
  }

  @override
  bool isLocalQueryTarget(int targetId) =>
      _localClientState.activeTargetIds.contains(targetId);

  @override
  void clearQueryState(int targetId) {
    _removeItem(queryTargetKey(_persistenceKey, targetId));
  }

  @override
  void updateQueryState(
    int targetId,
    QueryTargetState state, [
    FirestoreError? error,
  ]) {
    _setItem(
      queryTargetKey(_persistenceKey, targetId),
      QueryTargetMetadata(targetId, state, error).toStorageJson(),
    );
  }

  @override
  void handleUserChange(
    User user,
    List<int> removedBatchIds,
    List<int> addedBatchIds,
  ) {
    removedBatchIds.forEach(_removeMutationState);
    _currentUser = user;
    addedBatchIds.forEach(addPendingMutation);
  }

  @override
  void setOnlineState(OnlineState onlineState) {
    _storage.setItem(
      _onlineStateKey,
      SharedOnlineState(_localClientId, onlineState).toStorageJson(),
    );
  }

  @override
  void notifyBundleLoaded(Set<String> collectionGroups) {
    _setItem(_bundleLoadedKey, jsonEncode(collectionGroups.toList()));
  }

  @override
  void shutdown() {
    if (_started) {
      _storage.removeListener(_handleStorageEvent);
      _removeItem(_localClientStorageKey);
      _started = false;
    }
  }

  String? _getItem(String key) {
    final String? value = _storage.getItem(key);
    Log.d(SharedClientState._tag, 'READ $key $value');
    return value;
  }

  void _setItem(String key, String value) {
    Log.d(SharedClientState._tag, 'SET $key $value');
    _storage.setItem(key, value);
  }

  void _removeItem(String key) {
    Log.d(SharedClientState._tag, 'REMOVE $key');
    _storage.removeItem(key);
  }

  void _handleStorageEvent(SharedClientStateStorageEvent event) {
    if (!identical(event.storageArea, _storage)) {
      return;
    }
    Log.d(SharedClientState._tag, 'EVENT ${event.key} ${event.newValue}');

    if (event.key == _localClientStorageKey) {
      Log.e(
        SharedClientState._tag,
        'Received a notification for a local change. Another client might have garbage-collected our state',
      );
      return;
    }

    unawaited(
      _enqueue(() async {
        if (!_started) {
          _earlyEvents.add(event);
          return;
        }
        await _applyStorageEvent(event);
      }),
    );
  }

  Future<void> _applyStorageEvent(SharedClientStateStorageEvent event) async {
    final String key = event.key;
    final String? newValue = event.newValue;
    if (_clientStateKeyRe.hasMatch(key)) {
      final ClientId clientId = _clientStateKeyRe.firstMatch(key)!.group(1)!;
      if (newValue != null) {
        final _RemoteClientState? clientState =
            _RemoteClientState.fromStorageEntry(clientId, newValue);
        if (clientState != null) {
          await _handleClientStateEvent(clientId, clientState);
        }
      } else {
        await _handleClientStateEvent(clientId, null);
      }
    } else if (_mutationBatchKeyRe.hasMatch(key)) {
      final RegExpMatch match = _mutationBatchKeyRe.firstMatch(key)!;
      final int? batchId = _idFromKey(key, match.group(1)!);
      if (newValue != null && batchId != null) {
        final MutationMetadata? metadata = MutationMetadata.fromStorageEntry(
          User(match.group(2)),
          batchId,
          newValue,
        );
        if (metadata != null) {
          await _handleMutationBatchEvent(metadata);
        }
      }
    } else if (_queryTargetKeyRe.hasMatch(key)) {
      final int? targetId = _idFromKey(
        key,
        _queryTargetKeyRe.firstMatch(key)!.group(1)!,
      );
      if (newValue != null && targetId != null) {
        final QueryTargetMetadata? metadata =
            QueryTargetMetadata.fromStorageEntry(targetId, newValue);
        if (metadata != null) {
          await syncEngine!.applyTargetState(
            metadata.targetId,
            metadata.state,
            metadata.error,
          );
        }
      }
    } else if (key == _onlineStateKey) {
      if (newValue != null) {
        final SharedOnlineState? onlineState =
            SharedOnlineState.fromStorageEntry(newValue);
        if (onlineState != null) {
          _handleOnlineStateEvent(onlineState);
        }
      }
    } else if (key == _sequenceNumberKey) {
      final int sequenceNumber = _sequenceNumberFromStorage(newValue);
      if (sequenceNumber != ListenSequence.invalid) {
        sequenceNumberHandler?.call(sequenceNumber);
      }
    } else if (key == _bundleLoadedKey && newValue != null) {
      final Object? collectionGroups = _tryDecode(newValue);
      if (collectionGroups is List &&
          collectionGroups.every((Object? group) => group is String)) {
        await Future.wait(<Future<void>>[
          for (final Object? collectionGroup in collectionGroups)
            syncEngine!.synchronizeWithChangedDocuments(
              collectionGroup! as String,
            ),
        ]);
      } else {
        Log.e(
          SharedClientState._tag,
          'Failed to parse the collection groups of a loaded bundle: $newValue',
        );
      }
    }
  }

  void _persistClientState() {
    _setItem(_localClientStorageKey, _localClientState.toStorageJson());
  }

  void _persistMutationState(
    int batchId,
    MutationBatchState state, [
    FirestoreError? error,
  ]) {
    _setItem(
      mutationBatchKey(_persistenceKey, _currentUser, batchId),
      MutationMetadata(_currentUser, batchId, state, error).toStorageJson(),
    );
  }

  void _removeMutationState(int batchId) {
    _removeItem(mutationBatchKey(_persistenceKey, _currentUser, batchId));
  }

  Future<void> _handleMutationBatchEvent(MutationMetadata metadata) async {
    if (metadata.user.uid != _currentUser.uid) {
      Log.d(
        SharedClientState._tag,
        'Ignoring mutation for non-active user ${metadata.user.uid}',
      );
      return;
    }
    await syncEngine!.applyBatchState(
      metadata.batchId,
      metadata.state,
      metadata.error,
    );
  }

  Future<void> _handleClientStateEvent(
    ClientId clientId,
    _RemoteClientState? clientState,
  ) async {
    final Map<ClientId, ClientState> updatedClients =
        SplayTreeMap<ClientId, ClientState>.of(_activeClients);
    if (clientState != null) {
      updatedClients[clientId] = clientState;
    } else {
      updatedClients.remove(clientId);
    }

    final Set<int> existingTargets = _extractActiveQueryTargets(_activeClients);
    final Set<int> newTargets = _extractActiveQueryTargets(updatedClients);

    await syncEngine!.applyActiveTargetsChange(
      newTargets.difference(existingTargets).toList(),
      existingTargets.difference(newTargets).toList(),
    );
    _activeClients = updatedClients;
  }

  void _handleOnlineStateEvent(SharedOnlineState onlineState) {
    // The online state is only applied if the client that wrote it is still active.
    if (_activeClients.containsKey(onlineState.clientId)) {
      onlineStateHandler!(onlineState.onlineState);
    }
  }

  static SplayTreeSet<int> _extractActiveQueryTargets(
    Map<ClientId, ClientState> clients,
  ) {
    final SplayTreeSet<int> activeTargets = SplayTreeSet<int>();
    clients.values
        .map((ClientState state) => state.activeTargetIds)
        .forEach(activeTargets.addAll);
    return activeTargets;
  }

  /// The batch or target id in [key], or null (logged) when its digits do not fit an integer: no client wrote it.
  /// The JS SDK reads such an id as an imprecise number.
  static int? _idFromKey(String key, String digits) {
    final int? id = int.tryParse(digits);
    if (id == null) {
      Log.e(
        SharedClientState._tag,
        'Ignoring an entry with an invalid id: $key',
      );
    }
    return id;
  }

  static int _sequenceNumberFromStorage(String? value) {
    if (value != null) {
      final Object? parsed = _tryDecode(value);
      if (parsed is int) {
        return parsed;
      }
      Log.e(
        SharedClientState._tag,
        'Failed to read sequence number from storage: $value',
      );
    }
    return ListenSequence.invalid;
  }
}

/// The [SharedClientState] of a client that does not share its persistence (the JS `MemorySharedClientState`): it
/// keeps the state of the local client and notifies nobody.
class MemorySharedClientState extends SharedClientState {
  @override
  bool get sharesState => false;

  LocalClientState _localState = LocalClientState();
  final Map<int, QueryTargetState> _queryState = <int, QueryTargetState>{};

  @override
  void addPendingMutation(int batchId) {}

  @override
  void updateMutationState(
    int batchId,
    MutationBatchState state, [
    FirestoreError? error,
  ]) {}

  @override
  QueryTargetState addLocalQueryTarget(
    int targetId, {
    bool addToActiveTargetIds = true,
  }) {
    if (addToActiveTargetIds) {
      _localState.addQueryTarget(targetId);
    }
    return _queryState[targetId] ?? QueryTargetState.notCurrent;
  }

  @override
  void updateQueryState(
    int targetId,
    QueryTargetState state, [
    FirestoreError? error,
  ]) {
    _queryState[targetId] = state;
  }

  @override
  void removeLocalQueryTarget(int targetId) {
    _localState.removeQueryTarget(targetId);
  }

  @override
  bool isLocalQueryTarget(int targetId) =>
      _localState.activeTargetIds.contains(targetId);

  @override
  void clearQueryState(int targetId) {
    _queryState.remove(targetId);
  }

  @override
  SplayTreeSet<int> getAllActiveQueryTargets() =>
      SplayTreeSet<int>.of(_localState.activeTargetIds);

  @override
  bool isActiveQueryTarget(int targetId) =>
      _localState.activeTargetIds.contains(targetId);

  @override
  Future<void> start() async {
    _localState = LocalClientState();
  }

  @override
  void handleUserChange(
    User user,
    List<int> removedBatchIds,
    List<int> addedBatchIds,
  ) {}

  @override
  void setOnlineState(OnlineState onlineState) {}

  @override
  void shutdown() {}

  @override
  void writeSequenceNumber(int sequenceNumber) {}

  @override
  void notifyBundleLoaded(Set<String> collectionGroups) {}
}

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
import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/serial_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/shared_client_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/shared_client_state_storage.dart';
import 'package:test/test.dart';

/// Port of the JS SDK's `web_storage_shared_client_state.test.ts`, on the in-memory storage bus.
///
/// The JS test captures the storage listener of the client and calls it to simulate the writes of other clients. Here
/// the other clients write through their own participant of the same bus ([_writeToStorage]), which delivers the same
/// events to the client under test.

const String _persistencePrefix = 'firestore/[DEFAULT]/test-project';
const User _authenticatedUser = User('test');
const User _unauthenticatedUser = User.unauthenticated;
final FirestoreError _testError = FirestoreError(
  'Test Error',
  FirestoreErrorCode.internal,
);

int _nextId = 0;

/// A client id (without '_').
String _newClientId() => 'client${_nextId++}';

String _mutationKey(User user, int batchId) =>
    StorageSharedClientState.mutationBatchKey(
      _persistencePrefix,
      user,
      batchId,
    );

String _targetKey(int targetId) =>
    StorageSharedClientState.queryTargetKey(_persistencePrefix, targetId);

String _clientKey(String clientId) =>
    StorageSharedClientState.clientStateKey(_persistencePrefix, clientId);

const String _onlineStateKey = 'firestore_online_state_$_persistencePrefix';
const String _sequenceNumberKey =
    'firestore_sequence_number_$_persistencePrefix';
const String _bundleLoadedKey =
    'firestore_bundle_loaded_v2_$_persistencePrefix';

/// A [SharedClientStateSyncer] that records its callbacks.
class _TestSharedClientSyncer implements SharedClientStateSyncer {
  _TestSharedClientSyncer(this.activeClients);

  List<ClientId> activeClients;

  final Map<int, (MutationBatchState, FirestoreError?)> mutationState =
      <int, (MutationBatchState, FirestoreError?)>{};
  final Map<int, (QueryTargetState, FirestoreError?)> targetState =
      <int, (QueryTargetState, FirestoreError?)>{};
  final Set<int> activeTargets = <int>{};
  OnlineState onlineState = OnlineState.unknown;

  @override
  Future<void> applyBatchState(
    int batchId,
    MutationBatchState state,
    FirestoreError? error,
  ) async {
    mutationState[batchId] = (state, error);
  }

  @override
  Future<void> applyTargetState(
    int targetId,
    QueryTargetState state,
    FirestoreError? error,
  ) async {
    targetState[targetId] = (state, error);
  }

  @override
  Future<List<ClientId>> getActiveClients() async => activeClients;

  @override
  Future<void> applyActiveTargetsChange(
    List<int> added,
    List<int> removed,
  ) async {
    for (final int targetId in added) {
      expect(activeTargets.contains(targetId), isFalse);
      activeTargets.add(targetId);
    }
    for (final int targetId in removed) {
      expect(activeTargets.contains(targetId), isTrue);
      activeTargets.remove(targetId);
    }
  }

  void applyOnlineStateChange(OnlineState onlineState) {
    this.onlineState = onlineState;
  }

  @override
  Future<void> synchronizeWithChangedDocuments(String collectionGroup) async {}
}

void main() {
  late InMemorySharedClientStateStorage bus;
  late SharedClientStateStorage storage;

  /// The participant of the other clients.
  late SharedClientStateStorage otherClients;

  late SerialQueue queue;
  int pending = 0;
  late String primaryClientId;
  late StorageSharedClientState sharedClientState;
  late _TestSharedClientSyncer clientSyncer;

  Future<void> enqueue(Future<void> Function() operation) {
    pending++;
    return queue.run<void>(() async {
      try {
        await operation();
      } finally {
        pending--;
      }
    });
  }

  Future<void> drain() async {
    while (pending > 0) {
      await queue.run<void>(() async {});
    }
  }

  void writeToStorage(String key, String? value) {
    if (value == null) {
      otherClients.removeItem(key);
    } else {
      otherClients.setItem(key, value);
    }
  }

  setUp(() {
    bus = InMemorySharedClientStateStorage();
    storage = bus.connect();
    otherClients = bus.connect();
    queue = SerialQueue();
    pending = 0;
    primaryClientId = _newClientId();
    sharedClientState = StorageSharedClientState(
      storage,
      enqueue,
      _persistencePrefix,
      primaryClientId,
      _authenticatedUser,
    );
    clientSyncer = _TestSharedClientSyncer(<ClientId>[primaryClientId]);
    sharedClientState
      ..syncEngine = clientSyncer
      ..onlineStateHandler = clientSyncer.applyOnlineStateChange;
  });

  tearDown(() => sharedClientState.shutdown());

  void assertClientState(List<int> activeTargetIds) {
    final Map<String, dynamic> actual =
        jsonDecode(storage.getItem(_clientKey(primaryClientId))!)
            as Map<String, dynamic>;
    expect(
      actual.keys,
      unorderedEquals(<String>['activeTargetIds', 'updateTimeMs']),
    );
    expect(actual['activeTargetIds'], unorderedEquals(activeTargetIds));
  }

  group('persists mutation batches', () {
    void assertBatchState(
      int batchId,
      String mutationBatchState, [
      FirestoreError? error,
    ]) {
      final Map<String, dynamic> actual =
          jsonDecode(
                storage.getItem(_mutationKey(_authenticatedUser, batchId))!,
              )
              as Map<String, dynamic>;
      expect(actual['state'], mutationBatchState);
      final List<String> expectedMembers = <String>['state', 'updateTimeMs'];
      if (mutationBatchState == 'rejected') {
        expectedMembers.add('error');
        expect(actual['error']['code'], error!.code.toString());
        expect(actual['error']['message'], error.message);
      }
      expect(actual.keys, unorderedEquals(expectedMembers));
    }

    void assertNoBatchState(int batchId) {
      expect(
        storage.getItem(_mutationKey(_authenticatedUser, batchId)),
        isNull,
      );
    }

    setUp(() => sharedClientState.start());

    test('with a pending batch', () {
      sharedClientState.addPendingMutation(0);
      assertBatchState(0, 'pending');
    });

    test('with an acknowledged batch', () {
      sharedClientState.addPendingMutation(0);
      assertBatchState(0, 'pending');
      sharedClientState.updateMutationState(0, MutationBatchState.acknowledged);
      // The entry is garbage collected immediately.
      assertNoBatchState(0);
    });

    test('with a rejected batch', () {
      sharedClientState.addPendingMutation(0);
      assertBatchState(0, 'pending');
      sharedClientState.updateMutationState(
        0,
        MutationBatchState.rejected,
        _testError,
      );
      // The entry is garbage collected immediately.
      assertNoBatchState(0);
    });
  });

  group('persists query targets', () {
    void assertTargetState(
      int targetId,
      String queryTargetState, [
      FirestoreError? error,
    ]) {
      if (queryTargetState == 'pending') {
        expect(storage.getItem(_targetKey(targetId)), isNull);
      } else {
        final Map<String, dynamic> actual =
            jsonDecode(storage.getItem(_targetKey(targetId))!)
                as Map<String, dynamic>;
        expect(actual['state'], queryTargetState);
        final List<String> expectedMembers = <String>['state', 'updateTimeMs'];
        if (queryTargetState == 'rejected') {
          expectedMembers.add('error');
          expect(actual['error']['code'], error!.code.toString());
          expect(actual['error']['message'], error.message);
        }
        expect(actual.keys, unorderedEquals(expectedMembers));
      }
    }

    setUp(() => sharedClientState.start());

    test('when empty', () {
      assertClientState(<int>[]);
    });

    test('with multiple targets', () {
      sharedClientState.addLocalQueryTarget(0);
      assertClientState(<int>[0]);
      assertTargetState(0, 'pending');

      sharedClientState
        ..addLocalQueryTarget(1)
        ..addLocalQueryTarget(2);
      assertClientState(<int>[0, 1, 2]);
      assertTargetState(1, 'pending');
      assertTargetState(2, 'pending');

      sharedClientState.removeLocalQueryTarget(1);
      assertClientState(<int>[0, 2]);
    });

    test('with a not-current target', () {
      sharedClientState.addLocalQueryTarget(0);
      assertClientState(<int>[0]);
      assertTargetState(0, 'pending');
      sharedClientState.updateQueryState(0, QueryTargetState.notCurrent);
      assertTargetState(0, 'not-current');
    });

    test('with a current target', () {
      sharedClientState.addLocalQueryTarget(0);
      assertClientState(<int>[0]);
      assertTargetState(0, 'pending');
      sharedClientState.updateQueryState(0, QueryTargetState.notCurrent);
      assertTargetState(0, 'not-current');
      sharedClientState.updateQueryState(0, QueryTargetState.current);
      assertTargetState(0, 'current');
    });

    test('with an errored target', () {
      sharedClientState.addLocalQueryTarget(0);
      assertClientState(<int>[0]);
      assertTargetState(0, 'pending');
      sharedClientState.updateQueryState(
        0,
        QueryTargetState.rejected,
        _testError,
      );
      assertTargetState(0, 'rejected', _testError);
    });

    test('garbage collects entry', () {
      sharedClientState
        ..addLocalQueryTarget(0)
        ..updateQueryState(0, QueryTargetState.current);
      assertTargetState(0, 'current');
      sharedClientState.removeLocalQueryTarget(0);
      assertTargetState(0, 'current');
      sharedClientState.clearQueryState(0);
      expect(storage.getItem(_targetKey(0)), isNull);
    });
  });

  group('combines client state', () {
    late String secondaryClientId;
    late String secondaryClientStateKey;

    setUp(() async {
      secondaryClientId = _newClientId();
      secondaryClientStateKey = _clientKey(secondaryClientId);
      final String existingClientId = _newClientId();

      // Seed the storage with the state of an existing client. It is not shut down, which would delete the data.
      StorageSharedClientState(
          bus.connect(),
          (Future<void> Function() operation) async {},
          _persistencePrefix,
          existingClientId,
          _authenticatedUser,
        )
        ..addPendingMutation(1)
        ..addPendingMutation(2)
        ..addLocalQueryTarget(3)
        ..addLocalQueryTarget(4);

      clientSyncer.activeClients = <ClientId>[
        primaryClientId,
        existingClientId,
      ];
      await sharedClientState.start();
    });

    Future<void> verifyState(
      List<int> expectedTargets,
      OnlineState expectedOnlineState,
    ) async {
      await drain();
      expect(
        sharedClientState.getAllActiveQueryTargets(),
        unorderedEquals(expectedTargets),
      );
      expect(clientSyncer.onlineState, expectedOnlineState);
    }

    test('with targets from existing client', () async {
      // The prior client has two active query targets.
      await verifyState(<int>[3, 4], OnlineState.unknown);

      sharedClientState.addLocalQueryTarget(4);
      await verifyState(<int>[3, 4], OnlineState.unknown);

      sharedClientState.addLocalQueryTarget(5);
      await verifyState(<int>[3, 4, 5], OnlineState.unknown);

      sharedClientState.removeLocalQueryTarget(5);
      await verifyState(<int>[3, 4], OnlineState.unknown);
    });

    test('with targets from new client', () async {
      // The prior client has two active query targets.
      await verifyState(<int>[3, 4], OnlineState.unknown);

      final LocalClientState oldState = LocalClientState()..addQueryTarget(5);
      writeToStorage(secondaryClientStateKey, oldState.toStorageJson());
      await verifyState(<int>[3, 4, 5], OnlineState.unknown);

      final LocalClientState updatedState = LocalClientState()
        ..addQueryTarget(5)
        ..addQueryTarget(6);
      writeToStorage(secondaryClientStateKey, updatedState.toStorageJson());
      await verifyState(<int>[3, 4, 5, 6], OnlineState.unknown);

      writeToStorage(secondaryClientStateKey, null);
      await verifyState(<int>[3, 4], OnlineState.unknown);
    });

    test('with online state from new client', () async {
      // The prior client has two active query targets.
      await verifyState(<int>[3, 4], OnlineState.unknown);

      // Ensure that the client is considered active.
      writeToStorage(
        secondaryClientStateKey,
        LocalClientState().toStorageJson(),
      );

      writeToStorage(
        _onlineStateKey,
        jsonEncode(<String, String>{
          'onlineState': 'Unknown',
          'clientId': secondaryClientId,
        }),
      );
      await verifyState(<int>[3, 4], OnlineState.unknown);

      writeToStorage(
        _onlineStateKey,
        jsonEncode(<String, String>{
          'onlineState': 'Offline',
          'clientId': secondaryClientId,
        }),
      );
      await verifyState(<int>[3, 4], OnlineState.offline);

      writeToStorage(
        _onlineStateKey,
        jsonEncode(<String, String>{
          'onlineState': 'Online',
          'clientId': secondaryClientId,
        }),
      );
      await verifyState(<int>[3, 4], OnlineState.online);
    });

    test('ignores online state from inactive client', () async {
      // The prior client has two active query targets.
      await verifyState(<int>[3, 4], OnlineState.unknown);

      // The secondary client is inactive and its online state is ignored.
      writeToStorage(
        _onlineStateKey,
        jsonEncode(<String, String>{
          'onlineState': 'Online',
          'clientId': secondaryClientId,
        }),
      );
      await verifyState(<int>[3, 4], OnlineState.unknown);

      // Ensure that the client is considered active.
      writeToStorage(
        secondaryClientStateKey,
        LocalClientState().toStorageJson(),
      );

      writeToStorage(
        _onlineStateKey,
        jsonEncode(<String, String>{
          'onlineState': 'Online',
          'clientId': secondaryClientId,
        }),
      );
      await verifyState(<int>[3, 4], OnlineState.online);
    });

    test('ignores invalid data', () async {
      final String invalidClientStateKey = _clientKey(_newClientId());

      // The prior instance has two active query targets.
      await verifyState(<int>[3, 4], OnlineState.unknown);

      // The newly added target is ignored.
      writeToStorage(
        invalidClientStateKey,
        jsonEncode(<String, dynamic>{
          'activeTargetIds': <dynamic>[5, 'invalid'],
        }),
      );
      await verifyState(<int>[3, 4], OnlineState.unknown);
    });
  });

  group('processes mutation updates', () {
    setUp(() => sharedClientState.start());

    Future<_TestSharedClientSyncer> withUser(
      User user,
      void Function() fn,
    ) async {
      sharedClientState.handleUserChange(user, <int>[], <int>[]);
      fn();
      await drain();
      return clientSyncer;
    }

    test('for pending mutation', () async {
      final _TestSharedClientSyncer state = await withUser(
        _authenticatedUser,
        () {
          writeToStorage(
            _mutationKey(_authenticatedUser, 1),
            MutationMetadata(
              _authenticatedUser,
              1,
              MutationBatchState.pending,
            ).toStorageJson(),
          );
        },
      );
      expect(state.mutationState, hasLength(1));
      expect(state.mutationState[1]!.$1, MutationBatchState.pending);
    });

    test('for acknowledged mutation', () async {
      final _TestSharedClientSyncer state = await withUser(
        _authenticatedUser,
        () {
          writeToStorage(
            _mutationKey(_authenticatedUser, 1),
            MutationMetadata(
              _authenticatedUser,
              1,
              MutationBatchState.acknowledged,
            ).toStorageJson(),
          );
        },
      );
      expect(state.mutationState, hasLength(1));
      expect(state.mutationState[1]!.$1, MutationBatchState.acknowledged);
    });

    test('for rejected mutation', () async {
      final _TestSharedClientSyncer state = await withUser(
        _authenticatedUser,
        () {
          writeToStorage(
            _mutationKey(_authenticatedUser, 1),
            MutationMetadata(
              _authenticatedUser,
              1,
              MutationBatchState.rejected,
              _testError,
            ).toStorageJson(),
          );
        },
      );
      expect(state.mutationState, hasLength(1));
      expect(state.mutationState[1]!.$1, MutationBatchState.rejected);
      final FirestoreError error = state.mutationState[1]!.$2!;
      expect(error.code, FirestoreErrorCode.internal);
      expect(error.message, 'Test Error');
    });

    test('handles unauthenticated user', () async {
      final _TestSharedClientSyncer state = await withUser(
        _unauthenticatedUser,
        () {
          writeToStorage(
            _mutationKey(_unauthenticatedUser, 1),
            MutationMetadata(
              _unauthenticatedUser,
              1,
              MutationBatchState.pending,
            ).toStorageJson(),
          );
        },
      );
      expect(state.mutationState, hasLength(1));
      expect(state.mutationState[1]!.$1, MutationBatchState.pending);
    });

    test('ignores different user', () async {
      final _TestSharedClientSyncer state = await withUser(
        _authenticatedUser,
        () {
          const User otherUser = User('foobar');
          writeToStorage(
            _mutationKey(_authenticatedUser, 1),
            MutationMetadata(
              _authenticatedUser,
              1,
              MutationBatchState.pending,
            ).toStorageJson(),
          );
          writeToStorage(
            _mutationKey(otherUser, 1),
            MutationMetadata(
              otherUser,
              2,
              MutationBatchState.pending,
            ).toStorageJson(),
          );
        },
      );
      expect(state.mutationState, hasLength(1));
      expect(state.mutationState[1]!.$1, MutationBatchState.pending);
    });

    test('ignores invalid data', () async {
      final _TestSharedClientSyncer state = await withUser(
        _authenticatedUser,
        () {
          writeToStorage(
            _mutationKey(_authenticatedUser, 1),
            jsonEncode(<String, dynamic>{
              'state': 'invalid',
              'updateTimeMs': 0,
            }),
          );
        },
      );
      expect(state.mutationState, isEmpty);
    });
  });

  group('processes target updates', () {
    const int firstClientTargetId = 1;
    const int secondClientTargetId = 2;

    late String firstClientStorageKey;
    late String secondClientStorageKey;
    late LocalClientState firstClient;
    late LocalClientState secondClientState;

    setUp(() async {
      firstClientStorageKey = _clientKey(_newClientId());
      secondClientStorageKey = _clientKey(_newClientId());
      firstClient = LocalClientState()..addQueryTarget(firstClientTargetId);
      secondClientState = LocalClientState();
      await sharedClientState.start();
    });

    Future<_TestSharedClientSyncer> withClientState(void Function() fn) async {
      writeToStorage(firstClientStorageKey, firstClient.toStorageJson());
      fn();
      await drain();
      return clientSyncer;
    }

    test('for added target', () async {
      _TestSharedClientSyncer state = await withClientState(() {
        // Add a target that only exists in the second client.
        secondClientState.addQueryTarget(secondClientTargetId);
        writeToStorage(
          secondClientStorageKey,
          secondClientState.toStorageJson(),
        );
      });
      expect(state.activeTargets, hasLength(2));

      state = await withClientState(() {
        // Add a target that already exists in the first client.
        secondClientState.addQueryTarget(firstClientTargetId);
        writeToStorage(
          secondClientStorageKey,
          secondClientState.toStorageJson(),
        );
      });
      expect(state.activeTargets, hasLength(2));
    });

    test('for removed target', () async {
      _TestSharedClientSyncer state = await withClientState(() {
        secondClientState
          ..addQueryTarget(firstClientTargetId)
          ..addQueryTarget(secondClientTargetId);
        writeToStorage(
          secondClientStorageKey,
          secondClientState.toStorageJson(),
        );
      });
      expect(state.activeTargets, hasLength(2));

      state = await withClientState(() {
        // Remove a target that also exists in the first client.
        secondClientState.removeQueryTarget(firstClientTargetId);
        writeToStorage(
          secondClientStorageKey,
          secondClientState.toStorageJson(),
        );
      });
      expect(state.activeTargets, hasLength(2));

      state = await withClientState(() {
        // Remove a target that only exists in the second client.
        secondClientState.removeQueryTarget(secondClientTargetId);
        writeToStorage(
          secondClientStorageKey,
          secondClientState.toStorageJson(),
        );
      });
      expect(state.activeTargets, hasLength(1));
    });

    test('for not-current target', () async {
      final _TestSharedClientSyncer state = await withClientState(() {
        writeToStorage(
          _targetKey(firstClientTargetId),
          QueryTargetMetadata(
            firstClientTargetId,
            QueryTargetState.notCurrent,
          ).toStorageJson(),
        );
      });
      expect(state.activeTargets, hasLength(1));
      expect(
        state.targetState[firstClientTargetId]!.$1,
        QueryTargetState.notCurrent,
      );
    });

    test('for current target', () async {
      final _TestSharedClientSyncer state = await withClientState(() {
        writeToStorage(
          _targetKey(firstClientTargetId),
          QueryTargetMetadata(
            firstClientTargetId,
            QueryTargetState.current,
          ).toStorageJson(),
        );
      });
      expect(state.activeTargets, hasLength(1));
      expect(
        state.targetState[firstClientTargetId]!.$1,
        QueryTargetState.current,
      );
    });

    test('for errored target', () async {
      final _TestSharedClientSyncer state = await withClientState(() {
        writeToStorage(
          _targetKey(1),
          QueryTargetMetadata(
            firstClientTargetId,
            QueryTargetState.rejected,
            _testError,
          ).toStorageJson(),
        );
      });
      expect(state.activeTargets, hasLength(1));
      expect(
        state.targetState[firstClientTargetId]!.$1,
        QueryTargetState.rejected,
      );
      final FirestoreError error = state.targetState[firstClientTargetId]!.$2!;
      expect(error.code, FirestoreErrorCode.internal);
      expect(error.message, 'Test Error');
    });

    test('ignores invalid data', () async {
      final _TestSharedClientSyncer state = await withClientState(() {
        writeToStorage(
          _targetKey(firstClientTargetId),
          jsonEncode(<String, dynamic>{'state': 'invalid', 'updateTimeMs': 0}),
        );
      });
      expect(state.activeTargets, hasLength(1));
      expect(state.targetState[firstClientTargetId], isNull);
    });
  });

  group('syncs sequence numbers', () {
    setUp(() => sharedClientState.start());

    void assertSequenceNumber(int expected) {
      final String? sequenceNumberString = storage.getItem(_sequenceNumberKey);
      expect(sequenceNumberString, isNotNull);
      expect(jsonDecode(sequenceNumberString!), expected);
    }

    test('writes out new sequence numbers', () {
      sharedClientState.writeSequenceNumber(1);
      assertSequenceNumber(1);
    });

    test('notifies on new sequence numbers', () async {
      final List<int> sequenceNumbers = <int>[];
      sharedClientState.sequenceNumberHandler = sequenceNumbers.add;
      writeToStorage(_sequenceNumberKey, '1');
      await drain();
      expect(sequenceNumbers, <int>[1]);
      writeToStorage(_sequenceNumberKey, '2');
      writeToStorage(_sequenceNumberKey, '3');
      await drain();
      expect(sequenceNumbers, <int>[1, 2, 3]);
    });
  });

  group('processes bundles', () {
    setUp(() => sharedClientState.start());

    void assertBundlesLoaded(List<String> collectionGroups) {
      final String? bundleValue = storage.getItem(_bundleLoadedKey);
      expect(bundleValue, isNotNull);
      expect(jsonDecode(bundleValue!), unorderedEquals(collectionGroups));
    }

    test('writes out collection groups', () {
      sharedClientState.notifyBundleLoaded(<String>{'a', 'b'});
      assertBundlesLoaded(<String>['a', 'b']);
    });

    test('supports empty collection groups', () {
      sharedClientState.notifyBundleLoaded(<String>{});
      assertBundlesLoaded(<String>[]);
    });
  });
}

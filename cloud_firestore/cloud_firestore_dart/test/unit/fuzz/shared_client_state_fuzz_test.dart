// Fuzz: StorageSharedClientState reads the storage entries of the other
// clients (the JS WebStorageSharedClientState reads LocalStorage). Their keys
// and values come from other clients, maybe of another SDK version, and from
// anything else that writes the storage. A malformed entry must be ignored
// (and logged), as upstream does: applying an event runs on the queue of the
// client, where an error fails the client.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/serial_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/shared_client_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/shared_client_state_storage.dart';
import 'package:test/test.dart';

import '../../util/property.dart';

const String persistenceKey = 'firestore/[DEFAULT]/test-project';
const String localClientId = 'local';
const List<String> otherClientIds = <String>['a', 'b', 'c'];

/// A syncer that accepts every callback.
class Syncer implements SharedClientStateSyncer {
  int calls = 0;

  @override
  Future<void> applyBatchState(
    int batchId,
    MutationBatchState state,
    FirestoreError? error,
  ) async => calls++;

  @override
  Future<void> applyTargetState(
    int targetId,
    QueryTargetState state,
    FirestoreError? error,
  ) async => calls++;

  @override
  Future<List<ClientId>> getActiveClients() async => <ClientId>[
    localClientId,
    ...otherClientIds,
  ];

  @override
  Future<void> applyActiveTargetsChange(
    List<int> added,
    List<int> removed,
  ) async => calls++;

  @override
  Future<void> synchronizeWithChangedDocuments(String collectionGroup) async =>
      calls++;
}

extension on Gen {
  String key() {
    final String prefix = pick(const <String>[
      StorageSharedClientState.clientStateKeyPrefix,
      StorageSharedClientState.mutationBatchKeyPrefix,
      StorageSharedClientState.queryTargetKeyPrefix,
      StorageSharedClientState.onlineStateKeyPrefix,
      StorageSharedClientState.bundleLoadedKeyPrefix,
      StorageSharedClientState.sequenceNumberKeyPrefix,
    ]);
    final String suffix = pick(<String>[
      '',
      '_${pick(otherClientIds)}',
      '_$localClientId',
      '_${integer().abs()}',
      '_${'9' * between(19, 40)}',
      '_0_user',
      '_1_',
      '_${'9' * 30}_user',
      '_-1',
      '_1.5',
      '_${string()}',
      '__',
    ]);
    if (chance(10)) {
      return string();
    }
    final String key = '${prefix}_$persistenceKey';
    return prefix == StorageSharedClientState.onlineStateKeyPrefix ||
            prefix == StorageSharedClientState.bundleLoadedKeyPrefix ||
            prefix == StorageSharedClientState.sequenceNumberKeyPrefix
        ? (chance(80) ? key : '$key$suffix')
        : '$key$suffix';
  }

  Object? json([int depth = 0]) {
    switch (below(depth < 3 ? 11 : 8)) {
      case 0:
        return null;
      case 1:
        return chance(50);
      case 2:
        return integer();
      case 3:
        return pick(const <Object>[1.5, -0.0, 1e300, 9007199254740993.0]);
      case 4:
        return string();
      case 5:
        return pick(const <String>[
          'pending', 'acknowledged', 'rejected', 'not-current', 'current', //
          'Online', 'Offline', 'Unknown', 'local', 'a', 'b', 'c', 'ok',
          'internal', 'FirestoreErrorCode.internal', 'coll',
        ]);
      case 6:
        return <Object?>[];
      case 7:
        return <String, Object?>{};
      case 8:
        return <Object?>[for (int i = below(4); i > 0; i--) json(depth + 1)];
      default:
        return <String, Object?>{
          for (int i = below(4); i > 0; i--)
            pick(const <String>[
              'state', 'error', 'code', 'message', 'activeTargetIds', //
              'updateTimeMs', 'clientId', 'onlineState', 'x',
            ]): json(
              depth + 1,
            ),
        };
    }
  }

  /// A value shaped like one of the stored forms, with hostile parts.
  String storedValue() {
    switch (below(8)) {
      case 0:
        return jsonEncode(<String, Object?>{
          'state': json(),
          'updateTimeMs': json(),
          if (chance(50)) 'error': json(),
        });
      case 1:
        return jsonEncode(<String, Object?>{
          'state': 'rejected',
          'error': <String, Object?>{'code': json(), 'message': json()},
        });
      case 2:
        return jsonEncode(<String, Object?>{
          'activeTargetIds': chance(50)
              ? <Object?>[for (int i = below(4); i > 0; i--) json(2)]
              : json(),
        });
      case 3:
        return jsonEncode(<String, Object?>{
          'clientId': chance(70) ? pick(otherClientIds) : json(),
          'onlineState': json(),
        });
      case 4:
        return jsonEncode(json());
      case 5:
        // Truncated or otherwise not JSON.
        final String text = jsonEncode(json());
        return text.substring(0, below(text.length + 1));
      case 6:
        return '${'[' * 10000}${']' * 10000}';
      default:
        return string();
    }
  }
}

class Event {
  Event(this.key, this.value);

  final String key;
  final String? value;

  @override
  String toString() => '$key = $value';
}

void main() {
  test('malformed entries of other clients are ignored', () async {
    await forAllAsync<List<Event>>(
      'malformed shared client state entries',
      count: cases(400),
      generate: (Gen gen) => <Event>[
        for (int i = gen.between(1, 12); i > 0; i--)
          Event(gen.key(), gen.chance(85) ? gen.storedValue() : null),
      ],
      show: (List<Event> events) => events.join('\n'),
      check: (List<Event> events) async {
        final InMemorySharedClientStateStorage bus =
            InMemorySharedClientStateStorage();
        final SharedClientStateStorage storage = bus.connect();
        final SharedClientStateStorage others = bus.connect();
        final SerialQueue queue = SerialQueue();
        final List<(Object, StackTrace)> errors = <(Object, StackTrace)>[];
        final List<Future<void>> operations = <Future<void>>[];

        Future<void> enqueue(Future<void> Function() operation) {
          final Future<void> result = queue.run<void>(operation);
          operations.add(
            result.catchError((Object e, StackTrace s) => errors.add((e, s))),
          );
          return result.catchError((_) {});
        }

        void write(Event event) {
          final String? value = event.value;
          if (value == null) {
            others.removeItem(event.key);
          } else {
            others.setItem(event.key, value);
          }
        }

        // Half of the entries are there before the client starts.
        final int before = events.length ~/ 2;
        events.take(before).forEach(write);

        final StorageSharedClientState state =
            StorageSharedClientState(
                storage,
                enqueue,
                persistenceKey,
                localClientId,
                const User('user'),
              )
              ..syncEngine = Syncer()
              ..onlineStateHandler = (OnlineState _) {};
        try {
          await runZoned(
            () async {
              await state.start().timeout(const Duration(seconds: 5));
              events.skip(before).forEach(write);
              await Future.wait(operations).timeout(const Duration(seconds: 5));
            },
            zoneSpecification: ZoneSpecification(
              print: (Zone self, ZoneDelegate parent, Zone zone, String _) {},
            ),
          );
        } finally {
          state.shutdown();
        }
        if (errors.isNotEmpty) {
          final (Object error, StackTrace stackTrace) = errors.first;
          fail(
            'Applying an entry failed with ${error.runtimeType}: $error\n'
            '${stackTrace.toString().split('\n').take(6).join('\n')}',
          );
        }
      },
    );
  });
}

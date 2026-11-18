// `mergeUnsentWrites` against the backend: every ordered pair of a pool of writes, made offline on documents in
// several starting states, must leave the backend with the same documents whether the setting is on or off.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';

typedef _Write = Future<void> Function(DocumentReference ref);

final Map<String, _Write> _writes = <String, _Write>{
  'set a,b': (DocumentReference r) => r.set(<String, Object?>{'a': 1, 'b': 2}),
  'set nested': (DocumentReference r) => r.set(<String, Object?>{
    'n': <String, Object?>{'x': 1, 'y': 2},
  }),
  'set empty': (DocumentReference r) => r.set(<String, Object?>{}),
  'set with time': (DocumentReference r) =>
      r.set(<String, Object?>{'a': 3, 'time': FieldValue.serverTimestamp()}),
  'set with increment': (DocumentReference r) =>
      r.set(<String, Object?>{'a': 3, 'count': FieldValue.increment(2)}),
  'set with arrayUnion': (DocumentReference r) => r.set(<String, Object?>{
    'tags': FieldValue.arrayUnion(<Object?>[7]),
  }),
  'merge a': (DocumentReference r) =>
      r.set(<String, Object?>{'a': 10}, SetOptions(merge: true)),
  'merge nested x': (DocumentReference r) => r.set(<String, Object?>{
    'n': <String, Object?>{'x': 11},
  }, SetOptions(merge: true)),
  'merge deletes a': (DocumentReference r) => r.set(<String, Object?>{
    'a': FieldValue.delete(),
  }, SetOptions(merge: true)),
  'merge deletes n.x': (DocumentReference r) => r.set(<String, Object?>{
    'n': <String, Object?>{'x': FieldValue.delete()},
  }, SetOptions(merge: true)),
  'merge an empty map': (DocumentReference r) => r.set(<String, Object?>{
    'n': <String, Object?>{},
  }, SetOptions(merge: true)),
  'merge with increment': (DocumentReference r) => r.set(<String, Object?>{
    'count': FieldValue.increment(3),
  }, SetOptions(merge: true)),
  'update a': (DocumentReference r) => r.update(<String, Object?>{'a': 20}),
  'update n': (DocumentReference r) => r.update(<String, Object?>{
    'n': <String, Object?>{'z': 22},
  }),
  'update n.x': (DocumentReference r) => r.update(<String, Object?>{'n.x': 23}),
  'update n.y, a': (DocumentReference r) =>
      r.update(<String, Object?>{'n.y': 24, 'a': 25}),
  'update a.x': (DocumentReference r) => r.update(<String, Object?>{'a.x': 26}),
  'update n.x.deep': (DocumentReference r) =>
      r.update(<String, Object?>{'n.x.deep': 28}),
  'update deletes a': (DocumentReference r) =>
      r.update(<String, Object?>{'a': FieldValue.delete()}),
  'update deletes n.x': (DocumentReference r) =>
      r.update(<String, Object?>{'n.x': FieldValue.delete()}),
  'update deletes n': (DocumentReference r) =>
      r.update(<String, Object?>{'n': FieldValue.delete()}),
  'update n to a number': (DocumentReference r) =>
      r.update(<String, Object?>{'n': 29}),
  'update with time': (DocumentReference r) => r.update(<String, Object?>{
    'a': 27,
    'time': FieldValue.serverTimestamp(),
  }),
  'update with increment': (DocumentReference r) =>
      r.update(<String, Object?>{'count': FieldValue.increment(4)}),
  'update time only': (DocumentReference r) =>
      r.update(<String, Object?>{'time': FieldValue.serverTimestamp()}),
  'update time to a value': (DocumentReference r) =>
      r.update(<String, Object?>{'time': 40}),
  'update b with time': (DocumentReference r) => r.update(<String, Object?>{
    'b': 41,
    'time': FieldValue.serverTimestamp(),
  }),
  'update n.t time': (DocumentReference r) =>
      r.update(<String, Object?>{'n.t': FieldValue.serverTimestamp()}),
  'update count': (DocumentReference r) =>
      r.update(<String, Object?>{'count': 42}),
  'update count to a double': (DocumentReference r) =>
      r.update(<String, Object?>{'count': 1.5}),
  'update with increment 1.5': (DocumentReference r) =>
      r.update(<String, Object?>{'count': FieldValue.increment(1.5)}),
  'update with negative increment': (DocumentReference r) =>
      r.update(<String, Object?>{'count': FieldValue.increment(-4)}),
  'update a with increment': (DocumentReference r) =>
      r.update(<String, Object?>{'a': 43, 'count': FieldValue.increment(1)}),
  'update with arrayUnion': (DocumentReference r) => r.update(<String, Object?>{
    'tags': FieldValue.arrayUnion(<Object?>[2, 8]),
  }),
  'update with arrayUnion 8,9': (DocumentReference r) =>
      r.update(<String, Object?>{
        'tags': FieldValue.arrayUnion(<Object?>[8, 9, 3.0]),
      }),
  'update with arrayRemove': (DocumentReference r) =>
      r.update(<String, Object?>{
        'tags': FieldValue.arrayRemove(<Object?>[1]),
      }),
  'update with arrayRemove 2': (DocumentReference r) =>
      r.update(<String, Object?>{
        'tags': FieldValue.arrayRemove(<Object?>[2, 7]),
      }),
  'update tags': (DocumentReference r) => r.update(<String, Object?>{
    'tags': <int>[3, 4],
  }),
  'update n.tags union': (DocumentReference r) => r.update(<String, Object?>{
    'n.tags': FieldValue.arrayUnion(<Object?>[1]),
  }),
  'update n.count increment': (DocumentReference r) =>
      r.update(<String, Object?>{'n.count': FieldValue.increment(6)}),
  'merge with arrayUnion': (DocumentReference r) => r.set(<String, Object?>{
    'tags': FieldValue.arrayUnion(<Object?>[9]),
  }, SetOptions(merge: true)),
  'merge time and a': (DocumentReference r) => r.set(<String, Object?>{
    'a': 44,
    'time': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true)),
  'set count': (DocumentReference r) => r.set(<String, Object?>{'count': 0}),
  'set tags': (DocumentReference r) => r.set(<String, Object?>{
    'tags': <int>[1],
  }),
  'delete': (DocumentReference r) => r.delete(),
};

/// The starting documents; null is a document that does not exist.
final Map<String, Map<String, Object?>?> _documents =
    <String, Map<String, Object?>?>{
      'missing': null,
      'empty': <String, Object?>{},
      'flat': <String, Object?>{
        'a': 100,
        'b': 101,
        'count': 5,
        'tags': <int>[1, 2],
      },
      'nested': <String, Object?>{
        'a': <String, Object?>{'x': 1, 'w': 2},
        'n': <String, Object?>{'x': 103, 'y': 104, 'w': 105},
      },
      'deep': <String, Object?>{
        'n': <String, Object?>{
          'x': <String, Object?>{'deep': 106, 'other': 107},
        },
      },
      'n is a number': <String, Object?>{'n': 5, 'a': 6},
      'with time and doubles': <String, Object?>{
        'time': 7,
        'count': 2.5,
        'tags': <Object>[2.0, 'x', 8],
        'n': <String, Object?>{'t': 1, 'count': 9007199254740992.0, 'tags': 3},
      },
      'large count': <String, Object?>{
        'count': 9223372036854775806,
        'n': <String, Object?>{'count': 9223372036854775807},
      },
    };

/// The data with every timestamp replaced: the backend sets its own time on each write.
Object? _withoutTimes(Object? value) => switch (value) {
  Timestamp() => 'a time',
  final Map<String, Object?> map => <String, Object?>{
    for (final MapEntry<String, Object?> entry in map.entries)
      entry.key: _withoutTimes(entry.value),
  },
  final List<Object?> list => list.map(_withoutTimes).toList(),
  _ => value,
};

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/merge_unsent_writes';

  tearDown(() => IntegrationTestUtil.tearDown());

  /// Makes every pair of writes offline on a collection of its own and returns what the backend holds afterwards,
  /// and the number of write batches that were waiting when the network came back.
  Future<(Map<String, Object?>, int)> run({required bool merge}) async {
    final Settings settings = IntegrationTestUtil.newTestSettings().copyWith(
      cacheSettings: PersistentCacheSettings(mergeUnsentWrites: merge),
    );
    final FirebaseFirestore firestore = await IntegrationTestUtil.testFirestore(
      settings,
      'integration/merge_unsent_writes_$merge',
    );
    final CollectionReference collection = firestore.collection(
      'merge_unsent_${merge ? 'on' : 'off'}_${DateTime.now().microsecondsSinceEpoch}',
    );

    final List<String> names = _writes.keys.toList();
    final List<(DocumentReference, _Write, _Write)> cases =
        <(DocumentReference, _Write, _Write)>[];
    WriteBatch batch = firestore.batch();
    int inBatch = 0;
    for (int i = 0; i < names.length; i++) {
      for (int j = 0; j < names.length; j++) {
        for (final MapEntry<String, Map<String, Object?>?> start
            in _documents.entries) {
          final DocumentReference ref = collection.doc(
            '${names[i]} + ${names[j]} on ${start.key}',
          );
          cases.add((ref, _writes[names[i]]!, _writes[names[j]]!));
          if (start.value != null) {
            batch.set(ref, start.value!);
            if (++inBatch == 400) {
              await batch.commit();
              batch = firestore.batch();
              inBatch = 0;
            }
          }
        }
      }
    }
    await batch.commit();

    await firestore.disableNetwork();
    // First every first write, then every second one: the writes of the other documents are in between.
    for (final (DocumentReference, _Write, _Write) c in cases) {
      unawaited(c.$2(c.$1).catchError((Object _) {}));
    }
    for (final (DocumentReference, _Write, _Write) c in cases) {
      unawaited(c.$3(c.$1).catchError((Object _) {}));
    }
    // A read goes through the queue of the client, after the writes above.
    await collection.limit(1).get(const GetOptions(source: Source.cache));
    final int waiting = await firestore.client.persistence
        .runTransactionAndReturn(
          'count the batches',
          () async =>
              (await firestore.client.persistence
                      .getMutationQueue(User.unauthenticated)
                      .getAllMutationBatches())
                  .length,
        );

    // The count the app can show follows the merges.
    expect(await firestore.getPendingWriteCount(), waiting);

    await firestore.enableNetwork();
    await firestore.waitForPendingWrites();
    // In pages: one read of every document is too large for the web transport of the emulator.
    final Map<String, Object?> documents = <String, Object?>{};
    QueryDocumentSnapshot? last;
    while (true) {
      Query page = collection.orderBy(FieldPath.documentId).limit(500);
      if (last != null) {
        page = page.startAfterDocument(last);
      }
      final QuerySnapshot snapshot = await page.get(
        const GetOptions(source: Source.server),
      );
      for (final QueryDocumentSnapshot doc in snapshot.docs) {
        documents[doc.id] = _withoutTimes(doc.data());
      }
      if (snapshot.docs.length < 500) {
        break;
      }
      last = snapshot.docs.last;
    }
    return (documents, waiting);
  }

  test(
    'the backend ends with the same documents with and without the setting',
    () async {
      final (Map<String, Object?> merged, int mergedWaiting) = await run(
        merge: true,
      );
      final (Map<String, Object?> separate, int separateWaiting) = await run(
        merge: false,
      );
      final int documents = _writes.length * _writes.length * _documents.length;
      expect(separateWaiting, 2 * documents);
      // Most pairs merge: well under two writes a document.
      expect(mergedWaiting, lessThan(separateWaiting * 3 ~/ 4));
      expect(mergedWaiting, greaterThanOrEqualTo(documents));

      expect(merged.keys.toSet(), separate.keys.toSet());
      for (final String id in separate.keys) {
        expect(merged[id], separate[id], reason: id);
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

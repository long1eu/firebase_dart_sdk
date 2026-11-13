// Copyright 2024 Google LLC
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

// NOTE: these tests were run against the Firestore emulator (findNearest included, which needs no vector index
// there); against the production backend a vector index on `embedding` is required for findNearest.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/distance_measure.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';
import 'package:test/test.dart';

import '../../../util/event_accumulator.dart';
import '../../../util/integration_test_util.dart';

const testFirestore = IntegrationTestUtil.testFirestore;
const testCollectionWithDocs = IntegrationTestUtil.testCollectionWithDocs;

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/vector';

  setUp(() => testFirestore());

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  group('VectorValue documents', () {
    test('vectors round trip through a document', () async {
      final CollectionReference c =
          await testCollectionWithDocs(<String, Map<String, Object?>>{
        'a': <String, Object?>{
          'embedding': FieldValue.vector(<double>[1.0, 2.0, 3.0]),
        },
      });
      final DocumentSnapshot snap = await c.document('a').get();
      expect(snap.getVectorValue('embedding'),
          FieldValue.vector(<double>[1.0, 2.0, 3.0]));
      expect(snap.get('embedding'), isA<VectorValue>());
    });

    test('vectors order by length then values', () async {
      final CollectionReference c =
          await testCollectionWithDocs(<String, Map<String, Object?>>{
        'long': <String, Object?>{
          'v': FieldValue.vector(<double>[1.0, 1.0, 1.0])
        },
        'b': <String, Object?>{
          'v': FieldValue.vector(<double>[2.0, 0.0])
        },
        'a': <String, Object?>{
          'v': FieldValue.vector(<double>[1.0, 5.0])
        },
        'array': <String, Object?>{
          'v': <Object>[1]
        },
        'map': <String, Object?>{
          'v': <String, Object>{'a': 1}
        },
      });
      final List<String> ids = (await c.orderBy('v').get())
          .map((DocumentSnapshot d) => d.id)
          .toList();
      expect(ids, <String>['array', 'a', 'b', 'long', 'map']);
    });
  });

  group('findNearest', () {
    final Map<String, Map<String, Object?>> docs =
        <String, Map<String, Object?>>{
      'a': <String, Object?>{
        'group': 'x',
        'embedding': FieldValue.vector(<double>[1.0, 1.0])
      },
      'b': <String, Object?>{
        'group': 'x',
        'embedding': FieldValue.vector(<double>[2.0, 2.0])
      },
      'c': <String, Object?>{
        'group': 'y',
        'embedding': FieldValue.vector(<double>[10.0, 10.0])
      },
      'noVector': <String, Object?>{'group': 'x'},
    };

    test('returns the nearest documents ordered by distance', () async {
      final CollectionReference c = await testCollectionWithDocs(docs);
      final VectorQuerySnapshot s = await c
          .findNearest(
              'embedding', <double>[0.0, 0.0], 2, DistanceMeasure.euclidean)
          .get();
      expect(s.docs.map((DocumentSnapshot d) => d.id), <String>['a', 'b']);
    });

    test('writes the distance to distanceResultField', () async {
      final CollectionReference c = await testCollectionWithDocs(docs);
      final VectorQuerySnapshot s = await c
          .findNearest('embedding', FieldValue.vector(<double>[1.0, 1.0]), 1,
              DistanceMeasure.euclidean,
              distanceResultField: 'dist')
          .get();
      expect(s.size, 1);
      expect(s.docs.single.id, 'a');
      expect(s.docs.single.getDouble('dist'), 0.0);
    });

    test('respects distanceThreshold', () async {
      final CollectionReference c = await testCollectionWithDocs(docs);
      final VectorQuerySnapshot s = await c
          .findNearest(
              'embedding', <double>[0.0, 0.0], 10, DistanceMeasure.euclidean,
              distanceThreshold: 5.0)
          .get();
      expect(s.docs.map((DocumentSnapshot d) => d.id), <String>['a', 'b']);
    });

    test('applies the filters of the base query', () async {
      final CollectionReference c = await testCollectionWithDocs(docs);
      final VectorQuerySnapshot s = await c
          .whereEqualTo('group', 'y')
          .findNearest(
              'embedding', <double>[0.0, 0.0], 10, DistanceMeasure.euclidean)
          .get();
      expect(s.docs.map((DocumentSnapshot d) => d.id), <String>['c']);
    });

    test('fails without network', () async {
      final CollectionReference c = await testCollectionWithDocs(docs);
      await c.firestore.disableNetwork();
      await expectLater(
          c
              .findNearest(
                  'embedding', <double>[0.0, 0.0], 2, DistanceMeasure.cosine)
              .get(),
          throwsA(isA<FirestoreError>().having((FirestoreError e) => e.code,
              'code', FirestoreErrorCode.unavailable)));
      await c.firestore.enableNetwork();
    });
  });

  group('Upstream VectorTest', () {
    // Test data in the order that the backend sorts it.
    final List<Map<String, Object?>> docsInOrder = <Map<String, Object?>>[
      <String, Object?>{
        'embedding': <int>[1, 2, 3, 4, 5, 6],
      },
      <String, Object?>{
        'embedding': <int>[100],
      },
      <String, Object?>{
        'embedding': FieldValue.vector(<double>[double.negativeInfinity]),
      },
      <String, Object?>{
        'embedding': FieldValue.vector(<double>[-100]),
      },
      <String, Object?>{
        'embedding': FieldValue.vector(<double>[100]),
      },
      <String, Object?>{
        'embedding': FieldValue.vector(<double>[double.infinity]),
      },
      <String, Object?>{
        'embedding': FieldValue.vector(<double>[1, 2]),
      },
      <String, Object?>{
        'embedding': FieldValue.vector(<double>[2, 2]),
      },
      <String, Object?>{
        'embedding': FieldValue.vector(<double>[1, 2, 3]),
      },
      <String, Object?>{
        'embedding': FieldValue.vector(<double>[1, 2, 3, 4]),
      },
      <String, Object?>{
        'embedding': FieldValue.vector(<double>[1, 2, 3, 4, 5]),
      },
      <String, Object?>{
        'embedding': FieldValue.vector(<double>[1, 2, 100, 4, 4]),
      },
      <String, Object?>{
        'embedding': FieldValue.vector(<double>[100, 2, 3, 4, 5]),
      },
      <String, Object?>{'embedding': <String, Object?>{}},
      <String, Object?>{
        'embedding': <String, Object?>{'HELLO': 'WORLD'},
      },
      <String, Object?>{
        'embedding': <String, Object?>{'hello': 'world'},
      },
    ];

    Future<List<String>> addDocs(CollectionReference collection) async {
      final List<String> ids = <String>[];
      for (final Map<String, Object?> data in docsInOrder) {
        ids.add((await collection.add(data)).id);
      }
      return ids;
    }

    Future<void> checkOnlineAndOfflineResultsMatch(
        Query query, List<String> expectedIds) async {
      final QuerySnapshot fromServer = await query.get(Source.server);
      final QuerySnapshot fromCache = await query.get(Source.cache);
      expect(IntegrationTestUtil.querySnapshotToIds(fromServer), expectedIds);
      expect(IntegrationTestUtil.querySnapshotToIds(fromCache), expectedIds);
    }

    test('writeAndReadVectorEmbeddings', () async {
      final DocumentReference doc =
          (await testFirestore()).collection('vec').document();

      await doc.set(<String, Object?>{
        'vector0': FieldValue.vector(<double>[0.0]),
        'vector1': FieldValue.vector(<double>[1, 2, 3.99]),
      });
      await doc.set(<String, Object?>{
        'vector0': FieldValue.vector(<double>[0.0]),
        'vector1': FieldValue.vector(<double>[1, 2, 3.99]),
        'vector2': FieldValue.vector(<double>[0, 0, 0]),
      });
      await doc.update(<String, Object?>{
        'vector3': FieldValue.vector(<double>[-1, -200, -9999]),
      });

      final Map<String, List<double>> expected = <String, List<double>>{
        'vector0': <double>[0.0],
        'vector1': <double>[1, 2, 3.99],
        'vector2': <double>[0, 0, 0],
        'vector3': <double>[-1, -200, -9999],
      };
      final DocumentSnapshot actual = await doc.get();
      for (final MapEntry<String, List<double>> entry in expected.entries) {
        expect(actual.get(entry.key), isA<VectorValue>());
        expect(actual.getVectorValue(entry.key)!.toArray(), entry.value);
      }
    });

    test('listenToDocumentsWithVectors', () async {
      final CollectionReference collection =
          (await testFirestore()).collection('vec-listen-${autoId()}');
      final DocumentReference ref = collection.document();
      final EventAccumulator<QuerySnapshot> accumulator =
          EventAccumulator<QuerySnapshot>();
      final StreamSubscription<QuerySnapshot> registration = collection
          .whereEqualTo('purpose', 'vector tests')
          .snapshots
          .listen(accumulator.onData, onError: accumulator.onError);

      try {
        QuerySnapshot snap = await accumulator.wait();
        expect(snap.isEmpty, isTrue);

        await ref.set(<String, Object?>{
          'purpose': 'vector tests',
          'vector0': FieldValue.vector(<double>[0.0]),
          'vector1': FieldValue.vector(<double>[1, 2, 3.99]),
        });
        snap = await accumulator.wait();
        DocumentSnapshot doc = snap.documents.first;
        expect(doc.getVectorValue('vector0'), FieldValue.vector(<double>[0.0]));
        expect(doc.getVectorValue('vector1'),
            FieldValue.vector(<double>[1, 2, 3.99]));

        await ref.set(<String, Object?>{
          'purpose': 'vector tests',
          'vector0': FieldValue.vector(<double>[0.0]),
          'vector1': FieldValue.vector(<double>[1, 2, 3.99]),
          'vector2': FieldValue.vector(<double>[0, 0, 0]),
        });
        snap = await accumulator.wait();
        doc = snap.documents.first;
        expect(doc.getVectorValue('vector2'),
            FieldValue.vector(<double>[0, 0, 0]));

        await ref.update(<String, Object?>{
          'vector3': FieldValue.vector(<double>[-1, -200, -999]),
        });
        snap = await accumulator.wait();
        doc = snap.documents.first;
        expect(doc.getVectorValue('vector0'), FieldValue.vector(<double>[0.0]));
        expect(doc.getVectorValue('vector1'),
            FieldValue.vector(<double>[1, 2, 3.99]));
        expect(doc.getVectorValue('vector2'),
            FieldValue.vector(<double>[0, 0, 0]));
        expect(doc.getVectorValue('vector3'),
            FieldValue.vector(<double>[-1, -200, -999]));

        await ref.delete();
        snap = await accumulator.wait();
        expect(snap.isEmpty, isTrue);
      } finally {
        await registration.cancel();
      }
    });

    test('vectorFieldOrder', () async {
      // The SDK orders vector fields like the backend: compare the order of a listener (SDK) with Query.get()
      // (backend).
      final CollectionReference collection =
          (await testFirestore()).collection('vec-order-${autoId()}');
      final List<String> docIds = await addDocs(collection);

      final Query orderedQuery = collection.orderBy('embedding');

      final EventAccumulator<QuerySnapshot> accumulator =
          EventAccumulator<QuerySnapshot>();
      final StreamSubscription<QuerySnapshot> registration = orderedQuery
          .snapshots
          .listen(accumulator.onData, onError: accumulator.onError);
      List<String> watchIds;
      try {
        watchIds =
            IntegrationTestUtil.querySnapshotToIds(await accumulator.wait());
      } finally {
        await registration.cancel();
      }

      final List<String> getIds = IntegrationTestUtil.querySnapshotToIds(
          await orderedQuery.get(Source.server));

      expect(getIds, docIds);
      expect(watchIds, docIds);
    });

    test('vectorFieldOrderOnlineAndOffline', () async {
      final CollectionReference collection =
          (await testFirestore()).collection('vec-order2-${autoId()}');
      final List<String> docIds = await addDocs(collection);
      await checkOnlineAndOfflineResultsMatch(
          collection.orderBy('embedding'), docIds);
    });

    test('vectorFieldFilterOnlineAndOffline', () async {
      final CollectionReference collection =
          (await testFirestore()).collection('vec-filter-${autoId()}');
      final List<String> docIds = await addDocs(collection);

      await checkOnlineAndOfflineResultsMatch(
          collection.orderBy('embedding').whereLessThan(
              'embedding', FieldValue.vector(<double>[1, 2, 100, 4, 4])),
          docIds.sublist(2, 11));

      await checkOnlineAndOfflineResultsMatch(
          collection.orderBy('embedding').whereGreaterThan(
              'embedding', FieldValue.vector(<double>[1, 2, 100, 4, 4])),
          docIds.sublist(12, 13));
    });
  });
}

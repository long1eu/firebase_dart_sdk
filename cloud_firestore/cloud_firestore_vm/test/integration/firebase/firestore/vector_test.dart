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

// NOTE: vector search (find_nearest) support in the Firestore emulator is
// unverified. These tests are written against the production backend contract
// and may need a real project (and a vector index on `embedding`) to pass.

import 'package:cloud_firestore_vm/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/distance_measure.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/vector_query_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/vector_value.dart';
import 'package:test/test.dart';

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
}

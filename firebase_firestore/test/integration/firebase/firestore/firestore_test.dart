// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/collection_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/metadata_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/query_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/set_options.dart';
import 'package:firebase_firestore/src/firebase/firestore/source.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../util/await_helper.dart';
import '../../../util/event_accumulator.dart';
import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/firestore';

  setUp(() => testFirestore());

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test('testCanUpdateAnExistingDocument', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Map<String, Object> initialValue = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    final Map<String, Object> finalData = map(<dynamic>[
      'desc',
      'NewDescription',
      'owner',
      map<String>(<dynamic>['name', 'Jonny', 'email', 'new@xyz.com'])
    ]);
    await documentReference.set(initialValue);
    await documentReference.updateFromList(
        <dynamic>['desc', 'NewDescription', 'owner.email', 'new@xyz.com']);
    final DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, finalData);
  });

  test('testCanUpdateAnUnknownDocument', () async {
    final DocumentReference writerRef =
        (await testFirestore()).collection('collection').document();
    final DocumentReference readerRef =
        (await testFirestore()).collection('collection').document(writerRef.id);

    await writerRef.set(map(<String>['a', 'a']));
    await readerRef.update(map(<String>['b', 'b']));
    DocumentSnapshot writerSnap = await writerRef.get(Source.CACHE);
    expect(writerSnap.exists, isTrue);

    try {
      await readerRef.get(Source.CACHE);
      fail('Should have thrown exception');
    } catch (e) {
      expect((e as FirebaseFirestoreError).code,
          FirebaseFirestoreErrorCode.unavailable);
    }
    writerSnap = await writerRef.get();
    expect(writerSnap.data, map<String>(<String>['a', 'a', 'b', 'b']));
    final DocumentSnapshot readerSnap = await readerRef.get();
    expect(readerSnap.data, map<String>(<String>['a', 'a', 'b', 'b']));
  });

  test('testCanMergeDataWithAnExistingDocumentUsingSet', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Map<String, Object> initialValue = map(<dynamic>[
      'desc',
      'Description',
      'owner.data',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    final Map<String, Object> mergeData = map(<dynamic>[
      'updated',
      true,
      'owner.data',
      map<String>(<String>['name', 'Sebastian'])
    ]);
    final Map<String, Object> finalData = map(<dynamic>[
      'desc',
      'Description',
      'updated',
      true,
      'owner.data',
      map<String>(<String>['name', 'Sebastian', 'email', 'abc@xyz.com'])
    ]);

    await documentReference.set(initialValue);
    await documentReference.set(mergeData, SetOptions.mergeAllFields);
    final DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, finalData);
  });

  test('testCanMergeServerTimestamps', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Map<String, Object> initialValue = map(<dynamic>['untouched', true]);
    final Map<String, Object> mergeData = map(<dynamic>[
      'time',
      FieldValue.serverTimestamp(),
      'nested',
      map<dynamic>(<dynamic>['time', FieldValue.serverTimestamp()])
    ]);
    await documentReference.set(initialValue);
    await documentReference.set(mergeData, SetOptions.mergeAllFields);
    final DocumentSnapshot doc = await documentReference.get();

    expect(doc.getBool('untouched'), isTrue);
    expect(doc.get('time'), const TypeMatcher<Timestamp>());
    expect(doc.get('nested.time'), const TypeMatcher<Timestamp>());
  });

  test('testCanMergeEmptyObject', () async {
    final DocumentReference documentReference = await testDocument();
    final EventAccumulator<DocumentSnapshot> eventAccumulator =
        EventAccumulator<DocumentSnapshot>();
    final StreamSubscription<DocumentSnapshot> subscription = documentReference
        .snapshots
        .listen(eventAccumulator.onData, onError: eventAccumulator.onError);
    await eventAccumulator.wait();

    documentReference.set(<String, dynamic>{});
    DocumentSnapshot snapshot = await eventAccumulator.wait();
    expect(snapshot.data, isEmpty);

    await documentReference.set(map(<dynamic>['a', <String, dynamic>{}]),
        SetOptions.mergeFields(<String>['a']));
    snapshot = await eventAccumulator.wait();
    expect(snapshot.data, map<dynamic>(<dynamic>['a', <String, dynamic>{}]));

    await documentReference.set(
        map(<dynamic>['b', <String, dynamic>{}]), SetOptions.mergeAllFields);
    snapshot = await eventAccumulator.wait();
    expect(
        snapshot.data,
        map<dynamic>(
            <dynamic>['a', <String, dynamic>{}, 'b', <String, dynamic>{}]));

    snapshot = await documentReference.get(Source.SERVER);
    expect(
        snapshot.data,
        map<dynamic>(
            <dynamic>['a', <String, dynamic>{}, 'b', <String, dynamic>{}]));
    subscription.cancel();
  });

  test('testCanDeleteFieldUsingMerge', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');

    final Map<String, Object> initialValue = map(<dynamic>[
      'untouched',
      true,
      'foo',
      'bar',
      'nested',
      map<dynamic>(<dynamic>['untouched', true, 'foo', 'bar'])
    ]);
    await documentReference.set(initialValue);
    DocumentSnapshot doc = await documentReference.get();

    expect(doc.getBool('untouched'), isTrue);
    expect(doc.getBool('nested.untouched'), isTrue);
    expect(doc.contains('foo'), isTrue);
    expect(doc.contains('nested.foo'), isTrue);

    final Map<String, Object> mergeData = map(<dynamic>[
      'foo',
      FieldValue.delete(),
      'nested',
      map<dynamic>(<dynamic>['foo', FieldValue.delete()])
    ]);
    await documentReference.set(mergeData, SetOptions.mergeAllFields);

    doc = await documentReference.get();
    expect(doc.getBool('untouched'), isTrue);
    expect(doc.getBool('nested.untouched'), isTrue);
    expect(doc.contains('foo'), isFalse);
    expect(doc.contains('nested.foo'), isFalse);
  });

  test('testCanDeleteFieldUsingMergeFields', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');

    final Map<String, Object> initialValue = map(<dynamic>[
      'untouched',
      true,
      'foo',
      'bar',
      'inner',
      map<dynamic>(<dynamic>['removed', true, 'foo', 'bar']),
      'nested',
      map<dynamic>(<dynamic>['untouched', true, 'foo', 'bar'])
    ]);

    final Map<String, Object> mergeData = map(<dynamic>[
      'foo',
      FieldValue.delete(),
      'inner',
      map<dynamic>(<dynamic>['foo', FieldValue.delete()]),
      'nested',
      map<dynamic>(<dynamic>[
        'untouched',
        FieldValue.delete(),
        'foo',
        FieldValue.delete()
      ])
    ]);
    final Map<String, Object> finalData = map(<dynamic>[
      'untouched',
      true,
      'inner',
      map<dynamic>(),
      'nested',
      map<dynamic>(<dynamic>['untouched', true])
    ]);

    await documentReference.set(initialValue);
    await documentReference.set(mergeData,
        SetOptions.mergeFields(<String>['foo', 'inner', 'nested.foo']));

    final DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, finalData);
  });

  test('testCanSetServerTimestampsUsingMergeFields', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');

    final Map<String, Object> initialValue = map(<dynamic>[
      'untouched',
      true,
      'foo',
      'bar',
      'nested',
      map<dynamic>(<dynamic>['untouched', true, 'foo', 'bar'])
    ]);
    await documentReference.set(initialValue);
    final Map<String, Object> mergeData = map(<dynamic>[
      'foo',
      FieldValue.serverTimestamp(),
      'inner',
      map<dynamic>(<dynamic>['foo', FieldValue.serverTimestamp()]),
      'nested',
      map<dynamic>(<dynamic>['foo', FieldValue.serverTimestamp()])
    ]);

    await documentReference.set(mergeData,
        SetOptions.mergeFields(<String>['foo', 'inner', 'nested.foo']));

    final DocumentSnapshot doc = await documentReference.get();
    expect(doc.exists, isTrue);
    expect(doc.get('foo') is Timestamp, isTrue);
    expect(doc.get('inner.foo') is Timestamp, isTrue);
    expect(doc.get('nested.foo') is Timestamp, isTrue);
  });

  test('testMergeReplacesArrays', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Map<String, Object> initialValue = map(<dynamic>[
      'untouched',
      true,
      'data',
      'old',
      'topLevel',
      <String>['old', 'old'],
      'mapInArray',
      <Map<String, dynamic>>[
        map<String>(<String>['data', 'old'])
      ]
    ]);
    final Map<String, Object> mergeData = map(<dynamic>[
      'data',
      'new',
      'topLevel',
      <String>['new'],
      'mapInArray',
      <Map<String, dynamic>>[
        map<String>(<String>['data', 'new'])
      ]
    ]);
    final Map<String, Object> finalData = map(<dynamic>[
      'untouched',
      true,
      'data',
      'new',
      'topLevel',
      <String>['new'],
      'mapInArray',
      <Map<String, dynamic>>[
        map<String>(<String>['data', 'new'])
      ]
    ]);

    await documentReference.set(initialValue);
    await documentReference.set(mergeData, SetOptions.mergeAllFields);
    final DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, finalData);
  });

  test('testCanDeepMergeDataWithAnExistingDocumentUsingSet', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Map<String, Object> initialValue = map(<dynamic>[
      'owner.data',
      map<dynamic>(<dynamic>['name', 'Jonny', 'email', 'old@xyz.com'])
    ]);
    final Map<String, Object> finalData = map(<dynamic>[
      'desc',
      'NewDescription',
      'owner.data',
      map<String>(<String>['name', 'Sebastian', 'email', 'old@xyz.com'])
    ]);
    await documentReference.set(initialValue);
    await documentReference.set(
        map(<dynamic>[
          'desc',
          'NewDescription',
          'owner.data',
          map<String>(<String>['name', 'Sebastian', 'email', 'new@xyz.com'])
        ]),
        SetOptions.mergeFieldPaths(<FieldPath>[
          FieldPath.of(<String>['desc']),
          FieldPath.of(<String>['owner.data', 'name'])
        ]));
    final DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, finalData);
  });

  test('testFieldMaskCannotContainMissingFields', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');

    bool hadError = false;
    try {
      await documentReference.set(map(<String>['desc', 'NewDescription']),
          SetOptions.mergeFields(<String>['desc', 'owner']));
    } on ArgumentError catch (e) {
      hadError = true;
      expect(e.message,
          'Field \'owner\' is specified in your field mask but not in your input data.');
    } catch (e) {
      assert(false, 'This should not happen.');
    }

    expect(hadError, isTrue);
  });

  test('testFieldsNotInFieldMaskAreIgnored', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Map<String, Object> initialValue = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    final Map<String, Object> finalData = map(<dynamic>[
      'desc',
      'NewDescription',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    await documentReference.set(initialValue);
    await documentReference.set(
        map(<dynamic>['desc', 'NewDescription', 'owner', 'Sebastian']),
        SetOptions.mergeFields(<String>['desc']));
    final DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, finalData);
  });

  test('testFieldDeletesNotInFieldMaskAreIgnored', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Map<String, Object> initialValue = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    final Map<String, Object> finalData = map(<dynamic>[
      'desc',
      'NewDescription',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    await documentReference.set(initialValue);
    await documentReference.set(
        map(<dynamic>['desc', 'NewDescription', 'owner', FieldValue.delete()]),
        SetOptions.mergeFields(<String>['desc']));
    final DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, finalData);
  });

  test('testFieldTransformsNotInFieldMaskAreIgnored', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Map<String, Object> initialValue = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    final Map<String, Object> finalData = map(<dynamic>[
      'desc',
      'NewDescription',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    await documentReference.set(initialValue);
    await documentReference.set(
        map(<dynamic>[
          'desc',
          'NewDescription',
          'owner',
          FieldValue.serverTimestamp()
        ]),
        SetOptions.mergeFields(<String>['desc']));
    final DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, finalData);
  });

  test('testFieldMaskEmpty', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Map<String, Object> initialValue = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    final Map<String, Object> finalData = initialValue;
    await documentReference.set(initialValue);
    await documentReference.set(map(<String>['desc', 'NewDescription']),
        SetOptions.mergeFields(<String>[]));
    final DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, finalData);
  });

  test('testFieldInFieldMaskMultipleTimes', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Map<String, Object> initialValue = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    final Map<String, Object> finalData = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Sebastian', 'email', 'new@new.com'])
    ]);

    await documentReference.set(initialValue);
    await documentReference.set(
        map(<dynamic>[
          'desc',
          'NewDescription',
          'owner',
          map<String>(<String>['name', 'Sebastian', 'email', 'new@new.com'])
        ]),
        SetOptions.mergeFields(<String>['owner.name', 'owner', 'owner']));
    final DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, finalData);
  });

  test('testCanDeleteAFieldWithAnUpdate', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Map<String, Object> initialValue = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    final Map<String, Object> finalData = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Jonny'])
    ]);
    await documentReference.set(initialValue);
    await documentReference
        .updateFromList(<dynamic>['owner.email', FieldValue.delete()]);
    final DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, finalData);
  });

  test('testCanUpdateFieldsWithDots', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    await documentReference.set(map(<String>['a.b', 'old', 'c.d', 'old']));

    await documentReference.updateFromList(<dynamic>[
      FieldPath.of(<String>['a.b']),
      'new'
    ]);
    await documentReference.updateFromList(<dynamic>[
      FieldPath.of(<String>['c.d']),
      'new'
    ]);

    final DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, map<String>(<String>['a.b', 'new', 'c.d', 'new']));
  });

  test('testCanUpdateNestedFields', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    await documentReference.set(map(<dynamic>[
      'a',
      map<String>(<String>['b', 'old']),
      'c',
      map<String>(<String>['d', 'old'])
    ]));

    await documentReference.updateFromList(<String>['a.b', 'new']);
    await documentReference.update(map(<String>['c.d', 'new']));

    final DocumentSnapshot doc = await documentReference.get();
    expect(
        doc.data,
        map<dynamic>(<dynamic>[
          'a',
          map<String>(<String>['b', 'new']),
          'c',
          map<String>(<String>['d', 'new'])
        ]));
  });

  test('testDeleteDocument', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Map<String, Object> data = map(<String>['value', 'bar']);
    await documentReference.set(data);
    DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, data);
    await documentReference.delete();
    doc = await documentReference.get();
    expect(doc.exists, isFalse);
  });

  test('testCannotUpdateNonexistentDocument', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document();

    bool hadError = false;
    try {
      await documentReference.update(map(<String>['owner', 'abc']));
    } on FirebaseFirestoreError catch (e) {
      hadError = true;
      expect(e, isNotNull);
      expect(e.code, FirebaseFirestoreErrorCode.notFound);
    } catch (e) {
      assert(false, 'This should not happen.');
    }

    expect(hadError, isTrue);
  });

  test('testCanRetrieveNonexistentDocument', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document();
    final DocumentSnapshot documentSnapshot = await documentReference.get();
    expect(documentSnapshot.exists, isFalse);
    expect(documentSnapshot.data, isNull);

    final Completer<void> barrier = Completer<void>();

    StreamSubscription<DocumentSnapshot> listenerRegistration;

    try {
      listenerRegistration = documentReference.snapshots.listen(
        (DocumentSnapshot value) {
          expect(documentSnapshot.exists, isFalse);
          expect(documentSnapshot.data, isNull);
          barrier.complete(null);
        },
        onError: (dynamic error) {},
      );

      await barrier.future;
    } finally {
      if (listenerRegistration != null) {
        listenerRegistration.cancel();
      }
    }
  });

  test('testAddingToACollectionYieldsTheCorrectDocumentReference', () async {
    final Map<String, Object> data = map(<dynamic>['foo', 1.0]);
    final DocumentReference documentReference =
        await (await testCollection('rooms')).add(data);
    final DocumentSnapshot document = await documentReference.get();
    expect(document.data, data);
  });

  test('testQueriesAreValidatedOnClient', () async {
    // NOTE: Failure cases are validated in ValidationTest.
    final CollectionReference collection = await testCollection();
    final Query query = collection.whereGreaterThanOrEqualTo('x', 32);
    // Same inequality field works;
    query.whereLessThanOrEqualTo('x', 'cat');
    // Equality on different field works;
    query.whereEqualTo('y', 'cat');
    // Array contains on different field works;
    query.whereArrayContains('y', 'cat');

    // Ordering by inequality field succeeds.
    query.orderBy('x');
    collection.orderBy('x').whereGreaterThanOrEqualTo('x', 32);

    // inequality same as first order by works
    query.orderBy('x').orderBy('y');
    collection.orderBy('x').orderBy('y').whereGreaterThanOrEqualTo('x', 32);
    collection.orderBy('x', Direction.DESCENDING).whereEqualTo('y', 'true');

    // Equality different than orderBy works
    collection.orderBy('x').whereEqualTo('y', 'cat');
    // Array contains different than orderBy works
    collection.orderBy('x').whereArrayContains('y', 'cat');
  });

  test('testDocumentSnapshotEventsNonExistent', () async {
    final DocumentReference docRef = (await testCollection('rooms')).document();

    final Completer<void> completer = Completer<dynamic>();
    final StreamSubscription<DocumentSnapshot> listener = docRef
        .getSnapshots(MetadataChanges.include)
        .listen((DocumentSnapshot doc) {
      expect(doc, isNotNull);
      expect(doc.exists, isFalse);
      expect(completer.isCompleted, isFalse);
      completer.complete();
    }, onError: (dynamic error) {
      assert(false, 'This should not be reached.');
    });

    await completer.future;
    await listener.cancel();
  });

  test('testDocumentSnapshotEventsForAdd', () async {
    final DocumentReference docRef = (await testCollection('rooms')).document();

    final AwaitHelper<void> dataLatch = AwaitHelper<void>(3);
    final AwaitHelper<void> emptyLatch = AwaitHelper<void>(1);

    final StreamSubscription<DocumentSnapshot> listener = docRef
        .getSnapshots(MetadataChanges.include)
        .listen((DocumentSnapshot doc) {
      if (emptyLatch.isNotEmpty) {
        dataLatch.completeNext();
        emptyLatch.completeNext();
        expect(doc.exists, isFalse);
        return;
      }

      expect(doc.exists, isTrue);
      final int count = dataLatch.length;
      expect(count > 0, isTrue);

      dataLatch.completeNext();
      if (count == 2) {
        expect(doc.data, map<dynamic>(<dynamic>['a', 1.0]));
        expect(doc.metadata.hasPendingWrites, isTrue);
      } else if (count == 1) {
        expect(doc.data, map<dynamic>(<dynamic>['a', 1.0]));
        expect(doc.metadata.hasPendingWrites, isFalse);
      }
    });

    await emptyLatch.all;
    docRef.set(map(<dynamic>['a', 1.0]));
    await dataLatch.all;
    await listener.cancel();
  });

  test('testDocumentSnapshotEventsForChange', () async {
    final Map<String, Object> initialData = map(<dynamic>['a', 1.0]);
    final Map<String, Object> updateData = map(<dynamic>['a', 2.0]);
    final CollectionReference testCollection = await testCollectionWithDocs(
        map<Map<String, dynamic>>(<dynamic>['doc', initialData]));

    final DocumentReference docRef = testCollection.document('doc');
    final AwaitHelper<void> initialLatch = AwaitHelper<void>(1);
    final AwaitHelper<void> latch = AwaitHelper<void>(3);

    final StreamSubscription<DocumentSnapshot> listener = docRef
        .getSnapshots(MetadataChanges.include)
        .listen((DocumentSnapshot doc) {
      final int latchCount = latch.length;
      latch.completeNext();
      switch (latchCount) {
        case 3:
          expect(doc.data, initialData);
          expect(doc.metadata.hasPendingWrites, isFalse);
          expect(doc.metadata.isFromCache, isFalse);
          initialLatch.completeNext();
          break;
        case 2:
          expect(doc.data, updateData);
          expect(doc.metadata.hasPendingWrites, isTrue);
          expect(doc.metadata.isFromCache, isFalse);
          break;
        case 1:
          expect(doc.data, updateData);
          expect(doc.metadata.hasPendingWrites, isFalse);
          expect(doc.metadata.isFromCache, isFalse);
          break;
        default:
          fail('unexpected latch count');
      }
    });

    await initialLatch.all;
    await docRef.update(updateData);
    await latch.all;
    await listener.cancel();
  });

  test('testDocumentSnapshotEventsForDelete', () async {
    final Map<String, Object> initialData = map(<dynamic>['a', 1.0]);
    final DocumentReference docRef =
        (await testCollectionWithDocs(map(<dynamic>['doc', initialData])))
            .document('doc');
    final AwaitHelper<void> initialLatch = AwaitHelper<void>(1);
    final AwaitHelper<void> latch = AwaitHelper<void>(2);

    final StreamSubscription<DocumentSnapshot> listener = docRef
        .getSnapshots(MetadataChanges.include)
        .listen((DocumentSnapshot doc) {
      final int count = latch.length;
      latch.completeNext();
      switch (count) {
        case 2:
          expect(doc.exists, isTrue);
          expect(doc.data, initialData);
          expect(doc.metadata.hasPendingWrites, isFalse);
          initialLatch.completeNext();
          break;
        case 1:
          expect(doc.exists, isFalse);
          break;
        default:
          fail('unexpected latch count');
      }
    });

    await initialLatch.all;
    docRef.delete();
    await latch.all;
    await listener.cancel();
  });

  test('testQuerySnapshotEventsForAdd', () async {
    final CollectionReference collection = await testCollection();
    final DocumentReference docRef = collection.document();
    final Map<String, Object> data = map(<dynamic>['a', 1.0]);
    final AwaitHelper<void> emptyLatch = AwaitHelper<void>(1);
    final AwaitHelper<void> dataLatch = AwaitHelper<void>(3);

    final StreamSubscription<QuerySnapshot> listener = collection
        .getSnapshots(MetadataChanges.include)
        .listen((QuerySnapshot snapshot) {
      final int count = dataLatch.length;
      dataLatch.completeNext();
      expect(count > 0, isTrue);
      switch (count) {
        case 3:
          emptyLatch.completeNext();
          expect(snapshot.length, 0);
          break;
        case 2:
          expect(snapshot.length, 1);
          final DocumentSnapshot doc = snapshot.documents[0];
          expect(doc.data, data);
          expect(doc.metadata.hasPendingWrites, isTrue);
          break;
        case 1:
          expect(snapshot.length, 1);
          final DocumentSnapshot doc2 = snapshot.documents[0];
          expect(doc2.data, data);
          expect(doc2.metadata.hasPendingWrites, isFalse);
          break;
        default:
          fail('unexpected call to onSnapshot: $snapshot');
      }
    });

    await emptyLatch.all;
    docRef.set(data);
    await dataLatch.all;
    await listener.cancel();
  });

  test('testQuerySnapshotEventsForChange', () async {
    final Map<String, Object> initialData = map(<dynamic>['b', 1.0]);
    final Map<String, Object> updateData = map(<dynamic>['b', 2.0]);

    final CollectionReference collection =
        await testCollectionWithDocs(map(<dynamic>['doc', initialData]));
    final DocumentReference docRef = collection.document('doc');

    final AwaitHelper<void> initialLatch = AwaitHelper<void>(1);
    final AwaitHelper<void> dataLatch = AwaitHelper<void>(3);

    final StreamSubscription<QuerySnapshot> listener = collection
        .getSnapshots(MetadataChanges.include)
        .listen((QuerySnapshot snapshot) {
      final int count = dataLatch.length;
      dataLatch.completeNext();

      switch (count) {
        case 3:
          expect(snapshot.length, 1);
          final DocumentSnapshot document = snapshot.documents[0];
          expect(document.data, initialData);
          expect(document.metadata.hasPendingWrites, isFalse);
          expect(document.metadata.isFromCache, isFalse);
          initialLatch.completeNext();
          break;
        case 2:
          expect(snapshot.length, 1);
          final DocumentSnapshot document3 = snapshot.documents[0];
          expect(document3.data, updateData);
          expect(document3.metadata.hasPendingWrites, isTrue);
          expect(document3.metadata.isFromCache, isFalse);
          break;
        case 1:
          expect(snapshot.length, 1);
          final DocumentSnapshot document4 = snapshot.documents[0];
          expect(document4.data, updateData);
          expect(document4.metadata.hasPendingWrites, isFalse);
          expect(document4.metadata.isFromCache, isFalse);
          break;
        default:
          fail('unexpected event $snapshot');
      }
    });

    await initialLatch.all;
    await docRef.set(updateData);
    await dataLatch.all;
    await listener.cancel();
  });

  test('testQuerySnapshotEventsForDelete', () async {
    final Map<String, Object> initialData = map(<dynamic>['a', 1.0]);
    final CollectionReference collection =
        await testCollectionWithDocs(map(<dynamic>['doc', initialData]));
    final DocumentReference docRef = collection.document('doc');

    final AwaitHelper<void> initialLatch = AwaitHelper<void>(1);
    final AwaitHelper<void> dataLatch = AwaitHelper<void>(2);

    final StreamSubscription<QuerySnapshot> listener = collection
        .getSnapshots(MetadataChanges.include)
        .listen((QuerySnapshot snapshot) {
      final int count = dataLatch.length;
      dataLatch.completeNext();
      switch (count) {
        case 2:
          initialLatch.completeNext();
          expect(snapshot.length, 1);
          final DocumentSnapshot document = snapshot.documents[0];
          expect(document.data, map<double>(<dynamic>['a', 1.0]));
          expect(document.metadata.hasPendingWrites, isFalse);
          break;
        case 1:
          expect(snapshot.length, 0);
          break;
        default:
          fail('unexpected event $snapshot');
      }
    });

    await initialLatch.all;
    docRef.delete();
    await dataLatch.all;
    await listener.cancel();
  });

  test('testMetadataOnlyChangesAreNotFiredWhenNoOptionsProvided', () async {
    final DocumentReference docRef = (await testCollection()).document();

    final Map<String, Object> initialData = map(<dynamic>['a', 1.0]);
    final Map<String, Object> updateData = map(<dynamic>['b', 1.0]);

    final AwaitHelper<void> dataLatch = AwaitHelper<void>(2);
    final StreamSubscription<DocumentSnapshot> listener =
        docRef.snapshots.listen((DocumentSnapshot snapshot) {
      final int count = dataLatch.length;

      dataLatch.completeNext();
      switch (count) {
        case 2:
          expect(snapshot.data, map<double>(<dynamic>['a', 1.0]));
          break;
        case 1:
          expect(snapshot.data, map<double>(<dynamic>['b', 1.0]));
          break;
        default:
          fail('unexpected event $snapshot');
      }
    });

    docRef.set(initialData);
    docRef.set(updateData);
    await dataLatch.all;
    await listener.cancel();
  });

  test('testDocumentReferenceExposesFirestore', () async {
    final FirebaseFirestore firestore = await testFirestore();
    expect(
        identical(firestore.document('foo/bar').firestore, firestore), isTrue);
  });

  test('testCollectionReferenceExposesFirestore', () async {
    final FirebaseFirestore firestore = await testFirestore();
    expect(identical(firestore.collection('foo').firestore, firestore), isTrue);
  });

  test('testDocumentReferenceEquality', () async {
    final FirebaseFirestore firestore = await testFirestore();
    final DocumentReference docRef = firestore.document('foo/bar');
    expect(firestore.document('foo/bar'), docRef);
    expect(docRef, docRef.collection('blah').parent);

    expect(docRef, isNot(firestore.document('foo/BAR')));

    final FirebaseFirestore otherFirestore = await testFirestore();
    expect(docRef, isNot(otherFirestore.document('foo/bar')));
  });

  test('testQueryReferenceEquality', () async {
    final FirebaseFirestore firestore = await testFirestore();
    final Query query =
        firestore.collection('foo').orderBy('bar').whereEqualTo('baz', 42);
    final Query query2 =
        firestore.collection('foo').orderBy('bar').whereEqualTo('baz', 42);
    expect(query2, query);

    final Query query3 =
        firestore.collection('foo').orderBy('BAR').whereEqualTo('baz', 42);
    expect(query, isNot(query3));

    final FirebaseFirestore otherFirestore = await testFirestore();
    final Query query4 =
        otherFirestore.collection('foo').orderBy('bar').whereEqualTo('baz', 42);
    expect(query4, isNot(query));
  });

  test('testCanTraverseCollectionsAndDocuments', () async {
    final FirebaseFirestore firestore = await testFirestore();
    const String expected = 'a/b/c/d';
    // doc path from root Firestore.
    expect(firestore.document('a/b/c/d').path, expected);
    // collection path from root Firestore.
    expect(firestore.collection('a/b/c').document('d').path, expected);
    // doc path from CollectionReference.
    expect(firestore.collection('a').document('b/c/d').path, expected);
    // collection path from DocumentReference.
    expect(expected + '/e', firestore.document('a/b').collection('c/d/e').path);
  });

  test('testCanTraverseCollectionAndDocumentParents', () async {
    final FirebaseFirestore firestore = await testFirestore();
    CollectionReference collection = firestore.collection('a/b/c');
    expect(collection.path, 'a/b/c');

    final DocumentReference doc = collection.parent;
    expect(doc.path, 'a/b');

    collection = doc.parent;
    expect(collection.path, 'a');

    final DocumentReference nullDoc = collection.parent;
    expect(nullDoc, isNull);
  });

  test('testCanQueueWritesWhileOffline', () async {
    // Arrange
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final FirebaseFirestore firestore = documentReference.firestore;

    final Map<String, Object> data = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Sebastian', 'email', 'abc@xyz.com'])
    ]);

    // Act
    await firestore.disableNetwork();
    final Future<void> pendingWrite = documentReference.set(data);

    await firestore.enableNetwork();
    await pendingWrite;

    // Assert
    final DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, data);
    expect(doc.metadata.isFromCache, isFalse);
  });

  test('testCantGetDocumentsWhileOffline', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document();
    final FirebaseFirestore firestore = documentReference.firestore;
    await firestore.disableNetwork();

    expect(() => documentReference.get(), throwsA(anything));

    // Write the document to the local cache.
    final Map<String, Object> data = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Sebastian', 'email', 'abc@xyz.com'])
    ]);
    final Future<void> pendingWrite = documentReference.set(data);

    // The network is offline and we return a cached result.
    DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, data);
    expect(doc.metadata.isFromCache, isTrue);

    // Enable the network and fetch the document again.
    await firestore.enableNetwork();
    await pendingWrite;
    doc = await documentReference.get();
    expect(doc.data, data);
    expect(doc.metadata.isFromCache, isFalse);
  });

  test('testWriteStreamReconnectsAfterIdle', () async {
    final DocumentReference doc = await testDocument();
    final FirebaseFirestore firestore = doc.firestore;

    await doc.set(map(<String>['foo', 'bar']));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await firestore
        .getAsyncQueue()
        .runDelayedTasksUntil(TimerId.writeStreamIdle);
    await doc.set(map(<String>['foo', 'bar']));
  });

  test('testWatchStreamReconnectsAfterIdle', () async {
    final DocumentReference doc = await testDocument();
    final FirebaseFirestore firestore = doc.firestore;

    await waitForOnlineSnapshot(doc);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    firestore.getAsyncQueue().runDelayedTasksUntil(TimerId.listenStreamIdle);
    await waitForOnlineSnapshot(doc);
  });

  test('testCanDisableAndEnableNetworking', () async {
    // There's not currently a way to check if networking is in fact disabled,
    // so for now just test that the method is well-behaved and doesn't throw.
    final FirebaseFirestore firestore = await testFirestore();
    await firestore.enableNetwork();
    await firestore.enableNetwork();
    await firestore.disableNetwork();
    await firestore.disableNetwork();
    await firestore.enableNetwork();
  });
}

// ignore: always_specify_types
const map = TestUtil.map;
// ignore: always_specify_types
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types
const testCollection = IntegrationTestUtil.testCollection;
// ignore: always_specify_types
const testCollectionWithDocs = IntegrationTestUtil.testCollectionWithDocs;
// ignore: always_specify_types
const testDocument = IntegrationTestUtil.testDocument;
// ignore: always_specify_types
const waitForOnlineSnapshot = IntegrationTestUtil.waitForOnlineSnapshot;

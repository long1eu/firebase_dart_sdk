// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local_cache_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/metadata_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/set_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/transaction.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/write_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:firebase_app_dart/internal.dart' show InternalLogLevel;
import 'package:test/test.dart';

import '../../../unit/firebase/firestore/local/mock/database_mock.dart';
import '../../../util/await_helper.dart';
import '../../../util/event_accumulator.dart';
import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

// ignore_for_file: unawaited_futures
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
    final Map<String, Object?> initialValue = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    final Map<String, Object?> finalData = map(<dynamic>[
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
    DocumentSnapshot writerSnap = await writerRef.get(Source.cache);
    expect(writerSnap.exists, isTrue);

    await expectLater(
        () => readerRef.get(Source.cache), throwsA(isA<FirestoreError>()));
    /*try {
      await readerRef.get(Source.cache);
      fail('Should have thrown exception');
    } on FirebaseFirestoreError catch (e) {
      expect(e.code, FirestoreErrorCode.unavailable);
    }*/

    writerSnap = await writerRef.get();
    expect(writerSnap.data, map<String>(<String>['a', 'a', 'b', 'b']));
    final DocumentSnapshot readerSnap = await readerRef.get();
    expect(readerSnap.data, map<String>(<String>['a', 'a', 'b', 'b']));
  });

  test('testCanMergeDataWithAnExistingDocumentUsingSet', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Map<String, Object?> initialValue = map(<dynamic>[
      'desc',
      'Description',
      'owner.data',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    final Map<String, Object?> mergeData = map(<dynamic>[
      'updated',
      true,
      'owner.data',
      map<String>(<String>['name', 'Sebastian'])
    ]);
    final Map<String, Object?> finalData = map(<dynamic>[
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
    final Map<String, Object?> initialValue = map(<dynamic>['untouched', true]);
    final Map<String, Object?> mergeData = map(<dynamic>[
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

    snapshot = await documentReference.get(Source.server);
    expect(
        snapshot.data,
        map<dynamic>(
            <dynamic>['a', <String, dynamic>{}, 'b', <String, dynamic>{}]));
    await subscription.cancel();
  });

  test('testCanDeleteFieldUsingMerge', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');

    final Map<String, Object?> initialValue = map(<dynamic>[
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

    final Map<String, Object?> mergeData = map(<dynamic>[
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

    final Map<String, Object?> initialValue = map(<dynamic>[
      'untouched',
      true,
      'foo',
      'bar',
      'inner',
      map<dynamic>(<dynamic>['removed', true, 'foo', 'bar']),
      'nested',
      map<dynamic>(<dynamic>['untouched', true, 'foo', 'bar'])
    ]);

    final Map<String, Object?> mergeData = map(<dynamic>[
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
    final Map<String, Object?> finalData = map(<dynamic>[
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

    final Map<String, Object?> initialValue = map(<dynamic>[
      'untouched',
      true,
      'foo',
      'bar',
      'nested',
      map<dynamic>(<dynamic>['untouched', true, 'foo', 'bar'])
    ]);
    await documentReference.set(initialValue);
    final Map<String, Object?> mergeData = map(<dynamic>[
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
    expect(doc.get('foo'), isA<Timestamp>());
    expect(doc.get('inner.foo'), isA<Timestamp>());
    expect(doc.get('nested.foo'), isA<Timestamp>());
  });

  test('testMergeReplacesArrays', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Map<String, Object?> initialValue = map(<dynamic>[
      'untouched',
      true,
      'data',
      'old',
      'topLevel',
      <String>['old', 'old'],
      'mapInArray',
      <Map<String, Object?>>[
        map<String>(<String>['data', 'old'])
      ]
    ]);
    final Map<String, Object?> mergeData = map(<dynamic>[
      'data',
      'new',
      'topLevel',
      <String>['new'],
      'mapInArray',
      <Map<String, Object?>>[
        map<String>(<String>['data', 'new'])
      ]
    ]);
    final Map<String, Object?> finalData = map(<dynamic>[
      'untouched',
      true,
      'data',
      'new',
      'topLevel',
      <String>['new'],
      'mapInArray',
      <Map<String, Object?>>[
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
    final Map<String, Object?> initialValue = map(<dynamic>[
      'owner.data',
      map<dynamic>(<dynamic>['name', 'Jonny', 'email', 'old@xyz.com'])
    ]);
    final Map<String, Object?> finalData = map(<dynamic>[
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
      expect(
          e.message,
          'Field \'owner\' is specified in your field mask but not '
          'in your input data.');
    } catch (e) {
      assert(false, 'This should not happen.');
    }

    expect(hadError, isTrue);
  });

  test('testFieldsNotInFieldMaskAreIgnored', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Map<String, Object?> initialValue = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    final Map<String, Object?> finalData = map(<dynamic>[
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
    final Map<String, Object?> initialValue = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    final Map<String, Object?> finalData = map(<dynamic>[
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
    final Map<String, Object?> initialValue = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    final Map<String, Object?> finalData = map(<dynamic>[
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
    final Map<String, Object?> initialValue = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    final Map<String, Object?> finalData = initialValue;
    await documentReference.set(initialValue);
    await documentReference.set(map(<String>['desc', 'NewDescription']),
        SetOptions.mergeFields(<String>[]));
    final DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, finalData);
  });

  test('testFieldInFieldMaskMultipleTimes', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Map<String, Object?> initialValue = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    final Map<String, Object?> finalData = map(<dynamic>[
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
    final Map<String, Object?> initialValue = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    final Map<String, Object?> finalData = map(<dynamic>[
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
    final Map<String, Object?> data = map(<String>['value', 'bar']);
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
    } on FirestoreError catch (e) {
      hadError = true;
      expect(e, isNotNull);
      expect(e.code, FirestoreErrorCode.notFound);
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

    late StreamSubscription<DocumentSnapshot> listenerRegistration;
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
    final Map<String, Object?> data = map(<dynamic>['foo', 1.0]);
    final DocumentReference documentReference =
        await (await testCollection('rooms')).add(data);
    final DocumentSnapshot document = await documentReference.get();
    expect(document.data, data);
  });

  test('testQueriesAreValidatedOnClient', () async {
    // NOTE: Failure cases are validated in ValidationTest.
    final CollectionReference collection = await testCollection();
    final Query query = collection.whereGreaterThanOrEqualTo('x', 32)
      // Same inequality field works.
      ..whereLessThanOrEqualTo('x', 'cat')
      // Equality on different field works.
      ..whereEqualTo('y', 'cat')
      // Array contains on different field works.
      ..whereArrayContains('y', 'cat')
      // Array contains any on different field works.
      ..whereArrayContainsAny('y', <String>['cat'])
      // In on different field works.
      ..whereIn('y', <String>['cat'])
      // Ordering by inequality field succeeds.
      ..orderBy('x');
    collection.orderBy('x').whereGreaterThanOrEqualTo('x', 32);

    // Inequality same as first order by works
    query.orderBy('x').orderBy('y');
    collection.orderBy('x').orderBy('y').whereGreaterThanOrEqualTo('x', 32);
    collection.orderBy('x', Direction.descending).whereEqualTo('y', 'true');

    // Equality different than orderBy works.
    collection.orderBy('x').whereEqualTo('y', 'cat');
    // Array contains different than orderBy works.
    collection.orderBy('x').whereArrayContains('y', 'cat');
    // Array contains any different than orderBy works.
    collection.orderBy('x').whereArrayContainsAny('y', <String>['cat']);
    // In different than orderBy works.
    collection.orderBy('x').whereIn('y', <String>['cat']);
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
    final Map<String, Object?> initialData = map(<dynamic>['a', 1.0]);
    final Map<String, Object?> updateData = map(<dynamic>['a', 2.0]);
    final CollectionReference testCollection = await testCollectionWithDocs(
        map<Map<String, Object?>>(<dynamic>['doc', initialData]));

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
    final Map<String, Object?> initialData = map(<dynamic>['a', 1.0]);
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
    final Map<String, Object?> data = map(<dynamic>['a', 1.0]);
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
    final Map<String, Object?> initialData = map(<dynamic>['b', 1.0]);
    final Map<String, Object?> updateData = map(<dynamic>['b', 2.0]);

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
    final Map<String, Object?> initialData = map(<dynamic>['a', 1.0]);
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

    final Map<String, Object?> initialData = map(<dynamic>['a', 1.0]);
    final Map<String, Object?> updateData = map(<dynamic>['b', 1.0]);

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

    docRef //
      ..set(initialData)
      ..set(updateData);
    await dataLatch.all;
    await listener.cancel();
  });

  test('testDocumentReferenceExposesFirestore', () async {
    final Firestore firestore = await testFirestore();
    expect(
        identical(firestore.document('foo/bar').firestore, firestore), isTrue);
  });

  test('testCollectionReferenceExposesFirestore', () async {
    final Firestore firestore = await testFirestore();
    expect(identical(firestore.collection('foo').firestore, firestore), isTrue);
  });

  test('testDocumentReferenceEquality', () async {
    final Firestore firestore = await testFirestore();
    final DocumentReference docRef = firestore.document('foo/bar');
    expect(firestore.document('foo/bar'), docRef);
    expect(docRef, docRef.collection('blah').parent);

    expect(docRef, isNot(firestore.document('foo/BAR')));

    final Firestore otherFirestore = await testFirestore();
    expect(docRef, isNot(otherFirestore.document('foo/bar')));
  });

  test('testQueryReferenceEquality', () async {
    final Firestore firestore = await testFirestore();
    final Query query =
        firestore.collection('foo').orderBy('bar').whereEqualTo('baz', 42);
    final Query query2 =
        firestore.collection('foo').orderBy('bar').whereEqualTo('baz', 42);
    expect(query2, query);

    final Query query3 =
        firestore.collection('foo').orderBy('BAR').whereEqualTo('baz', 42);
    expect(query, isNot(query3));

    final Firestore otherFirestore = await testFirestore();
    final Query query4 =
        otherFirestore.collection('foo').orderBy('bar').whereEqualTo('baz', 42);
    expect(query4, isNot(query));
  });

  test('testCanTraverseCollectionsAndDocuments', () async {
    final Firestore firestore = await testFirestore();
    const String expected = 'a/b/c/d';
    // doc path from root Firestore.
    expect(firestore.document('a/b/c/d').path, expected);
    // collection path from root Firestore.
    expect(firestore.collection('a/b/c').document('d').path, expected);
    // doc path from CollectionReference.
    expect(firestore.collection('a').document('b/c/d').path, expected);
    // collection path from DocumentReference.
    expect('$expected/e', firestore.document('a/b').collection('c/d/e').path);
  });

  test('testCanTraverseCollectionAndDocumentParents', () async {
    final Firestore firestore = await testFirestore();
    CollectionReference collection = firestore.collection('a/b/c');
    expect(collection.path, 'a/b/c');

    final DocumentReference doc = collection.parent!;
    expect(doc.path, 'a/b');

    collection = doc.parent;
    expect(collection.path, 'a');

    final DocumentReference? nullDoc = collection.parent;
    expect(nullDoc, isNull);
  });

  test('testCanQueueWritesWhileOffline', () async {
    // Arrange
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Firestore firestore = documentReference.firestore;

    final Map<String, Object?> data = map(<dynamic>[
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
    final Firestore firestore = documentReference.firestore;
    await firestore.disableNetwork();

    expect(documentReference.get, throwsA(anything));

    // Write the document to the local cache.
    final Map<String, Object?> data = map(<dynamic>[
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
    final Firestore firestore = doc.firestore;
    final TaskScheduler scheduler = firestore.scheduler;

    await doc.set(map(<String>['foo', 'bar']));
    await Future<void>.delayed(const Duration(milliseconds: 250));

    scheduler.runUntil(TaskId.writeStreamIdle);
    await doc.set(map(<String>['foo', 'bar']));
  });

  test('testWatchStreamReconnectsAfterIdle', () async {
    final DocumentReference doc = await testDocument();
    final Firestore firestore = doc.firestore;
    final TaskScheduler scheduler = firestore.scheduler;

    await waitForOnlineSnapshot(doc);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    scheduler.runUntil(TaskId.listenStreamIdle);
    await waitForOnlineSnapshot(doc);
  });

  test('testCanDisableAndEnableNetworking', () async {
    // There's not currently a way to check if networking is in fact disabled,
    // so for now just test that the method is well-behaved and doesn't throw.
    final Firestore firestore = await testFirestore();
    await firestore.enableNetwork();
    await firestore.enableNetwork();
    await firestore.disableNetwork();
    await firestore.disableNetwork();
    await firestore.enableNetwork();
  });

  test('testWaitForPendingWritesResolves', () async {
    final DocumentReference documentReference =
        (await testCollection('abc')).document('123');
    final Firestore firestore = documentReference.firestore;
    final Map<String, Object?> data = map(<String>['foo', 'bar']);

    await firestore.disableNetwork();
    final Future<void> awaitsPendingWrites1 = firestore.waitForPendingWrites();
    final Future<void> pendingWrite = documentReference.set(data);
    final Future<void> awaitsPendingWrites2 = firestore.waitForPendingWrites();

    bool pendingWriteDone = false;
    bool awaitsPendingWrites2Done = false;
    unawaited(pendingWrite.then((_) => pendingWriteDone = true));
    unawaited(
        awaitsPendingWrites2.then((_) => awaitsPendingWrites2Done = true));

    // `awaitsPendingWrites1` completes immediately because there are no pending writes at the time it is created.
    await awaitsPendingWrites1;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(pendingWriteDone, isFalse);
    expect(awaitsPendingWrites2Done, isFalse);

    unawaited(firestore.enableNetwork());
    await awaitsPendingWrites2;
    await pendingWrite;
  });

  test('testWaitForPendingWritesFailsWhenUserChanges', () async {
    final DocumentReference documentReference =
        (await testCollection('abc')).document('123');
    final Firestore firestore = documentReference.firestore;
    final Map<String, Object?> data = map(<String>['foo', 'bar']);

    // Prevent pending writes receiving acknowledgement.
    await firestore.disableNetwork();
    final Future<void> pendingWrite = documentReference.set(data);
    final Future<void> awaitsPendingWrites = firestore.waitForPendingWrites();
    bool pendingWriteDone = false;
    unawaited(pendingWrite.then((_) => pendingWriteDone = true));
    unawaited(pendingWrite.catchError((Object _) {}));

    final Future<void> expectation = expectLater(
        awaitsPendingWrites,
        throwsA(isA<FirestoreError>().having(
            (FirestoreError e) => e.message,
            'message',
            "'waitForPendingWrites' task is cancelled due to User change.")));

    IntegrationTestUtil.testChangeUserTo(firestore, const User('new user'));
    await expectation;
    expect(pendingWriteDone, isFalse);
  });

  test('testPendingWriteTaskResolveWhenOfflineIfThereIsNoPending', () async {
    final DocumentReference documentReference =
        (await testCollection('abc')).document('123');
    final Firestore firestore = documentReference.firestore;

    await firestore.disableNetwork();
    await firestore.waitForPendingWrites();
  });

  test('testCancellingAListenerAfterTerminateDoesNotFail', () async {
    final Firestore firestore = await testFirestore();
    final StreamSubscription<QuerySnapshot> subscription =
        firestore.collection('abc').snapshots.listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await firestore.terminate();
    await subscription.cancel();
  });

  test('testSnapshotsInSyncListenerFiresAfterListenersInSync', () async {
    final Map<String, Object?> data = map(<dynamic>['foo', 1.0]);
    final CollectionReference collection = await testCollection();
    final DocumentReference documentReference = await collection.add(data);
    final List<String> events = <String>[];

    final Completer<void> gotInitialSnapshot = Completer<void>();
    final Completer<void> done = Completer<void>();

    final StreamSubscription<DocumentSnapshot> docSubscription =
        documentReference.snapshots.listen((DocumentSnapshot value) {
      events.add('doc');
      if (!gotInitialSnapshot.isCompleted) {
        gotInitialSnapshot.complete();
      }
    });
    await gotInitialSnapshot.future;
    events.clear();

    final StreamSubscription<void> inSyncSubscription =
        documentReference.firestore.snapshotsInSync.listen((_) {
      events.add('snapshots-in-sync');
      if (events.length == 3) {
        // We should have an initial snapshots-in-sync event, then a snapshot event for set(), then another event to
        // indicate we're in sync again.
        expect(
            events, <String>['snapshots-in-sync', 'doc', 'snapshots-in-sync']);
        done.complete();
      }
    });
    await documentReference.set(map(<dynamic>['foo', 3.0]));
    await done.future;

    await inSyncSubscription.cancel();
    await docSubscription.cancel();
  });

  test('testClientCallsAfterShutdownFails', () async {
    final Firestore firestore = await testFirestore();
    await firestore.shutdown();
    await expectError(
        firestore.disableNetwork, 'The client has already been terminated.');
  });

  test('testUpdateWithEmptyObjectReplacesAllFields', () async {
    final DocumentReference documentReference = await testDocument();
    await documentReference.set(<String, Object?>{'a': 'a'});

    await documentReference.update(<String, Object?>{'a': <String, Object?>{}});
    final DocumentSnapshot snapshot = await documentReference.get();
    expect(snapshot.data, <String, Object?>{'a': <String, Object?>{}});
  });

  test('testMergeWithEmptyObjectReplacesAllFields', () async {
    final DocumentReference documentReference = await testDocument();
    await documentReference.set(<String, Object?>{'a': 'a'});

    await documentReference.set(
        <String, Object?>{'a': <String, Object?>{}}, SetOptions.mergeAllFields);
    final DocumentSnapshot snapshot = await documentReference.get();
    expect(snapshot.data, <String, Object?>{'a': <String, Object?>{}});
  });

  test('testMaintainsPersistenceAfterRestarting', () async {
    // A fixed database file: the second instance must see what the first one persisted.
    const String dbName = 'integration/firestore_restart_persistence.db';
    DatabaseMock.deleteDatabaseFiles(dbName);

    final Firestore firestore = await IntegrationTestUtil.testFirestoreInstance(
        IntegrationTestUtil.provider.projectId,
        InternalLogLevel.w,
        IntegrationTestUtil.newTestSettings(),
        'integration/firestore',
        fixedDbName: dbName);
    final DocumentReference docRef =
        firestore.collection('col1').document('doc1');
    await docRef.set(<String, Object?>{'foo': 'bar'});
    await firestore.terminate();

    // Restart with the same database file to check that the persisted data is still there.
    final Firestore firestore2 =
        await IntegrationTestUtil.testFirestoreInstance(
            IntegrationTestUtil.provider.projectId,
            InternalLogLevel.w,
            IntegrationTestUtil.newTestSettings(),
            'integration/firestore',
            fixedDbName: dbName);
    final DocumentSnapshot doc =
        await firestore2.document(docRef.path).get(Source.cache);
    expect(doc.exists, isTrue);
    expect(doc.data, <String, Object?>{'foo': 'bar'});
  });

  // The message of errors that are wrapped into a FirestoreError by the document operations is prefixed with the type
  // of the original error ("Invalid argument(s): ..."), so only check that it contains the expected text.
  Future<void> expectErrorContaining(
      FutureOr<dynamic> Function() runnable, String text) async {
    await expectLater(
        () async => runnable(),
        throwsA(predicate(
            (Object? e) => (e as dynamic).message.toString().contains(text))));
  }

  test('testNewOperationThrowsAfterFirestoreTerminate', () async {
    final Firestore instance = await testFirestore();
    final DocumentReference reference = instance.document('abc/123');
    await reference.set(<String, Object?>{'Field': 100});

    await instance.terminate();

    const String expectedMessage = 'The client has already been terminated.';
    await expectErrorContaining(reference.get, expectedMessage);
    await expectErrorContaining(
        () => reference.update(<String, Object?>{'Field': 1}), expectedMessage);
    await expectErrorContaining(
        () => reference.set(<String, Object?>{'Field': 1}), expectedMessage);
    await expectErrorContaining(
        () => instance.runBatch((WriteBatch batch) async {
              batch.update(reference, <String, Object?>{'Field': 1});
            }),
        expectedMessage);
    await expectErrorContaining(
        () => instance.runTransaction<DocumentSnapshot>(
            (Transaction transaction) => transaction.get(reference)),
        expectedMessage);
  });

  test('testTerminateCalledMultipleTimes', () async {
    final Firestore instance = await testFirestore();
    final DocumentReference reference = instance.document('abc/123');
    await reference.set(<String, Object?>{'Field': 100});

    await instance.terminate();

    const String expectedMessage = 'The client has already been terminated.';
    await expectErrorContaining(reference.get, expectedMessage);

    // Calling a second time should go through and change nothing.
    await instance.terminate();

    await expectErrorContaining(reference.get, expectedMessage);
  });

  test('testNamedDbHaveDifferentPersistence', () async {
    final String projectId = IntegrationTestUtil.provider.projectId;
    final Firestore db1 = await IntegrationTestUtil.testFirestoreInstance(
        projectId,
        InternalLogLevel.w,
        IntegrationTestUtil.newTestSettings(),
        'integration/firestore',
        databaseName: 'db1');
    final Firestore db2 = await IntegrationTestUtil.testFirestoreInstance(
        projectId,
        InternalLogLevel.w,
        IntegrationTestUtil.newTestSettings(),
        'integration/firestore',
        databaseName: 'db2');

    final DocumentReference docRef = db1.collection('col1').document(autoId());
    await docRef.set(<String, Object?>{'foo': 'bar'});
    expect((await docRef.get(Source.server)).get('foo'), 'bar');

    final DocumentReference docRef2 = db2.document(docRef.path);

    // db2 never saw the document: it is neither in its cache nor on the server (a different named database).
    await expectLater(
        docRef2.get(Source.cache),
        throwsA(isA<FirestoreError>().having((FirestoreError e) => e.code,
            'code', FirestoreErrorCode.unavailable)));
    expect((await docRef2.get(Source.server)).exists, isFalse);
    expect((await docRef2.get()).exists, isFalse);
  });

  test('testCanGetDocumentWithMemoryLruGCEnabled', () async {
    final FirestoreSettings base = IntegrationTestUtil.newTestSettings();
    final Firestore db = await testFirestore(FirestoreSettings(
      host: base.host,
      port: base.port,
      sslEnabled: base.sslEnabled,
      cacheSettings: MemoryCacheSettings(gcSettings: MemoryLruGcSettings()),
    ));

    final DocumentReference doc = db.collection('abc').document('123');
    await doc.set(<String, Object?>{'key': 'value'});

    final DocumentSnapshot snapshot = await doc.get(Source.cache);
    expect(snapshot.exists, isTrue);
    expect(snapshot.metadata.isFromCache, isTrue);
    expect(snapshot.data, <String, Object?>{'key': 'value'});
  });

  test('testCannotGetDocumentWithMemoryEagerGcEnabled', () async {
    final FirestoreSettings base = IntegrationTestUtil.newTestSettings();
    final Firestore db = await testFirestore(FirestoreSettings(
      host: base.host,
      port: base.port,
      sslEnabled: base.sslEnabled,
      cacheSettings:
          const MemoryCacheSettings(gcSettings: MemoryEagerGcSettings()),
    ));

    final DocumentReference doc = db.collection('abc').document('123');
    await doc.set(<String, Object?>{'key': 'value'});

    await expectLater(
        doc.get(Source.cache),
        throwsA(isA<FirestoreError>().having((FirestoreError e) => e.code,
            'code', FirestoreErrorCode.unavailable)));
  });

  group('SDK ordering is consistent with the backend', () {
    final Map<String, Map<String, Object?>> idDocs =
        <String, Map<String, Object?>>{
      for (final String id in <String>[
        'A',
        'a',
        'Aa',
        '7',
        '12',
        '__id7__',
        '__id12__',
        '__id-2__',
        '__id1_',
        '_id1__',
        '__id',
        '__id9223372036854775807__',
        '__id-9223372036854775808__',
      ])
        id: <String, Object?>{'a': 1},
    };
    const List<String> idsInOrder = <String>[
      '__id-9223372036854775808__',
      '__id-2__',
      '__id7__',
      '__id12__',
      '__id9223372036854775807__',
      '12',
      '7',
      'A',
      'Aa',
      '__id',
      '__id1_',
      '_id1__',
      'a',
    ];

    // Values in the order of the backend (also used as map values, array elements and map keys).
    const List<String> unicodeValuesByDocId = <String>[
      'Łukasiewicz', // a
      'Sierpiński', // b
      '岩澤', // c
      '🄟', // d
      'Ｐ', // e
      '︒', // f
      '🐵', // g
      '你好', // h
      '你顥', // i
      '😁', // j
      '😀', // k
    ];
    const List<String> unicodeDocIds = <String>[
      'b', 'a', 'h', 'i', 'c', 'f', 'e', 'd', 'g', 'k', 'j', //
    ];

    Map<String, Map<String, Object?>> unicodeDocs(
        Object? Function(String value) wrap) {
      return <String, Map<String, Object?>>{
        for (int i = 0; i < unicodeValuesByDocId.length; i++)
          String.fromCharCode('a'.codeUnitAt(0) + i): <String, Object?>{
            'value': wrap(unicodeValuesByDocId[i]),
          },
      };
    }

    test('snapshotListenerSortsQueryByDocumentIdsSameAsGetQuery', () async {
      final CollectionReference colRef = await testCollectionWithDocs(idDocs);
      await IntegrationTestUtil.assertSDKQueryResultsConsistentWithBackend(
          colRef,
          colRef.orderByField(FieldPath.documentId()),
          idDocs,
          idsInOrder);
    });

    test('snapshotListenerSortsFilteredQueryByDocumentIdsSameAsGetQuery',
        () async {
      final CollectionReference colRef = await testCollectionWithDocs(idDocs);
      final Query filtered = colRef
          .whereGreaterThanField(FieldPath.documentId(), '__id7__')
          .whereLessThanOrEqualToField(FieldPath.documentId(), 'A')
          .orderByField(FieldPath.documentId());
      await IntegrationTestUtil.assertSDKQueryResultsConsistentWithBackend(
          colRef, filtered, idDocs, <String>[
        '__id12__',
        '__id9223372036854775807__',
        '12',
        '7',
        'A',
      ]);
    });

    test('sdkOrdersQueryByDocumentIdTheSameWayOnlineAndOffline', () async {
      final CollectionReference colRef = await testCollectionWithDocs(idDocs);
      await IntegrationTestUtil.checkOnlineAndOfflineResultsMatch(
          colRef, colRef.orderByField(FieldPath.documentId()), idsInOrder);
    });

    test('snapshotListenerSortsUnicodeStringsAsServer', () async {
      final Map<String, Map<String, Object?>> docs =
          unicodeDocs((String v) => v);
      final CollectionReference colRef = await testCollectionWithDocs(docs);
      await IntegrationTestUtil.assertSDKQueryResultsConsistentWithBackend(
          colRef, colRef.orderBy('value'), docs, unicodeDocIds);
    });

    test('snapshotListenerSortsUnicodeStringsInArrayAsServer', () async {
      final Map<String, Map<String, Object?>> docs =
          unicodeDocs((String v) => <Object?>[v]);
      final CollectionReference colRef = await testCollectionWithDocs(docs);
      await IntegrationTestUtil.assertSDKQueryResultsConsistentWithBackend(
          colRef, colRef.orderBy('value'), docs, unicodeDocIds);
    });

    test('snapshotListenerSortsUnicodeStringsInMapAsServer', () async {
      final Map<String, Map<String, Object?>> docs =
          unicodeDocs((String v) => <String, Object?>{'foo': v});
      final CollectionReference colRef = await testCollectionWithDocs(docs);
      await IntegrationTestUtil.assertSDKQueryResultsConsistentWithBackend(
          colRef, colRef.orderBy('value'), docs, unicodeDocIds);
    });

    test('snapshotListenerSortsUnicodeStringsInMapKeyAsServer', () async {
      final Map<String, Map<String, Object?>> docs =
          unicodeDocs((String v) => <String, Object?>{v: 'foo'});
      final CollectionReference colRef = await testCollectionWithDocs(docs);
      await IntegrationTestUtil.assertSDKQueryResultsConsistentWithBackend(
          colRef, colRef.orderBy('value'), docs, unicodeDocIds);
    });

    test('snapshotListenerSortsUnicodeStringsInDocumentKeyAsServer', () async {
      final List<String> keys = <String>[
        'Łukasiewicz',
        'Sierpiński',
        '岩澤',
        '🄟',
        'Ｐ',
        '︒',
        '🐵',
        '你好',
        '你顥',
        '😁',
        '😀',
      ];
      final Map<String, Map<String, Object?>> docs =
          <String, Map<String, Object?>>{
        for (final String key in keys) key: <String, Object?>{'value': 'foo'},
      };
      final CollectionReference colRef = await testCollectionWithDocs(docs);
      await IntegrationTestUtil.assertSDKQueryResultsConsistentWithBackend(
          colRef, colRef.orderByField(FieldPath.documentId()), docs, <String>[
        'Sierpiński',
        'Łukasiewicz',
        '你好',
        '你顥',
        '岩澤',
        '︒',
        'Ｐ',
        '🄟',
        '🐵',
        '😀',
        '😁',
      ]);
    });

    test('snapshotListenerSortsInvalidUnicodeStringsAsServer', () async {
      final Map<String, Map<String, Object?>> testDocs =
          <String, Map<String, Object?>>{
        'a': <String, Object?>{'value': 'Z'},
        'b': <String, Object?>{'value': '你好'},
        'c': <String, Object?>{'value': '😀'},
        'd': <String, Object?>{'value': 'ab\uD800'}, // Lone high surrogate.
        'e': <String, Object?>{'value': 'ab\uDC00'}, // Lone low surrogate.
        'f': <String, Object?>{'value': 'ab\uD800\uD800'}, // Unpaired high.
        'g': <String, Object?>{'value': 'ab\uDC00\uDC00'}, // Unpaired low.
      };
      final CollectionReference colRef = await testCollectionWithDocs(testDocs);

      // Invalid surrogates do not survive the UTF-8 encoding of the wire: upstream (Java protobuf) gets "?", Dart's UTF-8
      // encoder substitutes U+FFFD. Server, cache and listener agree on that, which is what this test checks.
      final Map<String, Map<String, Object?>> actualDocs =
          <String, Map<String, Object?>>{
        'a': <String, Object?>{'value': 'Z'},
        'b': <String, Object?>{'value': '你好'},
        'c': <String, Object?>{'value': '😀'},
        'd': <String, Object?>{'value': 'ab\uFFFD'},
        'e': <String, Object?>{'value': 'ab\uFFFD'},
        'f': <String, Object?>{'value': 'ab\uFFFD\uFFFD'},
        'g': <String, Object?>{'value': 'ab\uFFFD\uFFFD'},
      };
      await IntegrationTestUtil.assertSDKQueryResultsConsistentWithBackend(
          colRef,
          colRef.orderBy('value'),
          actualDocs,
          <String>['a', 'd', 'e', 'f', 'g', 'b', 'c']);
    });
  });
}

// ignore: always_specify_types, type_annotate_public_apis
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types, type_annotate_public_apis
const testCollection = IntegrationTestUtil.testCollection;
// ignore: always_specify_types, type_annotate_public_apis
const testCollectionWithDocs = IntegrationTestUtil.testCollectionWithDocs;
// ignore: always_specify_types, type_annotate_public_apis
const testDocument = IntegrationTestUtil.testDocument;
// ignore: always_specify_types, type_annotate_public_apis
const waitForOnlineSnapshot = IntegrationTestUtil.waitForOnlineSnapshot;

// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/collection_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_settings.dart';
import 'package:firebase_firestore/src/firebase/firestore/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/transaction.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/types.dart'
    hide Transaction;
import 'package:firebase_firestore/src/firebase/firestore/write_batch.dart';
import 'package:test/test.dart';

import '../../../unit/firebase/firestore/local/mock/database_mock.dart';
import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/validation_test';

  setUp(() => testFirestore());

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  // Helpers

  /// Performs a write using each set and/or update API and makes sure it fails
  /// with the expected reason.
  Future<void> expectWriteError(Map<String, dynamic> data, String reason,
      [bool includeSets = true, bool includeUpdates = true]) async {
    final DocumentReference ref = await testDocument();

    if (includeSets) {
      await expectError(() => ref.set(data), reason);
      await expectError(() => ref.firestore.batch().set(ref, data), reason);
    }

    if (includeUpdates) {
      await expectError(() => ref.update(data), reason);
      await expectError(() => ref.firestore.batch().update(ref, data), reason);
    }

    await ref.firestore.runTransaction<void>((Transaction transaction) async {
      if (includeSets) {
        await expectError(() => transaction.set(ref, data), reason);
      }

      if (includeUpdates) {
        await expectError(() => transaction.update(ref, data), reason);
      }

      return null;
    });
  }

  /// Performs a write using each update API and makes sure it fails with the
  /// expected reason.
  void expectUpdateError(Map<String, Object> data, String reason) {
    expectWriteError(
        data, reason, /*includeSets=*/ false, /*includeUpdates=*/ true);
  }

  /// Tests a field path with all of our APIs that accept field paths and
  /// ensures they fail with the specified reason.
  Future<void> verifyFieldPathThrows(String path, String reason) async {
    // Get an arbitrary snapshot we can use for testing.
    final DocumentReference docRef = await testDocument();
    await docRef.set(map(<dynamic>['test', 1]));
    final DocumentSnapshot snapshot = await docRef.get();

    // snapshot paths
    await expectError(() => snapshot.get(path), reason);

    // Query filter / order fields
    final CollectionReference coll = await testCollection();
    // whereLessThan(), etc. omitted for brevity since the code path is
    // trivially shared.
    await expectError(() => coll.whereEqualTo(path, 1), reason);
    await expectError(() => coll.orderBy(path), reason);

    // update() paths.
    await expectError(() => docRef.updateFromList(<dynamic>[path, 1]), reason);
  }

  test('firestoreSettingsNullHostFails', () async {
    await expectError(() => FirebaseFirestoreSettings(host: null),
        'Provided host must not be null.');
  });

  test('disableSslWithoutSettingHostFails', () async {
    await expectError(
        () => FirebaseFirestoreSettings(sslEnabled: false),
        'You can\'t set the \'sslEnabled\' setting unless you also set a '
        'non-default \'host\'.');
  });

  test('firestoreGetInstanceWithNullAppFails', () async {
    await expectError(() => FirebaseFirestore.getInstance(null),
        'Provided FirebaseApp must not be null.');
  });

  void withApp(String name, Consumer<FirebaseApp> toRun) {
    final FirebaseApp app = FirebaseApp.withOptions(
      FirebaseOptions(
        apiKey: 'key',
        applicationId: 'appId',
        projectId: 'projectId',
      ),
      (_) {},
      null,
      name,
    );

    try {
      toRun(app);
    } finally {
      app.delete();
    }
  }

  test('firestoreGetInstanceWithNonNullAppReturnsNonNullInstance', () async {
    withApp(
        'firestoreTestApp',
        (FirebaseApp app) => expect(
            FirebaseFirestore.getInstance(app,
                openDatabase: DatabaseMock.create),
            isNotNull));
  });

  test('collectionPathsMustBeOddLength', () async {
    final FirebaseFirestore firestore = await testFirestore();
    final DocumentReference baseDocRef = firestore.document('foo/bar');
    final List<String> badAbsolutePaths = <String>[
      'foo/bar',
      'foo/bar/baz/quu'
    ];

    final List<String> badRelativePaths = <String>['/', 'baz/quu'];
    final List<int> badPathLengths = <int>[2, 4];

    for (int i = 0; i < badAbsolutePaths.length; i++) {
      final String path = badAbsolutePaths[i];
      final String relativePath = badRelativePaths[i];
      final String error =
          'Invalid collection reference. Collection references must have an odd'
          ' number of segments, but $path has ${badPathLengths[i]}';

      await expectError(() => firestore.collection(path), error);
      await expectError(() => baseDocRef.collection(relativePath), error);
    }
  });

  test('pathsMustNotHaveEmptySegments', () async {
    final FirebaseFirestore firestore = await testFirestore()
      // NOTE: leading / trailing slashes are okay.
      ..collection('/foo/')
      ..collection('/foo')
      ..collection('foo/');

    final List<String> badPaths = <String>['foo//bar//baz', '//foo', 'foo//'];
    final CollectionReference collection =
        firestore.collection('test-collection');
    final DocumentReference doc = collection.document('test-document');
    for (String path in badPaths) {
      final String reason =
          'Invalid path ($path). Paths must not contain // in them.';

      await expectError(() => firestore.collection(path), reason);
      await expectError(() => firestore.document(path), reason);
      await expectError(() => collection.document(path), reason);
      await expectError(() => doc.collection(path), reason);
    }
  });

  test('documentPathsMustBeEvenLength', () async {
    final FirebaseFirestore firestore = await testFirestore();
    final CollectionReference baseCollectionRef = firestore.collection('foo');
    final List<String> badAbsolutePaths = <String>['foo', 'foo/bar/baz'];
    final List<String> badRelativePaths = <String>['/', 'bar/baz'];
    final List<int> badPathLengths = <int>[1, 3];

    for (int i = 0; i < badAbsolutePaths.length; i++) {
      final String path = badAbsolutePaths[i];
      final String relativePath = badRelativePaths[i];
      final String error =
          'Invalid document reference. Document references must have an even'
          ' number of segments, but $path has ${badPathLengths[i]}';
      await expectError(() => firestore.document(path), error);
      await expectError(() => baseCollectionRef.document(relativePath), error);
    }
  });

  test('writesMustNotContainDirectlyNestedLists', () async {
    await expectWriteError(
        map<dynamic>(<dynamic>[
          'nested-array',
          <dynamic>[
            1,
            <int>[2]
          ]
        ]),
        'Invalid data. Nested arrays are not supported');
  });

  test('writesMayContainIndirectlyNestedLists', () async {
    final Map<String, Object> data = map(<dynamic>[
      'nested-array',
      <dynamic>[
        1,
        map<List<int>>(<dynamic>[
          'foo',
          <int>[2]
        ])
      ]
    ]);

    final CollectionReference collection = await testCollection();
    final DocumentReference ref = collection.document();
    final DocumentReference ref2 = collection.document();

    await ref.set(data);
    await ref.firestore.batch().set(ref, data).commit();

    await ref.update(data);
    await ref.firestore.batch().update(ref, data).commit();

    await ref.firestore.runTransaction<void>((Transaction transaction) {
      // Note ref2 does not exist at this point so set that and update ref.
      transaction
        ..update(ref, data)
        ..set(ref2, data);
      return null;
    });
  });

  test('writesMustNotContainReferencesToADifferentDatabase', () async {
    final FirebaseFirestore firestore2 = await testAlternateFirestore();
    final DocumentReference ref = firestore2.document('baz/quu');
    final Map<String, Object> data = map<dynamic>(<dynamic>['foo', ref]);

    await expectWriteError(
        data,
        'Invalid data. Document reference is for database '
        '${IntegrationTestUtil.badProjectId}/(default) but should be for '
        'database ${IntegrationTestUtil.provider.projectId}/(default) '
        '(found in field foo)');
  });

  test('writesMustNotContainReservedFieldNames', () async {
    await expectWriteError(
        map<dynamic>(<dynamic>['__baz__', 1]),
        'Invalid data. Document fields cannot begin and end with __ '
        '(found in field __baz__)');
    await expectWriteError(
        map<dynamic>(<dynamic>[
          'foo',
          map<dynamic>(<dynamic>['__baz__', 1])
        ]),
        'Invalid data. Document fields cannot begin and end with __ '
        '(found in field foo.__baz__)');
    await expectWriteError(
        map<dynamic>(<dynamic>[
          '__baz__',
          map<dynamic>(<dynamic>['foo', 1])
        ]),
        'Invalid data. Document fields cannot begin and end with __ '
        '(found in field __baz__)');

    expectUpdateError(
        map<dynamic>(<dynamic>['__baz__', 1]),
        'Invalid data. Document fields cannot begin and end with __ '
        '(found in field __baz__)');
    expectUpdateError(
        map<dynamic>(<dynamic>['baz.__foo__', 1]),
        'Invalid data. Document fields cannot begin and end with '
        '__ (found in field baz.__foo__)');
  });

  test('setsMustNotContainFieldValueDelete', () async {
    final DocumentReference ref = await testDocument();
    await expectError(
        () => ref.set(map(<dynamic>['foo', FieldValue.delete()])),
        'Invalid data. FieldValue.delete() can only be used with update() and'
        ' set() with SetOptions.merge() (found in field foo)');
  });

  test('updatesMustNotContainNestedFieldValueDeletes', () async {
    final DocumentReference ref = await testDocument();
    await expectError(
        () => ref.update(map(<dynamic>[
              'foo',
              map<dynamic>(<dynamic>['bar', FieldValue.delete()])
            ])),
        'Invalid data. FieldValue.delete() can only appear at the top level of'
        ' your update data (found in field foo.bar)');
  });

  test('batchWritesRequireCorrectDocumentReferences', () async {
    final DocumentReference badRef =
        (await testAlternateFirestore()).document('foo/bar');
    const String reason =
        'Provided document reference is from a different Firestore instance.';
    final Map<String, Object> data = map<dynamic>(<dynamic>['foo', 1]);
    final WriteBatch batch = (await testFirestore()).batch();
    await expectError(() => batch.set(badRef, data), reason);
    await expectError(() => batch.update(badRef, data), reason);
    await expectError(() => batch.delete(badRef), reason);
  });

  test('transactionsRequireCorrectDocumentReferences', () async {
    final DocumentReference badRef =
        (await testAlternateFirestore()).document('foo/bar');
    const String reason =
        'Provided document reference is from a different Firestore instance.';
    final Map<String, Object> data = map<dynamic>(<dynamic>['foo', 1]);

    await (await testFirestore())
        .runTransaction<void>((Transaction transaction) async {
      await expectError(() async {
        // Because .get() throws a checked exception for missing docs, we have
        // to try/catch it.
        try {
          await transaction.get(badRef);
        } on FirebaseFirestoreError catch (e) {
          fail('transaction.get() triggered wrong exception: $e');
        }
      }, reason);

      await expectError(() => transaction.set(badRef, data), reason);
      await expectError(() => transaction.update(badRef, data), reason);
      await expectError(() => transaction.delete(badRef), reason);
      return null;
    });
  });

  test('fieldPathsMustNotHaveEmptySegments', () async {
    final List<String> badFieldPaths = <String>['', 'foo..baz', '.foo', 'foo.'];
    for (String fieldPath in badFieldPaths) {
      final String reason =
          'Invalid field path ($fieldPath). Paths must not be empty, begin '
          'with \'.\', end with \'.\', or contain \'..\'';
      await verifyFieldPathThrows(fieldPath, reason);
    }
  });

  test('fieldPathsMustNotHaveInvalidSegments', () async {
    final List<String> badFieldPaths = <String>[
      'foo~bar',
      'foo*bar',
      'foo/bar',
      'foo[1',
      'foo]1',
      'foo[1]'
    ];
    for (String fieldPath in badFieldPaths) {
      final String reason =
          'Invalid field path ($fieldPath). Paths must not contain \'~\', \'*\', \'/\', \'[\', or \']\'';
      await verifyFieldPathThrows(fieldPath, reason);
    }
  });

  test('fieldNamesMustNotBeEmpty', () async {
    String reason =
        'Invalid field path. Provided path must not be null or empty.';
    await expectError(() => FieldPath.of(<String>[]), reason);

    reason =
        'Invalid field name at argument 1. Field names must not be null or '
        'empty.';
    await expectError(() => FieldPath.of(<String>[null]), reason);
    await expectError(() => FieldPath.of(<String>['']), reason);

    reason =
        'Invalid field name at argument 2. Field names must not be null or '
        'empty.';
    await expectError(() => FieldPath.of(<String>['foo', '']), reason);
    await expectError(() => FieldPath.of(<String>['foo', null]), reason);
  });

  test('arrayTransformsFailInQueries', () async {
    final CollectionReference collection = await testCollection();
    String reason =
        'Invalid data. FieldValue.arrayUnion() can only be used with set() and '
        'update() (found in field test)';
    await expectError(
        () => collection.whereEqualTo(
            'test',
            map<dynamic>(<dynamic>[
              'test',
              FieldValue.arrayUnion(<dynamic>[1])
            ])),
        reason);

    reason =
        'Invalid data. FieldValue.arrayRemove() can only be used with set() '
        'and update() (found in field test)';
    await expectError(
        () => collection.whereEqualTo(
            'test',
            map<dynamic>(<dynamic>[
              'test',
              FieldValue.arrayRemove(<dynamic>[1])
            ])),
        reason);
  });

  test('arrayTransformsRejectInvalidElements', () async {
    final DocumentReference doc = await testDocument();
    const String reason = 'Invalid data. Unsupported type: Throws';

    await expectError(
        () => doc.set(map(<dynamic>[
              'x',
              FieldValue.arrayUnion(
                  <dynamic>[1, throwsCyclicInitializationError])
            ])),
        reason);
    await expectError(
        () => doc.set(map(<dynamic>[
              'x',
              FieldValue.arrayRemove(
                  <dynamic>[1, throwsCyclicInitializationError])
            ])),
        reason);
  });

  test('arrayTransformsRejectArrays', () async {
    final DocumentReference doc = await testDocument();
    // This would result in a directly nested array which is not supported.
    const String reason = 'Invalid data. Nested arrays are not supported';
    await expectError(
        () => doc.set(map(<dynamic>[
              'x',
              FieldValue.arrayUnion(<dynamic>[
                1,
                <dynamic>['nested']
              ])
            ])),
        reason);
    await expectError(
        () => doc.set(map(<dynamic>[
              'x',
              FieldValue.arrayRemove(<dynamic>[
                1,
                <dynamic>['nested']
              ])
            ])),
        reason);
  });

  test('queriesWithNonPositiveLimitFail', () async {
    final CollectionReference collection = await testCollection();
    await expectError(() => collection.limit(0),
        'Invalid Query. Query limit (0) is invalid. Limit must be positive.');
    await expectError(() => collection.limit(-1),
        'Invalid Query. Query limit (-1) is invalid. Limit must be positive.');
  });

  test('queriesWithNullOrNaNFiltersOtherThanEqualityFail', () async {
    final CollectionReference collection = await testCollection();
    await expectError(
        () => collection.whereGreaterThan('a', null),
        'Invalid Query. You can only perform equality comparisons on null '
        '(via whereEqualTo()).');
    await expectError(
        () => collection.whereArrayContains('a', null),
        'Invalid Query. You can only perform equality comparisons on null '
        '(via whereEqualTo()).');

    await expectError(
        () => collection.whereGreaterThan('a', double.nan),
        'Invalid Query. You can only perform equality comparisons on NaN '
        '(via whereEqualTo()).');
    await expectError(
        () => collection.whereArrayContains('a', double.nan),
        'Invalid Query. You can only perform equality comparisons on NaN '
        '(via whereEqualTo()).');
  });

  test('queriesCannotBeCreatedFromDocumentsMissingSortValues', () async {
    final CollectionReference collection =
        await testCollectionWithDocs(map(<dynamic>[
      'f',
      map<dynamic>(<dynamic>['k', 'f', 'nosort', 1.0])
    ]));

    final Query query = collection.orderBy('sort');
    final DocumentSnapshot snapshot = await collection.document('f').get();

    expect(snapshot.data, map<dynamic>(<dynamic>['k', 'f', 'nosort', 1.0]));

    const String reason =
        'Invalid query. You are trying to start or end a query using a '
        'document for which the field \'sort\' (used as the orderBy) does not'
        ' exist.';

    await expectError(() => query.startAtDocument(snapshot), reason);
    await expectError(() => query.startAfterDocument(snapshot), reason);
    await expectError(() => query.endBeforeDocument(snapshot), reason);
    await expectError(() => query.endAtDocument(snapshot), reason);
  });

  test('queriesMustNotHaveMoreComponentsThanOrderBy', () async {
    final CollectionReference collection = await testCollection();
    final Query query = collection.orderBy('foo');

    const String reason =
        'Too many arguments provided to startAt(). The number of arguments '
        'must be less than or equal to the number of orderBy() clauses.';
    await expectError(() => query.startAt(<int>[1, 2]), reason);
    await expectError(
        () => query.orderBy('bar').startAt(<int>[1, 2, 3]), reason);
  });

  test('queryOrderByKeyBoundsMustBeStringsWithoutSlashes', () async {
    final CollectionReference collection = await testCollection();
    final Query query = collection.orderByField(FieldPath.documentId());
    await expectError(
        () => query.startAt(<int>[1]),
        'Invalid query. Expected a string for document ID in startAt(), but'
        ' got 1.');
    await expectError(() => query.startAt(<String>['foo/bar']),
        'Invalid query. Document ID \'foo/bar\' contains a slash in startAt().');
  });

  test('queriesWithDifferentInequalityFieldsFail', () async {
    await expectError(
        () async => (await testCollection())
            .whereGreaterThan('x', 32)
            .whereLessThan('y', 'cat'),
        'All where filters other than whereEqualTo() must be on the same '
        'field. But you have filters on \'x\' and \'y\'');
  });

  test('queriesWithInequalityDifferentThanFirstOrderByFail', () async {
    final CollectionReference collection = await testCollection();
    const String reason =
        'Invalid query. You have an inequality where filter (whereLessThan(), '
        'whereGreaterThan(), etc.) on field \'x\' and so you must also have '
        '\'x\' as your first orderBy() field, but your first orderBy() is '
        'currently on field \'y\' instead.';

    await expectError(
        () => collection.whereGreaterThan('x', 32).orderBy('y'), reason);
    await expectError(
        () => collection.orderBy('y').whereGreaterThan('x', 32), reason);
    await expectError(
        () => collection.whereGreaterThan('x', 32).orderBy('y').orderBy('x'),
        reason);
    await expectError(
        () => collection.orderBy('y').orderBy('x').whereGreaterThan('x', 32),
        reason);
  });

  test('queriesWithMultipleArrayContainsFiltersFail', () async {
    await expectError(
        () async => (await testCollection())
            .whereArrayContains('foo', 1)
            .whereArrayContains('foo', 2),
        'Invalid Query. Queries only support having a single array-contains'
        ' filter.');
  });

  test('queriesMustNotSpecifyStartingOrEndingPointAfterOrderBy', () async {
    final CollectionReference collection = await testCollection();
    final Query query = collection.orderBy('foo');
    String reason = 'Invalid query. You must not call Query.startAt() or '
        'Query.startAfter() before calling Query.orderBy().';
    await expectError(() => query.startAt(<int>[1]).orderBy('bar'), reason);
    await expectError(() => query.startAfter(<int>[1]).orderBy('bar'), reason);
    reason =
        'Invalid query. You must not call Query.endAt() or Query.endAfter() '
        'before calling Query.orderBy().';
    await expectError(() => query.endAt(<int>[1]).orderBy('bar'), reason);
    await expectError(() => query.endBefore(<int>[1]).orderBy('bar'), reason);
  });

  test('queriesFilteredByDocumentIDMustUseStringsOrDocumentReferences',
      () async {
    final CollectionReference collection = await testCollection();
    String reason =
        'Invalid query. When querying with FieldPath.documentId() you must '
        'provide a valid document ID, but it was an empty string.';
    await expectError(
        () => collection.whereGreaterThanOrEqualToField(
            FieldPath.documentId(), ''),
        reason);

    reason =
        'Invalid query. When querying with FieldPath.documentId() you must '
        'provide a valid document ID, but \'foo/bar/baz\' contains a \'/\' '
        'character.';
    await expectError(
        () => collection.whereGreaterThanOrEqualToField(
            FieldPath.documentId(), 'foo/bar/baz'),
        reason);

    reason =
        'Invalid query. When querying with FieldPath.documentId() you must '
        'provide a valid String or DocumentReference, but it was of type: int';
    await expectError(
        () => collection.whereGreaterThanOrEqualToField(
            FieldPath.documentId(), 1),
        reason);

    reason = 'Invalid query. You can\'t perform array-contains queries on '
        'FieldPath.documentId() since document IDs are not arrays.';
    await expectError(
        () => collection.whereArrayContainsField(FieldPath.documentId(), 1),
        reason);
  });
}

// ignore: always_specify_types, type_annotate_public_apis
const testCollectionWithDocs = IntegrationTestUtil.testCollectionWithDocs;
// ignore: always_specify_types, type_annotate_public_apis
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types, type_annotate_public_apis
const testCollection = IntegrationTestUtil.testCollection;
// ignore: always_specify_types, type_annotate_public_apis
const testDocument = IntegrationTestUtil.testDocument;
// ignore: always_specify_types, type_annotate_public_apis
const testAlternateFirestore = IntegrationTestUtil.testAlternateFirestore;

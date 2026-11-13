// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/filter.dart'
    show Filter;
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/transaction.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/write_batch.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
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

  /// The message of an invalid data error of [methodName], as in the JS SDK:
  /// [documentPath] is added to the "(found in field ...)" part of [reason],
  /// or as "(found in document ...)" when [reason] has none.
  String invalidData(String methodName, String reason, {String? documentPath}) {
    String message = reason;
    if (documentPath != null) {
      message = reason.contains('(found in field ')
          ? '${reason.substring(0, reason.length - 1)} in document '
                '$documentPath)'
          : '$reason (found in document $documentPath)';
    }
    return 'Function $methodName() called with invalid data. $message';
  }

  /// Performs a write using each set and/or update API and makes sure it fails
  /// with the expected reason. Like the JS SDK's `expectWriteToFail`, the
  /// message names the method and the document:
  /// `Function WriteBatch.set() called with invalid data. <reason>
  /// (found in field f in document c/d)`.
  Future<void> expectWriteError(
    Map<String, Object?> data,
    String reason, {
    bool includeSets = true,
    bool includeUpdates = true,
  }) async {
    final DocumentReference ref = await testDocument();
    String error(String methodName) =>
        invalidData(methodName, reason, documentPath: ref.path);

    if (includeSets) {
      await expectError(() => ref.set(data), error('DocumentReference.set'));
      await expectError(
        () => ref.firestore.batch().set(ref, data),
        error('WriteBatch.set'),
      );
    }

    if (includeUpdates) {
      await expectError(
        () => ref.update(data),
        error('DocumentReference.update'),
      );
      await expectError(
        () => ref.firestore.batch().update(ref, data),
        error('WriteBatch.update'),
      );
    }

    await ref.firestore.runTransaction<void>((Transaction transaction) async {
      if (includeSets) {
        await expectError(
          () => transaction.set(ref, data),
          error('Transaction.set'),
        );
      }

      if (includeUpdates) {
        await expectError(
          () => transaction.update(ref, data),
          error('Transaction.update'),
        );
      }

      return;
    });
  }

  /// Performs a write using each update API and makes sure it fails with the
  /// expected reason.
  ///
  /// Must be awaited: it runs a transaction, which would otherwise still be in flight when the test ends and fail
  /// with a connection error once the instance is shut down.
  Future<void> expectUpdateError(Map<String, Object?> data, String reason) {
    return expectWriteError(
      data,
      reason,
      includeSets: false,
      includeUpdates: true,
    );
  }

  /// Tests a field path with all of our APIs that accept field paths and
  /// ensures they fail with the specified reason.
  Future<void> verifyFieldPathThrows(String path, String reason) async {
    // Get an arbitrary snapshot we can use for testing.
    final DocumentReference docRef = await testDocument();
    await docRef.set(map(<dynamic>['test', 1]));
    final DocumentSnapshot snapshot = await docRef.get();

    // snapshot paths
    await expectError(
      () => snapshot.get(path),
      invalidData('DocumentSnapshot.get', reason),
    );

    // Query filter / order fields
    final CollectionReference coll = await testCollection();
    // whereLessThan(), etc. omitted for brevity since the code path is
    // trivially shared.
    await expectError(
      () => coll.whereEqualTo(path, 1),
      invalidData('where', reason),
    );
    await expectError(() => coll.orderBy(path), invalidData('orderBy', reason));

    // update() paths.
    await expectError(
      () => docRef.updateFromList(<dynamic>[path, 1]),
      invalidData(
        'DocumentReference.updateFromList',
        reason,
        documentPath: docRef.path,
      ),
    );
    await expectError(
      () => docRef.update(<String, Object?>{path: 1}),
      invalidData(
        'DocumentReference.update',
        reason,
        documentPath: docRef.path,
      ),
    );
  }

  test('firestoreSettingsNullHostFails', () async {
    // Null is rejected statically by the null-safe API; a dynamic null
    // fails the argument type check at runtime.
    expect(
      () => FirestoreSettings(host: null as dynamic),
      throwsA(isA<TypeError>()),
    );
  });

  test('disableSslWithoutSettingHostFails', () async {
    await expectError(
      () => FirestoreSettings(sslEnabled: false),
      'You can\'t set the \'sslEnabled\' setting unless you also set a '
      'non-default \'host\'.',
    );
  });

  test('firestoreGetInstanceWithNullAppFails', () async {
    // Null is rejected statically by the null-safe API; a dynamic null
    // fails the argument type check at runtime.
    expect(
      () => Firestore.getInstance(null as dynamic),
      throwsA(isA<TypeError>()),
    );
  });

  Future<void> withApp(
    String name,
    Future<void> Function(FirebaseApp app) toRun,
  ) async {
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'key',
        applicationId: 'appId',
        projectId: 'projectId',
      ),
      dependencies: null,
      name: name,
    );

    try {
      await toRun(app);
    } finally {
      app.delete();
    }
  }

  test('firestoreGetInstanceWithNonNullAppReturnsNonNullInstance', () async {
    await withApp('firestoreTestApp', (FirebaseApp app) async {
      expect(
        Firestore.getInstance(app, openDatabase: DatabaseMock.create),
        isNotNull,
      );
    });
  });

  test('collectionPathsMustBeOddLength', () async {
    final Firestore firestore = await testFirestore();
    final DocumentReference baseDocRef = firestore.document('foo/bar');
    final List<String> badAbsolutePaths = <String>[
      'foo/bar',
      'foo/bar/baz/quu',
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
    final Firestore firestore = await testFirestore()
      // NOTE: leading / trailing slashes are okay.
      ..collection('/foo/')
      ..collection('/foo')
      ..collection('foo/');

    final List<String> badPaths = <String>['foo//bar//baz', '//foo', 'foo//'];
    final CollectionReference collection = firestore.collection(
      'test-collection',
    );
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
    final Firestore firestore = await testFirestore();
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
          <int>[2],
        ],
      ]),
      'Nested arrays are not supported',
    );
  });

  test('writesMayContainIndirectlyNestedLists', () async {
    final Map<String, Object?> data = map(<dynamic>[
      'nested-array',
      <dynamic>[
        1,
        map<List<int>>(<dynamic>[
          'foo',
          <int>[2],
        ]),
      ],
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
      return Future<void>.value();
    });
  });

  test('writesMustNotContainReferencesToADifferentDatabase', () async {
    final Firestore firestore2 = await testAlternateFirestore();
    final DocumentReference ref = firestore2.document('baz/quu');
    final Map<String, Object?> data = map<dynamic>(<dynamic>['foo', ref]);

    await expectWriteError(
      data,
      'Document reference is for database '
      '${IntegrationTestUtil.badProjectId}/(default) but should be for '
      'database ${IntegrationTestUtil.provider.projectId}/(default) '
      '(found in field foo)',
    );
  });

  test('writesMustNotContainReservedFieldNames', () async {
    await expectWriteError(
      map<dynamic>(<dynamic>['__baz__', 1]),
      'Document fields cannot begin and end with "__" '
      '(found in field __baz__)',
    );
    await expectWriteError(
      map<dynamic>(<dynamic>[
        'foo',
        map<dynamic>(<dynamic>['__baz__', 1]),
      ]),
      'Document fields cannot begin and end with "__" '
      '(found in field foo.__baz__)',
    );
    await expectWriteError(
      map<dynamic>(<dynamic>[
        '__baz__',
        map<dynamic>(<dynamic>['foo', 1]),
      ]),
      'Document fields cannot begin and end with "__" '
      '(found in field __baz__)',
    );

    await expectUpdateError(
      map<dynamic>(<dynamic>['__baz__', 1]),
      'Document fields cannot begin and end with "__" '
      '(found in field __baz__)',
    );
    await expectUpdateError(
      map<dynamic>(<dynamic>['baz.__foo__', 1]),
      'Document fields cannot begin and end with "__" '
      '(found in field baz.__foo__)',
    );
  });

  test('writesMustNotContainEmptyFieldNames', () async {
    await expectWriteError(
      map<dynamic>(<dynamic>['', 'foo']),
      'Document fields must not be empty (found in field ``)',
      includeUpdates: false,
    );
  });

  test(
    'writesMayContainFieldNamesThatOnlyBeginOrEndWithDoubleUnderscore',
    () async {
      final DocumentReference ref = await testDocument();
      await ref.set(map<dynamic>(<dynamic>['__bar', 1]));
      await ref.set(map<dynamic>(<dynamic>['bar__', 1]));
    },
  );

  test('setsMustNotContainFieldValueDelete', () async {
    final DocumentReference ref = await testDocument();
    await expectError(
      () => ref.set(map(<dynamic>['foo', FieldValue.delete()])),
      invalidData(
        'DocumentReference.set',
        'FieldValue.delete() can only be used with update() and set() with '
            'SetOptions.merge() (found in field foo)',
        documentPath: ref.path,
      ),
    );
  });

  test('updatesMustNotContainNestedFieldValueDeletes', () async {
    final DocumentReference ref = await testDocument();
    await expectError(
      () => ref.update(
        map(<dynamic>[
          'foo',
          map<dynamic>(<dynamic>['bar', FieldValue.delete()]),
        ]),
      ),
      invalidData(
        'DocumentReference.update',
        'FieldValue.delete() can only appear at the top level of your update '
            'data (found in field foo.bar)',
        documentPath: ref.path,
      ),
    );
  });

  test('batchWritesRequireCorrectDocumentReferences', () async {
    final DocumentReference badRef = (await testAlternateFirestore()).document(
      'foo/bar',
    );
    const String reason =
        'Provided document reference is from a different Cloud Firestore instance.';
    final Map<String, Object?> data = map<dynamic>(<dynamic>['foo', 1]);
    final WriteBatch batch = (await testFirestore()).batch();
    await expectError(() => batch.set(badRef, data), reason);
    await expectError(() => batch.update(badRef, data), reason);
    await expectError(() => batch.delete(badRef), reason);
  });

  test('transactionsRequireCorrectDocumentReferences', () async {
    final DocumentReference badRef = (await testAlternateFirestore()).document(
      'foo/bar',
    );
    const String reason =
        'Provided document reference is from a different Cloud Firestore instance.';
    final Map<String, Object?> data = map<dynamic>(<dynamic>['foo', 1]);

    await (await testFirestore()).runTransaction<void>((
      Transaction transaction,
    ) async {
      await expectError(() async {
        // Because .get() throws a checked exception for missing docs, we have
        // to try/catch it.
        try {
          await transaction.get(badRef);
        } on FirestoreError catch (e) {
          fail('transaction.get() triggered wrong exception: $e');
        }
      }, reason);

      await expectError(() => transaction.set(badRef, data), reason);
      await expectError(() => transaction.update(badRef, data), reason);
      await expectError(() => transaction.delete(badRef), reason);
      return;
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
      'foo[1]',
    ];
    for (String fieldPath in badFieldPaths) {
      final String reason =
          'Invalid field path ($fieldPath). Paths must not contain '
          "'~', '*', '/', '[', or ']'. Use FieldPath.of() for field names "
          'that contain them.';
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
    // Null is rejected statically by the null-safe API; a dynamic null
    // fails the argument type check at runtime.
    expect(
      () => FieldPath.of(<dynamic>[null] as dynamic),
      throwsA(isA<TypeError>()),
    );
    await expectError(() => FieldPath.of(<String>['']), reason);

    reason =
        'Invalid field name at argument 2. Field names must not be null or '
        'empty.';
    await expectError(() => FieldPath.of(<String>['foo', '']), reason);
    // Null is rejected statically by the null-safe API; a dynamic null
    // fails the argument type check at runtime.
    expect(
      () => FieldPath.of(<dynamic>['foo', null] as dynamic),
      throwsA(isA<TypeError>()),
    );
  });

  test('arrayTransformsFailInQueries', () async {
    final CollectionReference collection = await testCollection();
    String reason = invalidData(
      'where',
      'FieldValue.arrayUnion() can only be used with set() and update() '
          '(found in field test)',
    );
    await expectError(
      () => collection.whereEqualTo(
        'test',
        map<dynamic>(<dynamic>[
          'test',
          FieldValue.arrayUnion(<dynamic>[1]),
        ]),
      ),
      reason,
    );

    reason = invalidData(
      'where',
      'FieldValue.arrayRemove() can only be used with set() and update() '
          '(found in field test)',
    );
    await expectError(
      () => collection.whereEqualTo(
        'test',
        map<dynamic>(<dynamic>[
          'test',
          FieldValue.arrayRemove(<dynamic>[1]),
        ]),
      ),
      reason,
    );
  });

  test('arrayTransformsRejectInvalidElements', () async {
    final DocumentReference doc = await testDocument();
    String reason(String transform) => invalidData(
      transform,
      'Unsupported field value: a custom _ValidationTest object',
      documentPath: doc.path,
    );

    await expectError(
      () => doc.set(
        map(<dynamic>[
          'x',
          FieldValue.arrayUnion(<dynamic>[1, const _ValidationTest()]),
        ]),
      ),
      reason('FieldValue.arrayUnion'),
    );
    await expectError(
      () => doc.set(
        map(<dynamic>[
          'x',
          FieldValue.arrayRemove(<dynamic>[1, const _ValidationTest()]),
        ]),
      ),
      reason('FieldValue.arrayRemove'),
    );
  });

  test('arrayTransformsRejectArrays', () async {
    final DocumentReference doc = await testDocument();
    // This would result in a directly nested array which is not supported.
    String reason(String transform) => invalidData(
      transform,
      'Nested arrays are not supported',
      documentPath: doc.path,
    );
    await expectError(
      () => doc.set(
        map(<dynamic>[
          'x',
          FieldValue.arrayUnion(<dynamic>[
            1,
            <dynamic>['nested'],
          ]),
        ]),
      ),
      reason('FieldValue.arrayUnion'),
    );
    await expectError(
      () => doc.set(
        map(<dynamic>[
          'x',
          FieldValue.arrayRemove(<dynamic>[
            1,
            <dynamic>['nested'],
          ]),
        ]),
      ),
      reason('FieldValue.arrayRemove'),
    );
  });

  test('queriesWithNonPositiveLimitFail', () async {
    final CollectionReference collection = await testCollection();
    await expectError(
      () => collection.limit(0),
      'Invalid Query. Query limit (0) is invalid. Limit must be positive.',
    );
    await expectError(
      () => collection.limit(-1),
      'Invalid Query. Query limit (-1) is invalid. Limit must be positive.',
    );
    await expectError(
      () => collection.limitToLast(0),
      'Invalid Query. Query limitToLast (0) is invalid. Limit must be positive.',
    );
    await expectError(
      () => collection.limitToLast(-1),
      'Invalid Query. Query limitToLast (-1) is invalid. Limit must be positive.',
    );
  });

  test('queriesCannotBeCreatedFromDocumentsMissingSortValues', () async {
    final CollectionReference collection = await testCollectionWithDocs(
      map(<dynamic>[
        'f',
        map<dynamic>(<dynamic>['k', 'f', 'nosort', 1.0]),
      ]),
    );

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

  test('queriesCannotBeSortedByAnUncommittedServerTimestamp', () async {
    final CollectionReference collection = await testCollection();

    // Ensure the server timestamp stays uncommitted for the first half of the test
    await collection.firestore.client.disableNetwork();

    final Completer<void> offlineCallbackDone = Completer<void>();
    final Completer<void> onlineCallbackDone = Completer<void>();

    collection.snapshots.listen((QuerySnapshot snapshot) {
      expect(snapshot, isNotNull);

      // Skip the initial empty snapshot.
      if (snapshot.isEmpty) {
        return;
      }

      expect(snapshot.documents.length, 1);
      final DocumentSnapshot docSnap = snapshot.documents[0];

      if (snapshot.metadata.hasPendingWrites) {
        // Offline snapshot. Since the server timestamp is uncommitted, we shouldn't be able to
        // query by it.
        expect(
          () => collection
              .orderBy('timestamp')
              .endAtDocument(docSnap)
              .snapshots
              .listen(null),
          throwsArgumentError,
        );
        // The emulator may deliver the committed document before the write acknowledgement, which raises a second
        // snapshot that still has pending writes.
        if (!offlineCallbackDone.isCompleted) {
          offlineCallbackDone.complete(null);
        }
      } else {
        // Online snapshot. Since the server timestamp is committed, we should be able to query
        // by it.
        collection
            .orderBy('timestamp')
            .endAtDocument(docSnap)
            .snapshots
            .listen(null);
        if (!onlineCallbackDone.isCompleted) {
          onlineCallbackDone.complete(null);
        }
      }
    });

    final DocumentReference document = collection.document();
    // The write only completes once the network is enabled again, so it must
    // not be awaited before that.
    final Future<void> write = document.set(
      map(<dynamic>['timestamp', FieldValue.serverTimestamp()]),
    );
    await offlineCallbackDone.future;

    await collection.firestore.client.enableNetwork();
    await onlineCallbackDone.future;
    await write;
  });

  test('queriesMustNotHaveMoreComponentsThanOrderBy', () async {
    final CollectionReference collection = await testCollection();
    final Query query = collection.orderBy('foo');

    const String reason =
        'Too many arguments provided to startAt(). The number of arguments '
        'must be less than or equal to the number of orderBy() clauses.';
    await expectError(() => query.startAt(<int>[1, 2]), reason);
    await expectError(
      () => query.orderBy('bar').startAt(<int>[1, 2, 3]),
      reason,
    );
  });

  test('queryOrderByKeyBoundsMustBeStringsWithoutSlashes', () async {
    final Query query = (await testFirestore())
        .collection('collection')
        .orderByField(FieldPath.documentId());
    final Query cgQuery = (await testFirestore())
        .collectionGroup('collection')
        .orderByField(FieldPath.documentId());

    await expectError(
      () => query.startAt(<int>[1]),
      'Invalid query. Expected a string for document ID in startAt(), but '
      'got 1.',
    );
    await expectError(
      () => query.startAt(<String>['foo/bar']),
      'Invalid query. When querying a collection and ordering by FieldPath.documentId(), the value passed to startAt() must be a plain document ID, but "foo/bar" contains a slash.',
    );
    await expectError(
      () async => cgQuery.startAt(<String>['foo']),
      'Invalid query. When querying a collection group and ordering by '
      'FieldPath.documentId(), the value passed to startAt() must result in '
      'a valid document path, but "foo" is not because it contains an odd '
      'number of segments.',
    );
  });

  // Multiple inequality filters are allowed (the backend validates them, and
  // they need a composite index in production).
  test('queriesWithDifferentInequalityFieldsAreAllowed', () async {
    final CollectionReference collection = await testCollection();
    collection.whereGreaterThan('x', 32).whereLessThan('y', 'cat');
    collection.whereNotEqualTo('x', 32).whereGreaterThan('y', 33);
    collection.whereNotIn('foo', <int>[1, 2]).whereGreaterThan('bar', 1);
  });

  test('queriesWithMultipleNotEqualAndInequalitiesFail', () async {
    await expectError(
      () async => (await testCollection())
          .whereNotEqualTo('x', 32)
          .whereNotEqualTo('x', 33),
      'Invalid Query. You cannot use more than one "!=" filter.',
    );
  });

  test('queriesWithNotEqualAndNotInFiltersFail', () async {
    await expectError(
      () async => (await testCollection())
          .whereNotIn('foo', <int>[1, 2])
          .whereNotEqualTo('foo', 1),
      'Invalid Query. You cannot use "!=" filters with "not_in" filters.',
    );

    await expectError(
      () async => (await testCollection()).whereNotEqualTo('foo', 1).whereNotIn(
        'foo',
        <int>[1, 2],
      ),
      'Invalid Query. You cannot use "not_in" filters with "!=" filters.',
    );
  });

  test('queriesWithMultipleDisjunctiveFiltersFail', () async {
    await expectError(
      () async => (await testCollection())
          .whereNotIn('foo', <int>[1, 2])
          .whereNotIn('bar', <int>[1, 2]),
      'Invalid Query. You cannot use more than one "not_in" filter.',
    );

    await expectError(
      () async => (await testCollection())
          .whereNotIn('bar', <int>[1, 2])
          .whereArrayContainsAny('foo', <int>[1, 2]),
      'Invalid Query. You cannot use "array_contains_any" filters with "not_in" filters.',
    );

    await expectError(
      () async => (await testCollection())
          .whereNotIn('bar', <int>[1, 2])
          .whereIn('foo', <int>[1, 2]),
      'Invalid Query. You cannot use "in" filters with "not_in" filters.',
    );

    await expectError(
      () async => (await testCollection())
          .whereIn('bar', <int>[1, 2])
          .whereNotIn('foo', <int>[1, 2]),
      'Invalid Query. You cannot use "not_in" filters with "in" filters.',
    );
  });

  test('queriesCanUseNotEqualAndNotInWithEqualityAndOrderBy', () async {
    final CollectionReference collection = await testCollection();
    collection.whereEqualTo('a', 1).whereNotEqualTo('b', 2);
    collection.whereEqualTo('a', 1).whereNotIn('b', <int>[2, 3]);
    collection.whereNotEqualTo('b', 2).orderBy('b');
    collection.whereNotIn('b', <int>[2, 3]).orderBy('b');
    collection.whereNotEqualTo('b', null);
    collection.whereNotEqualTo('b', double.nan);
    // The first orderBy does not have to match the inequality field anymore.
    collection.whereNotEqualTo('b', 2).orderBy('c');
    collection.orderBy('c').whereNotIn('b', <int>[2, 3]);
  });

  test('queriesInAndArrayContainsAnyArrayRules', () async {
    await expectError(
      () async => (await testCollection()).whereIn('bar', <dynamic>[]),
      'Invalid Query. A non-empty array is required for "in" filters.',
    );

    await expectError(
      () async => (await testCollection()).whereNotIn('bar', <dynamic>[]),
      'Invalid Query. A non-empty array is required for "not_in" filters.',
    );

    await expectError(
      () async =>
          (await testCollection()).whereArrayContainsAny('bar', <dynamic>[]),
      'Invalid Query. A non-empty array is required for "array_contains_any" filters.',
    );
  });

  test('queriesCanCombineArrayAndDisjunctiveFilters', () async {
    final CollectionReference collection = await testCollection();
    collection.whereArrayContains('foo', 1).whereArrayContains('foo', 2);
    collection.whereArrayContains('foo', 1).whereIn('bar', <int>[1, 2]);
    collection.whereIn('bar', <int>[1, 2]).whereIn('baz', <int>[1, 2]);
    collection.whereIn('bar', <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
  });

  test('testConflictingOperatorsInCompositeFilters', () async {
    final CollectionReference collection = await testCollection();
    // Composite queries can validate conflicting operators in multiple
    // inequality.
    String reason = 'Invalid Query. You cannot use more than one "!=" filter.';
    await expectError(
      () => collection
          .where(
            Filter.or(<Filter>[
              Filter.and(<Filter>[
                Filter.lessThan('a', 'b'),
                Filter.inArray('c', <String>['d', 'e']),
              ]),
              Filter.and(<Filter>[
                Filter.equalTo('e', 'f'),
                Filter.notEqualTo('g', 'h'),
              ]),
            ]),
          )
          .where(
            Filter.or(<Filter>[
              Filter.and(<Filter>[
                Filter.greaterThan('i', 'j'),
                Filter.greaterThan('k', 'l'),
              ]),
              Filter.and(<Filter>[
                Filter.notEqualTo('o', 'p'),
                Filter.lessThan('q', 'r'),
              ]),
            ]),
          ),
      reason,
    );

    reason = 'Invalid Query. You cannot use more than one "not_in" filter.';
    await expectError(
      () => collection
          .where(
            Filter.or(<Filter>[
              Filter.and(<Filter>[
                Filter.lessThan('a', 'b'),
                Filter.notInArray('c', <String>['d', 'e']),
              ]),
              Filter.and(<Filter>[
                Filter.equalTo('e', 'f'),
                Filter.lessThan('g', 'j'),
              ]),
            ]),
          )
          .where(
            Filter.or(<Filter>[
              Filter.and(<Filter>[
                Filter.greaterThan('i', 'j'),
                Filter.greaterThan('k', 'l'),
              ]),
              Filter.and(<Filter>[
                Filter.notInArray('o', <String>['p', 'q']),
                Filter.lessThan('q', 'r'),
              ]),
            ]),
          ),
      reason,
    );

    reason =
        'Invalid Query. You cannot use "not_in" filters with "!=" filters.';
    await expectError(
      () => collection
          .where(
            Filter.or(<Filter>[
              Filter.and(<Filter>[
                Filter.lessThan('a', 'b'),
                Filter.greaterThan('c', 'd'),
              ]),
              Filter.and(<Filter>[
                Filter.equalTo('e', 'f'),
                Filter.notEqualTo('g', 'h'),
              ]),
            ]),
          )
          .where(
            Filter.or(<Filter>[
              Filter.and(<Filter>[
                Filter.greaterThan('i', 'j'),
                Filter.greaterThan('k', 'l'),
              ]),
              Filter.and(<Filter>[
                Filter.notInArray('o', <String>['p', 'q']),
                Filter.lessThan('q', 'r'),
              ]),
            ]),
          ),
      reason,
    );

    reason =
        'Invalid Query. You cannot use "not_in" filters with "in" filters.';
    await expectError(
      () => collection
          .where(
            Filter.or(<Filter>[
              Filter.and(<Filter>[
                Filter.lessThan('a', 'b'),
                Filter.inArray('c', <String>['d', 'e']),
              ]),
              Filter.and(<Filter>[
                Filter.equalTo('e', 'f'),
                Filter.lessThan('g', 'j'),
              ]),
            ]),
          )
          .where(
            Filter.or(<Filter>[
              Filter.and(<Filter>[
                Filter.greaterThan('i', 'j'),
                Filter.greaterThan('k', 'l'),
              ]),
              Filter.and(<Filter>[
                Filter.notInArray('o', <String>['p', 'q']),
                Filter.lessThan('q', 'r'),
              ]),
            ]),
          ),
      reason,
    );
  });

  test('testInvalidQueryFilters', () async {
    final CollectionReference collection = await testCollection();
    // Conflicting operations within a composite filter.
    String reason =
        'Invalid Query. You cannot use "not_in" filters with "in" filters.';
    await expectError(
      () => collection.where(
        Filter.or(<Filter>[
          Filter.and(<Filter>[
            Filter.equalTo('a', 'b'),
            Filter.inArray('c', <String>['d', 'e']),
          ]),
          Filter.and(<Filter>[
            Filter.equalTo('e', 'f'),
            Filter.notInArray('c', <String>['f', 'g']),
          ]),
        ]),
      ),
      reason,
    );

    // Conflicting operations between a field filter and a composite filter.
    reason =
        'Invalid Query. You cannot use "not_in" filters with "in" filters.';
    await expectError(
      () => collection
          .where(
            Filter.or(<Filter>[
              Filter.and(<Filter>[
                Filter.equalTo('a', 'b'),
                Filter.inArray('c', <String>['d', 'e']),
              ]),
              Filter.and(<Filter>[
                Filter.equalTo('e', 'f'),
                Filter.equalTo('g', 'h'),
              ]),
            ]),
          )
          .where(Filter.notInArray('i', <String>['j', 'k'])),
      reason,
    );

    // Conflicting operations between two composite filters.
    reason =
        'Invalid Query. You cannot use "not_in" filters with "in" filters.';
    await expectError(
      () => collection
          .where(
            Filter.or(<Filter>[
              Filter.and(<Filter>[
                Filter.equalTo('a', 'b'),
                Filter.inArray('c', <String>['d', 'e']),
              ]),
              Filter.and(<Filter>[
                Filter.equalTo('e', 'f'),
                Filter.equalTo('g', 'h'),
              ]),
            ]),
          )
          .where(
            Filter.or(<Filter>[
              Filter.and(<Filter>[
                Filter.equalTo('i', 'j'),
                Filter.notInArray('l', <String>['m', 'n']),
              ]),
              Filter.and(<Filter>[
                Filter.equalTo('o', 'p'),
                Filter.equalTo('q', 'r'),
              ]),
            ]),
          ),
      reason,
    );
  });

  test('queriesMustNotSpecifyStartingOrEndingPointAfterOrderBy', () async {
    final CollectionReference collection = await testCollection();
    final Query query = collection.orderBy('foo');
    String reason =
        'Invalid query. You must not call Query.startAt() or '
        'Query.startAfter() before calling Query.orderBy().';
    await expectError(() => query.startAt(<int>[1]).orderBy('bar'), reason);
    await expectError(() => query.startAfter(<int>[1]).orderBy('bar'), reason);
    reason =
        'Invalid query. You must not call Query.endAt() or Query.endBefore() '
        'before calling Query.orderBy().';
    await expectError(() => query.endAt(<int>[1]).orderBy('bar'), reason);
    await expectError(() => query.endBefore(<int>[1]).orderBy('bar'), reason);
  });

  test('queriesFilteredByDocumentIDMustUseStringsOrDocumentReferences', () async {
    final CollectionReference collection = await testCollection();
    String reason =
        'Invalid query. When querying with FieldPath.documentId() you must '
        'provide a valid document ID, but it was an empty string.';
    await expectError(
      () =>
          collection.whereGreaterThanOrEqualToField(FieldPath.documentId(), ''),
      reason,
    );

    reason =
        'Invalid query. When querying a collection by FieldPath.documentId() '
        'you must provide a plain document ID, but "foo/bar/baz" contains a '
        '"/" character.';
    await expectError(
      () => collection.whereGreaterThanOrEqualToField(
        FieldPath.documentId(),
        'foo/bar/baz',
      ),
      reason,
    );

    reason =
        'Invalid query. When querying with FieldPath.documentId() you must '
        'provide a valid String or DocumentReference, but it was of type: int';
    await expectError(
      () =>
          collection.whereGreaterThanOrEqualToField(FieldPath.documentId(), 1),
      reason,
    );

    reason =
        'Invalid query. When querying a collection group by FieldPath.documentId(), the value '
        'provided must result in a valid document path, but "foo" is not because it has '
        'an odd number of segments (1).';
    await expectError(
      () async => (await testFirestore())
          .collectionGroup('collection')
          .whereGreaterThanOrEqualToField(FieldPath.documentId(), 'foo'),
      reason,
    );

    reason =
        "Invalid query. You can't perform \"array_contains\" queries on FieldPath.documentId().";
    await expectError(
      () => collection.whereArrayContainsField(FieldPath.documentId(), 1),
      reason,
    );

    reason =
        "Invalid query. You can't perform \"array_contains_any\" queries on FieldPath.documentId().";
    await expectError(
      () => collection.whereArrayContainsAnyField(FieldPath.documentId(), <int>[
        1,
        2,
      ]),
      reason,
    );
  });

  test('queriesUsingInAndDocumentIdMustHaveProperDocumentReferencesInArray', () async {
    final CollectionReference collection = await testCollection();
    collection.whereInField(FieldPath.documentId(), <String>[collection.path]);

    String reason =
        'Invalid query. When querying with FieldPath.documentId() you must provide a valid document ID, but it was an empty string.';
    await expectError(
      () async => collection.whereInField(FieldPath.documentId(), <String>['']),
      reason,
    );

    reason =
        'Invalid query. When querying a collection by FieldPath.documentId() you must provide a plain document ID, but "foo/bar/baz" contains a "/" character.';
    await expectError(
      () async => collection.whereInField(FieldPath.documentId(), <String>[
        'foo/bar/baz',
      ]),
      reason,
    );

    reason =
        'Invalid query. When querying with FieldPath.documentId() you must provide a valid String or DocumentReference, but it was of type: int';
    await expectError(
      () async => collection.whereInField(FieldPath.documentId(), <int>[1, 2]),
      reason,
    );

    reason =
        'Invalid query. When querying a collection group by FieldPath.documentId(), the value provided must result in a valid document path, but "foo" is not because it has an odd number of segments (1).';
    await expectError(
      () async => (await testFirestore())
          .collectionGroup('collection')
          .whereInField(FieldPath.documentId(), <String>['foo']),
      reason,
    );
  });

  // Cases of the JS validation.test.ts and database.test.ts that the tests
  // above do not cover (see notes/parity/integration_test_map.md).
  group('upstream parity', () {
    Matcher throwsWith(String message) => throwsA(
      predicate(
        (Object? e) => e.toString().contains(message),
        'an error with "$message"',
      ),
    );

    test('enforces minimum cache size', () {
      expect(
        () => FirestoreSettings(cacheSizeBytes: 1),
        throwsWith('Cache size must be set to at least 1048576 bytes'),
      );
    });

    test('garbage collection can be disabled', () {
      // Does not throw.
      final FirestoreSettings settings = FirestoreSettings(
        cacheSizeBytes: FirestoreSettings.cacheSizeUnlimited,
      );
      expect(settings.cacheSizeBytes, FirestoreSettings.cacheSizeUnlimited);
    });

    test('the emulator settings can set host and port', () {
      final FirestoreSettings settings = FirestoreSettings().withEmulator(
        '127.0.0.1',
        9000,
      );
      expect(settings.host, '127.0.0.1');
      expect(settings.port, 9000);
      expect(settings.sslEnabled, isFalse);
    });

    test('throws if sub / user_id is missing in mockUserToken', () {
      expect(
        () => FirestoreSettings().withEmulator(
          '127.0.0.1',
          9000,
          mockUserToken: <String, Object?>{},
        ),
        throwsWith("mockUserToken must contain 'sub' or 'user_id' field!"),
      );
    });

    test('collection paths must be non-empty strings', () async {
      final Firestore db = await testFirestore();
      expect(
        () => db.collection(''),
        throwsWith(
          'Function Firestore.collection() cannot be called with an empty '
          'path.',
        ),
      );
    });

    test('document paths must be non-empty strings', () async {
      final Firestore db = await testFirestore();
      expect(
        () => db.doc(''),
        throwsWith(
          'Function Firestore.doc() cannot be called with an empty path.',
        ),
      );
    });

    test('writes must not contain custom objects or functions', () async {
      // The JS SDK's reasons; `_TestClass` is its `TestClass`.
      final Map<Map<String, Object?>, String> badData =
          <Map<String, Object?>, String>{
            <String, Object?>{'foo': _TestClass('foo')}:
                'Unsupported field value: a custom _TestClass object '
                '(found in field foo)',
            <String, Object?>{
              'foo': <Object?>[_TestClass('foo')],
            }: 'Unsupported field value: a custom _TestClass object',
            <String, Object?>{
              'foo': <String, Object?>{'bar': _TestClass('foo')},
            }: 'Unsupported field value: a custom _TestClass object '
                '(found in field foo.bar)',
            <String, Object?>{'foo': () {}}:
                'Unsupported field value: a function (found in field foo)',
            <String, Object?>{
              'foo': <Object?>[() {}],
            }: 'Unsupported field value: a function',
            <String, Object?>{
              'foo': <String, Object?>{'bar': () {}},
            }: 'Unsupported field value: a function (found in field foo.bar)',
          };
      for (final MapEntry<Map<String, Object?>, String> entry
          in badData.entries) {
        await expectWriteError(entry.key, entry.value);
      }
    });

    test('writes must not contain field value transforms in arrays', () async {
      final DocumentReference ref = await testDocument();
      await expectLater(
        () => ref.set(<String, Object?>{
          'array': <Object?>[FieldValue.serverTimestamp()],
        }),
        throwsWith('is not currently supported inside arrays'),
      );
    });

    test('numeric transforms fail in queries', () async {
      final CollectionReference coll = await testCollection();
      expect(
        () => coll.whereEqualTo('test', <String, Object?>{
          'test': FieldValue.increment(1),
        }),
        throwsWith(
          'Function where() called with invalid data. '
          'FieldValue.increment() can only be used with set() and '
          'update() (found in field test)',
        ),
      );
    });

    group('Queries are validated client-side', () {
      late CollectionReference coll;
      setUp(() async {
        coll = await testCollection();
      });

      final Map<String, Query Function(CollectionReference)>
      cases = <String, Query Function(CollectionReference)>{
        'same inequality fields works': (CollectionReference c) => c
            .whereGreaterThanOrEqualTo('x', 32)
            .whereLessThanOrEqualTo('x', 'cat'),
        'inequality and equality on different fields works':
            (CollectionReference c) =>
                c.whereGreaterThanOrEqualTo('x', 32).whereEqualTo('y', 'cat'),
        'inequality on multiple fields works': (CollectionReference c) =>
            c.whereGreaterThanOrEqualTo('x', 32).whereNotEqualTo('y', 'cat'),
        'inequality with key fields works': (CollectionReference c) => c
            .whereGreaterThanOrEqualToField(FieldPath.documentId(), 'aa')
            .whereGreaterThanOrEqualTo('x', 32),
        'inequality and array-contains on different fields works':
            (CollectionReference c) => c
                .whereGreaterThanOrEqualTo('x', 32)
                .whereArrayContains('y', 'cat'),
        'inequality and array-contains-any on different fields works':
            (CollectionReference c) => c
                .whereGreaterThanOrEqualTo('x', 32)
                .whereArrayContainsAny('y', <Object?>[1, 2]),
        'multiple inequality and array-contains on different fields works':
            (CollectionReference c) => c
                .whereGreaterThanOrEqualTo('x', 32)
                .whereArrayContains('y', 'cat')
                .whereLessThanOrEqualTo('z', 42),
        'multiple inequality and array-contains-any on different fields works':
            (CollectionReference c) => c
                .whereGreaterThanOrEqualTo('x', 32)
                .whereArrayContainsAny('y', <Object?>[1, 2])
                .whereLessThanOrEqualTo('z', 42),
        'inequality and IN on different fields works':
            (CollectionReference c) => c
                .whereGreaterThanOrEqualTo('x', 32)
                .whereIn('y', <Object?>[1, 2]),
        'multiple inequality and IN on different fields works':
            (CollectionReference c) => c
                .whereGreaterThanOrEqualTo('x', 32)
                .whereIn('y', <Object?>[1, 2])
                .whereLessThanOrEqualTo('z', 42),
        'inequality and NOT IN on different fields works':
            (CollectionReference c) => c
                .whereGreaterThanOrEqualTo('x', 32)
                .whereNotIn('y', <Object?>[1, 2]),
        'multiple inequality and NOT IN on different fields works':
            (CollectionReference c) => c
                .whereGreaterThanOrEqualTo('x', 32)
                .whereNotIn('y', <Object?>[1, 2])
                .whereLessThanOrEqualTo('z', 42),
        'inequality same as orderBy works.': (CollectionReference c) =>
            c.whereGreaterThan('x', 32).orderBy('x'),
        '!= same as orderBy works.': (CollectionReference c) =>
            c.whereNotEqualTo('x', 32).orderBy('x'),
        'equality different than orderBy works': (CollectionReference c) =>
            c.whereEqualTo('x', 32).orderBy('y'),
        'inequality different than orderBy works.': (CollectionReference c) =>
            c.whereGreaterThan('x', 32).orderBy('y'),
        'multiple inequality different from orderBy works.':
            (CollectionReference c) => c
                .whereGreaterThan('x', 32)
                .whereNotEqualTo('y', 'cat')
                .orderBy('z'),
        'array-contains different than orderBy works':
            (CollectionReference c) =>
                c.whereArrayContains('x', 32).orderBy('y'),
        'IN different than orderBy works': (CollectionReference c) =>
            c.whereIn('x', <Object?>[32]).orderBy('y'),
        'array-contains-any different than orderBy works':
            (CollectionReference c) =>
                c.whereArrayContainsAny('x', <Object?>[32]).orderBy('y'),
      };
      cases.forEach((String name, Query Function(CollectionReference) build) {
        test(name, () {
          expect(() => build(coll), returnsNormally);
        });
      });
    });
  });
}

class _TestClass {
  _TestClass(this.property);

  final String property;
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

/// Stands in for the `this` (the test class) that upstream's
/// arrayTransformsRejectInvalidElements puts in the array: a type that cannot
/// be stored.
class _ValidationTest {
  const _ValidationTest();
}

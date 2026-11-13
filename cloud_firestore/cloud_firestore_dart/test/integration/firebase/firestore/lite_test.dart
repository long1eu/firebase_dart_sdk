// Firestore Lite against the emulator: a port of the integration tests of
// the JS SDK's lite library (packages/firestore/test/lite/integration.test.ts).
// The groups and test names are those of the JS file. Not ported: the tests
// of TypeScript's static types (`types test`, `is properly typed`, `requires
// the correct converter for Partial usage`), `ignoreUndefinedProperties`
// (Dart has no `undefined`), the variadic path forms of `doc()` and
// `collection()` (Dart takes one path), and the tests JS skips on the
// emulator (the console link of a missing index, `BSON types`, which JS runs
// only against an Enterprise backend). The two `FieldValue` tests that need
// no backend (`isEqual()` and `instanceof`) are in
// test/unit/firebase/firestore/lite/lite_api_test.dart. The JS tests of
// aggregations with one filter, order or cursor each are one test here.
//
// Runs over gRPC by default and over REST (the transport of the web) with
// FIRESTORE_TEST_TRANSPORT=rest.

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/lite.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/grpc_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rest_transport.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import '../../../util/lite_test_util.dart';
import '../../../util/test_backend.dart';

class Post {
  Post(this.title, this.author);

  final String title;
  final String author;

  String byline() => '$title, by $author';
}

final FirestoreDataConverter<Post> postConverter =
    FirestoreDataConverter<Post>.from(
      fromFirestore: (QueryDocumentSnapshot<Map<String, Object?>> snapshot) {
        final Map<String, Object?> data = snapshot.data;
        return Post(data['title']! as String, data['author']! as String);
      },
      toFirestore: (Post post, SetOptions? options) => <String, Object?>{
        'title': post.title,
        'author': post.author,
      },
    );

/// The operations of DocumentReference, WriteBatch and Transaction that the
/// same tests run against (`MutationTester` of the JS file).
class MutationTester {
  MutationTester(
    this.name,
    this.set,
    this.update,
    this.updateFromList,
    this.delete, {
    this.mayUseBackoff = false,
  });

  final String name;
  final Future<void> Function<T>(
    DocumentReference<T> ref,
    T data, [
    SetOptions? options,
  ])
  set;
  final Future<void> Function(
    DocumentReference<Object?> ref,
    Map<String, Object?> data,
  )
  update;
  final Future<void> Function(
    DocumentReference<Object?> ref,
    List<Object?> data,
  )
  updateFromList;
  final Future<void> Function(DocumentReference<Object?> ref) delete;

  /// The transaction runner retries failed preconditions with a backoff.
  final bool mayUseBackoff;
}

final MutationTester documentTester = MutationTester(
  'DocumentReference',
  <T>(DocumentReference<T> ref, T data, [SetOptions? options]) =>
      ref.set(data, options),
  (DocumentReference<Object?> ref, Map<String, Object?> data) =>
      ref.update(data),
  (DocumentReference<Object?> ref, List<Object?> data) =>
      ref.updateFromList(data),
  (DocumentReference<Object?> ref) => ref.delete(),
);

final MutationTester batchTester = MutationTester(
  'WriteBatch',
  <T>(DocumentReference<T> ref, T data, [SetOptions? options]) async =>
      (ref.firestore.batch()..set<T>(ref, data, options)).commit(),
  (DocumentReference<Object?> ref, Map<String, Object?> data) async =>
      (ref.firestore.batch()..update(ref, data)).commit(),
  (DocumentReference<Object?> ref, List<Object?> data) async =>
      (ref.firestore.batch()..updateFromList(ref, data)).commit(),
  (DocumentReference<Object?> ref) async =>
      (ref.firestore.batch()..delete(ref)).commit(),
);

final MutationTester transactionTester = MutationTester(
  'Transaction',
  <T>(DocumentReference<T> ref, T data, [SetOptions? options]) =>
      ref.firestore.runTransaction<void>((Transaction transaction) async {
        transaction.set<T>(ref, data, options);
      }),
  (DocumentReference<Object?> ref, Map<String, Object?> data) =>
      ref.firestore.runTransaction<void>((Transaction transaction) async {
        transaction.update(ref, data);
      }),
  (DocumentReference<Object?> ref, List<Object?> data) =>
      ref.firestore.runTransaction<void>((Transaction transaction) async {
        transaction.updateFromList(ref, data);
      }),
  (DocumentReference<Object?> ref) =>
      ref.firestore.runTransaction<void>((Transaction transaction) async {
        transaction.delete(ref);
      }),
  mayUseBackoff: true,
);

void genericMutationTests(MutationTester op) {
  group('${op.name} mutations', () {
    group('delete', () {
      test('can delete a non-existing document', () async {
        await op.delete(await newLiteTestDoc());
      });

      test('can delete an existing document', () async {
        final DocumentReference<Map<String, Object?>> ref =
            await newLiteTestDoc();
        await op.set(ref, <String, Object?>{});
        await op.delete(ref);
        expect((await ref.get()).exists, isFalse);
      });
    });

    group('set', () {
      test('can set a new document', () async {
        final DocumentReference<Map<String, Object?>> ref =
            await newLiteTestDoc();
        await op.set(ref, <String, Object?>{'val': 1});
        expect((await ref.get()).data, <String, Object?>{'val': 1});
      });

      test('can merge a document', () async {
        final DocumentReference<Map<String, Object?>> ref =
            await newLiteTestDoc(<String, Object?>{'foo': 1});
        await op.set(ref, <String, Object?>{
          'bar': 2,
        }, SetOptions.mergeAllFields);
        expect((await ref.get()).data, <String, Object?>{'foo': 1, 'bar': 2});
      });

      test('can merge a document with mergeFields', () async {
        final DocumentReference<Map<String, Object?>> ref =
            await newLiteTestDoc(<String, Object?>{'foo': 1});
        await op.set(
          ref,
          <String, Object?>{
            'foo': 'ignored',
            'bar': 2,
            'baz': <String, Object?>{'foobar': 3},
          },
          SetOptions.mergeFieldPaths(<FieldPath>[
            FieldPath.of(<String>['bar']),
            FieldPath.of(<String>['baz', 'foobar']),
          ]),
        );
        expect((await ref.get()).data, <String, Object?>{
          'foo': 1,
          'bar': 2,
          'baz': <String, Object?>{'foobar': 3},
        });
      });

      test('supports partials with merge', () async {
        // The converter sees the merge options and writes only what it is
        // given.
        final FirestoreDataConverter<Map<String, Object?>> mergeConverter =
            FirestoreDataConverter<Map<String, Object?>>.from(
              fromFirestore:
                  (QueryDocumentSnapshot<Map<String, Object?>> snapshot) =>
                      snapshot.data,
              toFirestore: (Map<String, Object?> post, SetOptions? options) {
                if (options == null || !options.merge) {
                  expect(post.keys, containsAll(<String>['title', 'author']));
                }
                return post;
              },
            );
        final DocumentReference<Map<String, Object?>> ref =
            newLiteTestCollection().doc('post').withConverter(mergeConverter);
        await op.set(ref, <String, Object?>{
          'title': 'walnut',
          'author': 'author',
        });
        await op.set(ref, <String, Object?>{
          'title': 'olive',
          'id': FieldValue.increment(2),
        }, SetOptions.mergeAllFields);
        final DocumentSnapshot<Map<String, Object?>> post = await ref.get();
        expect(post.get('title'), 'olive');
        expect(post.get('author'), 'author');
        expect(post.get('id'), 2);
      });

      test('supports partials with mergeFields', () async {
        final DocumentReference<Map<String, Object?>> ref =
            newLiteTestCollection().doc('post');
        await op.set(ref, <String, Object?>{
          'title': 'walnut',
          'author': 'author',
        });
        await op.set(ref, <String, Object?>{
          'title': 'olive',
        }, SetOptions.mergeFields(<String>['title']));
        final DocumentSnapshot<Map<String, Object?>> post = await ref.get();
        expect(post.get('title'), 'olive');
        expect(post.get('author'), 'author');
      });

      test('throws when user input fails validation', () async {
        final DocumentReference<Map<String, Object?>> ref =
            await newLiteTestDoc();
        // Dart has no `undefined`: a value of an unsupported type is the
        // invalid input.
        await expectLater(
          Future<void>.sync(
            () => op.set(ref, <String, Object?>{'val': Object()}),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '${e.message}',
              'message',
              contains('Unsupported type: Object (found in field val)'),
            ),
          ),
        );
      });
    });

    group('update', () {
      test('can update a document', () async {
        final DocumentReference<Map<String, Object?>> ref =
            await newLiteTestDoc(<String, Object?>{'foo': 1, 'bar': 1});
        await op.update(ref, <String, Object?>{'foo': 2, 'baz': 2});
        expect((await ref.get()).data, <String, Object?>{
          'foo': 2,
          'bar': 1,
          'baz': 2,
        });
      });

      test('can update a document (using varargs)', () async {
        final DocumentReference<Map<String, Object?>> ref =
            await newLiteTestDoc(<String, Object?>{'foo': 1, 'bar': 1});
        await op.updateFromList(ref, <Object?>[
          'foo',
          2,
          FieldPath.of(<String>['baz']),
          2,
        ]);
        expect((await ref.get()).data, <String, Object?>{
          'foo': 2,
          'bar': 1,
          'baz': 2,
        });
      });

      test(
        'enforces that document exists',
        () async {
          final DocumentReference<Map<String, Object?>> ref =
              await newLiteTestDoc();
          await expectLater(
            op.update(ref, <String, Object?>{'foo': 2, 'baz': 2}),
            throwsA(
              isA<FirestoreError>().having(
                (FirestoreError e) => e.code,
                'code',
                FirestoreErrorCode.notFound,
              ),
            ),
          );
        },
        skip: op.mayUseBackoff
            ? 'As in the JS file: the transaction runner retries failed '
                  'preconditions with a backoff, which makes this test slow'
            : null,
      );

      test('throws when user input fails validation', () async {
        final DocumentReference<Map<String, Object?>> ref =
            await newLiteTestDoc();
        await expectLater(
          Future<void>.sync(
            () => op.update(ref, <String, Object?>{'val': Object()}),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '${e.message}',
              'message',
              contains('Unsupported type: Object (found in field val)'),
            ),
          ),
        );
      });
    });
  });
}

void verifyResults(
  QuerySnapshot<Map<String, Object?>> actual,
  List<Map<String, Object?>> expected,
) {
  expect(actual.isEmpty, expected.isEmpty);
  expect(actual.length, expected.length);
  expect(
    actual.docs
        .map((QueryDocumentSnapshot<Map<String, Object?>> doc) => doc.data)
        .toList(),
    expected,
  );
}

Matcher get throwsTerminated => throwsA(
  isA<FirestoreError>()
      .having(
        (FirestoreError e) => e.code,
        'code',
        FirestoreErrorCode.failedPrecondition,
      )
      .having(
        (FirestoreError e) => e.message,
        'message',
        'The client has already been terminated.',
      ),
);

void main() {
  final String? skip = liteEmulatorSkipReason;

  group('Firestore', () {
    test('can provide setting', () {
      final Firestore firestore = Firestore.instanceFor(
        app: newLiteTestApp(),
        settings: FirestoreSettings(host: 'localhost', sslEnabled: false),
      );
      addTearDown(firestore.terminate);
      expect(firestore.settings.host, 'localhost');
      expect(firestore.settings.sslEnabled, isFalse);
    });

    test('returns same default instance from named app', () {
      final FirebaseApp app = newLiteTestApp();
      final Firestore fs1 = Firestore.instanceFor(app: app);
      addTearDown(fs1.terminate);
      final Firestore fs2 = Firestore.instanceFor(app: app);
      final Firestore fs3 = Firestore.instanceFor(
        app: app,
        database: '(default)',
      );
      expect(fs1, same(fs2));
      expect(fs1, same(fs3));
    });

    test('returns same default instance from default app', () {
      final FirebaseApp app = FirebaseApp.withOptions(
        const FirebaseOptions(
          apiKey: 'fake-api-key',
          applicationId: 'appId',
          projectId: 'test-project',
        ),
        dependencies: null,
      );
      addTearDown(app.delete);
      final Firestore fs1 = Firestore.instanceFor(
        app: app,
        settings: FirestoreSettings(host: 'localhost', sslEnabled: false),
      );
      addTearDown(fs1.terminate);
      // getFirestore(), getFirestore(app), getFirestore('(default)') and
      // getFirestore(app, '(default)') of the JS test.
      expect(Firestore.instance, same(fs1));
      expect(Firestore.instanceFor(app: app), same(fs1));
      expect(
        Firestore.instanceFor(app: FirebaseApp.instance, database: '(default)'),
        same(fs1),
      );
      expect(Firestore.instanceFor(app: app, database: '(default)'), same(fs1));
    });

    test('returns different instance from named app', () {
      final FirebaseApp app = newLiteTestApp();
      final List<Firestore> instances = <Firestore>[
        Firestore.instanceFor(app: app, database: 'init1'),
        Firestore.instanceFor(app: app, database: 'init2'),
        Firestore.instanceFor(app: app),
        Firestore.instanceFor(app: app, database: 'name1'),
        Firestore.instanceFor(app: app, database: 'name2'),
      ];
      for (final Firestore firestore in instances) {
        addTearDown(firestore.terminate);
      }
      expect(instances.toSet(), hasLength(5));
      expect(instances[0].databaseId, 'init1');
      expect(instances[2].databaseId, '(default)');
    });

    test('returns different instance from different named app', () {
      final Firestore fs1 = Firestore.instanceFor(app: newLiteTestApp());
      final Firestore fs2 = Firestore.instanceFor(app: newLiteTestApp());
      addTearDown(fs1.terminate);
      addTearDown(fs2.terminate);
      expect(fs1, isNot(same(fs2)));
    });

    test('cannot call initializeFirestore() twice', () {
      // In Dart: asking for the instance again with other settings.
      final FirebaseApp app = newLiteTestApp();
      final Firestore firestore = Firestore.instanceFor(
        app: app,
        settings: FirestoreSettings(host: 'localhost', sslEnabled: false),
      );
      addTearDown(firestore.terminate);
      expect(
        () => Firestore.instanceFor(
          app: app,
          settings: FirestoreSettings(host: 'otherhost', sslEnabled: false),
        ),
        throwsStateError,
      );
      // The same settings are not a second initialization.
      expect(
        Firestore.instanceFor(
          app: app,
          settings: FirestoreSettings(host: 'localhost', sslEnabled: false),
        ),
        same(firestore),
      );
    });

    test('cannot use once terminated', () async {
      final Firestore firestore = Firestore.instanceFor(
        app: newLiteTestApp(),
        settings: FirestoreSettings(host: 'localhost', sslEnabled: false),
      );
      // The termination is not awaited: any operation started after it is
      // rejected.
      unawaited(firestore.terminate());
      await expectLater(firestore.doc('coll/doc').get(), throwsTerminated);
    });

    test('can call terminate() multiple times', () async {
      final Firestore firestore = Firestore.instanceFor(
        app: newLiteTestApp(),
        settings: FirestoreSettings(host: 'localhost', sslEnabled: false),
      );
      await firestore.terminate();
      await firestore.terminate();
    });

    test('returns a new instance after terminate()', () async {
      final FirebaseApp app = newLiteTestApp();
      final Firestore first = Firestore.instanceFor(app: app);
      await first.terminate();
      final Firestore second = Firestore.instanceFor(app: app);
      addTearDown(second.terminate);
      expect(second, isNot(same(first)));
    });

    test('is terminated when its app is deleted', () async {
      final FirebaseApp app = FirebaseApp.withOptions(
        const FirebaseOptions(
          apiKey: 'fake-api-key',
          applicationId: 'appId',
          projectId: 'demo-test',
        ),
        dependencies: null,
        name: 'lite-deleted-app',
      );
      final Firestore firestore = Firestore.instanceFor(app: app);
      app.delete();
      await pumpEventQueue();
      await expectLater(firestore.doc('coll/doc').get(), throwsTerminated);
    });
  });

  group('doc', () {
    late Firestore db;
    setUp(() {
      db = Firestore.instanceFor(app: newLiteTestApp());
      addTearDown(db.terminate);
    });

    test('can be used relative to Firestore root', () {
      final DocumentReference<Map<String, Object?>> result = db.doc('coll/doc');
      expect(result.id, 'doc');
      expect(result.path, 'coll/doc');
    });

    test('can be used relative to collection', () {
      final DocumentReference<Map<String, Object?>> result = db
          .collection('coll')
          .doc('doc');
      expect(result.id, 'doc');
      expect(result.path, 'coll/doc');
    });

    test('can be used with multiple arguments', () {
      // Dart takes one path: the segments are joined by the caller.
      final DocumentReference<Map<String, Object?>> result = db.doc(
        <String>['coll1/doc1', 'coll2', 'doc2'].join('/'),
      );
      expect(result.id, 'doc2');
      expect(result.path, 'coll1/doc1/coll2/doc2');
    });

    test('strips leading and trailing slashes', () {
      final DocumentReference<Map<String, Object?>> result = db.doc(
        '/coll/doc/',
      );
      expect(result.id, 'doc');
      expect(result.path, 'coll/doc');
    });

    test('can be relative to doc', () {
      final DocumentReference<Map<String, Object?>> result = db
          .doc('coll/doc')
          .collection('subcoll')
          .doc('subdoc');
      expect(result.id, 'subdoc');
      expect(result.path, 'coll/doc/subcoll/subdoc');
    });

    test('validates path', () {
      expect(
        () => db.doc('coll'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            'Invalid document reference. Document references must have an '
                'even number of segments, but coll has 1',
          ),
        ),
      );
      expect(
        () => db.doc(''),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            'Invalid document reference. A document path must not be empty.',
          ),
        ),
      );
      expect(
        () => db.collection('coll').doc('doc/coll'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            'Invalid document reference. Document references must have an '
                'even number of segments, but coll/doc/coll has 3',
          ),
        ),
      );
      expect(
        () => db.doc('coll//doc'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            'Invalid path (coll//doc). Paths must not contain // in them.',
          ),
        ),
      );
    });

    test('supports AutoId', () {
      expect(db.collection('coll').doc().id, hasLength(20));
    });
  });

  group('collection', () {
    late Firestore db;
    setUp(() {
      db = Firestore.instanceFor(app: newLiteTestApp());
      addTearDown(db.terminate);
    });

    test('can be used relative to Firestore root', () {
      final CollectionReference<Map<String, Object?>> result = db.collection(
        'coll/doc/subcoll',
      );
      expect(result.id, 'subcoll');
      expect(result.path, 'coll/doc/subcoll');
    });

    test('can be used relative to collection', () {
      final CollectionReference<Map<String, Object?>> result = db
          .collection('coll')
          .doc('doc')
          .collection('subcoll');
      expect(result.id, 'subcoll');
      expect(result.path, 'coll/doc/subcoll');
    });

    test('can be used relative to doc', () {
      final CollectionReference<Map<String, Object?>> result = db
          .doc('coll/doc')
          .collection('subcoll');
      expect(result.id, 'subcoll');
      expect(result.path, 'coll/doc/subcoll');
    });

    test('can be used relative to doc with a longer path', () {
      final CollectionReference<Map<String, Object?>> result = db
          .doc('coll/doc')
          .collection('subcoll/subdoc/subsubcoll');
      expect(result.id, 'subsubcoll');
      expect(result.path, 'coll/doc/subcoll/subdoc/subsubcoll');
    });

    test('validates path', () {
      expect(
        () => db.collection('coll/doc'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            'Invalid collection reference. Collection references must have '
                'an odd number of segments, but coll/doc has 2',
          ),
        ),
      );
      expect(() => db.collection(''), throwsArgumentError);
      expect(
        () => db.doc('coll/doc').collection('coll/doc'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            'Invalid collection reference. Collection references must have '
                'an odd number of segments, but coll/doc/coll/doc has 4',
          ),
        ),
      );
      expect(() => db.collection('coll//doc'), throwsArgumentError);
    });
  });

  group('parent', () {
    late Firestore db;
    setUp(() {
      db = Firestore.instanceFor(app: newLiteTestApp());
      addTearDown(db.terminate);
    });

    test('returns CollectionReferences for DocumentReferences', () {
      final CollectionReference<Map<String, Object?>> result = db
          .doc('coll/doc')
          .parent;
      expect(result.path, 'coll');
    });

    test('returns DocumentReferences for CollectionReferences', () {
      final DocumentReference<Map<String, Object?>>? result = db
          .collection('coll/doc/coll')
          .parent;
      expect(result!.path, 'coll/doc');
    });

    test('returns null for root collection', () {
      expect(db.collection('coll').parent, isNull);
    });
  });

  group('transport', () {
    test('the run uses the transport it asks for', () async {
      final int transportsBefore = liteTestTransports.length;
      final int clientsBefore = liteTestHttpClients.length;
      final DocumentReference<Map<String, Object?>> ref = await newLiteTestDoc(
        <String, Object?>{'n': 1},
      );
      expect((await ref.get()).data, <String, Object?>{'n': 1});
      expect((await ref.parent.where('n', isEqualTo: 1).get()).length, 1);
      expect((await ref.parent.count().get()).getCount(), 1);

      // One instance, one transport.
      expect(liteTestTransports, hasLength(transportsBefore + 1));
      if (liteWebTransportRequested) {
        expect(liteTestTransports.last, isA<RestTransport>());
        // Every call was an HTTP request to a REST endpoint.
        expect(liteTestHttpClients, hasLength(clientsBefore + 1));
        final String documents =
            '/v1/projects/${ref.firestore.projectId}/databases/(default)'
            '/documents';
        expect(liteTestHttpClients.last.log, <String>[
          'POST $documents:commit',
          'POST $documents:batchGet',
          'POST $documents:runQuery',
          'POST $documents:runAggregationQuery',
        ]);
      } else {
        expect(liteTestTransports.last, isA<GrpcTransport>());
        expect(
          liteTestHttpClients,
          hasLength(clientsBefore),
          reason: 'no HTTP client is made for a gRPC run',
        );
      }
    });
  }, skip: skip);

  group('getDoc()', () {
    test('can get a non-existing document', () async {
      final DocumentReference<Map<String, Object?>> ref =
          await newLiteTestDoc();
      expect((await ref.get()).exists, isFalse);
    });

    test('can get an existing document', () async {
      final DocumentReference<Map<String, Object?>> ref = await newLiteTestDoc(
        <String, Object?>{'val': 1},
      );
      expect((await ref.get()).exists, isTrue);
    });

    test('can get doc with a deserialized reference', () async {
      final DocumentReference<Map<String, Object?>> ref = await newLiteTestDoc(
        <String, Object?>{'val': 1},
      );
      expect((await ref.get()).exists, isTrue);
      final DocumentReference<Map<String, Object?>> deserialized =
          DocumentReference<Map<String, Object?>>.fromJson(
            ref.firestore,
            ref.toJson(),
          );
      expect(deserialized, ref);
      expect((await deserialized.get()).exists, isTrue);
    });
  }, skip: skip);

  group('mutations', () {
    genericMutationTests(documentTester);
    genericMutationTests(batchTester);
    genericMutationTests(transactionTester);
  }, skip: skip);

  group('WriteBatch', () {
    test('can add multiple operations', () async {
      final CollectionReference<Map<String, Object?>> coll =
          newLiteTestCollection();
      final WriteBatch batch = coll.firestore.batch()
        ..set(coll.doc(), <String, Object?>{'doc': 1})
        ..set(coll.doc(), <String, Object?>{'doc': 2});
      await batch.commit();
      verifyResults(await coll.orderBy('doc').get(), <Map<String, Object?>>[
        <String, Object?>{'doc': 1},
        <String, Object?>{'doc': 2},
      ]);
    });

    test('cannot add write after commit', () async {
      final DocumentReference<Map<String, Object?>> doc =
          await newLiteTestDoc();
      final WriteBatch batch = doc.firestore.batch()
        ..set(doc, <String, Object?>{'doc': 1});
      final Future<void> op = batch.commit();
      final Matcher throwsCommitted = throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          'A write batch can no longer be used after commit() has been called.',
        ),
      );
      expect(() => batch.delete(doc), throwsCommitted);
      await op;
      expect(() => batch.delete(doc), throwsCommitted);
    });
  }, skip: skip);

  group('Transaction', () {
    test('can read and then write', () async {
      final DocumentReference<Map<String, Object?>> doc = await newLiteTestDoc(
        <String, Object?>{'counter': 1},
      );
      await doc.firestore.runTransaction<void>((Transaction transaction) async {
        final DocumentSnapshot<Map<String, Object?>> snap = await transaction
            .get(doc);
        transaction.updateFromList(doc, <Object?>[
          'counter',
          (snap.get('counter')! as int) + 1,
        ]);
      });
      expect((await doc.get()).get('counter'), 2);
    });

    test('can read non-existing doc then write', () async {
      final DocumentReference<Map<String, Object?>> doc =
          await newLiteTestDoc();
      await doc.firestore.runTransaction<void>((Transaction transaction) async {
        final DocumentSnapshot<Map<String, Object?>> snap = await transaction
            .get(doc);
        expect(snap.exists, isFalse);
        transaction.set(doc, <String, Object?>{'counter': 1});
      });
      expect((await doc.get()).get('counter'), 1);
    });

    test('can read deleted doc then write', () async {
      final DocumentReference<Map<String, Object?>> doc = await newLiteTestDoc(
        <String, Object?>{'counter': 1},
      );
      await doc.delete();
      await doc.firestore.runTransaction<void>((Transaction transaction) async {
        final DocumentSnapshot<Map<String, Object?>> snap = await transaction
            .get(doc);
        expect(snap.exists, isFalse);
        transaction.set(doc, <String, Object?>{'counter': 1});
      });
      expect((await doc.get()).get('counter'), 1);
    });

    test('retries when document is modified', () async {
      final DocumentReference<Map<String, Object?>> doc =
          await newLiteTestDoc();
      int retryCounter = 0;
      await doc.firestore.runTransaction<void>((Transaction transaction) async {
        ++retryCounter;
        await transaction.get(doc);
        if (retryCounter == 1) {
          // Out of band modification that doesn't use the transaction.
          await doc.set(<String, Object?>{'counter': 'invalid'});
        }
        transaction.set(doc, <String, Object?>{'counter': 1});
      });
      expect(retryCounter, 2);
      expect((await doc.get()).get('counter'), 1);
    });

    test('returns the result of the update function', () async {
      final DocumentReference<Map<String, Object?>> doc = await newLiteTestDoc(
        <String, Object?>{'counter': 41},
      );
      final int result = await doc.firestore.runTransaction<int>((
        Transaction transaction,
      ) async {
        final int next =
            ((await transaction.get(doc)).get('counter')! as int) + 1;
        transaction.update(doc, <String, Object?>{'counter': next});
        return next;
      });
      expect(result, 42);
    });

    test('honours maxAttempts', () async {
      final DocumentReference<Map<String, Object?>> doc = await newLiteTestDoc(
        <String, Object?>{'counter': 0},
      );
      int attempts = 0;
      await expectLater(
        doc.firestore.runTransaction<void>((Transaction transaction) async {
          attempts++;
          await transaction.get(doc);
          await doc.update(<String, Object?>{'counter': attempts});
          transaction.update(doc, <String, Object?>{'counter': -1});
        }, options: TransactionOptions(maxAttempts: 1)),
        throwsA(isA<FirestoreError>()),
      );
      expect(attempts, 1);
    });

    test('a read-only transaction reads and rejects writes', () async {
      final DocumentReference<Map<String, Object?>> doc = await newLiteTestDoc(
        <String, Object?>{'counter': 7},
      );
      final Object? value = await doc.firestore.runTransaction<Object?>(
        (Transaction transaction) async =>
            (await transaction.get(doc)).get('counter'),
        options: TransactionOptions(readOnly: true),
      );
      expect(value, 7);
      await expectLater(
        doc.firestore.runTransaction<void>((Transaction transaction) async {
          transaction.set(doc, <String, Object?>{'counter': 8});
        }, options: TransactionOptions(readOnly: true)),
        throwsA(
          isA<FirestoreError>().having(
            (FirestoreError e) => e.code,
            'code',
            FirestoreErrorCode.invalidArgument,
          ),
        ),
      );
    });
    test(
      'a read-only transaction reads queries at one point in time',
      () async {
        final CollectionReference<Map<String, Object?>> coll =
            await newLiteTestCollectionWith(<Map<String, Object?>>[
              <String, Object?>{'n': 1},
              <String, Object?>{'n': 2},
              <String, Object?>{'n': 3},
            ]);
        await coll.firestore.runTransaction<void>((
          Transaction transaction,
        ) async {
          final QuerySnapshot<Map<String, Object?>> before = await transaction
              .getQuery(coll.orderBy('n').limitToLast(2));
          expect(
            before.docs
                .map(
                  (QueryDocumentSnapshot<Map<String, Object?>> doc) =>
                      doc.data['n'],
                )
                .toList(),
            <int>[2, 3],
          );
          // A write outside the transaction is not seen by its later reads.
          final DocumentReference<Map<String, Object?>> added = await coll.add(
            <String, Object?>{'n': 4},
          );
          expect((await transaction.getQuery(coll.orderBy('n'))).length, 3);
          expect((await transaction.get(added)).exists, isFalse);
          final AggregateQuerySnapshot totals = await transaction.getAggregate(
            coll.aggregateWithAliases(<String, AggregateField>{
              'count': AggregateField.count(),
              'sum': AggregateField.sum('n'),
            }),
          );
          expect(totals.data(), <String, Object?>{'count': 3, 'sum': 6});
        }, options: TransactionOptions(readOnly: true));
        expect((await coll.count().get()).getCount(), 4);
      },
    );

    test(
      'a read after a write fails the transaction, even when caught',
      () async {
        final DocumentReference<Map<String, Object?>> doc =
            await newLiteTestDoc(<String, Object?>{'counter': 1});
        await expectLater(
          doc.firestore.runTransaction<void>((Transaction transaction) async {
            transaction.set(doc, <String, Object?>{'counter': 2});
            try {
              await transaction.get(doc);
            } on FirestoreError catch (_) {
              // The commit fails all the same.
            }
          }),
          throwsA(
            isA<FirestoreError>().having(
              (FirestoreError e) => e.code,
              'code',
              FirestoreErrorCode.invalidArgument,
            ),
          ),
        );
        expect((await doc.get()).get('counter'), 1);
      },
    );

    test('terminate() inside a transaction fails its commit', () async {
      final DocumentReference<Map<String, Object?>> doc = await newLiteTestDoc(
        <String, Object?>{'counter': 1},
      );
      final Firestore db = doc.firestore;
      int attempts = 0;
      await expectLater(
        db.runTransaction<void>((Transaction transaction) async {
          attempts++;
          await transaction.get(doc);
          transaction.set(doc, <String, Object?>{'counter': 2});
          // Does not wait for the transaction.
          await db.terminate();
        }),
        throwsTerminated,
      );
      expect(attempts, 1);
      final Firestore other = newLiteTestFirestore();
      expect((await other.doc(doc.path).get()).get('counter'), 1);
    });

    test('queries need a read-only transaction', () async {
      final CollectionReference<Map<String, Object?>> coll =
          newLiteTestCollection();
      await expectLater(
        coll.firestore.runTransaction<void>(
          (Transaction transaction) => transaction.getQuery(coll),
        ),
        throwsA(
          isA<FirestoreError>().having(
            (FirestoreError e) => e.code,
            'code',
            FirestoreErrorCode.invalidArgument,
          ),
        ),
      );
    });
  }, skip: skip);

  group('addDoc()', () {
    test('can add a document', () async {
      final DocumentReference<Map<String, Object?>> ref =
          await newLiteTestCollection().add(<String, Object?>{'val': 1});
      expect((await ref.get()).data, <String, Object?>{'val': 1});
    });

    test('throws when user input fails validation', () async {
      await expectLater(
        newLiteTestCollection().add(<String, Object?>{'val': Object()}),
        throwsArgumentError,
      );
    });
  }, skip: skip);

  group('DocumentSnapshot', () {
    test('can represent missing data', () async {
      final DocumentSnapshot<Map<String, Object?>> snap =
          await (await newLiteTestDoc()).get();
      expect(snap.exists, isFalse);
      expect(snap.data, isNull);
      expect(snap.get('foo'), isNull);
    });

    test('can return data', () async {
      final DocumentSnapshot<Map<String, Object?>> snap =
          await (await newLiteTestDoc(<String, Object?>{'foo': 1})).get();
      expect(snap.exists, isTrue);
      expect(snap.data, <String, Object?>{'foo': 1});
    });

    test('can return single field', () async {
      final DocumentSnapshot<Map<String, Object?>> snap =
          await (await newLiteTestDoc(<String, Object?>{
            'foo': 1,
            'bar': 2,
          })).get();
      expect(snap.get('foo'), 1);
      expect(snap['foo'], 1);
      expect(snap.getField(FieldPath.of(<String>['bar'])), 2);
      expect(snap.contains('foo'), isTrue);
      expect(snap.contains('baz'), isFalse);
    });

    test('can return nested field', () async {
      final DocumentSnapshot<Map<String, Object?>> snap =
          await (await newLiteTestDoc(<String, Object?>{
            'foo': <String, Object?>{'bar': 1},
          })).get();
      expect(snap.get('foo.bar'), 1);
      expect(snap.getField(FieldPath.of(<String>['foo', 'bar'])), 1);
    });

    test('returns Bytes', () async {
      final DocumentSnapshot<Map<String, Object?>> snap =
          await (await newLiteTestDoc(<String, Object?>{
            'bytes': Blob.fromBase64String('YWE='),
          })).get();
      expect(snap.get('bytes'), Blob.fromBase64String('YWE='));
    });

    test('returns the value types and references', () async {
      final DocumentReference<Map<String, Object?>> ref =
          await newLiteTestDoc();
      const Timestamp timestamp = Timestamp(1700000000, 123456000);
      await ref.set(<String, Object?>{
        'null': null,
        'bool': true,
        'int': 42,
        'double': 1.5,
        'string': 'text',
        'timestamp': timestamp,
        'geo': const GeoPoint(1.5, -2.5),
        'bytes': Blob(Uint8List.fromList(<int>[1, 2, 3])),
        'ref': ref,
        'array': <Object?>[
          1,
          'two',
          <String, Object?>{'three': 3},
        ],
        'map': <String, Object?>{
          'nested': <String, Object?>{'deep': true},
        },
      });
      final Map<String, Object?> data = (await ref.get()).data!;
      expect(data, <String, Object?>{
        'null': null,
        'bool': true,
        'int': 42,
        'double': 1.5,
        'string': 'text',
        'timestamp': timestamp,
        'geo': const GeoPoint(1.5, -2.5),
        'bytes': Blob(Uint8List.fromList(<int>[1, 2, 3])),
        'ref': ref,
        'array': <Object?>[
          1,
          'two',
          <String, Object?>{'three': 3},
        ],
        'map': <String, Object?>{
          'nested': <String, Object?>{'deep': true},
        },
      });
      expect(data['ref'], isA<DocumentReference<Map<String, Object?>>>());
    });
  }, skip: skip);

  group('deleteDoc()', () {
    test('can delete a non-existing document', () async {
      await (await newLiteTestDoc()).delete();
    });
  }, skip: skip);

  group('FieldValue', () {
    Future<Map<String, Object?>?> applied(
      Map<String, Object?> initial,
      FieldValue value,
    ) async {
      final DocumentReference<Map<String, Object?>> ref = await newLiteTestDoc(
        initial,
      );
      await ref.updateFromList(<Object?>['val', value]);
      return (await ref.get()).data;
    }

    test('can apply arrayUnion', () async {
      expect(
        await applied(<String, Object?>{
          'val': <Object?>['foo'],
        }, FieldValue.arrayUnion(<Object>['bar'])),
        <String, Object?>{
          'val': <Object?>['foo', 'bar'],
        },
      );
    });

    test('can apply arrayRemove', () async {
      expect(
        await applied(<String, Object?>{
          'val': <Object?>['foo', 'bar'],
        }, FieldValue.arrayRemove(<Object>['bar'])),
        <String, Object?>{
          'val': <Object?>['foo'],
        },
      );
    });

    test('can apply serverTimestamp', () async {
      final Map<String, Object?>? data = await applied(<String, Object?>{
        'val': null,
      }, FieldValue.serverTimestamp());
      expect(data!['val'], isA<Timestamp>());
    });

    test('can apply increment', () async {
      expect(
        await applied(<String, Object?>{'val': 1}, FieldValue.increment(2)),
        <String, Object?>{'val': 3},
      );
    });

    test('can apply minimum', () async {
      expect(
        await applied(<String, Object?>{'val': 2}, FieldValue.minimum(1)),
        <String, Object?>{'val': 1},
      );
    });

    test('can apply minimum (noop)', () async {
      expect(
        await applied(<String, Object?>{'val': 1}, FieldValue.minimum(2)),
        <String, Object?>{'val': 1},
      );
    });

    test('can apply maximum', () async {
      expect(
        await applied(<String, Object?>{'val': 1}, FieldValue.maximum(2)),
        <String, Object?>{'val': 2},
      );
    });

    test('can apply maximum (noop)', () async {
      expect(
        await applied(<String, Object?>{'val': 2}, FieldValue.maximum(1)),
        <String, Object?>{'val': 2},
      );
    });

    test('can apply minimum against non-numeric', () async {
      expect(
        await applied(<String, Object?>{
          'val': 'string',
        }, FieldValue.minimum(1)),
        <String, Object?>{'val': 1},
      );
    });

    test('can apply maximum against non-numeric', () async {
      expect(
        await applied(<String, Object?>{
          'val': 'string',
        }, FieldValue.maximum(1)),
        <String, Object?>{'val': 1},
      );
    });

    test('can delete field', () async {
      expect(
        await applied(<String, Object?>{'val': 'foo'}, FieldValue.delete()),
        <String, Object?>{},
      );
    });
  }, skip: skip);

  group('Query', () {
    Map<String, Object?> foo(int value) => <String, Object?>{'foo': value};

    test('supports default query', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[foo(1)]);
      verifyResults(await coll.get(), <Map<String, Object?>>[foo(1)]);
    });

    test('supports empty results', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[]);
      verifyResults(await coll.get(), <Map<String, Object?>>[]);
    });

    test('supports filtered query', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            foo(1),
            foo(2),
          ]);
      verifyResults(
        await coll.where('foo', isEqualTo: 1).get(),
        <Map<String, Object?>>[foo(1)],
      );
    });

    test('supports filtered query (with FieldPath)', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            foo(1),
            foo(2),
          ]);
      verifyResults(
        await coll.where(FieldPath.of(<String>['foo']), isEqualTo: 1).get(),
        <Map<String, Object?>>[foo(1)],
      );
    });

    test('supports filtered query (with a Filter)', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            foo(1),
            foo(2),
            foo(3),
          ]);
      verifyResults(
        await coll
            .where(
              Filter.or(<Filter>[
                Filter.equalTo('foo', 1),
                Filter.greaterThan('foo', 2),
              ]),
            )
            .orderBy('foo')
            .get(),
        <Map<String, Object?>>[foo(1), foo(3)],
      );
    });

    test('supports ordered query (with default order)', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            foo(1),
            foo(2),
          ]);
      verifyResults(await coll.orderBy('foo').get(), <Map<String, Object?>>[
        foo(1),
        foo(2),
      ]);
    });

    test('supports ordered query (with asc)', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            foo(1),
            foo(2),
          ]);
      verifyResults(
        await coll.orderBy('foo', Direction.ascending).get(),
        <Map<String, Object?>>[foo(1), foo(2)],
      );
    });

    test('supports ordered query (with desc)', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            foo(1),
            foo(2),
          ]);
      verifyResults(
        await coll.orderBy('foo', Direction.descending).get(),
        <Map<String, Object?>>[foo(2), foo(1)],
      );
    });

    test('supports limit query', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            foo(1),
            foo(2),
          ]);
      verifyResults(
        await coll.orderBy('foo').limit(1).get(),
        <Map<String, Object?>>[foo(1)],
      );
    });

    test('supports limitToLast query', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            foo(1),
            foo(2),
            foo(3),
          ]);
      verifyResults(
        await coll.orderBy('foo').limitToLast(2).get(),
        <Map<String, Object?>>[foo(2), foo(3)],
      );
    });

    test(
      'supports limitToLast query with cursors and descending order',
      () async {
        final CollectionReference<Map<String, Object?>> coll =
            await newLiteTestCollectionWith(<Map<String, Object?>>[
              foo(1),
              foo(2),
              foo(3),
              foo(4),
              foo(5),
            ]);
        verifyResults(
          await coll
              .orderBy('foo')
              .endBefore(<Object?>[5])
              .limitToLast(2)
              .get(),
          <Map<String, Object?>>[foo(3), foo(4)],
        );
        verifyResults(
          await coll
              .orderBy('foo', Direction.descending)
              .startAfter(<Object?>[5])
              .limitToLast(2)
              .get(),
          <Map<String, Object?>>[foo(2), foo(1)],
        );
      },
    );

    test('limitToLast requires an orderBy', () async {
      await expectLater(
        newLiteTestCollection().limitToLast(2).get(),
        throwsStateError,
      );
    });

    test('supports startAt', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            foo(1),
            foo(2),
          ]);
      verifyResults(
        await coll.orderBy('foo').startAt(<Object?>[2]).get(),
        <Map<String, Object?>>[foo(2)],
      );
    });

    test('supports startAfter', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            foo(1),
            foo(2),
          ]);
      verifyResults(
        await coll.orderBy('foo').startAfter(<Object?>[1]).get(),
        <Map<String, Object?>>[foo(2)],
      );
    });

    test('supports endAt', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            foo(1),
            foo(2),
          ]);
      verifyResults(
        await coll.orderBy('foo').endAt(<Object?>[1]).get(),
        <Map<String, Object?>>[foo(1)],
      );
    });

    test('supports endBefore', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            foo(1),
            foo(2),
          ]);
      verifyResults(
        await coll.orderBy('foo').endBefore(<Object?>[2]).get(),
        <Map<String, Object?>>[foo(1)],
      );
    });

    test('supports pagination', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            foo(1),
            foo(2),
          ]);
      Query<Map<String, Object?>> query = coll.orderBy('foo').limit(1);
      QuerySnapshot<Map<String, Object?>> result = await query.get();
      verifyResults(result, <Map<String, Object?>>[foo(1)]);

      // Pass the document snapshot from the previous result.
      query = query.startAfterDocument(result.docs[0]);
      result = await query.get();
      verifyResults(result, <Map<String, Object?>>[foo(2)]);
    });

    test('supports collection groups', () async {
      final CollectionReference<Map<String, Object?>> coll =
          newLiteTestCollection();
      final Firestore db = coll.firestore;
      final String group = '${coll.id}group';
      await db.doc('${coll.id}/foo/$group/doc1').set(<String, Object?>{
        'foo': 1,
      });
      await db.doc('${coll.id}/bar/baz/boo/$group/doc2').set(<String, Object?>{
        'bar': 1,
      });

      verifyResults(
        await db.collectionGroup(group).get(),
        <Map<String, Object?>>[
          <String, Object?>{'bar': 1},
          <String, Object?>{'foo': 1},
        ],
      );
    });

    test('validates collection groups', () {
      final Firestore db = newLiteTestFirestore();
      expect(() => db.collectionGroup(''), throwsArgumentError);
      expect(
        () => db.collectionGroup('/'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            "Invalid collectionId '/'. Collection IDs must not contain '/'.",
          ),
        ),
      );
    });

    test(
      'supports query over collection path with special characters',
      () async {
        final CollectionReference<Map<String, Object?>> coll =
            newLiteTestCollection();
        final CollectionReference<Map<String, Object?>> withSpecials = coll
            .doc(r'so!@#$%^&*()_+special')
            .collection(r'so!@#$%^&*()_+special');
        await withSpecials.add(foo(1));
        await withSpecials.add(foo(2));
        verifyResults(
          await withSpecials.orderBy('foo').get(),
          <Map<String, Object?>>[foo(1), foo(2)],
        );
      },
    );
  }, skip: skip);

  group('equality', () {
    final FirestoreDataConverter<Map<String, Object?>> identityConverter =
        FirestoreDataConverter<Map<String, Object?>>.from(
          fromFirestore:
              (QueryDocumentSnapshot<Map<String, Object?>> snapshot) =>
                  snapshot.data,
          toFirestore: (Map<String, Object?> data, SetOptions? options) => data,
        );

    test('for collection references', () {
      final Firestore db = Firestore.instanceFor(app: newLiteTestApp());
      addTearDown(db.terminate);
      final CollectionReference<Map<String, Object?>> coll1a = db.collection(
        'a',
      );
      expect(coll1a, db.doc('a/b').parent);
      expect(coll1a.hashCode, db.doc('a/b').parent.hashCode);
      expect(coll1a, isNot(db.collection('c')));
      expect(
        coll1a,
        isNot(db.collection('a').withConverter(identityConverter)),
      );
      expect(coll1a, isNot(db.doc('a/b')));
    });

    test('for document references', () {
      final Firestore db = Firestore.instanceFor(app: newLiteTestApp());
      addTearDown(db.terminate);
      final DocumentReference<Map<String, Object?>> doc1a = db.doc('a/b');
      expect(doc1a, db.collection('a').doc('b'));
      expect(doc1a.hashCode, db.collection('a').doc('b').hashCode);
      expect(doc1a, isNot(db.doc('a/c')));
      expect(doc1a, isNot(db.doc('a/b').withConverter(identityConverter)));
      expect(doc1a, isNot(db.collection('a')));
    });

    test('for queries', () {
      final Firestore db = Firestore.instanceFor(app: newLiteTestApp());
      addTearDown(db.terminate);
      final CollectionReference<Map<String, Object?>> coll = db.collection(
        'coll',
      );
      final Query<Map<String, Object?>> query1a = coll.orderBy('foo');
      expect(query1a, coll.orderBy('foo', Direction.ascending));
      expect(query1a, isNot(coll.orderBy('foo', Direction.descending)));
      expect(query1a, isNot(coll.doc('a').collection('b').orderBy('foo')));
    });

    test('for query snapshots', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            <String, Object?>{'foo': 1},
            <String, Object?>{'foo': 2},
          ]);
      final QuerySnapshot<Map<String, Object?>> snap1a = await coll
          .limit(10)
          .get();
      final QuerySnapshot<Map<String, Object?>> snap1b = await coll
          .limit(10)
          .get();
      final QuerySnapshot<Map<String, Object?>> snap2 = await coll
          .limit(100)
          .get();
      expect(snap1a, snap1b);
      expect(snap1a.hashCode, snap1b.hashCode);
      expect(snap1a, isNot(snap2));

      // Re-run the query with an additional result.
      await coll.add(<String, Object?>{'foo': 3});
      expect(snap1a, isNot(await coll.limit(10).get()));
    }, skip: skip);

    test('for document snapshots', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            <String, Object?>{'foo': 1},
            <String, Object?>{'foo': 2},
          ]);
      final QuerySnapshot<Map<String, Object?>> snap1a = await coll.get();
      final QuerySnapshot<Map<String, Object?>> snap1b = await coll.get();
      expect(snap1a.docs[0], snap1b.docs[0]);
      expect(snap1a.docs[0].hashCode, snap1b.docs[0].hashCode);

      // Modify the document and obtain the snapshot again.
      await snap1a.docs[0].ref.update(<String, Object?>{'foo': 3});
      final QuerySnapshot<Map<String, Object?>> snap3 = await coll.get();
      expect(snap1a.docs[0], isNot(snap3.docs[0]));
    }, skip: skip);
  });

  group('withConverter() support', () {
    test('for DocumentReference.withConverter()', () async {
      final DocumentReference<Post> ref = (await newLiteTestDoc())
          .withConverter(postConverter);
      await ref.set(Post('post', 'author'));
      final Post? post = (await ref.get()).data;
      expect(post!.byline(), 'post, by author');
    });

    test(
      'for DocumentReference.withoutConverter() applies no converter',
      () async {
        final DocumentReference<Map<String, Object?>> ref =
            (await newLiteTestDoc())
                .withConverter(postConverter)
                .withoutConverter();
        await ref.set(<String, Object?>{'title': 'post', 'author': 'author'});
        expect((await ref.get()).data, <String, Object?>{
          'title': 'post',
          'author': 'author',
        });
      },
    );

    test('for CollectionReference.withConverter()', () async {
      final CollectionReference<Post> coll = newLiteTestCollection()
          .withConverter(postConverter);
      final DocumentReference<Post> ref = await coll.add(
        Post('post', 'author'),
      );
      final Post? post = (await ref.get()).data;
      expect(post!.byline(), 'post, by author');
    });

    test('for Query.withConverter()', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            <String, Object?>{'title': 'post', 'author': 'author'},
          ]);
      final QuerySnapshot<Post> result = await coll
          .where('title', isEqualTo: 'post')
          .withConverter(postConverter)
          .get();
      expect(result.docs[0].data, isA<Post>());
      expect(result.docs[0].data.byline(), 'post, by author');
    });

    test('for Query.withoutConverter() applies no converter', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            <String, Object?>{'title': 'post', 'author': 'author'},
          ]);
      final QuerySnapshot<Map<String, Object?>> result = await coll
          .where('title', isEqualTo: 'post')
          .withConverter(postConverter)
          .withoutConverter()
          .get();
      expect(result.docs[0].data, <String, Object?>{
        'title': 'post',
        'author': 'author',
      });
    });

    test('for Transaction.get() and Transaction.set()', () async {
      final DocumentReference<Post> ref = (await newLiteTestDoc())
          .withConverter(postConverter);
      await ref.set(Post('post', 'author'));
      await ref.firestore.runTransaction<void>((Transaction transaction) async {
        final Post post = (await transaction.get(ref)).data!;
        transaction.set(ref, Post('${post.title}!', post.author));
      });
      expect((await ref.get()).data!.byline(), 'post!, by author');
    });

    test(
      'keeps the converter when calling parent() with a DocumentReference',
      () {
        final Firestore db = newLiteTestFirestore();
        final DocumentReference<Post> doc = db
            .doc('root/doc')
            .withConverter(postConverter);
        expect(doc.parent, db.collection('root').withConverter(postConverter));
      },
    );

    test(
      'drops the converter when calling parent() with a CollectionReference',
      () {
        final Firestore db = newLiteTestFirestore();
        final CollectionReference<Post> coll = db
            .collection('root/doc/parent')
            .withConverter(postConverter);
        expect(coll.parent, db.doc('root/doc'));
      },
    );

    test('checks converter when comparing with isEqual()', () {
      final Firestore db = newLiteTestFirestore();
      final FirestoreDataConverter<Post>
      postConverter2 = FirestoreDataConverter<Post>.from(
        fromFirestore: (QueryDocumentSnapshot<Map<String, Object?>> snapshot) =>
            Post('', ''),
        toFirestore: (Post post, SetOptions? options) => <String, Object?>{},
      );
      expect(
        db.collection('users/user1/posts').withConverter(postConverter),
        isNot(db.collection('users/user1/posts').withConverter(postConverter2)),
      );
      expect(
        db.doc('some/doc').withConverter(postConverter),
        isNot(db.doc('some/doc').withConverter(postConverter2)),
      );
    });

    test('supports primitive types with valid converter', () async {
      final FirestoreDataConverter<int> primitiveConverter =
          FirestoreDataConverter<int>.from(
            fromFirestore:
                (QueryDocumentSnapshot<Map<String, Object?>> snapshot) =>
                    snapshot.data['value']! as int,
            toFirestore: (int value, SetOptions? options) => <String, Object?>{
              'value': value,
            },
          );
      final FirestoreDataConverter<List<int>> arrayConverter =
          FirestoreDataConverter<List<int>>.from(
            fromFirestore:
                (QueryDocumentSnapshot<Map<String, Object?>> snapshot) =>
                    (snapshot.data['values']! as List<Object?>).cast<int>(),
            toFirestore: (List<int> value, SetOptions? options) =>
                <String, Object?>{'values': value},
          );
      final CollectionReference<Map<String, Object?>> coll =
          newLiteTestCollection();
      final DocumentReference<int> ref = coll
          .doc('number')
          .withConverter(primitiveConverter);
      await ref.set(3);
      expect((await ref.get()).data, 3);

      final DocumentReference<List<int>> ref2 = coll
          .doc('array')
          .withConverter(arrayConverter);
      await ref2.set(<int>[1, 2, 3]);
      expect((await ref2.get()).data, <int>[1, 2, 3]);
    });
  }, skip: skip);

  final List<Map<String, Object?>> threeBooks = <Map<String, Object?>>[
    <String, Object?>{'author': 'authorA', 'title': 'titleA'},
    <String, Object?>{'author': 'authorA', 'title': 'titleB'},
    <String, Object?>{'author': 'authorB', 'title': 'titleC'},
  ];

  group('Count queries', () {
    test('AggregateQuerySnapshot inherits the original query', () async {
      final AggregateQuery query = newLiteTestCollection().count();
      expect((await query.get()).query, same(query));
    });

    for (final String documentPath in <String>[
      r'so!@#$%^&*()_+special/sub',
      r'b1/so!@#$%^&*()_+special',
    ]) {
      test('can run count query getCount with special chars in the document '
          'path: $documentPath', () async {
        final CollectionReference<Map<String, Object?>> coll =
            newLiteTestCollection();
        final List<String> segments = documentPath.split('/');
        final CollectionReference<Map<String, Object?>> sub = coll
            .doc(segments[0])
            .collection(segments[1]);
        await sub.add(<String, Object?>{'foo': 'bar'});
        await sub.add(<String, Object?>{'foo': 'baz'});
        expect((await sub.count().get()).getCount(), 2);
      });
    }

    test('run count query on empty collection', () async {
      expect((await newLiteTestCollection().count().get()).getCount(), 0);
    });

    test('run count query on collection with 3 docs', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(threeBooks);
      final AggregateQuerySnapshot snapshot = await coll.count().get();
      expect(snapshot.getCount(), 3);
      expect(snapshot.data(), <String, Object?>{'count': 3});
    });

    test('run count query fails on invalid collection reference', () async {
      final Firestore db = newLiteTestFirestore();
      await expectLater(
        db.collection('__badpath__').count().get(),
        throwsA(isA<FirestoreError>()),
      );
    });

    test('count query supports filter', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(threeBooks);
      expect(
        (await coll.where('author', isEqualTo: 'authorA').count().get())
            .getCount(),
        2,
      );
    });

    test('count query supports filter and a small limit size', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(threeBooks);
      expect(
        (await coll
                .where('author', isEqualTo: 'authorA')
                .limit(1)
                .count()
                .get())
            .getCount(),
        1,
      );
    });

    test('count query supports filter and a large limit size', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(threeBooks);
      expect(
        (await coll
                .where('author', isEqualTo: 'authorA')
                .limit(3)
                .count()
                .get())
            .getCount(),
        2,
      );
    });

    final List<Map<String, Object?>> ids = <Map<String, Object?>>[
      <String, Object?>{'id': 3},
      <String, Object?>{'id': 1},
      <String, Object?>{'id': 2},
      <String, Object?>{'id': 4},
      <String, Object?>{'other': 5},
    ];

    test('count query supports order by', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(ids);
      expect((await coll.orderBy('id').count().get()).getCount(), 4);
    });

    test('count query supports order by and startAt', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(ids);
      expect(
        (await coll.orderBy('id').startAt(<Object?>[2]).count().get())
            .getCount(),
        3,
      );
    });

    test('count query supports order by and startAfter', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(ids);
      expect(
        (await coll.orderBy('id').startAfter(<Object?>[2]).count().get())
            .getCount(),
        2,
      );
    });

    test('count query supports order by and endAt', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(ids);
      expect(
        (await coll
                .orderBy('id')
                .startAt(<Object?>[1])
                .endAt(<Object?>[2])
                .count()
                .get())
            .getCount(),
        2,
      );
    });

    test('count query supports order by and endBefore', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(ids);
      expect(
        (await coll
                .orderBy('id')
                .startAt(<Object?>[1])
                .endBefore(<Object?>[2])
                .count()
                .get())
            .getCount(),
        1,
      );
    });

    test("count query doesn't use converter", () async {
      final FirestoreDataConverter<Object> throwingConverter =
          FirestoreDataConverter<Object>.from(
            fromFirestore:
                (QueryDocumentSnapshot<Map<String, Object?>> snapshot) =>
                    throw StateError('should never be called'),
            toFirestore: (Object value, SetOptions? options) =>
                throw StateError('should never be called'),
          );
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(threeBooks);
      expect(
        (await coll
                .where('author', isEqualTo: 'authorA')
                .withConverter(throwingConverter)
                .count()
                .get())
            .getCount(),
        2,
      );
    });

    test('count query supports collection groups', () async {
      final Firestore db = newLiteTestFirestore();
      final String group = db.collection('countTest').doc().id;
      final WriteBatch batch = db.batch();
      for (final String path in <String>[
        '$group/cg-doc1',
        'abc/123/$group/cg-doc2',
        'zzz$group/cg-doc3',
        'abc/123/zzz$group/cg-doc4',
        'abc/123/zzz/$group',
      ]) {
        batch.set(db.doc(path), <String, Object?>{'x': 1});
      }
      await batch.commit();
      expect((await db.collectionGroup(group).count().get()).getCount(), 2);
    });

    test('aggregateQuerySnapshotEqual on same queries be truthy', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(threeBooks);
      final AggregateQuery query1 = coll
          .where('author', isEqualTo: 'authorA')
          .count();
      final AggregateQuery query2 = coll
          .where('author', isEqualTo: 'authorA')
          .count();
      final AggregateQuerySnapshot snapshot1A = await query1.get();
      expect(snapshot1A, await query1.get());
      expect(snapshot1A, await query2.get());
    });

    test('aggregateQuerySnapshotEqual on same queries with different documents '
        'size be falsy', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(threeBooks);
      final AggregateQuery query1 = coll
          .where('author', isEqualTo: 'authorA')
          .count();
      final AggregateQuerySnapshot snapshot1A = await query1.get();
      await coll.add(<String, Object?>{'author': 'authorA', 'title': 'titleD'});
      expect(snapshot1A, isNot(await query1.get()));
      expect(
        snapshot1A,
        isNot(await coll.where('author', isEqualTo: 'authorA').count().get()),
      );
    });

    test('aggregateQuerySnapshotEqual on different queries be falsy', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            ...threeBooks,
            <String, Object?>{'author': 'authorB', 'title': 'titleD'},
          ]);
      expect(
        await coll.where('author', isEqualTo: 'authorA').count().get(),
        isNot(await coll.where('author', isEqualTo: 'authorB').count().get()),
      );
    });

    test('count query fails on a terminated Firestore', () async {
      final CollectionReference<Map<String, Object?>> coll =
          newLiteTestCollection();
      await coll.firestore.terminate();
      await expectLater(coll.count().get(), throwsTerminated);
    });

    test('terminate Firestore not effect count query in flight', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(threeBooks);
      final Future<AggregateQuerySnapshot> future = coll.count().get();
      await coll.firestore.terminate();
      expect((await future).getCount(), 3);
    });
  }, skip: skip);

  group('Aggregate queries', () {
    test('AggregateQuerySnapshot inherits the original query', () async {
      final AggregateQuery query = newLiteTestCollection().aggregateWithAliases(
        <String, AggregateField>{'count': AggregateField.count()},
      );
      expect((await query.get()).query, same(query));
    });

    test('run aggregate query on empty collection', () async {
      final AggregateQuerySnapshot snapshot = await newLiteTestCollection()
          .aggregateWithAliases(<String, AggregateField>{
            'myCount': AggregateField.count(),
          })
          .get();
      expect(snapshot.data(), <String, Object?>{'myCount': 0});
    });

    test('run aggregate query on collection with 3 docs', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(threeBooks);
      final AggregateQuerySnapshot snapshot = await coll.aggregateWithAliases(
        <String, AggregateField>{'myCount': AggregateField.count()},
      ).get();
      expect(snapshot.data(), <String, Object?>{'myCount': 3});
    });

    test('run aggregate query with duplicate aggregates', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(threeBooks);
      final AggregateQuerySnapshot snapshot = await coll.aggregateWithAliases(
        <String, AggregateField>{
          'myCount': AggregateField.count(),
          'yourCount': AggregateField.count(),
        },
      ).get();
      expect(snapshot.data(), <String, Object?>{'myCount': 3, 'yourCount': 3});
    });

    test('run aggregate query fails on invalid collection reference', () async {
      final Firestore db = newLiteTestFirestore();
      await expectLater(
        db.collection('__badpath__').aggregateWithAliases(
          <String, AggregateField>{'myCount': AggregateField.count()},
        ).get(),
        throwsA(isA<FirestoreError>()),
      );
    });

    test('aggregate query supports filter, order and cursors', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            <String, Object?>{'id': 3, 'pages': 30},
            <String, Object?>{'id': 1, 'pages': 10},
            <String, Object?>{'id': 2, 'pages': 20},
            <String, Object?>{'id': 4, 'pages': 40},
            <String, Object?>{'other': 5, 'pages': 50},
          ]);
      Future<Map<String, Object?>> run(Query<Object?> query) async {
        return (await query.aggregateWithAliases(<String, AggregateField>{
          'n': AggregateField.count(),
          'pages': AggregateField.sum('pages'),
        }).get()).data();
      }

      expect(await run(coll.where('id', isGreaterThan: 2)), <String, Object?>{
        'n': 2,
        'pages': 70,
      });
      expect(
        await run(coll.where('id', isGreaterThan: 0).limit(1)),
        containsPair('n', 1),
      );
      expect(await run(coll.orderBy('id')), <String, Object?>{
        'n': 4,
        'pages': 100,
      });
      expect(
        await run(coll.orderBy('id').startAt(<Object?>[2])),
        <String, Object?>{'n': 3, 'pages': 90},
      );
      expect(
        await run(coll.orderBy('id').startAfter(<Object?>[2])),
        <String, Object?>{'n': 2, 'pages': 70},
      );
      expect(
        await run(coll.orderBy('id').startAt(<Object?>[1]).endAt(<Object?>[2])),
        <String, Object?>{'n': 2, 'pages': 30},
      );
      expect(
        await run(
          coll.orderBy('id').startAt(<Object?>[1]).endBefore(<Object?>[2]),
        ),
        <String, Object?>{'n': 1, 'pages': 10},
      );
    });

    test("aggregate query doesn't use converter", () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(threeBooks);
      final FirestoreDataConverter<Object> throwingConverter =
          FirestoreDataConverter<Object>.from(
            fromFirestore:
                (QueryDocumentSnapshot<Map<String, Object?>> snapshot) =>
                    throw StateError('should never be called'),
            toFirestore: (Object value, SetOptions? options) =>
                throw StateError('should never be called'),
          );
      final AggregateQuerySnapshot snapshot = await coll
          .where('author', isEqualTo: 'authorA')
          .withConverter(throwingConverter)
          .aggregateWithAliases(<String, AggregateField>{
            'myCount': AggregateField.count(),
          })
          .get();
      expect(snapshot.data(), <String, Object?>{'myCount': 2});
    });

    test('aggregate query supports collection groups', () async {
      final Firestore db = newLiteTestFirestore();
      final String group = db.collection('aggregateTest').doc().id;
      final WriteBatch batch = db.batch();
      for (final String path in <String>[
        '$group/cg-doc1',
        'abc/123/$group/cg-doc2',
        'zzz$group/cg-doc3',
        'abc/123/zzz$group/cg-doc4',
        'abc/123/zzz/$group',
      ]) {
        batch.set(db.doc(path), <String, Object?>{'x': 2});
      }
      await batch.commit();
      final AggregateQuerySnapshot snapshot = await db
          .collectionGroup(group)
          .aggregateWithAliases(<String, AggregateField>{
            'myCount': AggregateField.count(),
            'total': AggregateField.sum('x'),
          })
          .get();
      expect(snapshot.data(), <String, Object?>{'myCount': 2, 'total': 4});
    });

    test('aggregateQuerySnapshotEqual on same queries be truthy', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(threeBooks);
      AggregateQuery myCount(Query<Object?> query) =>
          query.aggregateWithAliases(<String, AggregateField>{
            'myCount': AggregateField.count(),
          });
      final Query<Map<String, Object?>> query1 = coll.where(
        'author',
        isEqualTo: 'authorA',
      );
      final Query<Map<String, Object?>> query2 = coll.where(
        'author',
        isEqualTo: 'authorA',
      );
      final AggregateQuerySnapshot snapshot1A = await myCount(query1).get();
      expect(snapshot1A, await myCount(query1).get());
      expect(snapshot1A, await myCount(query2).get());
    });

    test('aggregateQuerySnapshotEqual on same queries with different documents '
        'size be falsy', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(threeBooks);
      AggregateQuery myCount(Query<Object?> query) =>
          query.aggregateWithAliases(<String, AggregateField>{
            'myCount': AggregateField.count(),
          });
      final Query<Map<String, Object?>> query1 = coll.where(
        'author',
        isEqualTo: 'authorA',
      );
      final AggregateQuerySnapshot snapshot1A = await myCount(query1).get();
      await coll.add(<String, Object?>{'author': 'authorA', 'title': 'titleD'});
      final Query<Map<String, Object?>> query2 = coll.where(
        'author',
        isEqualTo: 'authorA',
      );
      expect(snapshot1A, isNot(await myCount(query1).get()));
      expect(snapshot1A, isNot(await myCount(query2).get()));
    });

    test('aggregateQuerySnapshotEqual on different queries be falsy', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(<Map<String, Object?>>[
            ...threeBooks,
            <String, Object?>{'author': 'authorB', 'title': 'titleD'},
          ]);
      AggregateQuery myCount(Query<Object?> query) =>
          query.aggregateWithAliases(<String, AggregateField>{
            'myCount': AggregateField.count(),
          });
      expect(
        await myCount(coll.where('author', isEqualTo: 'authorA')).get(),
        isNot(await myCount(coll.where('author', isEqualTo: 'authorB')).get()),
      );
    });

    test('aggregate query fails on a terminated Firestore', () async {
      final CollectionReference<Map<String, Object?>> coll =
          newLiteTestCollection();
      await coll.firestore.terminate();
      await expectLater(
        coll.aggregateWithAliases(<String, AggregateField>{
          'myCount': AggregateField.count(),
        }).get(),
        throwsTerminated,
      );
    });

    test('terminate Firestore not effect aggregate query in flight', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(threeBooks);
      final Future<AggregateQuerySnapshot> future = coll.aggregateWithAliases(
        <String, AggregateField>{'myCount': AggregateField.count()},
      ).get();
      await coll.firestore.terminate();
      expect((await future).data(), <String, Object?>{'myCount': 3});
    });
  }, skip: skip);

  group('Aggregate queries - sum / average', () {
    final List<Map<String, Object?>> rated = <Map<String, Object?>>[
      <String, Object?>{'author': 'authorA', 'title': 'titleA', 'rating': 1},
      <String, Object?>{'author': 'authorA', 'title': 'titleB', 'rating': 5},
      <String, Object?>{'author': 'authorB', 'title': 'titleC', 'rating': 4},
      <String, Object?>{'author': 'authorB', 'title': 'titleD', 'rating': 3},
    ];
    final List<Map<String, Object?>> paged = <Map<String, Object?>>[
      <String, Object?>{'author': 'authorA', 'title': 'titleA', 'pages': 100},
      <String, Object?>{'author': 'authorB', 'title': 'titleB', 'pages': 50},
    ];

    test(
      'aggregateQuerySnapshotEqual on different aggregations to be falsy',
      () async {
        final CollectionReference<Map<String, Object?>> coll =
            await newLiteTestCollectionWith(rated);
        expect(
          await coll.aggregateWithAliases(<String, AggregateField>{
            'sum': AggregateField.sum('rating'),
          }).get(),
          isNot(
            await coll.aggregateWithAliases(<String, AggregateField>{
              'avg': AggregateField.average('rating'),
            }).get(),
          ),
        );
      },
    );

    test('aggregateQuerySnapshotEqual on same aggregations with different '
        'aliases to be falsy', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(rated);
      expect(
        await coll.aggregateWithAliases(<String, AggregateField>{
          'foo': AggregateField.average('rating'),
        }).get(),
        isNot(
          await coll.aggregateWithAliases(<String, AggregateField>{
            'bar': AggregateField.average('rating'),
          }).get(),
        ),
      );
    });

    test('aggregateQuerySnapshotEqual on same aggregations with same aliases '
        'to be truthy', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(rated);
      expect(
        await coll.aggregateWithAliases(<String, AggregateField>{
          'foo': AggregateField.average('rating'),
          'bar': AggregateField.sum('rating'),
        }).get(),
        await coll.aggregateWithAliases(<String, AggregateField>{
          'bar': AggregateField.sum('rating'),
          'foo': AggregateField.average('rating'),
        }).get(),
      );
    });

    test('can run sum query getAggregationFromServer', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(paged);
      final AggregateQuerySnapshot snapshot = await coll.aggregateWithAliases(
        <String, AggregateField>{'totalPages': AggregateField.sum('pages')},
      ).get();
      expect(snapshot.data(), <String, Object?>{'totalPages': 150});
    });

    test('can run average query getAggregationFromServer', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(paged);
      final AggregateQuerySnapshot snapshot = await coll.aggregateWithAliases(
        <String, AggregateField>{
          'averagePages': AggregateField.average('pages'),
        },
      ).get();
      expect(snapshot.data(), <String, Object?>{'averagePages': 75});
    });

    test(
      'can get multiple aggregations using getAggregationFromServer',
      () async {
        final CollectionReference<Map<String, Object?>> coll =
            await newLiteTestCollectionWith(paged);
        final AggregateQuerySnapshot snapshot =
            await coll.aggregateWithAliases(<String, AggregateField>{
              'totalPages': AggregateField.sum('pages'),
              'averagePages': AggregateField.average('pages'),
              'count': AggregateField.count(),
            }).get();
        expect(snapshot.data(), <String, Object?>{
          'totalPages': 150,
          'averagePages': 75,
          'count': 2,
        });
      },
    );

    test('can get aggregations without aliases', () async {
      final CollectionReference<Map<String, Object?>> coll =
          await newLiteTestCollectionWith(paged);
      final AggregateQuerySnapshot snapshot =
          await coll.aggregate(<AggregateField>[
            AggregateField.sum('pages'),
            AggregateField.average('pages'),
            AggregateField.count(),
          ]).get();
      expect(snapshot.get(AggregateField.sum('pages')), 150);
      expect(snapshot.getDouble(AggregateField.average('pages')), 75.0);
      expect(snapshot.getCount(), 2);
      expect(
        () => snapshot.get(AggregateField.sum('other')),
        throwsArgumentError,
      );
    });

    test(
      'performs aggregations on documents with all aggregated fields using '
      'getAggregationFromServer',
      skip: TestBackend().skipOnEnterprise(
        'an aggregation counts every document, not only those that have '
        'all the aggregated fields',
      ),
      () async {
        final CollectionReference<Map<String, Object?>> coll =
            await newLiteTestCollectionWith(<Map<String, Object?>>[
              <String, Object?>{
                'author': 'authorA',
                'title': 'titleA',
                'pages': 100,
                'year': 1980,
              },
              <String, Object?>{
                'author': 'authorB',
                'title': 'titleB',
                'pages': 50,
                'year': 2020,
              },
              <String, Object?>{
                'author': 'authorC',
                'title': 'titleC',
                'pages': 150,
                'year': 2021,
              },
              <String, Object?>{
                'author': 'authorD',
                'title': 'titleD',
                'pages': 50,
              },
            ]);
        final AggregateQuerySnapshot snapshot =
            await coll.aggregateWithAliases(<String, AggregateField>{
              'totalPages': AggregateField.sum('pages'),
              'averagePages': AggregateField.average('pages'),
              'averageYear': AggregateField.average('year'),
              'count': AggregateField.count(),
            }).get();
        expect(snapshot.data(), <String, Object?>{
          'totalPages': 300,
          'averagePages': 100,
          'averageYear': 2007,
          'count': 3,
        });
      },
    );
  }, skip: skip);

  group('Vectors', () {
    test('can be read and written using the lite SDK', () async {
      final CollectionReference<Map<String, Object?>> coll =
          newLiteTestCollection();
      final DocumentReference<Map<String, Object?>> ref = await coll.add(
        <String, Object?>{
          'vector0': FieldValue.vector(<double>[0.0]),
          'vector1': FieldValue.vector(<double>[1, 2, 3.99]),
        },
      );
      await ref.set(<String, Object?>{
        'vector0': FieldValue.vector(<double>[0.0]),
        'vector1': FieldValue.vector(<double>[1, 2, 3.99]),
        'vector2': FieldValue.vector(<double>[0, 0, 0]),
      });
      await ref.update(<String, Object?>{
        'vector3': FieldValue.vector(<double>[-1, -200, -999]),
      });

      final DocumentSnapshot<Map<String, Object?>> snap = await ref.get();
      expect(snap.get('vector0'), FieldValue.vector(<double>[0.0]));
      expect(snap.get('vector1'), FieldValue.vector(<double>[1, 2, 3.99]));
      expect(snap.get('vector2'), FieldValue.vector(<double>[0, 0, 0]));
      expect(snap.get('vector3'), FieldValue.vector(<double>[-1, -200, -999]));
    });
  }, skip: skip);

  group('mockUserToken', () {
    test('requests with a mock user token succeed', () async {
      final Firestore db = newLiteTestFirestore(
        mockUserToken: <String, Object?>{'sub': 'alice'},
      );
      final DocumentReference<Map<String, Object?>> ref = newLiteTestCollection(
        db,
      ).doc();
      await ref.set(<String, Object?>{'a': 1});
      expect((await ref.get()).data, <String, Object?>{'a': 1});
    });

    test('a malformed token reaches the emulator', () async {
      // The emulator decodes the token: one that is not a JWT is rejected,
      // which shows that the header is sent.
      final Firestore db = newLiteTestFirestore(mockUserToken: 'not-a-jwt');
      await expectLater(
        newLiteTestCollection(db).doc().set(<String, Object?>{'a': 1}),
        throwsA(isA<FirestoreError>()),
      );
    });
  }, skip: skip);
}

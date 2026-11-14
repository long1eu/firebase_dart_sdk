// The toString() of every public class that has one, pinned. Each is one
// line. Where the Android SDK has a toString(), its format is used; the
// classes that print a document print it as Android does, and the ones that
// hold many documents print their number.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/lite.dart' as lite;
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../util/test_hygiene.dart';
import 'clear_persistence_test.dart' show newApp, offlineSettings;

void main() {
  checkTestsLeaveNothingBehind();

  void expectString(Object? object, String expected) {
    expect(object.toString(), expected);
    expect(object.toString(), isNot(contains('\n')));
  }

  group('values', () {
    test('Timestamp', () {
      expectString(
        const Timestamp(1, 2),
        'Timestamp(seconds=1, nanoseconds=2)',
      );
    });

    test('GeoPoint', () {
      expectString(
        const GeoPoint(1.5, -2),
        'GeoPoint { latitude=1.5, longitude=-2.0 }',
      );
    });

    test('Blob', () {
      expectString(
        Blob(Uint8List.fromList(<int>[1, 2, 255])),
        'Blob { bytes=0102ff, subtype=0 }',
      );
      expectString(
        Blob.bsonBinary(128, Uint8List.fromList(<int>[1, 2])),
        'Blob { bytes=0102, subtype=128 }',
      );
    });

    test('VectorValue', () {
      expectString(VectorValue(<double>[1, 2.5]), 'VectorValue([1.0, 2.5])');
    });

    test('BSON types', () {
      expectString(
        BsonObjectId('507f191e810c19729de860ea'),
        "BsonObjectId{value='507f191e810c19729de860ea'}",
      );
      expectString(
        BsonTimestamp(1, 2),
        'BsonTimestamp{seconds=1, increment=2}',
      );
      expectString(Decimal128Value('1.2e3'), 'Decimal128Value{value=1.2e3}');
      expectString(Int32Value(7), 'Int32Value{value=7}');
      expectString(
        const RegexValue('^a', 'i'),
        "RegexValue{pattern='^a', options='i'}",
      );
      expectString(MinKey.instance, 'MinKey');
      expectString(MaxKey.instance, 'MaxKey');
    });

    test('FieldPath', () {
      expectString(FieldPath.of(<String>['a', 'b.c']), 'a.`b.c`');
      expectString(FieldPath.documentId(), '__name__');
    });

    test('AggregateField', () {
      expectString(AggregateField.count(), 'count()');
      expectString(AggregateField.sum('n'), 'sum(n)');
      expectString(AggregateField.average('n'), 'average(n)');
    });
  });

  group('errors', () {
    test('FirestoreErrorCode is the name of the code', () {
      expect(
        FirestoreErrorCode.values
            .map((FirestoreErrorCode c) => c.toString())
            .toList(),
        <String>[
          'ok',
          'cancelled',
          'unknown',
          'invalidArgument',
          'deadlineExceeded',
          'notFound',
          'alreadyExists',
          'permissionDenied',
          'resourceExhausted',
          'failedPrecondition',
          'aborted',
          'outOfRange',
          'unimplemented',
          'internal',
          'unavailable',
          'dataLoss',
          'unauthenticated',
        ],
      );
      // Each one is the name of its constant.
      expectString(FirestoreErrorCode.cancelled, 'cancelled');
      expectString(FirestoreErrorCode.resourceExhausted, 'resourceExhausted');
    });

    test('FirestoreError', () {
      expectString(
        FirestoreError('Missing', FirestoreErrorCode.permissionDenied),
        'FirestoreError: [code=permissionDenied]: Missing',
      );
    });

    test('TransientDatabaseException', () {
      expectString(
        TransientDatabaseException('busy'),
        'TransientDatabaseException: busy',
      );
    });
  });

  group('settings and options', () {
    test('FirestoreSettings', () {
      expectString(
        FirestoreSettings(),
        'FirestoreSettings{host=firestore.googleapis.com, port=443, '
        'sslEnabled=true, persistenceEnabled=true, cacheSizeBytes=104857600, '
        'grpcFlowControlWindow=262144, cacheSettings=null, '
        'experimentalForceLongPolling=false, '
        'experimentalAutoDetectLongPolling=true, '
        'experimentalLongPollingOptions='
        'ExperimentalLongPollingOptions{timeoutSeconds=null}, '
        'mockUserToken=null}',
      );
    });

    test('ExperimentalLongPollingOptions', () {
      expectString(
        const ExperimentalLongPollingOptions(timeoutSeconds: 25),
        'ExperimentalLongPollingOptions{timeoutSeconds=25}',
      );
    });

    test('FirestoreSettings does not print the mock user token', () {
      final String text = FirestoreSettings()
          .withEmulator(
            '127.0.0.1',
            8080,
            mockUserToken: <String, Object?>{'sub': 'secret-user'},
          )
          .toString();
      expect(text, contains('host=127.0.0.1, port=8080, sslEnabled=false'));
      expect(text, endsWith('mockUserToken=<set>}'));
      expect(text, isNot(contains('secret-user')));
      expect(text, isNot(contains('\n')));
    });

    test('cache settings', () {
      expectString(
        PersistentCacheSettings(),
        'PersistentCacheSettings{sizeBytes=104857600}',
      );
      expectString(
        MemoryCacheSettings(),
        'MemoryCacheSettings{gcSettings=MemoryEagerGcSettings{}}',
      );
      expectString(MemoryEagerGcSettings(), 'MemoryEagerGcSettings{}');
      expectString(
        MemoryLruGcSettings(),
        'MemoryLruGcSettings{sizeBytes=104857600}',
      );
    });

    test('SnapshotMetadata', () {
      expectString(
        const SnapshotMetadata(true, false),
        'SnapshotMetadata{hasPendingWrites=true, isFromCache=false}',
      );
    });

    test('SnapshotListenOptions', () {
      expectString(
        const SnapshotListenOptions(),
        'SnapshotListenOptions{metadataChanges=MetadataChanges.exclude, '
        'source=ListenSource.defaultSource}',
      );
    });

    test('TransactionOptions', () {
      expectString(
        TransactionOptions(),
        'TransactionOptions{maxAttempts=5, readOnly=false}',
      );
      expectString(
        TransactionOptions(readOnly: true, readTime: const Timestamp(5, 0)),
        'TransactionOptions{maxAttempts=5, readOnly=true, '
        'readTime=Timestamp(seconds=5, nanoseconds=0)}',
      );
    });

    test('LoadBundleTaskProgress', () {
      expectString(
        LoadBundleTaskProgress.initial,
        'LoadBundleTaskProgress{documentsLoaded: 0, totalDocuments: 0, '
        'bytesLoaded: 0, totalBytes: 0, '
        'taskState: LoadBundleTaskState.success, exception: null}',
      );
    });
  });

  group('references and snapshots', () {
    late Firestore db;
    late CollectionReference<Map<String, Object?>> rooms;

    setUp(() {
      final FirebaseApp app = newApp('to-string-${const Uuid().v4()}');
      addTearDown(app.delete);
      db = Firestore.instanceFor(app: app, settings: offlineSettings);
      addTearDown(db.terminate);
      rooms = db.collection('rooms');
    });

    test('CollectionReference and Query', () {
      expectString(rooms, 'CollectionReference(path: rooms)');
      expectString(
        rooms.where('n', isGreaterThan: 1).orderBy('n').limit(2),
        'Query(target=Query(rooms where n > 1 order by n, __name__);'
        'limitType=LIMIT_TO_FIRST)',
      );
      expectString(
        rooms.where('tags', arrayContainsAny: <Object?>['a']).limitToLast(2),
        'Query(target=Query(rooms where tags array-contains-any [a] order by '
        '-__name__);limitType=LIMIT_TO_LAST)',
      );
    });

    test('DocumentSnapshot, QuerySnapshot and DocumentChange', () async {
      // ignore: unawaited_futures, the write stays pending: nothing listens on the port.
      rooms.doc('eros').set(<String, Object?>{
        'n': 5,
        'at': const Timestamp(1, 2000),
        'owner': db.doc('users/a'),
      });
      const String metadata =
          'SnapshotMetadata{hasPendingWrites=true, isFromCache=true}';
      const String document =
          'DocumentSnapshot{key=rooms/eros, metadata=$metadata, '
          'doc=Document{key=rooms/eros, '
          'version=SnapshotVersion(seconds=0, nanos=0), '
          'documentState=DocumentState.localMutations, '
          'value=ObjectValue{internalValue='
          '{at:time(1,2000),n:5,owner:users/a}}}}';

      expectString(await rooms.doc('eros').get(Source.cache), document);

      final QuerySnapshot<Map<String, Object?>> snapshot = await rooms
          .where('n', isGreaterThan: 1)
          .get(Source.cache);
      // The number of documents, not the documents.
      expectString(
        snapshot,
        'QuerySnapshot(query: Query(target=Query(rooms where n > 1 order by '
        'n, __name__);limitType=LIMIT_TO_FIRST), metadata: $metadata, '
        'size: 1)',
      );
      expectString(snapshot.docs.single, document);
      expectString(
        snapshot.docChanges.single,
        'DocumentChange(type: added, document: rooms/eros, oldIndex: -1, '
        'newIndex: 0)',
      );
    });
  });

  group('pipelines', () {
    test('expressions', () {
      expectString(Field.of('a.b'), 'Field(a.b)');
      expectString(
        Constant(const Timestamp(1, 2)),
        'Constant(Timestamp(seconds=1, nanoseconds=2))',
      );
      expectString(
        Field.of('a').add(Constant(1)),
        'add(Field(a), Constant(1))',
      );
      expectString(
        Field.of('a').equal(Constant('x')),
        'equal(Field(a), Constant(x))',
      );
      expectString(Field.of('a').as('b'), 'Field(a) as b');
      expectString(Field.of('a').descending(), 'Field(a) descending');
      expectString(Field.of('a').sum(), 'sum(Field(a))');
      expectString(Field.of('a').sum().as('total'), 'sum(Field(a)) as total');
      expectString(
        const PipelineExplainOptions(),
        'PipelineExplainOptions(mode: null, outputFormat: null)',
      );
    });

    test('Pipeline', () {
      final FirebaseApp app = newApp('to-string-${const Uuid().v4()}');
      addTearDown(app.delete);
      final Firestore db = Firestore.instanceFor(
        app: app,
        settings: offlineSettings,
      );
      addTearDown(db.terminate);
      expectString(
        db
            .pipeline()
            .collection('rooms')
            .where(Field.of('a').equal(Constant(1)))
            .limit(3),
        'Pipeline(collection | where | limit)',
      );
    });
  });

  group('lite', () {
    test('Firestore, references, Query and FirestoreSettings', () {
      final FirebaseApp app = newApp('to-string-lite');
      addTearDown(app.delete);
      final lite.Firestore db = lite.Firestore.instanceFor(app: app);
      expectString(db, 'Firestore{app: to-string-lite, database: (default)}');
      expectString(db.collection('rooms'), 'CollectionReference{path: rooms}');
      expectString(db.doc('rooms/eros'), 'DocumentReference{path: rooms/eros}');
      expectString(
        db.collection('rooms').where('n', isGreaterThan: 1).limit(2),
        'Query{query: Query(target=Query(rooms where n > 1 order by n, '
        '__name__);limitType=LIMIT_TO_FIRST)}',
      );
      expectString(
        lite.FirestoreSettings(),
        'FirestoreSettings{host: firestore.googleapis.com, port: 443, '
        'sslEnabled: true, grpcFlowControlWindow: 262144}',
      );
    });
  });
}

// Firestore Lite against a fake transport: what each call of the public API
// sends, how the responses come back, and what never reaches the wire.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore_dart/lite.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/firestore.dart'
    show liteTransportOverride;
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;
import 'package:cloud_firestore_dart/src/proto/google/protobuf/index.dart'
    as protobuf;
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart';
import 'package:test/test.dart';

import 'fake_lite_transport.dart';

const String database = 'projects/lite-project/databases/(default)';
const String documents = '$database/documents';

int _apps = 0;

proto.Document document(
  String path,
  Map<String, int> fields, {
  int version = 5,
}) {
  return proto.Document()
    ..name = '$documents/$path'
    ..fields.addAll(<String, proto.Value>{
      for (final MapEntry<String, int> entry in fields.entries)
        entry.key: proto.Value()..integerValue = Int64(entry.value),
    })
    ..updateTime = (protobuf.Timestamp()..seconds = Int64(version));
}

void main() {
  late List<FakeLiteTransport> transports;
  late FirebaseApp app;

  FakeLiteTransport transport() => transports.single;

  Firestore newFirestore({FirestoreSettings? settings, String? databaseName}) {
    final Firestore firestore = databaseName == null
        ? Firestore.instanceFor(app: app, settings: settings)
        : Firestore.instanceFor(
            app: app,
            database: databaseName,
            settings: settings,
          );
    addTearDown(firestore.terminate);
    return firestore;
  }

  setUp(() {
    transports = <FakeLiteTransport>[];
    liteTransportOverride =
        (DatabaseInfo databaseInfo, ChannelOptionsProvider options) {
          final FakeLiteTransport transport = FakeLiteTransport(
            databaseInfo,
            options,
          );
          transports.add(transport);
          return transport;
        };
    addTearDown(() => liteTransportOverride = null);
    app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'key',
        applicationId: 'appId',
        projectId: 'lite-project',
      ),
      dependencies: null,
      name: 'lite-unit-${_apps++}',
    );
    addTearDown(app.delete);
  });

  group('instance', () {
    test('opens no transport until the first call', () async {
      final Firestore firestore = newFirestore();
      firestore.collection('coll').where('a', isEqualTo: 1).orderBy('a');
      firestore.batch().set(firestore.doc('coll/doc'), <String, Object?>{});
      expect(transports, isEmpty);

      await firestore.doc('coll/doc').get();
      expect(transports, hasLength(1));
      await firestore.doc('coll/other').get();
      expect(transports, hasLength(1), reason: 'one transport per instance');
    });

    test('talks to the host of the settings', () async {
      final Firestore firestore = newFirestore(
        settings: FirestoreSettings(
          host: 'example.test',
          port: 8443,
          sslEnabled: false,
        ),
      );
      await firestore.doc('coll/doc').get();
      expect(transport().databaseInfo.host, 'example.test');
      expect(transport().databaseInfo.port, 8443);
      expect(transport().databaseInfo.sslEnabled, isFalse);
    });

    test('defaults to the production service', () async {
      final Firestore firestore = newFirestore();
      expect(firestore.projectId, 'lite-project');
      expect(firestore.databaseId, '(default)');
      await firestore.doc('coll/doc').get();
      expect(transport().databaseInfo.host, 'firestore.googleapis.com');
      expect(transport().databaseInfo.port, 443);
      expect(transport().databaseInfo.sslEnabled, isTrue);
    });

    test('addresses a named database', () async {
      final Firestore firestore = newFirestore(databaseName: 'other');
      await firestore.doc('coll/doc').get();
      expect(
        transport()
            .requests<proto.BatchGetDocumentsRequest>('BatchGetDocuments')
            .single
            .database,
        'projects/lite-project/databases/other',
      );
    });

    test('sends the routing headers and no credentials without auth', () async {
      final Firestore firestore = newFirestore();
      await firestore.doc('coll/doc').get();
      final Map<String, String> headers = await transport().headers();
      expect(headers['x-goog-request-params'], database);
      expect(headers['google-cloud-resource-prefix'], database);
      expect(headers['x-goog-api-client'], contains('fire/'));
      expect(
        headers.keys.map((String key) => key.toLowerCase()),
        isNot(contains('authorization')),
      );
    });

    test('sends the mock user token of the emulator settings', () async {
      final Firestore firestore = newFirestore(
        settings: FirestoreSettings().withEmulator(
          '127.0.0.1',
          8080,
          mockUserToken: 'owner-token',
        ),
      );
      await firestore.doc('coll/doc').get();
      expect(transport().databaseInfo.host, '127.0.0.1');
      expect(transport().databaseInfo.sslEnabled, isFalse);
      final Map<String, String> headers = await transport().headers();
      expect(
        headers.entries
            .firstWhere(
              (MapEntry<String, String> entry) =>
                  entry.key.toLowerCase() == 'authorization',
            )
            .value,
        'Bearer owner-token',
      );
    });

    test('sends the Auth and App Check tokens of the app', () async {
      final _Auth auth = _Auth();
      final _AppCheck appCheck = _AppCheck();
      app
        ..authProvider = auth
        ..appCheckProvider = appCheck;
      final Firestore firestore = newFirestore();
      await firestore.doc('coll/doc').get();

      final Map<String, String> headers = await transport().headers();
      expect(headers['Authorization'], 'Bearer ${auth.token}');
      expect(headers['x-firebase-appcheck'], 'app-check-token');
      expect(auth.tokenChanges.hasListener, isTrue);
      expect(appCheck.changes.hasListener, isTrue);

      // A terminated instance no longer follows the token changes of the app.
      await firestore.terminate();
      expect(auth.tokenChanges.hasListener, isFalse);
      expect(appCheck.changes.hasListener, isFalse);
      await auth.tokenChanges.close();
      await appCheck.changes.close();
    });

    test(
      'terminate() shuts the transport down and rejects later calls',
      () async {
        final Firestore firestore = newFirestore();
        await firestore.doc('coll/doc').get();
        await firestore.terminate();
        expect(transport().isShutDown, isTrue);

        final Matcher throwsTerminated = throwsA(
          isA<FirestoreError>().having(
            (FirestoreError e) => e.code,
            'code',
            FirestoreErrorCode.failedPrecondition,
          ),
        );
        await expectLater(firestore.doc('coll/doc').get(), throwsTerminated);
        await expectLater(
          firestore.doc('coll/doc').set(<String, Object?>{}),
          throwsTerminated,
        );
        await expectLater(firestore.doc('coll/doc').delete(), throwsTerminated);
        await expectLater(firestore.collection('coll').get(), throwsTerminated);
        await expectLater(
          firestore.collection('coll').count().get(),
          throwsTerminated,
        );
        await expectLater(firestore.batch().commit(), throwsTerminated);
        await expectLater(
          firestore.runTransaction<void>((Transaction transaction) async {}),
          throwsTerminated,
        );
        expect(transport().calls, hasLength(1));
      },
    );

    test('terminate() lets the calls in flight finish first', () async {
      final Firestore firestore = newFirestore();
      final Completer<void> release = Completer<void>();
      await firestore.doc('coll/warmup').get();
      transport().handlers['BatchGetDocuments'] =
          (GeneratedMessage request) async {
            await release.future;
            return <GeneratedMessage>[
              proto.BatchGetDocumentsResponse()
                ..found = document('coll/doc', <String, int>{'a': 1}),
            ];
          };

      final Future<DocumentSnapshot<Map<String, Object?>>> inFlight = firestore
          .doc('coll/doc')
          .get();
      bool terminated = false;
      final Future<void> termination = firestore.terminate().then(
        (_) => terminated = true,
      );
      await pumpEventQueue();
      expect(terminated, isFalse);
      expect(transport().isShutDown, isFalse);

      release.complete();
      expect((await inFlight).data, <String, Object?>{'a': 1});
      await termination;
      expect(transport().isShutDown, isTrue);
    });

    test('terminate() before any call opens no transport', () async {
      final Firestore firestore = newFirestore();
      await firestore.terminate();
      expect(transports, isEmpty);
    });
  });

  group('settings', () {
    test('are compared by value', () {
      expect(FirestoreSettings(), FirestoreSettings());
      expect(FirestoreSettings().hashCode, FirestoreSettings().hashCode);
      expect(
        FirestoreSettings(host: 'a.test'),
        isNot(FirestoreSettings(host: 'b.test')),
      );
      expect(
        FirestoreSettings().withEmulator(
          'localhost',
          8080,
          mockUserToken: <String, Object?>{'sub': 'alice'},
        ),
        FirestoreSettings().withEmulator(
          'localhost',
          8080,
          mockUserToken: <String, Object?>{'sub': 'alice'},
        ),
      );
      expect(
        FirestoreSettings().withEmulator(
          'localhost',
          8080,
          mockUserToken: <String, Object?>{'sub': 'alice'},
        ),
        isNot(FirestoreSettings().withEmulator('localhost', 8080)),
      );
    });

    test('reject a host that is not a host and plain text to production', () {
      expect(
        () => FirestoreSettings(host: 'http://example.test'),
        throwsArgumentError,
      );
      expect(() => FirestoreSettings(sslEnabled: false), throwsArgumentError);
      expect(
        () => FirestoreSettings().withEmulator(
          FirestoreSettings.defaultHost,
          443,
        ),
        throwsArgumentError,
      );
    });

    test('reject a mock user token without a user id', () {
      expect(
        () => FirestoreSettings().withEmulator(
          'localhost',
          8080,
          mockUserToken: <String, Object?>{'email': 'a@example.com'},
        ),
        throwsArgumentError,
      );
      expect(
        () => FirestoreSettings().withEmulator(
          'localhost',
          8080,
          mockUserToken: 42,
        ),
        throwsArgumentError,
      );
    });
  });

  group('documents', () {
    test('get() asks for the document and decodes it', () async {
      final Firestore firestore = newFirestore();
      await firestore.doc('coll/warmup').get();
      transport().handlers['BatchGetDocuments'] = (GeneratedMessage request) =>
          <GeneratedMessage>[
            proto.BatchGetDocumentsResponse()
              ..found = (document('coll/doc', <String, int>{'a': 1})
                ..fields['ref'] = (proto.Value()
                  ..referenceValue = '$documents/other/target')),
          ];

      final DocumentSnapshot<Map<String, Object?>> snapshot = await firestore
          .doc('coll/doc')
          .get();
      expect(
        transport()
            .requests<proto.BatchGetDocumentsRequest>('BatchGetDocuments')
            .last
            .documents,
        <String>['$documents/coll/doc'],
      );
      expect(snapshot.exists, isTrue);
      expect(snapshot.id, 'doc');
      expect(snapshot.ref, firestore.doc('coll/doc'));
      expect(snapshot.data, <String, Object?>{
        'a': 1,
        'ref': firestore.doc('other/target'),
      });
    });

    test('get() of a missing document', () async {
      final Firestore firestore = newFirestore();
      final DocumentSnapshot<Map<String, Object?>> snapshot = await firestore
          .doc('coll/doc')
          .get();
      expect(snapshot.exists, isFalse);
      expect(snapshot.data, isNull);
      expect(snapshot.ref.path, 'coll/doc');
    });

    test('set() commits one write without a precondition', () async {
      final Firestore firestore = newFirestore();
      await firestore.doc('coll/doc').set(<String, Object?>{'a': 1});
      final proto.CommitRequest request = transport()
          .requests<proto.CommitRequest>('Commit')
          .single;
      expect(request.database, database);
      expect(request.writes, hasLength(1));
      expect(request.writes.single.update.name, '$documents/coll/doc');
      expect(request.writes.single.update.fields['a']!.integerValue, Int64(1));
      expect(request.writes.single.hasUpdateMask(), isFalse);
      expect(request.writes.single.hasCurrentDocument(), isFalse);
    });

    test('set() with merge sends the field mask and the transforms', () async {
      final Firestore firestore = newFirestore();
      await firestore.doc('coll/doc').set(<String, Object?>{
        'a': 1,
        'when': FieldValue.serverTimestamp(),
      }, SetOptions.mergeAllFields);
      final proto.Write write = transport()
          .requests<proto.CommitRequest>('Commit')
          .single
          .writes[0];
      expect(write.updateMask.fieldPaths, <String>['a']);
      expect(write.updateTransforms.single.fieldPath, 'when');
    });

    test('update() requires the document to exist', () async {
      final Firestore firestore = newFirestore();
      await firestore.doc('coll/doc').update(<String, Object?>{'a.b': 1});
      await firestore.doc('coll/doc').updateFromList(<Object?>[
        'c',
        FieldValue.delete(),
      ]);
      final List<proto.CommitRequest> requests = transport()
          .requests<proto.CommitRequest>('Commit');
      expect(requests[0].writes.single.updateMask.fieldPaths, <String>['a.b']);
      expect(requests[0].writes.single.currentDocument.exists, isTrue);
      expect(requests[1].writes.single.updateMask.fieldPaths, <String>['c']);
      expect(requests[1].writes.single.currentDocument.exists, isTrue);
    });

    test('delete() commits a delete', () async {
      final Firestore firestore = newFirestore();
      await firestore.doc('coll/doc').delete();
      expect(
        transport()
            .requests<proto.CommitRequest>('Commit')
            .single
            .writes
            .single
            .delete,
        '$documents/coll/doc',
      );
    });

    test('add() writes a document with an auto id', () async {
      final Firestore firestore = newFirestore();
      final DocumentReference<Map<String, Object?>> ref = await firestore
          .collection('coll')
          .add(<String, Object?>{'a': 1});
      expect(ref.id, hasLength(20));
      expect(
        transport()
            .requests<proto.CommitRequest>('Commit')
            .single
            .writes
            .single
            .update
            .name,
        '$documents/coll/${ref.id}',
      );
    });

    test('a backend error is a FirestoreError with its code', () async {
      final Firestore firestore = newFirestore();
      await firestore.doc('coll/warmup').get();
      transport().handlers['Commit'] = (GeneratedMessage request) =>
          throw const GrpcError.permissionDenied('no');
      await expectLater(
        firestore.doc('coll/doc').set(<String, Object?>{'a': 1}),
        throwsA(
          isA<FirestoreError>()
              .having(
                (FirestoreError e) => e.code,
                'code',
                FirestoreErrorCode.permissionDenied,
              )
              .having((FirestoreError e) => e.message, 'message', 'no'),
        ),
      );
      expect(
        transport().requests<proto.CommitRequest>('Commit'),
        hasLength(1),
        reason: 'a failed write is not retried',
      );
    });

    test('invalid data fails the future and sends nothing', () async {
      final Firestore firestore = newFirestore();
      await expectLater(
        firestore.doc('coll/doc').set(<String, Object?>{'a': Object()}),
        throwsArgumentError,
      );
      await expectLater(
        firestore.doc('coll/doc').update(<String, Object?>{'a': Object()}),
        throwsArgumentError,
      );
      await expectLater(
        firestore.doc('coll/doc').updateFromList(<Object?>['a']),
        throwsArgumentError,
      );
      expect(transports, isEmpty);
    });

    test('a reference of another database is rejected in data', () async {
      final Firestore firestore = newFirestore();
      final Firestore other = newFirestore(databaseName: 'other');
      await expectLater(
        firestore.doc('coll/doc').set(<String, Object?>{
          'ref': other.doc('coll/doc'),
        }),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            contains(
              'Document reference is for database '
              'lite-project/other but should be for database '
              'lite-project/(default)',
            ),
          ),
        ),
      );
    });

    test(
      'a reference of the same database is written as a reference',
      () async {
        final Firestore firestore = newFirestore();
        await firestore.doc('coll/doc').set(<String, Object?>{
          'ref': firestore.doc('other/target'),
        });
        expect(
          transport()
              .requests<proto.CommitRequest>('Commit')
              .single
              .writes
              .single
              .update
              .fields['ref']!
              .referenceValue,
          '$documents/other/target',
        );
      },
    );

    test('toJson() and fromJson() round trip', () {
      final Firestore firestore = newFirestore();
      final DocumentReference<Map<String, Object?>> ref = firestore.doc(
        'coll/doc',
      );
      expect(ref.toJson(), <String, Object>{
        'type': 'firestore/documentReference/1.0',
        'referencePath': 'coll/doc',
      });
      expect(
        DocumentReference<Map<String, Object?>>.fromJson(
          firestore,
          ref.toJson(),
        ),
        ref,
      );
      expect(
        () => DocumentReference<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{'type': 'other'},
        ),
        throwsArgumentError,
      );
    });
  });

  group('write batch', () {
    test('commits all the writes in one request', () async {
      final Firestore firestore = newFirestore();
      final WriteBatch batch = firestore.batch()
        ..set(firestore.doc('coll/a'), <String, Object?>{'a': 1})
        ..update(firestore.doc('coll/b'), <String, Object?>{'b': 2})
        ..updateFromList(firestore.doc('coll/c'), <Object?>['c', 3])
        ..delete(firestore.doc('coll/d'));
      await batch.commit();
      final List<proto.Write> writes = transport()
          .requests<proto.CommitRequest>('Commit')
          .single
          .writes;
      expect(writes, hasLength(4));
      expect(writes[0].update.name, '$documents/coll/a');
      expect(writes[0].hasCurrentDocument(), isFalse);
      expect(writes[1].currentDocument.exists, isTrue);
      expect(writes[2].currentDocument.exists, isTrue);
      expect(writes[3].delete, '$documents/coll/d');
    });

    test('an empty batch sends nothing', () async {
      final Firestore firestore = newFirestore();
      await firestore.batch().commit();
      expect(transport().calls, isEmpty);
    });

    test('rejects a reference of another instance', () {
      final Firestore firestore = newFirestore();
      final Firestore other = newFirestore(databaseName: 'other');
      final WriteBatch batch = firestore.batch();
      expect(
        () => batch.set(other.doc('coll/doc'), <String, Object?>{}),
        throwsArgumentError,
      );
      expect(
        () => batch.update(other.doc('coll/doc'), <String, Object?>{}),
        throwsArgumentError,
      );
      expect(() => batch.delete(other.doc('coll/doc')), throwsArgumentError);
    });

    test('cannot be used after commit()', () async {
      final Firestore firestore = newFirestore();
      final WriteBatch batch = firestore.batch();
      await batch.commit();
      expect(() => batch.delete(firestore.doc('coll/doc')), throwsStateError);
      await expectLater(batch.commit(), throwsStateError);
    });
  });

  group('queries', () {
    List<GeneratedMessage> results(List<int> values) => <GeneratedMessage>[
      // A response without a document only reports progress.
      proto.RunQueryResponse()
        ..readTime = (protobuf.Timestamp()..seconds = Int64(9)),
      for (final int value in values)
        proto.RunQueryResponse()
          ..document = document('coll/doc$value', <String, int>{'a': value}),
    ];

    test(
      'get() sends the structured query and returns the documents in order',
      () async {
        final Firestore firestore = newFirestore();
        await firestore.doc('coll/warmup').get();
        transport().handlers['RunQuery'] = (GeneratedMessage request) =>
            results(<int>[1, 2]);

        final Query<Map<String, Object?>> query = firestore
            .collection('parent/doc/coll')
            .where('a', isGreaterThan: 0)
            .orderBy('a')
            .startAt(<Object?>[1])
            .limit(5);
        final QuerySnapshot<Map<String, Object?>> snapshot = await query.get();

        final proto.RunQueryRequest request = transport()
            .requests<proto.RunQueryRequest>('RunQuery')
            .single;
        expect(request.parent, '$documents/parent/doc');
        final proto.StructuredQuery structured = request.structuredQuery;
        expect(structured.from.single.collectionId, 'coll');
        expect(structured.from.single.allDescendants, isFalse);
        expect(structured.where.fieldFilter.field_1.fieldPath, 'a');
        expect(
          structured.where.fieldFilter.op,
          proto.StructuredQuery_FieldFilter_Operator.GREATER_THAN,
        );
        expect(
          structured.orderBy
              .map(
                (proto.StructuredQuery_Order order) =>
                    '${order.field_1.fieldPath} ${order.direction.name}',
              )
              .toList(),
          <String>['a ASCENDING', '__name__ ASCENDING'],
        );
        expect(structured.limit.value, 5);
        expect(structured.startAt.values.single.integerValue, Int64(1));
        expect(structured.startAt.before, isTrue);

        expect(snapshot.query, same(query));
        expect(snapshot.length, 2);
        expect(snapshot.isEmpty, isFalse);
        expect(
          snapshot.docs
              .map((QueryDocumentSnapshot<Map<String, Object?>> doc) => doc.id)
              .toList(),
          <String>['doc1', 'doc2'],
        );
        expect(snapshot.docs.first.data, <String, Object?>{'a': 1});
        expect(snapshot.docs.first.ref, firestore.doc('coll/doc1'));
      },
    );

    test(
      'limitToLast() sends the flipped query and reverses the result',
      () async {
        final Firestore firestore = newFirestore();
        await firestore.doc('coll/warmup').get();
        // The backend answers the flipped query: largest first.
        transport().handlers['RunQuery'] = (GeneratedMessage request) =>
            results(<int>[5, 4]);

        final QuerySnapshot<Map<String, Object?>> snapshot = await firestore
            .collection('coll')
            .orderBy('a')
            .endBefore(<Object?>[6])
            .limitToLast(2)
            .get();

        final proto.StructuredQuery structured = transport()
            .requests<proto.RunQueryRequest>('RunQuery')
            .single
            .structuredQuery;
        expect(
          structured.orderBy
              .map(
                (proto.StructuredQuery_Order order) =>
                    '${order.field_1.fieldPath} ${order.direction.name}',
              )
              .toList(),
          <String>['a DESCENDING', '__name__ DESCENDING'],
        );
        expect(structured.limit.value, 2);
        // The end bound of the query is the start bound of the flipped one.
        expect(structured.startAt.values.single.integerValue, Int64(6));
        expect(structured.hasEndAt(), isFalse);

        expect(
          snapshot.docs
              .map(
                (QueryDocumentSnapshot<Map<String, Object?>> doc) =>
                    doc.data['a'],
              )
              .toList(),
          <int>[4, 5],
        );
      },
    );

    test('limitToLast() without orderBy() fails and sends nothing', () async {
      final Firestore firestore = newFirestore();
      await expectLater(
        firestore.collection('coll').limitToLast(2).get(),
        throwsStateError,
      );
      expect(transports, isEmpty);
    });

    test('a collection group query asks for all descendants', () async {
      final Firestore firestore = newFirestore();
      await firestore.collectionGroup('coll').get();
      final proto.RunQueryRequest request = transport()
          .requests<proto.RunQueryRequest>('RunQuery')
          .single;
      expect(request.parent, documents);
      expect(request.structuredQuery.from.single.collectionId, 'coll');
      expect(request.structuredQuery.from.single.allDescendants, isTrue);
    });

    test('a cursor from a snapshot continues after that document', () async {
      final Firestore firestore = newFirestore();
      await firestore.doc('coll/warmup').get();
      transport().handlers['RunQuery'] = (GeneratedMessage request) =>
          results(<int>[1]);
      final Query<Map<String, Object?>> query = firestore
          .collection('coll')
          .orderBy('a')
          .limit(1);
      final QuerySnapshot<Map<String, Object?>> first = await query.get();
      await query.startAfterDocument(first.docs.single).get();

      final proto.Cursor cursor = transport()
          .requests<proto.RunQueryRequest>('RunQuery')
          .last
          .structuredQuery
          .startAt;
      expect(cursor.before, isFalse);
      expect(cursor.values[0].integerValue, Int64(1));
      expect(cursor.values[1].referenceValue, '$documents/coll/doc1');
    });

    test('validates the query like the main library', () {
      final Firestore firestore = newFirestore();
      final CollectionReference<Map<String, Object?>> coll = firestore
          .collection('coll');
      expect(() => coll.where('a'), throwsArgumentError);
      expect(() => coll.where(42, isEqualTo: 1), throwsArgumentError);
      expect(
        () => coll.where(Filter.equalTo('a', 1), isEqualTo: 1),
        throwsArgumentError,
      );
      expect(() => coll.where('a', whereIn: <Object?>[]), throwsArgumentError);
      expect(
        () => coll
            .where('a', isNotEqualTo: 1)
            .where('b', whereNotIn: <Object?>[1]),
        throwsArgumentError,
      );
      expect(() => coll.limit(0), throwsArgumentError);
      expect(() => coll.limitToLast(-1), throwsArgumentError);
      expect(
        () => coll.orderBy('a').startAt(<Object?>[1, 2]),
        throwsArgumentError,
      );
      expect(
        () => coll.startAt(<Object?>[1]).orderBy('a'),
        throwsArgumentError,
      );
      expect(
        () => coll.where(FieldPath.documentIdField, isEqualTo: 'a/b'),
        throwsArgumentError,
      );
      expect(
        () => coll.where(FieldPath.documentIdField, arrayContains: 'a'),
        throwsArgumentError,
      );
      expect(transports, isEmpty);
    });

    test('filters on the document id accept ids and references', () async {
      final Firestore firestore = newFirestore();
      await firestore
          .collection('coll')
          .where(
            FieldPath.documentIdField,
            whereIn: <Object?>['a', firestore.doc('coll/b')],
          )
          .get();
      final proto.StructuredQuery_FieldFilter filter = transport()
          .requests<proto.RunQueryRequest>('RunQuery')
          .single
          .structuredQuery
          .where
          .fieldFilter;
      expect(
        filter.value.arrayValue.values
            .map((proto.Value value) => value.referenceValue)
            .toList(),
        <String>['$documents/coll/a', '$documents/coll/b'],
      );
    });

    test('isNull compares with null', () async {
      final Firestore firestore = newFirestore();
      await firestore.collection('coll').where('a', isNull: true).get();
      final proto.StructuredQuery where = transport()
          .requests<proto.RunQueryRequest>('RunQuery')
          .single
          .structuredQuery;
      expect(
        where.where.unaryFilter.op,
        proto.StructuredQuery_UnaryFilter_Operator.IS_NULL,
      );
    });

    test('a converter is applied to the results', () async {
      final Firestore firestore = newFirestore();
      await firestore.doc('coll/warmup').get();
      transport().handlers['RunQuery'] = (GeneratedMessage request) =>
          results(<int>[7]);
      final QuerySnapshot<int> snapshot = await firestore
          .collection('coll')
          .withConverter(
            FirestoreDataConverter<int>.from(
              fromFirestore:
                  (QueryDocumentSnapshot<Map<String, Object?>> snapshot) =>
                      snapshot.data['a']! as int,
              toFirestore: (int value, SetOptions? options) =>
                  <String, Object?>{'a': value},
            ),
          )
          .get();
      expect(snapshot.docs.single.data, 7);
      // The fields are read unconverted.
      expect(snapshot.docs.single.get('a'), 7);
    });
  });

  group('aggregations', () {
    test('count() sends one aggregation and reads it back', () async {
      final Firestore firestore = newFirestore();
      await firestore.doc('coll/warmup').get();
      transport().handlers['RunAggregationQuery'] = (GeneratedMessage message) {
        final proto.RunAggregationQueryRequest request =
            message as proto.RunAggregationQueryRequest;
        return <GeneratedMessage>[
          proto.RunAggregationQueryResponse()
            ..result = (proto.AggregationResult()
              ..aggregateFields.addAll(<String, proto.Value>{
                for (final proto.StructuredAggregationQuery_Aggregation a
                    in request.structuredAggregationQuery.aggregations)
                  a.alias: proto.Value()..integerValue = Int64(3),
              })),
        ];
      };

      final AggregateQuerySnapshot snapshot = await firestore
          .collection('coll')
          .where('a', isEqualTo: 1)
          .count()
          .get();
      final proto.RunAggregationQueryRequest request = transport()
          .requests<proto.RunAggregationQueryRequest>('RunAggregationQuery')
          .single;
      expect(request.parent, documents);
      expect(request.structuredAggregationQuery.aggregations, hasLength(1));
      expect(
        request.structuredAggregationQuery.aggregations.single.hasCount(),
        isTrue,
      );
      expect(
        request
            .structuredAggregationQuery
            .structuredQuery
            .where
            .fieldFilter
            .field_1
            .fieldPath,
        'a',
      );
      expect(snapshot.getCount(), 3);
      expect(snapshot.data(), <String, Object?>{'count': 3});
    });

    test('aliases name the results and duplicates are sent once', () async {
      final Firestore firestore = newFirestore();
      await firestore.doc('coll/warmup').get();
      transport().handlers['RunAggregationQuery'] = (GeneratedMessage message) {
        final proto.RunAggregationQueryRequest request =
            message as proto.RunAggregationQueryRequest;
        return <GeneratedMessage>[
          proto.RunAggregationQueryResponse()
            ..result = (proto.AggregationResult()
              ..aggregateFields.addAll(<String, proto.Value>{
                for (final proto.StructuredAggregationQuery_Aggregation a
                    in request.structuredAggregationQuery.aggregations)
                  a.alias: a.hasCount()
                      ? (proto.Value()..integerValue = Int64(2))
                      : a.hasSum()
                      ? (proto.Value()..integerValue = Int64(150))
                      : (proto.Value()..doubleValue = 75.0),
              })),
        ];
      };

      final AggregateQuerySnapshot snapshot = await firestore
          .collection('coll')
          .aggregateWithAliases(<String, AggregateField>{
            'n': AggregateField.count(),
            'again': AggregateField.count(),
            'total': AggregateField.sum('pages'),
            'mean': AggregateField.average('pages'),
          })
          .get();
      expect(
        transport()
            .requests<proto.RunAggregationQueryRequest>('RunAggregationQuery')
            .single
            .structuredAggregationQuery
            .aggregations,
        hasLength(3),
      );
      expect(snapshot.data(), <String, Object?>{
        'n': 2,
        'again': 2,
        'total': 150,
        'mean': 75.0,
      });
      expect(snapshot.getInt(AggregateField.sum('pages')), 150);
      expect(snapshot.getDouble(AggregateField.average('pages')), 75.0);
    });

    test('an aggregation needs at least one field', () {
      final Firestore firestore = newFirestore();
      expect(
        () => firestore.collection('coll').aggregate(<AggregateField>[]),
        throwsArgumentError,
      );
      expect(
        () => firestore
            .collection('coll')
            .aggregateWithAliases(<String, AggregateField>{}),
        throwsArgumentError,
      );
    });
  });

  group('transactions', () {
    test('commit the writes with the versions that were read', () async {
      final Firestore firestore = newFirestore();
      await firestore.doc('coll/warmup').get();
      transport().handlers['BatchGetDocuments'] = (GeneratedMessage message) {
        final proto.BatchGetDocumentsRequest request =
            message as proto.BatchGetDocumentsRequest;
        return <GeneratedMessage>[
          if (request.documents.single.endsWith('/existing'))
            proto.BatchGetDocumentsResponse()
              ..found = document('coll/existing', <String, int>{
                'a': 1,
              }, version: 7)
          else
            proto.BatchGetDocumentsResponse()
              ..missing = request.documents[0]
              ..readTime = (protobuf.Timestamp()..seconds = Int64(8)),
        ];
      };

      final int result = await firestore.runTransaction<int>((
        Transaction transaction,
      ) async {
        final DocumentSnapshot<Map<String, Object?>> existing =
            await transaction.get(firestore.doc('coll/existing'));
        final DocumentSnapshot<Map<String, Object?>> missing = await transaction
            .get(firestore.doc('coll/missing'));
        final DocumentSnapshot<Map<String, Object?>> onlyRead =
            await transaction.get(firestore.doc('coll/existing'));
        expect(existing.data, <String, Object?>{'a': 1});
        expect(missing.exists, isFalse);
        expect(onlyRead.exists, isTrue);
        transaction
          ..update(firestore.doc('coll/existing'), <String, Object?>{'a': 2})
          ..set(firestore.doc('coll/missing'), <String, Object?>{'a': 0})
          ..delete(firestore.doc('coll/blind'));
        return 42;
      });
      expect(result, 42);

      final List<proto.Write> writes = transport()
          .requests<proto.CommitRequest>('Commit')
          .single
          .writes;
      expect(writes, hasLength(3));
      expect(writes[0].currentDocument.updateTime.seconds, Int64(7));
      expect(writes[1].currentDocument.exists, isFalse);
      expect(writes[1].currentDocument.hasExists(), isTrue);
      expect(writes[2].delete, '$documents/coll/blind');
      expect(writes[2].hasCurrentDocument(), isFalse);
    });

    test('are retried when the commit is aborted', () async {
      final Firestore firestore = newFirestore();
      await firestore.doc('coll/warmup').get();
      int commits = 0;
      transport().handlers['Commit'] = (GeneratedMessage request) {
        if (++commits == 1) {
          throw const GrpcError.aborted('contention');
        }
        return <GeneratedMessage>[
          proto.CommitResponse()
            ..commitTime = (protobuf.Timestamp()..seconds = Int64(2))
            ..writeResults.add(proto.WriteResult()),
        ];
      };
      int attempts = 0;
      await firestore.runTransaction<void>((Transaction transaction) async {
        attempts++;
        transaction.set(firestore.doc('coll/doc'), <String, Object?>{'a': 1});
      });
      expect(attempts, 2);
      expect(commits, 2);
    });

    test(
      'are not retried after a permanent error or beyond maxAttempts',
      () async {
        final Firestore firestore = newFirestore();
        await firestore.doc('coll/warmup').get();
        transport().handlers['Commit'] = (GeneratedMessage request) =>
            throw const GrpcError.permissionDenied('no');
        int attempts = 0;
        await expectLater(
          firestore.runTransaction<void>((Transaction transaction) async {
            attempts++;
            transaction.set(firestore.doc('coll/doc'), <String, Object?>{
              'a': 1,
            });
          }),
          throwsA(
            isA<FirestoreError>().having(
              (FirestoreError e) => e.code,
              'code',
              FirestoreErrorCode.permissionDenied,
            ),
          ),
        );
        expect(attempts, 1);

        transport().handlers['Commit'] = (GeneratedMessage request) =>
            throw const GrpcError.aborted('busy');
        attempts = 0;
        await expectLater(
          firestore.runTransaction<void>((Transaction transaction) async {
            attempts++;
            transaction.set(firestore.doc('coll/doc'), <String, Object?>{
              'a': 1,
            });
          }, options: TransactionOptions(maxAttempts: 1)),
          throwsA(
            isA<FirestoreError>().having(
              (FirestoreError e) => e.code,
              'code',
              FirestoreErrorCode.aborted,
            ),
          ),
        );
        expect(attempts, 1);
      },
    );

    test(
      'an error of the update function fails the transaction as it is',
      () async {
        final Firestore firestore = newFirestore();
        await expectLater(
          firestore.runTransaction<void>(
            (Transaction transaction) async => throw StateError('mine'),
          ),
          throwsA(
            isA<StateError>().having(
              (StateError e) => e.message,
              'message',
              'mine',
            ),
          ),
        );
        expect(transport().requests<proto.CommitRequest>('Commit'), isEmpty);
      },
    );

    test('a read-only transaction reads in one backend transaction', () async {
      final Firestore firestore = newFirestore();
      await firestore.doc('coll/warmup').get();
      transport().handlers['RunQuery'] = (GeneratedMessage request) =>
          <GeneratedMessage>[
            for (final int value in <int>[5, 4])
              proto.RunQueryResponse()
                ..document = document('coll/doc$value', <String, int>{
                  'a': value,
                }),
          ];
      transport().handlers['RunAggregationQuery'] = (GeneratedMessage message) {
        final proto.RunAggregationQueryRequest request =
            message as proto.RunAggregationQueryRequest;
        return <GeneratedMessage>[
          proto.RunAggregationQueryResponse()
            ..result = (proto.AggregationResult()
              ..aggregateFields.addAll(<String, proto.Value>{
                for (final proto.StructuredAggregationQuery_Aggregation a
                    in request.structuredAggregationQuery.aggregations)
                  a.alias: proto.Value()..integerValue = Int64(2),
              })),
        ];
      };

      final CollectionReference<Map<String, Object?>> coll = firestore
          .collection('coll');
      await firestore.runTransaction<void>(
        (Transaction transaction) async {
          expect((await transaction.get(coll.doc('missing'))).exists, isFalse);
          final QuerySnapshot<Map<String, Object?>> last = await transaction
              .getQuery(coll.orderBy('a').limitToLast(2));
          expect(
            last.docs
                .map(
                  (QueryDocumentSnapshot<Map<String, Object?>> doc) =>
                      doc.data['a'],
                )
                .toList(),
            <int>[4, 5],
            reason: 'the flipped query was sent and its result reversed',
          );
          expect((await transaction.getAggregate(coll.count())).getCount(), 2);
          expect(
            () => transaction.set(coll.doc('a'), <String, Object?>{}),
            throwsA(isA<FirestoreError>()),
          );
        },
        options: TransactionOptions(
          readOnly: true,
          readTime: const Timestamp(100, 0),
        ),
      );

      final proto.BeginTransactionRequest begin = transport()
          .requests<proto.BeginTransactionRequest>('BeginTransaction')
          .single;
      expect(begin.database, database);
      expect(begin.options.readOnly.readTime.seconds, Int64(100));
      expect(
        transport()
            .requests<proto.BatchGetDocumentsRequest>('BatchGetDocuments')
            .last
            .transaction,
        <int>[1, 2, 3],
      );
      final proto.RunQueryRequest query = transport()
          .requests<proto.RunQueryRequest>('RunQuery')
          .single;
      expect(query.transaction, <int>[1, 2, 3]);
      expect(
        query.structuredQuery.orderBy.first.direction,
        proto.StructuredQuery_Direction.DESCENDING,
      );
      expect(
        transport()
            .requests<proto.RunAggregationQueryRequest>('RunAggregationQuery')
            .single
            .transaction,
        <int>[1, 2, 3],
      );
      expect(
        transport()
            .requests<proto.RollbackRequest>('Rollback')
            .single
            .transaction,
        <int>[1, 2, 3],
      );
      expect(transport().requests<proto.CommitRequest>('Commit'), isEmpty);
    });

    test('queries need a read-only transaction', () async {
      final Firestore firestore = newFirestore();
      final Firestore other = newFirestore(databaseName: 'other');
      await expectLater(
        firestore.runTransaction<void>(
          (Transaction transaction) =>
              transaction.getQuery(firestore.collection('coll')),
        ),
        throwsA(
          isA<FirestoreError>().having(
            (FirestoreError e) => e.code,
            'code',
            FirestoreErrorCode.invalidArgument,
          ),
        ),
      );
      await expectLater(
        firestore.runTransaction<void>(
          (Transaction transaction) =>
              transaction.getQuery(other.collection('coll')),
          options: TransactionOptions(readOnly: true),
        ),
        throwsArgumentError,
      );
      await expectLater(
        firestore.runTransaction<void>(
          (Transaction transaction) =>
              transaction.getQuery(firestore.collection('coll').limitToLast(1)),
          options: TransactionOptions(readOnly: true),
        ),
        throwsStateError,
      );
    });

    test('reject a reference of another instance', () async {
      final Firestore firestore = newFirestore();
      final Firestore other = newFirestore(databaseName: 'other');
      await expectLater(
        firestore.runTransaction<void>((Transaction transaction) async {
          transaction.set(other.doc('coll/doc'), <String, Object?>{});
        }),
        throwsArgumentError,
      );
    });
  });
}

class _Auth extends InternalTokenProvider {
  // Closed by the test.
  // ignore: close_sinks
  final StreamController<InternalTokenResult> tokenChanges =
      StreamController<InternalTokenResult>.broadcast();

  /// An unsigned JWT for the user `alice`.
  final String token = <String>[
    base64Url.encode(utf8.encode('{"alg":"none"}')),
    base64Url.encode(utf8.encode('{"sub":"alice","user_id":"alice"}')),
    '',
  ].join('.');

  @override
  String? get uid => 'alice';

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async =>
      GetTokenResult(token);

  @override
  Stream<InternalTokenResult> get onTokenChanged => tokenChanges.stream;
}

class _AppCheck implements InternalAppCheckTokenProvider {
  // Closed by the test.
  // ignore: close_sinks
  final StreamController<AppCheckTokenResult> changes =
      StreamController<AppCheckTokenResult>.broadcast();

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async =>
      const AppCheckTokenResult('app-check-token');

  @override
  Stream<AppCheckTokenResult> get onTokenChanged => changes.stream;
}

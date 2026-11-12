// A smoke test of the web transport (REST and WebChannel over `fetch`) in a
// real browser, against a private Firestore emulator on 127.0.0.1:8090
// (tool/start_private_emulator.sh):
//
//   dart test -p chrome -c dart2wasm test/browser/web_transport_smoke_test.dart
//
// The cache is in memory: there is no SQLite persistence on the web yet.

@TestOn('browser')
library;

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:rxdart/subjects.dart';
import 'package:test/test.dart';

const String emulatorHost = String.fromEnvironment(
    'FIRESTORE_EMULATOR_HOST_NAME',
    defaultValue: '127.0.0.1');
const int emulatorPort =
    int.fromEnvironment('FIRESTORE_EMULATOR_PORT', defaultValue: 8090);
const String projectId =
    String.fromEnvironment('FIRESTORE_PROJECT_ID', defaultValue: 'demo-test');

final List<Firestore> _instances = <Firestore>[];
final Random _random = Random();

/// A new client with its own (memory) cache.
Future<Firestore> newFirestore() async {
  final DatabaseId databaseId = DatabaseId.forProject(projectId);
  final FirestoreSettings settings = FirestoreSettings(
      host: emulatorHost, port: emulatorPort, sslEnabled: false);
  final TaskScheduler scheduler = TaskScheduler('');
  final FirestoreClient client = await FirestoreClient.initialize(
    DatabaseInfo(
        databaseId, 'browser-${_random.nextInt(0x7fffffff)}', settings.host,
        port: settings.port, sslEnabled: settings.sslEnabled),
    settings,
    EmptyCredentialsProvider(),
    null,
    BehaviorSubject<bool>.seeded(true),
    scheduler,
  );
  // ignore: invalid_use_of_internal_member
  final Firestore firestore = Firestore(databaseId, null, client, scheduler);
  _instances.add(firestore);
  return firestore;
}

String newCollection() =>
    'browser-smoke-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff)}';

void main() {
  tearDown(() async {
    for (final Firestore firestore in _instances) {
      await firestore.terminate();
    }
    _instances.clear();
  });

  test('works through the public API (FirebaseApp, Firestore.instanceFor)',
      () async {
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'demo-key',
        applicationId: '1:1234567890:dart:browser',
        projectId: projectId,
      ),
    );
    final Firestore firestore = await Firestore.instanceFor(
      app: app,
      settings: FirestoreSettings(cacheSettings: const MemoryCacheSettings())
          .withEmulator(emulatorHost, emulatorPort),
    );
    addTearDown(firestore.terminate);

    final CollectionReference<Map<String, dynamic>> collection =
        firestore.collection(newCollection());
    final Completer<void> listened = Completer<void>();
    final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> sub =
        collection.snapshots.listen((QuerySnapshot<Map<String, dynamic>> s) {
      if (s.docs.length == 1 && !listened.isCompleted) {
        listened.complete();
      }
    });
    await collection.doc('ada').set(<String, dynamic>{'name': 'Ada'});
    await listened.future.timeout(const Duration(seconds: 20));
    await sub.cancel();

    expect((await collection.doc('ada').get(Source.server)).data,
        <String, dynamic>{'name': 'Ada'});
    expect((await collection.count().get()).getCount(), 1);
  });

  test('writes a document and reads it back from the server', () async {
    final Firestore firestore = await newFirestore();
    final DocumentReference<Map<String, dynamic>> doc =
        firestore.collection(newCollection()).doc('a');

    // The Write stream (WebChannel).
    await doc.set(<String, dynamic>{
      'text': 'héllo \u{1F600} 日本',
      'int': 42,
      'double': 1.5,
      'bool': true,
      'null': null,
      'list': <dynamic>[1, 'two', null],
      'map': <String, dynamic>{'nested': 'yes'},
    });

    // The Listen stream (WebChannel), with another client so that nothing
    // comes from the cache.
    final Firestore other = await newFirestore();
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await other.doc(doc.path).get(Source.server);
    expect(snapshot.exists, isTrue);
    expect(snapshot.metadata.isFromCache, isFalse);
    expect(snapshot.data, <String, dynamic>{
      'text': 'héllo \u{1F600} 日本',
      'int': 42,
      'double': 1.5,
      'bool': true,
      'null': null,
      'list': <dynamic>[1, 'two', null],
      'map': <String, dynamic>{'nested': 'yes'},
    });
  });

  test('a listener receives a change another client makes', () async {
    final Firestore firestore = await newFirestore();
    final Firestore other = await newFirestore();
    final String collection = newCollection();
    await firestore
        .collection(collection)
        .doc('a')
        .set(<String, dynamic>{'n': 1});

    final List<List<int>> seen = <List<int>>[];
    final Completer<void> sawBoth = Completer<void>();
    final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> sub =
        firestore
            .collection(collection)
            .orderBy('n')
            .snapshots
            .listen((QuerySnapshot<Map<String, dynamic>> snapshot) {
      seen.add(snapshot.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              d.data['n'] as int)
          .toList());
      if (snapshot.docs.length == 2 && !sawBoth.isCompleted) {
        sawBoth.complete();
      }
    });

    await other.collection(collection).doc('b').set(<String, dynamic>{'n': 2});
    await sawBoth.future.timeout(const Duration(seconds: 20));
    await sub.cancel();
    expect(seen.last, <int>[1, 2]);
  });

  test('queries with a filter', () async {
    final Firestore firestore = await newFirestore();
    final CollectionReference<Map<String, dynamic>> collection =
        firestore.collection(newCollection());
    for (int i = 0; i < 5; i++) {
      await collection.doc('d$i').set(<String, dynamic>{'n': i});
    }

    final QuerySnapshot<Map<String, dynamic>> snapshot =
        await collection.where('n', isGreaterThan: 2).get(Source.server);
    expect(
        snapshot.docs
            .map((QueryDocumentSnapshot<Map<String, dynamic>> d) => d.id)
            .toList(),
        <String>['d3', 'd4']);
  });

  test('runs a transaction and an aggregation (REST)', () async {
    final Firestore firestore = await newFirestore();
    final CollectionReference<Map<String, dynamic>> collection =
        firestore.collection(newCollection());
    final DocumentReference<Map<String, dynamic>> counter =
        collection.doc('counter');
    await counter.set(<String, dynamic>{'count': 1});

    // BatchGetDocuments and Commit.
    await firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await transaction.get(counter);
      transaction.update(counter,
          <String, dynamic>{'count': (snapshot.data!['count'] as int) + 1});
    });
    expect(
        (await counter.get(Source.server)).data, <String, dynamic>{'count': 2});

    // RunAggregationQuery.
    await collection.doc('other').set(<String, dynamic>{'count': 10});
    final AggregateQuerySnapshot aggregate = await collection.count().get();
    expect(aggregate.getCount(), 2);
  });

  test('reports a server error with its code (REST)', () async {
    final Firestore firestore = await newFirestore();
    final DocumentReference<Map<String, dynamic>> doc =
        firestore.collection(newCollection()).doc('missing');

    // Updating a missing document in a transaction fails with NOT_FOUND.
    Object? error;
    try {
      await firestore.runTransaction<void>((Transaction transaction) async {
        transaction.update(doc, <String, dynamic>{'a': 1});
      });
    } catch (e) {
      error = e;
    }
    expect(error, isA<FirestoreError>());
    expect((error! as FirestoreError).code, FirestoreErrorCode.notFound);
  });

  test('keeps 64 bit integers exact', () async {
    final Firestore firestore = await newFirestore();
    final DocumentReference<Map<String, dynamic>> doc =
        firestore.collection(newCollection()).doc('a');
    // 2^53 + 1, which a JavaScript number cannot hold.
    final int big = int.parse('9007199254740993');
    await doc.set(<String, dynamic>{'big': big});

    final Firestore other = await newFirestore();
    final Object? read =
        (await other.doc(doc.path).get(Source.server)).data!['big'];
    expect(read, big);
    expect('$read', '9007199254740993');
  },
      // Compiled to JavaScript an int is a double.
      skip: identical(1, 1.0)
          ? 'dart2js: integers above 2^53 lose precision'
          : null);
}

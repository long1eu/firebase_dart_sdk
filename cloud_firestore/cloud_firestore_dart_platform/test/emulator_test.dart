// The core of the official cloud_firestore API, run through this package
// against a Firestore emulator.
//
// Needs FIRESTORE_EMULATOR_HOST (for example 127.0.0.1:8090, started with
// tool/start_private_emulator.sh 8090 from the repository root); skipped
// without it. The emulator project is demo-test, with open rules.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_dart_platform/cloud_firestore_dart_platform.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

final String? _emulator = Platform.environment['FIRESTORE_EMULATOR_HOST'];

class City {
  const City(this.name, this.population);

  factory City.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    // ignore: avoid_unused_constructor_parameters
    SnapshotOptions? options,
  ) {
    final Map<String, dynamic> data = snapshot.data()!;
    return City(data['name'] as String, data['population'] as int);
  }

  final String name;
  final int population;

  Map<String, Object?> toFirestore(SetOptions? options) => <String, Object?>{
    'name': name,
    'population': population,
  };
}

void main() {
  late FirebaseFirestore firestore;
  late CollectionReference<Map<String, dynamic>> root;

  setUpAll(() async {
    if (_emulator == null) {
      return;
    }
    // Simulate an app with the package on Linux: the plugin registrant calls
    // registerWith, which also installs the Dart core there.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    CloudFirestoreDart.registerWith();
    final FirebaseApp app = await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'emulator-api-key',
        appId: '1:1:web:1',
        messagingSenderId: '1',
        projectId: 'demo-test',
      ),
    );
    firestore = FirebaseFirestore.instanceFor(app: app);
    final List<String> hostAndPort = _emulator!.split(':');
    firestore.useFirestoreEmulator(hostAndPort[0], int.parse(hostAndPort[1]));
    root = firestore.collection(
      'platform-tests/run-${DateTime.now().microsecondsSinceEpoch}/items',
    );
  });

  tearDownAll(() async {
    if (_emulator != null) {
      await firestore.terminate();
    }
    debugDefaultTargetPlatformOverride = null;
  });

  final Object? skip = _emulator == null
      ? 'Set FIRESTORE_EMULATOR_HOST to run the emulator tests'
      : null;

  group('through cloud_firestore', skip: skip, () {
    test('set, get, update with a FieldPath, delete', () async {
      final DocumentReference<Map<String, dynamic>> ref = root.doc('crud');
      await ref.set(<String, Object?>{
        'name': 'San Francisco',
        'stats': <String, Object?>{'pop': 1},
      });
      DocumentSnapshot<Map<String, dynamic>> snapshot = await ref.get();
      expect(snapshot.exists, isTrue);
      expect(snapshot.id, 'crud');
      expect(snapshot.reference, ref);
      expect(snapshot.data(), <String, Object?>{
        'name': 'San Francisco',
        'stats': <String, Object?>{'pop': 1},
      });
      expect(snapshot.get('stats.pop'), 1);
      expect(snapshot['name'], 'San Francisco');

      await ref.update(<Object, Object?>{
        'stats.pop': 2,
        FieldPath(const <String>['with.dot']): true,
      });
      snapshot = await ref.get(const GetOptions(source: Source.server));
      expect(snapshot.get(FieldPath(const <String>['with.dot'])), isTrue);
      expect(snapshot.get('stats.pop'), 2);

      await ref.set(<String, Object?>{'extra': 1}, SetOptions(merge: true));
      await ref.set(<String, Object?>{
        'name': 'SF',
        'ignored': 1,
      }, SetOptions(mergeFields: <Object>['name']));
      snapshot = await ref.get();
      expect(snapshot.data(), <String, Object?>{
        'name': 'SF',
        'stats': <String, Object?>{'pop': 2},
        'with.dot': true,
        'extra': 1,
      });

      await ref.delete();
      snapshot = await ref.get();
      expect(snapshot.exists, isFalse);
      expect(snapshot.data(), isNull);

      final DocumentReference<Map<String, dynamic>> added = await root.add(
        <String, Object?>{'auto': true},
      );
      expect(added.id, hasLength(20));
      expect((await added.get()).get('auto'), isTrue);
    });

    test('withConverter', () async {
      final CollectionReference<City> cities = root
          .doc('converter')
          .collection('cities')
          .withConverter<City>(
            fromFirestore: City.fromFirestore,
            toFirestore: (City city, SetOptions? options) =>
                city.toFirestore(options),
          );
      await cities.doc('SF').set(const City('San Francisco', 860000));
      final City? city = (await cities.doc('SF').get()).data();
      expect(city?.name, 'San Francisco');
      expect(city?.population, 860000);
      final QuerySnapshot<City> big = await cities
          .where('population', isGreaterThan: 100)
          .get();
      expect(big.docs.single.data().name, 'San Francisco');
    });

    test('queries: filters, Filter.or, order, limits, cursors', () async {
      final CollectionReference<Map<String, dynamic>> numbers = root
          .doc('queries')
          .collection('numbers');
      final WriteBatch batch = firestore.batch();
      for (int i = 1; i <= 6; i++) {
        batch.set(numbers.doc('n$i'), <String, Object?>{
          'value': i,
          'even': i.isEven,
          'tags': <String>['t$i', if (i.isEven) 'even'],
          'maybe': i == 3 ? null : i,
        });
      }
      await batch.commit();

      List<int> values(QuerySnapshot<Map<String, dynamic>> snapshot) => <int>[
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in snapshot.docs)
          doc.get('value') as int,
      ];

      expect(
        values(await numbers.where('value', isGreaterThan: 4).get()),
        <int>[5, 6],
      );
      expect(values(await numbers.where('value', isLessThan: 2).get()), <int>[
        1,
      ]);
      expect(
        values(await numbers.where('value', isGreaterThanOrEqualTo: 5).get()),
        <int>[5, 6],
      );
      expect(
        values(await numbers.where('value', isLessThanOrEqualTo: 2).get()),
        <int>[1, 2],
      );
      expect(values(await numbers.where('even', isEqualTo: true).get()), <int>[
        2,
        4,
        6,
      ]);
      expect(values(await numbers.where('value', isNotEqualTo: 2).get()), <int>[
        1,
        3,
        4,
        5,
        6,
      ]);
      expect(
        values(await numbers.where('tags', arrayContains: 'even').get()),
        <int>[2, 4, 6],
      );
      expect(
        values(
          await numbers
              .where('tags', arrayContainsAny: <String>['t1', 't2'])
              .get(),
        ),
        <int>[1, 2],
      );
      expect(
        values(await numbers.where('value', whereIn: <int>[1, 5]).get()),
        <int>[1, 5],
      );
      expect(
        values(await numbers.where('value', whereNotIn: <int>[1, 5]).get()),
        <int>[2, 3, 4, 6],
      );
      expect(values(await numbers.where('maybe', isNull: true).get()), <int>[
        3,
      ]);
      expect(
        values(
          await numbers
              .where(
                Filter.or(
                  Filter('value', isEqualTo: 1),
                  Filter.and(
                    Filter('even', isEqualTo: true),
                    Filter('value', isGreaterThan: 4),
                  ),
                ),
              )
              .get(),
        ),
        <int>[1, 6],
      );
      expect(
        values(
          await numbers.where(FieldPath.documentId, isEqualTo: 'n2').get(),
        ),
        <int>[2],
      );

      final Query<Map<String, dynamic>> ordered = numbers.orderBy(
        'value',
        descending: true,
      );
      expect(values(await ordered.limit(2).get()), <int>[6, 5]);
      expect(values(await ordered.limitToLast(2).get()), <int>[2, 1]);
      expect(values(await ordered.startAfter(<Object?>[4]).get()), <int>[
        3,
        2,
        1,
      ]);
      expect(
        values(
          await ordered.startAt(<Object?>[4]).endBefore(<Object?>[2]).get(),
        ),
        <int>[4, 3],
      );
      expect(values(await ordered.endAt(<Object?>[5]).get()), <int>[6, 5]);
      final DocumentSnapshot<Map<String, dynamic>> four = await numbers
          .doc('n4')
          .get();
      expect(values(await ordered.startAfterDocument(four).get()), <int>[
        3,
        2,
        1,
      ]);
      expect(values(await ordered.endAtDocument(four).get()), <int>[6, 5, 4]);

      final QuerySnapshot<Map<String, dynamic>> group = await firestore
          .collectionGroup('numbers')
          .where('value', isLessThanOrEqualTo: 2)
          .get();
      expect(
        group.docs.map((QueryDocumentSnapshot<Map<String, dynamic>> d) => d.id),
        containsAll(<String>['n1', 'n2']),
      );
    });

    test('aggregate count, sum, average', () async {
      final CollectionReference<Map<String, dynamic>> scores = root
          .doc('aggregates')
          .collection('scores');
      await Future.wait(<Future<void>>[
        for (final int score in <int>[10, 20, 30])
          scores.add(<String, Object?>{'score': score}),
      ]);
      final AggregateQuerySnapshot counted = await scores.count().get();
      expect(counted.count, 3);
      final AggregateQuerySnapshot all = await scores
          .aggregate(count(), sum('score'), average('score'))
          .get();
      expect(all.count, 3);
      expect(all.getSum('score'), 60);
      expect(all.getAverage('score'), 20);
      expect(
        (await scores.where('score', isGreaterThan: 15).count().get()).count,
        2,
      );
    });

    test('document and query listeners with metadata changes', () async {
      final DocumentReference<Map<String, dynamic>> ref = root.doc('listen');
      await ref.set(<String, Object?>{'v': 0});

      final List<DocumentSnapshot<Map<String, dynamic>>> events =
          <DocumentSnapshot<Map<String, dynamic>>>[];
      final Completer<void> synced = Completer<void>();
      final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> sub = ref
          .snapshots(includeMetadataChanges: true)
          .listen((DocumentSnapshot<Map<String, dynamic>> snapshot) {
            events.add(snapshot);
            if (snapshot.get('v') == 1 &&
                !snapshot.metadata.hasPendingWrites &&
                !synced.isCompleted) {
              synced.complete();
            }
          });
      // Wait for the first snapshot from the server before writing.
      while (events.isEmpty || events.last.metadata.isFromCache) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await ref.update(<Object, Object?>{'v': 1});
      await synced.future.timeout(const Duration(seconds: 10));
      await sub.cancel();

      final DocumentSnapshot<Map<String, dynamic>> pending = events.firstWhere(
        (DocumentSnapshot<Map<String, dynamic>> s) => s.get('v') == 1,
      );
      expect(pending.metadata.hasPendingWrites, isTrue);
      expect(events.last.metadata.hasPendingWrites, isFalse);
      expect(events.last.get('v'), 1);

      final CollectionReference<Map<String, dynamic>> items = root
          .doc('listen')
          .collection('items');
      final StreamController<QuerySnapshot<Map<String, dynamic>>> snapshots =
          StreamController<QuerySnapshot<Map<String, dynamic>>>();
      final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> qsub = items
          .orderBy('n')
          .snapshots()
          .listen(snapshots.add, onError: snapshots.addError);
      final StreamIterator<QuerySnapshot<Map<String, dynamic>>> it =
          StreamIterator<QuerySnapshot<Map<String, dynamic>>>(snapshots.stream);
      expect(await it.moveNext(), isTrue);
      expect(it.current.docs, isEmpty);

      await items.doc('a').set(<String, Object?>{'n': 1});
      expect(await it.moveNext(), isTrue);
      expect(it.current.docs.single.id, 'a');
      expect(it.current.docChanges.single.type, DocumentChangeType.added);
      expect(it.current.docChanges.single.oldIndex, -1);
      expect(it.current.docChanges.single.newIndex, 0);

      await items.doc('a').delete();
      QuerySnapshot<Map<String, dynamic>> last;
      do {
        expect(await it.moveNext(), isTrue);
        last = it.current;
      } while (last.docs.isNotEmpty);
      expect(last.docChanges.single.type, DocumentChangeType.removed);
      expect(last.docChanges.single.doc.id, 'a');
      await qsub.cancel();
      await it.cancel();
    });

    test('write batch', () async {
      final CollectionReference<Map<String, dynamic>> col = root
          .doc('batch')
          .collection('docs');
      await col.doc('gone').set(<String, Object?>{'x': 1});
      await col.doc('upd').set(<String, Object?>{'x': 1});
      final WriteBatch batch = firestore.batch()
        ..set(col.doc('new'), <String, Object?>{'x': 2})
        ..update(col.doc('upd'), <String, Object?>{'x': 3})
        ..delete(col.doc('gone'));
      await batch.commit();
      expect((await col.doc('new').get()).get('x'), 2);
      expect((await col.doc('upd').get()).get('x'), 3);
      expect((await col.doc('gone').get()).exists, isFalse);
    });

    test('transaction', () async {
      final DocumentReference<Map<String, dynamic>> counter = root.doc(
        'counter',
      );
      await counter.set(<String, Object?>{'n': 1});
      final int result = await firestore.runTransaction((
        Transaction transaction,
      ) async {
        final DocumentSnapshot<Map<String, dynamic>> snapshot =
            await transaction.get(counter);
        final int next = (snapshot.get('n') as int) + 1;
        transaction
          ..update(counter, <String, Object?>{'n': next})
          ..set(root.doc('tx-log'), <String, Object?>{'last': next});
        return next;
      });
      expect(result, 2);
      expect((await counter.get()).get('n'), 2);
      expect((await root.doc('tx-log').get()).get('last'), 2);

      await expectLater(
        firestore.runTransaction<void>((Transaction transaction) async {
          await transaction.get(counter);
          throw StateError('abort');
        }),
        throwsStateError,
      );
      expect((await counter.get()).get('n'), 2);
    });

    test('field values', () async {
      final DocumentReference<Map<String, dynamic>> ref = root.doc('fields');
      await ref.set(<String, Object?>{
        'n': 1,
        'arr': <Object?>[1, 2],
        'drop': true,
        'low': 5,
        'high': 5,
      });
      await ref.update(<Object, Object?>{
        'n': FieldValue.increment(2),
        'arr': FieldValue.arrayUnion(<Object?>[3]),
        'drop': FieldValue.delete(),
        'at': FieldValue.serverTimestamp(),
        'low': FieldValue.minimum(3),
        'high': FieldValue.maximum(9),
      });
      await ref.update(<Object, Object?>{
        'arr': FieldValue.arrayRemove(<Object?>[1]),
      });
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await ref.get();
      expect(snapshot.get('n'), 3);
      expect(snapshot.get('arr'), <Object?>[2, 3]);
      expect(snapshot.data()!.containsKey('drop'), isFalse);
      expect(snapshot.get('at'), isA<Timestamp>());
      expect(snapshot.get('low'), 3);
      expect(snapshot.get('high'), 9);
    });

    test('value types round trip', () async {
      final DocumentReference<Map<String, dynamic>> ref = root.doc('types');
      final DocumentReference<Map<String, dynamic>> other = root.doc('other');
      final Map<String, Object?> data = <String, Object?>{
        'null': null,
        'bool': true,
        'int': 9007199254740993,
        'double': 1.5,
        'string': 'text \u{1F600}',
        'timestamp': Timestamp(1700000000, 123456000),
        'geo': const GeoPoint(37.7, -122.4),
        'blob': Blob(Uint8List.fromList(<int>[0, 1, 255])),
        'ref': other,
        'vector': const VectorValue(<double>[0.25, 0.5]),
        'list': <Object?>[
          1,
          'a',
          <String, Object?>{'deep': other},
        ],
        'map': <String, Object?>{
          'nested': <String, Object?>{
            'list': <Object?>[Timestamp(1, 0)],
          },
        },
      };
      await ref.set(data);
      await ref.update(<Object, Object?>{'date': DateTime.utc(2026, 11, 16)});
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await ref.get(
        const GetOptions(source: Source.server),
      );
      final Map<String, dynamic> read = snapshot.data()!;
      for (final String key in data.keys) {
        expect(read[key], data[key], reason: key);
      }
      expect(read['ref'], isA<DocumentReference<Map<String, dynamic>>>());
      expect(
        (read['ref'] as DocumentReference<Map<String, dynamic>>).path,
        other.path,
      );
      expect(read['date'], Timestamp.fromDate(DateTime.utc(2026, 11, 16)));

      // A document reference works as a query value.
      final QuerySnapshot<Map<String, dynamic>> byRef = await root
          .where('ref', isEqualTo: other)
          .get();
      expect(byRef.docs.single.id, 'types');
    });

    test('errors are FirebaseExceptions with the official codes', () async {
      await expectLater(
        root.doc('missing').update(<Object, Object?>{'a': 1}),
        throwsA(
          isA<FirebaseException>()
              .having(
                (FirebaseException e) => e.plugin,
                'plugin',
                'cloud_firestore',
              )
              .having((FirebaseException e) => e.code, 'code', 'not-found'),
        ),
      );
      final WriteBatch batch = firestore.batch()
        ..update(root.doc('missing-in-batch'), <String, Object?>{'a': 1});
      await expectLater(
        batch.commit(),
        throwsA(
          isA<FirebaseException>().having(
            (FirebaseException e) => e.code,
            'code',
            'not-found',
          ),
        ),
      );
      expect(
        () => firestore.settings = const Settings(cacheSizeBytes: 2000000),
        throwsA(
          isA<FirebaseException>().having(
            (FirebaseException e) => e.code,
            'code',
            'failed-precondition',
          ),
        ),
      );
    });

    test('network, pending writes, cache reads, snapshotsInSync', () async {
      final DocumentReference<Map<String, dynamic>> ref = root.doc('offline');
      await ref.set(<String, Object?>{'v': 1});
      final Future<void> inSync = firestore.snapshotsInSync().first;
      await inSync.timeout(const Duration(seconds: 10));

      await firestore.disableNetwork();
      final Future<void> write = ref.set(<String, Object?>{'v': 2});
      final DocumentSnapshot<Map<String, dynamic>> cached = await ref.get(
        const GetOptions(source: Source.cache),
      );
      expect(cached.get('v'), 2);
      expect(cached.metadata.hasPendingWrites, isTrue);
      expect(cached.metadata.isFromCache, isTrue);

      // Server timestamps that are not set yet, read with each behaviour.
      final DocumentReference<Map<String, dynamic>> stamped = root.doc(
        'stamped',
      );
      final Future<void> stamp = stamped.set(<String, Object?>{
        'at': FieldValue.serverTimestamp(),
      });
      Future<Object?> readAt(ServerTimestampBehavior behavior) async =>
          (await stamped.get(
            GetOptions(source: Source.cache, serverTimestampBehavior: behavior),
          )).get('at');
      expect(await readAt(ServerTimestampBehavior.none), isNull);
      expect(await readAt(ServerTimestampBehavior.estimate), isA<Timestamp>());
      expect(await readAt(ServerTimestampBehavior.previous), isNull);

      // A listener on the cache only.
      final DocumentSnapshot<Map<String, dynamic>> fromCache = await ref
          .snapshots(source: ListenSource.cache)
          .first;
      expect(fromCache.get('v'), 2);
      expect(fromCache.metadata.isFromCache, isTrue);

      await firestore.enableNetwork();
      await stamp;
      await firestore.waitForPendingWrites();
      await write;
      expect(
        (await ref.get(const GetOptions(source: Source.server))).get('v'),
        2,
      );
    });

    test('loadBundle and namedQueryGet', () async {
      final List<String> elements = <String>[
        '{"namedQuery":{"name":"platform-limit","readTime":{"seconds":1000,"nanos":9999},'
            '"bundledQuery":{"parent":"projects/demo-test/databases/(default)/documents",'
            '"structuredQuery":{"from":[{"collectionId":"platform-bundle"}],"orderBy":'
            '[{"field":{"fieldPath":"bar"},"direction":"DESCENDING"},{"field":'
            '{"fieldPath":"__name__"},"direction":"DESCENDING"}],"limit":'
            '{"value":1}},"limitType":"FIRST"}}}',
        '{"documentMetadata":{"name":'
            '"projects/demo-test/databases/(default)/documents/platform-bundle/a",'
            '"readTime":{"seconds":1000,"nanos":9999},"exists":true}}',
        '{"document":{"name":"projects/demo-test/databases/(default)/documents/platform-bundle/a",'
            '"createTime":{"seconds":1,"nanos":9},"updateTime":{"seconds":1,'
            '"nanos":9},"fields":{"k":{"stringValue":"a"},"bar":'
            '{"integerValue":1}}}}',
        '{"documentMetadata":{"name":'
            '"projects/demo-test/databases/(default)/documents/platform-bundle/b",'
            '"readTime":{"seconds":1000,"nanos":9999},"exists":true}}',
        '{"document":{"name":"projects/demo-test/databases/(default)/documents/platform-bundle/b",'
            '"createTime":{"seconds":1,"nanos":9},"updateTime":{"seconds":1,'
            '"nanos":9},"fields":{"k":{"stringValue":"b"},"bar":'
            '{"integerValue":2}}}}',
      ];
      int length(String s) => utf8.encode(s).length;
      final String body = elements.map((String e) => '${length(e)}$e').join();
      final String metadata =
          '{"metadata":{"id":"platform-bundle","createTime":{"seconds":1001,"nanos":9999},'
          '"version":1,"totalDocuments":2,"totalBytes":${length(body)}}}';
      final Uint8List bundle = Uint8List.fromList(
        utf8.encode('${length(metadata)}$metadata$body'),
      );

      final LoadBundleTask task = firestore.loadBundle(bundle);
      final LoadBundleTaskSnapshot done = await task.stream.last;
      expect(done.taskState, LoadBundleTaskState.success);
      expect(done.documentsLoaded, 2);

      final QuerySnapshot<Map<String, dynamic>> named = await firestore
          .namedQueryGet(
            'platform-limit',
            options: const GetOptions(source: Source.cache),
          );
      expect(named.docs.single.get('k'), 'b');

      await expectLater(
        firestore.namedQueryGet('no-such-query'),
        throwsA(
          isA<FirebaseException>().having(
            (FirebaseException e) => e.code,
            'code',
            'not-found',
          ),
        ),
      );
    });

    test(
      'terminate, then the instance starts again on the next call',
      () async {
        await root.doc('restart').set(<String, Object?>{'v': 1});
        await expectLater(
          firestore.clearPersistence(),
          throwsA(
            isA<FirebaseException>().having(
              (FirebaseException e) => e.code,
              'code',
              'failed-precondition',
            ),
          ),
        );
        await firestore.terminate();
        await firestore.clearPersistence();
        // Settings may change again until the next start.
        firestore.settings = firestore.settings.copyWith(
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
        expect((await root.doc('restart').get()).get('v'), 1);
      },
    );
  });
}

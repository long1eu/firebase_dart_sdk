// What every public entry point that does I/O does on a running instance and
// on a terminated one.
//
// The rule, as upstream (JS: FirestoreError failed-precondition "The client
// has already been terminated."; Android: IllegalStateException with the same
// message):
//
//  * a method that returns a Future never throws synchronously; after
//    terminate the future fails with FirestoreError(failedPrecondition);
//  * a Stream delivers that error as its first event and closes;
//  * a LoadBundleTask fails with it;
//  * builders that do no I/O (collection, doc, batch, where, ...) keep
//    working, so no synchronous API has to throw.
//
// The table is checked against the public API with dart:mirrors: a new public
// member that returns a Future, a Stream or a LoadBundleTask fails the test
// until it is listed here.

import 'dart:async';
import 'dart:convert';
import 'dart:mirrors';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';

const String terminatedMessage = 'The client has already been terminated.';

/// What an entry point does once the instance is terminated.
enum After {
  /// The returned future fails with the terminated error.
  futureFails,

  /// The stream emits the terminated error first and closes.
  streamFails,

  /// The returned [LoadBundleTask] fails with the terminated error.
  taskFails,

  /// The returned future completes normally.
  completes,
}

/// Everything the entries need, created while the instance is running.
class Fixture {
  Fixture(
      this.firestore, this.collection, this.doc, this.docJson, this.queryJson);

  final Firestore firestore;
  final CollectionReference<Map<String, Object?>> collection;
  final DocumentReference<Map<String, Object?>> doc;
  final Map<String, Object?> docJson;
  final Map<String, Object?> queryJson;
}

class Entry {
  const Entry(this.name, this.covers, this.after, this.call);

  final String name;

  /// The `Class.member` names of the public API this entry exercises.
  final Set<String> covers;
  final After after;

  /// Returns a Future, a Stream or a LoadBundleTask. Must not throw.
  final Object Function(Fixture f) call;
}

const Map<String, Object?> _data = <String, Object?>{'a': 1};

/// A bundle with only its metadata element.
List<int> _emptyBundle() {
  const String metadata = '{"metadata":{"id":"terminated-test",'
      '"createTime":{"seconds":1,"nanos":0},"version":1,'
      '"totalDocuments":0,"totalBytes":0}}';
  return utf8.encode('${utf8.encode(metadata).length}$metadata');
}

const String _indexConfiguration = '{"indexes":[{"collectionGroup":"terminated",'
    '"fields":[{"fieldPath":"a","order":"ASCENDING"}]}]}';

final List<Entry> entries = <Entry>[
  // Documents.
  Entry('DocumentReference.get', <String>{'DocumentReference.get'},
      After.futureFails, (Fixture f) => f.doc.get()),
  Entry('DocumentReference.get(Source.cache)', <String>{}, After.futureFails,
      (Fixture f) => f.doc.get(Source.cache)),
  Entry('DocumentReference.get(Source.server)', <String>{}, After.futureFails,
      (Fixture f) => f.doc.get(Source.server)),
  Entry('DocumentReference.set', <String>{'DocumentReference.set'},
      After.futureFails, (Fixture f) => f.doc.set(_data)),
  Entry('DocumentReference.update', <String>{'DocumentReference.update'},
      After.futureFails, (Fixture f) => f.doc.update(_data)),
  Entry(
      'DocumentReference.updateFromList',
      <String>{'DocumentReference.updateFromList'},
      After.futureFails,
      (Fixture f) => f.doc.updateFromList(<Object?>['a', 2])),
  Entry('DocumentReference.delete', <String>{'DocumentReference.delete'},
      After.futureFails, (Fixture f) => f.collection.doc('gone').delete()),
  Entry('CollectionReference.add', <String>{'CollectionReference.add'},
      After.futureFails, (Fixture f) => f.collection.add(_data)),

  // Document listeners.
  Entry('DocumentReference.snapshots', <String>{'DocumentReference.snapshots'},
      After.streamFails, (Fixture f) => f.doc.snapshots),
  Entry(
      'DocumentReference.getSnapshots',
      <String>{'DocumentReference.getSnapshots'},
      After.streamFails,
      (Fixture f) => f.doc.getSnapshots(MetadataChanges.include)),
  Entry(
      'DocumentReference.getSnapshotsWithOptions',
      <String>{'DocumentReference.getSnapshotsWithOptions'},
      After.streamFails,
      (Fixture f) => f.doc.getSnapshotsWithOptions(
          const SnapshotListenOptions(source: ListenSource.cache))),

  // Queries.
  Entry('Query.get', <String>{'Query.get'}, After.futureFails,
      (Fixture f) => f.collection.where('a', isEqualTo: 1).get()),
  Entry('Query.get(Source.cache)', <String>{}, After.futureFails,
      (Fixture f) => f.collection.get(Source.cache)),
  Entry('Query.get(Source.server)', <String>{}, After.futureFails,
      (Fixture f) => f.collection.get(Source.server)),
  Entry('Query.snapshots', <String>{'Query.snapshots'}, After.streamFails,
      (Fixture f) => f.collection.snapshots),
  Entry('Query.getSnapshots', <String>{'Query.getSnapshots'}, After.streamFails,
      (Fixture f) => f.collection.limit(1).getSnapshots()),
  Entry(
      'Query.getSnapshotsWithOptions',
      <String>{'Query.getSnapshotsWithOptions'},
      After.streamFails,
      (Fixture f) =>
          f.collection.getSnapshotsWithOptions(const SnapshotListenOptions())),
  Entry('AggregateQuery.get', <String>{'AggregateQuery.get'}, After.futureFails,
      (Fixture f) => f.collection.count().get()),
  Entry(
      'VectorQuery.get',
      <String>{'VectorQuery.get'},
      After.futureFails,
      (Fixture f) => f.collection
          .findNearest('embedding', FieldValue.vector(<double>[1, 2]), 1,
              DistanceMeasure.euclidean)
          .get()),
  // On the standard edition emulator a pipeline is rejected by the server
  // while the instance runs; that is still not the terminated error.
  Entry(
      'Pipeline.execute',
      <String>{'Pipeline.execute'},
      After.futureFails,
      (Fixture f) =>
          f.firestore.pipeline().collection(f.collection.path).execute()),

  // Batches and transactions.
  Entry('WriteBatch.commit', <String>{'WriteBatch.commit'}, After.futureFails,
      (Fixture f) => (f.firestore.batch()..set(f.doc, _data)).commit()),
  // As upstream (JS and Android): a batch without writes never reaches the
  // client, so committing it completes.
  Entry('WriteBatch.commit (empty)', <String>{}, After.completes,
      (Fixture f) => f.firestore.batch().commit()),
  Entry(
      'Firestore.runBatch',
      <String>{'Firestore.runBatch'},
      After.futureFails,
      (Fixture f) => f.firestore
          .runBatch((WriteBatch batch) async => batch.set(f.doc, _data))),
  Entry(
      'Firestore.runTransaction',
      <String>{'Firestore.runTransaction', 'Transaction.get'},
      After.futureFails,
      (Fixture f) =>
          f.firestore.runTransaction<void>((Transaction transaction) async {
            await transaction.get(f.doc);
            transaction.set(f.doc, _data);
          })),
  Entry(
      'Firestore.runTransaction (read-only)',
      <String>{},
      After.futureFails,
      (Fixture f) => f.firestore.runTransaction<void>(
          (Transaction transaction) => transaction.get(f.doc),
          options: TransactionOptions(readOnly: true))),

  // Bundles and snapshot JSON.
  Entry(
      'Firestore.loadBundle',
      <String>{
        'Firestore.loadBundle',
        'LoadBundleTask.future',
        'LoadBundleTask.stream'
      },
      After.taskFails,
      (Fixture f) => f.firestore.loadBundle(_emptyBundle())),
  Entry(
      'Firestore.loadBundleStream',
      <String>{'Firestore.loadBundleStream'},
      After.taskFails,
      (Fixture f) => f.firestore.loadBundleStream(
          Stream<List<int>>.fromIterable(<List<int>>[_emptyBundle()]))),
  Entry('Firestore.getNamedQuery', <String>{'Firestore.getNamedQuery'},
      After.futureFails, (Fixture f) => f.firestore.getNamedQuery('missing')),
  Entry(
      'Firestore.documentSnapshotsFromJson',
      <String>{'Firestore.documentSnapshotsFromJson'},
      After.streamFails,
      (Fixture f) => f.firestore
          .documentSnapshotsFromJson<Map<String, Object?>>(f.docJson)),
  Entry(
      'Firestore.querySnapshotsFromJson',
      <String>{'Firestore.querySnapshotsFromJson'},
      After.streamFails,
      (Fixture f) => f.firestore
          .querySnapshotsFromJson<Map<String, Object?>>(f.queryJson)),

  // Instance.
  Entry(
      'Firestore.waitForPendingWrites',
      <String>{'Firestore.waitForPendingWrites'},
      After.futureFails,
      (Fixture f) => f.firestore.waitForPendingWrites()),
  Entry('Firestore.snapshotsInSync', <String>{'Firestore.snapshotsInSync'},
      After.streamFails, (Fixture f) => f.firestore.snapshotsInSync),
  Entry('Firestore.disableNetwork', <String>{'Firestore.disableNetwork'},
      After.futureFails, (Fixture f) => f.firestore.disableNetwork()),
  Entry('Firestore.enableNetwork', <String>{'Firestore.enableNetwork'},
      After.futureFails, (Fixture f) => f.firestore.enableNetwork()),

  // Persistent cache indexes. The getter of the manager keeps working after
  // terminate (see the test below); its methods fail.
  Entry(
      'Firestore.setIndexConfiguration',
      <String>{'Firestore.setIndexConfiguration'},
      After.futureFails,
      // ignore: deprecated_member_use_from_same_package
      (Fixture f) => f.firestore.setIndexConfiguration(_indexConfiguration)),
  Entry(
      'PersistentCacheIndexManager.enableIndexAutoCreation',
      <String>{'PersistentCacheIndexManager.enableIndexAutoCreation'},
      After.futureFails,
      (Fixture f) =>
          f.firestore.persistentCacheIndexManager!.enableIndexAutoCreation()),
  Entry(
      'PersistentCacheIndexManager.disableIndexAutoCreation',
      <String>{'PersistentCacheIndexManager.disableIndexAutoCreation'},
      After.futureFails,
      (Fixture f) =>
          f.firestore.persistentCacheIndexManager!.disableIndexAutoCreation()),
  Entry(
      'PersistentCacheIndexManager.deleteAllIndexes',
      <String>{'PersistentCacheIndexManager.deleteAllIndexes'},
      After.futureFails,
      (Fixture f) =>
          f.firestore.persistentCacheIndexManager!.deleteAllIndexes()),
];

/// Public members that return a Future, Stream or LoadBundleTask and are not
/// in [entries], with the reason.
const Map<String, String> exempt = <String, String>{
  'Firestore.instanceFor': 'static: creates an instance',
  'Firestore.getInstance': 'static: creates an instance',
  'Firestore.terminate': 'tested below: completes, also when repeated',
  'Firestore.shutdown': 'deprecated alias of terminate, tested below',
  'Firestore.clearPersistence':
      'tested below: fails while running, completes after terminate',
  'LoadBundleTask.addOnProgressListener': 'returns the task itself, no I/O',
  'Database.execute': 'implemented by the user of the package',
  'Database.query': 'implemented by the user of the package',
  'Database.delete': 'implemented by the user of the package',
  'ClearableDatabase.clearStorage': 'implemented by the user of the package',
};

/// `Class.member` of every public, non-internal member of the exported
/// classes (and of the pipelines library) that returns a Future, a Stream or
/// a LoadBundleTask.
Set<String> publicIoMembers() {
  final Set<String> result = <String>{};
  for (final Symbol library in <Symbol>[
    #cloud_firestore_dart,
    #cloud_firestore_dart.pipelines
  ]) {
    final LibraryMirror barrel = currentMirrorSystem().findLibrary(library);
    for (final LibraryDependencyMirror dep in barrel.libraryDependencies) {
      if (!dep.isExport) {
        continue;
      }
      final Iterable<CombinatorMirror> shows =
          dep.combinators.where((CombinatorMirror c) => c.isShow);
      for (final ClassMirror cls
          in dep.targetLibrary!.declarations.values.whereType<ClassMirror>()) {
        final bool shown = shows.isEmpty ||
            shows.any(
                (CombinatorMirror c) => c.identifiers.contains(cls.simpleName));
        final bool hidden = dep.combinators.any((CombinatorMirror c) =>
            c.isHide && c.identifiers.contains(cls.simpleName));
        if (!shown || hidden || cls.isPrivate) {
          continue;
        }
        for (final MethodMirror method
            in cls.declarations.values.whereType<MethodMirror>()) {
          final String returns =
              MirrorSystem.getName(method.returnType.simpleName);
          final bool internal = method.metadata.any((InstanceMirror m) =>
              m.reflectee.runtimeType.toString() == '_Internal');
          if (method.isPrivate ||
              method.isConstructor ||
              internal ||
              !const <String>{'Future', 'Stream', 'LoadBundleTask'}
                  .contains(returns)) {
            continue;
          }
          result.add('${MirrorSystem.getName(cls.simpleName)}.'
              '${MirrorSystem.getName(method.simpleName)}');
        }
      }
    }
  }
  return result;
}

bool isTerminatedError(Object? error) =>
    error is FirestoreError &&
    error.code == FirestoreErrorCode.failedPrecondition &&
    error.message == terminatedMessage;

final Matcher throwsTerminated = throwsA(predicate<Object?>(isTerminatedError,
    'FirestoreError(failedPrecondition, "$terminatedMessage")'));

/// The outcome of [call]: `null` if it completed (a stream: delivered an
/// event), otherwise the error. A synchronous throw fails the test.
Future<Object?> outcome(Entry entry, Fixture fixture) async {
  final Object result;
  try {
    result = entry.call(fixture);
  } catch (e) {
    fail('${entry.name} threw synchronously: $e');
  }

  Future<void> future;
  if (result is LoadBundleTask) {
    future = result.future;
  } else if (result is Stream) {
    final Completer<void> first = Completer<void>();
    late final StreamSubscription<Object?> subscription;
    subscription = result.listen((Object? _) {
      if (!first.isCompleted) {
        first.complete();
      }
    }, onError: (Object e, StackTrace s) {
      if (!first.isCompleted) {
        first.completeError(e, s);
      }
    }, onDone: () {
      if (!first.isCompleted) {
        first.completeError(StateError('closed without an event'));
      }
    });
    future = first.future.whenComplete(subscription.cancel);
  } else {
    future = result as Future<Object?>;
  }

  try {
    await future.timeout(const Duration(seconds: 20));
    return null;
  } catch (e) {
    return e;
  }
}

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/terminated_instance';

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  Future<Fixture> newFixture() async {
    final Firestore firestore = await IntegrationTestUtil.testFirestore();
    final CollectionReference<Map<String, Object?>> collection = firestore
        .collection('terminated-${DateTime.now().microsecondsSinceEpoch}');
    final DocumentReference<Map<String, Object?>> doc = collection.doc('doc');
    await doc.set(_data);
    return Fixture(
      firestore,
      collection,
      doc,
      jsonDecode(jsonEncode((await doc.get()).toJson()))
          as Map<String, Object?>,
      jsonDecode(jsonEncode((await collection.get()).toJson()))
          as Map<String, Object?>,
    );
  }

  test('the table lists every public member that does I/O', () {
    final Set<String> covered = <String>{
      for (final Entry entry in entries) ...entry.covers,
      ...exempt.keys,
    };
    final Set<String> public = publicIoMembers();
    expect(public.difference(covered), isEmpty,
        reason: 'Add these members to `entries` (or to `exempt`).');
    expect(covered.difference(public), isEmpty,
        reason: 'These are listed but no longer part of the public API.');
  });

  group('on a running instance', () {
    late Fixture fixture;

    setUp(() async {
      fixture = await newFixture();
    });

    for (final Entry entry in entries) {
      test('${entry.name} does not report termination', () async {
        final Object? error = await outcome(entry, fixture);
        expect(isTerminatedError(error), isFalse, reason: '$error');
        // Pipelines need an Enterprise edition database, and a vector query
        // an index the emulator may not have: the server answers, which is
        // all this row is about. Everything else has to succeed.
        if (!const <String>{'Pipeline.execute', 'VectorQuery.get'}
            .contains(entry.name)) {
          expect(error, isNull);
        }
      });
    }

    test('clearPersistence fails with failedPrecondition', () async {
      await expectLater(
          fixture.firestore.clearPersistence(),
          throwsA(isA<FirestoreError>().having((FirestoreError e) => e.code,
              'code', FirestoreErrorCode.failedPrecondition)));
    });
  });

  group('on a terminated instance', () {
    late Fixture fixture;

    setUp(() async {
      fixture = await newFixture();
      await fixture.firestore.terminate();
    });

    for (final Entry entry in entries) {
      test('${entry.name}: ${entry.after.name}', () async {
        final Object? error = await outcome(entry, fixture);
        switch (entry.after) {
          case After.futureFails:
          case After.streamFails:
          case After.taskFails:
            expect(isTerminatedError(error), isTrue,
                reason: 'Expected the terminated error, got: $error');
          case After.completes:
            expect(error, isNull);
        }
      });
    }

    test('a stream closes after the error', () async {
      final List<Object> errors = <Object>[];
      final Completer<void> done = Completer<void>();
      fixture.doc.snapshots.listen((_) {},
          onError: (Object e) => errors.add(e), onDone: done.complete);
      await done.future.timeout(const Duration(seconds: 20));
      expect(errors, hasLength(1));
      expect(isTerminatedError(errors.single), isTrue);
    });

    test('a bundle task reports the error to its listeners', () async {
      final LoadBundleTask task = fixture.firestore.loadBundle(_emptyBundle());
      await expectLater(task.future, throwsTerminated);
      expect(task.isComplete, isTrue);
      expect(task.isSuccessful, isFalse);
      expect(isTerminatedError(task.exception), isTrue);
    });

    test('terminate and shutdown can be repeated', () async {
      await fixture.firestore.terminate();
      // ignore: deprecated_member_use_from_same_package
      await fixture.firestore.shutdown();
    });

    test('clearPersistence completes', () async {
      await fixture.firestore.clearPersistence();
    });

    test('persistentCacheIndexManager is still the manager of the instance',
        () async {
      final Fixture running = await newFixture();
      final PersistentCacheIndexManager? manager =
          running.firestore.persistentCacheIndexManager;
      expect(manager, isNotNull);
      await running.firestore.terminate();
      expect(running.firestore.persistentCacheIndexManager, same(manager));
      await expectLater(manager!.deleteAllIndexes(), throwsTerminated);
    });

    test('setIndexConfiguration reports termination before a bad definition',
        () async {
      await expectLater(
          // ignore: deprecated_member_use_from_same_package
          fixture.firestore.setIndexConfiguration('not json'),
          throwsTerminated);
    });

    test('builders that do no I/O keep working', () {
      final Firestore firestore = fixture.firestore;
      expect(firestore.collection('a').doc('b').path, 'a/b');
      expect(firestore.doc('a/b').parent.id, 'a');
      expect(firestore.collectionGroup('a').where('x', isEqualTo: 1).limit(1),
          isNotNull);
      expect(firestore.batch()..set(fixture.doc, _data), isNotNull);
      expect(fixture.collection.count(), isNotNull);
      expect(firestore.pipeline().collection('a'), isNotNull);
      expect(firestore.projectId, isNotEmpty);
    });
  });

  test('a transaction that is running when the instance is terminated fails',
      () async {
    final Fixture fixture = await newFixture();
    await expectLater(
        fixture.firestore.runTransaction<void>((Transaction transaction) async {
      await fixture.firestore.terminate();
      await transaction.get(fixture.doc);
    }), throwsA(isA<FirestoreError>()));
  });
}

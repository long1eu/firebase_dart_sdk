// The costs of the key-value cache that grow with the size of the cache, over the SQLite example store
// (example/cache_store/sqlite): the pending write count with 10,000 pending writes, and the passes of the LRU garbage
// collector over 100,000 cached documents (90,000 held by 90 targets, 10,000 that no target holds any more).
//
//   cd tool/bench && dart run cache_store_costs_bench.dart [<directory>]

import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';

import '../../cloud_firestore/cloud_firestore_dart/example/cache_store/sqlite/sqlite_cache_store.dart';

const int targets = 100;
const int docsPerTarget = 1000;
const int orphanTargets = 10;
const int pendingWrites = 10000;
final DatabaseId databaseId = DatabaseId.forProject('bench');
final String payload = 'x' * 200;

ObjectValue dataOf(int i) => ObjectValue.fromMap(<String, FieldValue>{
      'a': IntegerValue.valueOf(i % 100),
      'payload': StringValue.valueOf(payload),
    });

SnapshotVersion version(int seconds) => SnapshotVersion(Timestamp(seconds, 0));

String stats(List<double> values) {
  final List<double> sorted = values.toList()..sort();
  return 'median ${sorted[sorted.length ~/ 2].toStringAsFixed(1)} ms, '
      'min ${sorted.first.toStringAsFixed(1)} ms';
}

Future<List<double>> measure(int rounds, Future<void> Function() body) async {
  final List<double> times = <double>[];
  for (int round = 0; round <= rounds; round++) {
    final Stopwatch sw = Stopwatch()..start();
    await body();
    if (round > 0) {
      times.add(sw.elapsedMicroseconds / 1000);
    }
  }
  return times;
}

TargetChange change({
  ImmutableSortedSet<DocumentKey>? added,
  ImmutableSortedSet<DocumentKey>? removed,
}) =>
    TargetChange(
      resumeToken: Uint8List.fromList(<int>[1, 2, 3]),
      current: true,
      addedDocuments: added ?? DocumentKey.emptyKeySet,
      modifiedDocuments: DocumentKey.emptyKeySet,
      removedDocuments: removed ?? DocumentKey.emptyKeySet,
    );

Future<void> main(List<String> args) async {
  final Directory directory = args.isEmpty
      ? Directory.systemTemp.createTempSync('cache_store_costs_')
      : Directory(args.first);
  final String path = '${directory.path}/costs.db';
  for (final String suffix in <String>['', '-wal', '-shm']) {
    final File file = File('$path$suffix');
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
  CacheStorePersistence open() => CacheStorePersistence(
        SqliteCacheStore(path),
        databaseId: databaseId,
        serializer: LocalSerializer(RemoteSerializer(databaseId)),
        lruParams: const LruGarbageCollectorParams(
          minBytesThreshold: 1,
          percentileToCollect: 10,
          maximumSequenceNumbersToCollect: 1000,
        ),
      );
  CacheStorePersistence persistence = open();
  await persistence.start();
  LocalStore store = LocalStore(persistence, User.unauthenticated);
  await store.start();

  final Stopwatch fill = Stopwatch()..start();
  int seconds = 1000;
  for (int t = 0; t < targets; t++) {
    final QueryData target = await store.allocateTarget(
      Query(ResourcePath.fromString('t$t')).toTarget(),
    );
    final Map<DocumentKey, MaybeDocument> updates =
        <DocumentKey, MaybeDocument>{};
    ImmutableSortedSet<DocumentKey> added = DocumentKey.emptyKeySet;
    for (int i = 0; i < docsPerTarget; i++) {
      final DocumentKey key = DocumentKey.fromPathString(
        't$t/doc${i.toString().padLeft(5, '0')}',
      );
      updates[key] = Document(
        key,
        version(seconds),
        DocumentState.synced,
        dataOf(i),
      );
      added = added.insert(key);
    }
    seconds++;
    await store.applyRemoteEvent(
      RemoteEvent(
        documentUpdates: updates,
        resolvedLimboDocuments: const <DocumentKey>{},
        snapshotVersion: version(seconds++),
        targetChanges: <int, TargetChange>{
          target.targetId: change(added: added),
        },
      ),
    );
    if (t >= targets - orphanTargets) {
      // The documents leave the target: no target holds them, only their sentinel.
      await store.applyRemoteEvent(
        RemoteEvent(
          documentUpdates: const <DocumentKey, MaybeDocument>{},
          resolvedLimboDocuments: const <DocumentKey>{},
          snapshotVersion: version(seconds++),
          targetChanges: <int, TargetChange>{
            target.targetId: change(removed: added),
          },
        ),
      );
    }
    await store.releaseTarget(target.targetId);
  }
  print(
    'fill: ${targets * docsPerTarget} documents in $targets targets: '
    '${fill.elapsedMilliseconds} ms',
  );

  fill.reset();
  for (int i = 0; i < pendingWrites; i++) {
    await store.writeLocally(<Mutation>[
      SetMutation(
        DocumentKey.fromPathString('w/doc$i'),
        dataOf(i),
        Precondition.none,
      ),
    ]);
  }
  print(
    'fill: $pendingWrites pending writes: ${fill.elapsedMilliseconds} ms',
  );

  print(
    'getPendingWriteCount with $pendingWrites pending writes: '
    '${stats(await measure(10, () async {
      if (await store.getPendingWriteCount() < pendingWrites) {
        throw StateError('count');
      }
    }))}',
  );
  print(
    'one more write with $pendingWrites pending writes: '
    '${stats(await measure(50, () async {
      await store.writeLocally(<Mutation>[
        SetMutation(
            DocumentKey.fromPathString('x/doc'), dataOf(1), Precondition.none),
      ]);
    }))}',
  );

  final LruGarbageCollector gc = persistence.garbageCollector;
  print(
    'GC, count of sequence numbers: '
    '${stats(await measure(5, () => persistence.runTransaction('count', () async {
          await gc.calculateQueryCount(10);
        })))}',
  );
  print(
    'GC, nth sequence number: '
    '${stats(await measure(5, () => persistence.runTransaction('nth', () async {
          await gc.getNthSequenceNumber(1000);
        })))}',
  );
  print(
    'GC, orphan pass that removes nothing: '
    '${stats(await measure(5, () => persistence.runTransaction('orphans', () async {
          await gc.removeOrphanedDocuments(0);
        })))}',
  );
  final Stopwatch collect = Stopwatch()..start();
  final LruGarbageCollectorResults results = await store.collectGarbage(gc);
  print(
    'GC, one collection: ${collect.elapsedMilliseconds} ms '
    '(${results.targetsRemoved} targets, ${results.documentsRemoved} documents removed)',
  );

  await persistence.shutdown();
  final Stopwatch restart = Stopwatch()..start();
  persistence = open();
  await persistence.start();
  store = LocalStore(persistence, User.unauthenticated);
  await store.start();
  print('restart: ${restart.elapsedMilliseconds} ms');
  final Stopwatch firstCount = Stopwatch()..start();
  final int count = await store.getPendingWriteCount();
  print(
    'first getPendingWriteCount after the restart ($count pending writes, reads every batch): '
    '${(firstCount.elapsedMicroseconds / 1000).toStringAsFixed(1)} ms',
  );
  await persistence.shutdown();
  if (args.isEmpty) {
    directory.deleteSync(recursive: true);
  }
}

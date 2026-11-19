// The key-value cache over the SQLite example store (example/cache_store/sqlite): one local write, a read by key and a
// read of a whole collection of 20,000 documents, warm, through the local store.
//
//   cd tool/bench && dart run cache_store_bench.dart [<directory>]

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
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

const int docs = 20000;
final DatabaseId databaseId = DatabaseId.forProject('bench');
final String payload = 'x' * 200;

DocumentKey keyOf(int i) =>
    DocumentKey.fromPathString('c0/doc${i.toString().padLeft(6, '0')}');

ObjectValue dataOf(int i) => ObjectValue.fromMap(<String, FieldValue>{
      'a': IntegerValue.valueOf(i % 100),
      'payload': StringValue.valueOf(payload),
    });

SnapshotVersion version(int seconds) => SnapshotVersion(Timestamp(seconds, 0));

/// The median and the minimum: on a busy machine the minimum is the steadier of the two.
String stats(List<double> values, int digits) {
  final List<double> sorted = values.toList()..sort();
  return 'median ${sorted[sorted.length ~/ 2].toStringAsFixed(digits)}, '
      'min ${sorted.first.toStringAsFixed(digits)}';
}

Future<void> main(List<String> args) async {
  final Directory directory = args.isEmpty
      ? Directory.systemTemp.createTempSync('cache_store_bench_')
      : Directory(args.first);
  final String path = '${directory.path}/bench.db';
  for (final String suffix in <String>['', '-wal', '-shm']) {
    final File file = File('$path$suffix');
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
  final CacheStorePersistence persistence = CacheStorePersistence(
    SqliteCacheStore(path),
    databaseId: databaseId,
    serializer: LocalSerializer(RemoteSerializer(databaseId)),
    lruParams: const LruGarbageCollectorParams(),
  );
  await persistence.start();
  final LocalStore store = LocalStore(persistence, User.unauthenticated);
  await store.start();

  // 20,000 acknowledged documents, delivered in remote events of 1,000.
  final Stopwatch fill = Stopwatch()..start();
  final target = await store.allocateTarget(
    Query(ResourcePath.fromString('seed')).toTarget(),
  );
  for (int start = 0; start < docs; start += 1000) {
    final Map<DocumentKey, MaybeDocument> updates =
        <DocumentKey, MaybeDocument>{};
    ImmutableSortedSet<DocumentKey> added = DocumentKey.emptyKeySet;
    for (int i = start; i < start + 1000; i++) {
      updates[keyOf(i)] = Document(
        keyOf(i),
        version(1000 + start),
        DocumentState.synced,
        dataOf(i),
      );
      added = added.insert(keyOf(i));
    }
    await store.applyRemoteEvent(
      RemoteEvent(
        documentUpdates: updates,
        resolvedLimboDocuments: const <DocumentKey>{},
        snapshotVersion: version(1001 + start),
        targetChanges: <int, TargetChange>{
          target.targetId: TargetChange(
            resumeToken: Uint8List.fromList(<int>[1, 2, 3]),
            current: true,
            addedDocuments: added,
            modifiedDocuments: DocumentKey.emptyKeySet,
            removedDocuments: DocumentKey.emptyKeySet,
          ),
        },
      ),
    );
  }
  print(
      'fill: 20 remote events of 1,000 documents: ${fill.elapsedMilliseconds} ms');

  // Read by key: 1,000 random documents, 10 rounds after one dropped; per read.
  final Random random = Random(7);
  final List<DocumentKey> keys = <DocumentKey>[
    for (int i = 0; i < 1000; i++) keyOf(random.nextInt(docs)),
  ];
  final List<double> reads = <double>[];
  for (int round = 0; round < 11; round++) {
    final Stopwatch sw = Stopwatch()..start();
    for (final DocumentKey key in keys) {
      if (await store.readDocument(key) == null) {
        throw StateError('missing $key');
      }
    }
    if (round > 0) {
      reads.add(sw.elapsedMicroseconds / keys.length);
    }
  }

  // The whole collection: 15 reads after one dropped.
  final List<double> wholes = <double>[];
  for (int round = 0; round < 16; round++) {
    final Stopwatch sw = Stopwatch()..start();
    final int count =
        (await store.executeQuery(Query(ResourcePath.fromString('c0')), true))
            .documents
            .length;
    if (count != docs) {
      throw StateError('read $count documents');
    }
    if (round > 0) {
      wholes.add(sw.elapsedMicroseconds / 1000);
    }
  }

  // One write: 500 local writes of one document (to its own collection, so the whole read above is unchanged).
  final List<double> writes = <double>[];
  for (int i = 0; i < 520; i++) {
    final Stopwatch sw = Stopwatch()..start();
    await store.writeLocally(<Mutation>[
      SetMutation(
        DocumentKey.fromPathString('w/doc$i'),
        dataOf(i),
        Precondition.none,
      ),
    ]);
    if (i >= 20) {
      writes.add(sw.elapsedMicroseconds / 1000);
    }
  }

  print('one write, 500 times (ms): ${stats(writes, 3)}');
  print('read by key, 10 rounds of 1,000 (us per read): ${stats(reads, 1)}');
  print('whole collection of $docs, 15 times (ms): ${stats(wholes, 1)}');
  await persistence.shutdown();
  if (args.isEmpty) {
    directory.deleteSync(recursive: true);
  }
}

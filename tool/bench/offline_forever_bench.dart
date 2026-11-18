// "A year offline": a SQLite cache in which every document is a pending write that the backend never acknowledged
// (it exists only in the mutation queue and as an overlay; the remote document cache is empty). Measures what grows
// with the number of pending writes. Results and discussion: docs/spikes/offline_forever.md.
//
// The first two modes call the local store directly, as local_store_bench.dart does (no backend, SQLite with
// `synchronous = OFF`); the drain modes use the public API against a Firestore emulator.
//
//   dart run offline_forever_bench.dart pending <documents> <shape> [--index] [--ack] [<directory>]
//     shape: c1k (collections of 1,000), c100k (collections of 100,000), small (collections of 10, all named
//     `items`, below `s/p<i>`). One write per batch (a set), the collection of each write picked at random.
//     --index configures cache indexes, fills them and queries again. --ack then acknowledges every batch, puts the
//     queried collections in sync once (a remote event, as after a listen) and reads again: the "mixed" case.
//     --forget-batch-keys drops the keys the local store keeps in memory for every written batch (a memory check).
//     --fill-once stops after the first index fill run. --no-group skips the collection group queries.
//   dart run offline_forever_bench.dart hot <updates> [--transform] [<directory>]
//     One document, set once and then updated <updates> times (with --transform each update also sets a
//     serverTimestamp field). Reads, queries, one rejection, then acknowledgements.
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8391 dart run offline_forever_bench.dart drain <documents> [<directory>]
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8391 dart run offline_forever_bench.dart drainhot <updates> [--transform] [<directory>]
//     Public API: writes offline (network disabled), then enables the network and times waitForPendingWrites.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as api;
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/index_backfiller.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_view_changes.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/server_timestamp_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

import 'local_store_bench.dart'
    show BenchDatabase, keys, openPersistence, record, results, version;

final Random random = Random(42);
const String _alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

/// A random 20 character id, like the ids of `CollectionReference.doc()`.
String autoId() => String.fromCharCodes(<int>[
      for (int i = 0; i < 20; i++)
        _alphabet.codeUnitAt(random.nextInt(_alphabet.length)),
    ]);

FieldPath f(String name) => FieldPath.fromSingleSegment(name);
double mb(int bytes) => bytes / (1024 * 1024);
final String payload = 'x' * 200;

/// The size of the database file and its write-ahead log.
int fileSize(String file) {
  int total = 0;
  for (final String suffix in <String>['', '-wal', '-journal']) {
    final File f = File('$file$suffix');
    if (f.existsSync()) {
      total += f.lengthSync();
    }
  }
  return total;
}

void deleteFiles(String file) {
  for (final String suffix in <String>['', '-journal', '-wal', '-shm']) {
    final File f = File('$file$suffix');
    if (f.existsSync()) {
      f.deleteSync();
    }
  }
}

ObjectValue dataOf(int i) => ObjectValue.fromMap(<String, FieldValue>{
      'a': IntegerValue.valueOf(i % 100),
      'order': IntegerValue.valueOf(random.nextInt(1 << 30)),
      'payload': StringValue.valueOf(payload),
    });

/// Median in milliseconds of [reps] runs of a query; records it with the number of results and the growth of the
/// resident memory during the first run.
Future<void> timeQuery(String name, LocalStore store, Query query,
    {bool previous = true, int reps = 3}) async {
  final List<double> times = <double>[];
  int size = 0;
  final int rssBefore = ProcessInfo.currentRss;
  int rssAfterFirst = rssBefore;
  for (int i = 0; i < reps; i++) {
    final Stopwatch sw = Stopwatch()..start();
    size = (await store.executeQuery(query, previous)).documents.length;
    times.add(sw.elapsedMicroseconds / 1000);
    if (i == 0) {
      rssAfterFirst = ProcessInfo.currentRss;
      if (times.first > 5000) {
        break; // one run is enough (and all there is time for)
      }
    }
  }
  final double first = times.first;
  times.sort();
  record(name, times[times.length ~/ 2], 'ms',
      '$size results, first run ${first.toStringAsFixed(1)} ms, rss +${mb(rssAfterFirst - rssBefore).toStringAsFixed(0)} MB');
}

Future<void> main(List<String> args) async {
  final List<String> flags =
      args.where((String a) => a.startsWith('--')).toList();
  final List<String> positional =
      args.where((String a) => !a.startsWith('--')).toList();
  final String mode = positional[0];
  final int n = int.parse(positional[1]);
  switch (mode) {
    case 'pending':
      await pending(n, positional[2], flags,
          positional.length > 3 ? positional[3] : Directory.systemTemp.path);
    case 'hot':
      await hot(n, flags.contains('--transform'),
          positional.length > 2 ? positional[2] : Directory.systemTemp.path);
    case 'drain':
    case 'drainhot':
      await drain(mode == 'drainhot', n, flags.contains('--transform'),
          positional.length > 2 ? positional[2] : Directory.systemTemp.path);
    default:
      throw ArgumentError('unknown mode $mode');
  }
  record('peak resident set size of the process', mb(ProcessInfo.maxRss), 'MB');
  print('\n=== offline_forever_bench ${args.join(' ')} ===');
  results.forEach(print);
}

// ---------------------------------------------------------------------------------------------------------------------
// pending

Future<void> pending(
    int n, String shape, List<String> flags, String dir) async {
  final int collectionSize = switch (shape) {
    'c1k' => 1000,
    'c100k' => 100000,
    'small' => 10,
    _ => throw ArgumentError('shape: c1k, c100k or small'),
  };
  final int collections = max(1, (n / collectionSize).ceil());
  ResourcePath collectionPath(int c) => shape == 'small'
      ? ResourcePath.fromSegments(<String>['s', 'p$c', 'items'])
      : ResourcePath.fromString('c$c');
  final String file = '$dir/offline_forever_${shape}_$n.db';
  deleteFiles(file);
  print(
      'pending: $n documents, collections of $collectionSize ($collections collections), $file');

  SQLitePersistence persistence = await openPersistence(file);
  LocalStore store = LocalStore(persistence, User.unauthenticated);
  await store.start();

  // --- Writes: one set per batch, a random collection each time. A tiny collection of 10 is written at the middle.
  final ResourcePath tiny = ResourcePath.fromString('tiny');
  final bool forgetBatchKeys = flags.contains('--forget-batch-keys');
  final List<DocumentKey> sample = <DocumentKey>[];
  int c0Count = 0;
  const int window = 1000;
  final int report = max(window, n ~/ 10);
  record('resident memory before the writes', mb(ProcessInfo.currentRss), 'MB');
  final Stopwatch total = Stopwatch()..start();
  Stopwatch sw = Stopwatch()..start();
  Stopwatch windowSw = Stopwatch();
  for (int i = 0; i < n; i++) {
    if (i == n ~/ 2) {
      for (int t = 0; t < 10; t++) {
        await store.writeLocally(<Mutation>[
          SetMutation(DocumentKey.fromPath(tiny.appendSegment(autoId())),
              dataOf(t), Precondition.none)
        ]);
      }
    }
    final int c = random.nextInt(collections);
    if (c == 0) {
      c0Count++;
    }
    final DocumentKey key =
        DocumentKey.fromPath(collectionPath(c).appendSegment(autoId()));
    // Reservoir sample of 1,000 keys for the reads by key.
    if (sample.length < 1000) {
      sample.add(key);
    } else if (random.nextInt(i + 1) < 1000) {
      sample[random.nextInt(1000)] = key;
    }
    final int batchId = (await store.writeLocally(
            <Mutation>[SetMutation(key, dataOf(i), Precondition.none)]))
        .batchId;
    if (forgetBatchKeys) {
      // Drops what the local store keeps in memory per written batch (see the spike document).
      store.removeCachedMutationBatchMetadata(batchId);
    }
    if (i == window - 1 || i == n - window - 1) {
      windowSw = Stopwatch()..start();
    }
    if (i + 1 == 2 * window) {
      record('write, at the start (writes 1,001 to 2,000)',
          windowSw.elapsedMicroseconds / window, 'us/write');
    }
    if ((i + 1) % report == 0) {
      print(
          '  ${i + 1} written, ${(sw.elapsedMicroseconds / report).toStringAsFixed(0)} us/write over the last '
          '$report, rss ${mb(ProcessInfo.currentRss).toStringAsFixed(0)} MB, file ${mb(fileSize(file)).toStringAsFixed(0)} MB');
      sw = Stopwatch()..start();
    }
  }
  record('write, at the end (last 1,000)',
      windowSw.elapsedMicroseconds / window, 'us/write');
  record('write, all ($n)', total.elapsedMicroseconds / n, 'us/write',
      '${(total.elapsedMilliseconds / 1000).toStringAsFixed(0)} s');
  record('resident memory after the writes', mb(ProcessInfo.currentRss), 'MB');
  record('file size (database + WAL)', mb(fileSize(file)), 'MB');

  // --- Reopen.
  await persistence.shutdown();
  record('file size after close (checkpointed)', mb(fileSize(file)), 'MB');
  sw = Stopwatch()..start();
  persistence = await openPersistence(file);
  store = LocalStore(persistence, User.unauthenticated);
  await store.start();
  record('reopen (open the file, start the local store)',
      sw.elapsedMicroseconds / 1000, 'ms', '${n + 10} pending batches');
  record('resident memory after reopen', mb(ProcessInfo.currentRss), 'MB');

  // --- Queries. For the big shapes on collection c0; for the small shape on the collection group `items`.
  final Query base = shape == 'small'
      ? Query(ResourcePath.empty, collectionGroup: 'items')
      : Query(collectionPath(0));
  final String where = shape == 'small'
      ? 'collection group items ($n documents in $collections collections)'
      : 'c0 ($c0Count documents)';
  final Query equality = base.filter(
      FieldFilter(f('a'), FilterOperator.equal, IntegerValue.valueOf(7)));
  final Query ordered = base
      .orderBy(OrderBy.getInstance(OrderByDirection.descending, f('order')))
      .limitToFirst(10);
  final Query smallWhole =
      shape == 'small' ? Query(collectionPath(0)) : Query(tiny);
  final bool groupQueries = !flags.contains('--no-group');
  Future<void> queries(String label) async {
    if (!groupQueries && shape == 'small') {
      await timeQuery('$label: whole small collection (${smallWhole.path})',
          store, smallWhole);
      return;
    }
    await timeQuery('$label: a == 7 (1 %) on $where', store, equality);
    await timeQuery(
        '$label: orderBy(order desc).limit(10) on $where', store, ordered);
    await timeQuery('$label: whole small collection (${smallWhole.path})',
        store, smallWhole);
    if (shape != 'small') {
      await timeQuery('$label: whole collection c0', store, base);
    }
  }

  // The first query after the reopen reads cold pages.
  await queries('pending, scan');

  sw = Stopwatch()..start();
  for (final DocumentKey key in sample) {
    await store.readDocument(key);
  }
  record('pending: one document by key (avg of ${sample.length})',
      sw.elapsedMicroseconds / sample.length, 'us/doc');

  // --- Garbage collection with only pending writes (threshold 1 byte, so that it runs).
  final LruGarbageCollector collector = LruGarbageCollector(
      persistence.referenceDelegate,
      const LruGarbageCollectorParams(minBytesThreshold: 1));
  sw = Stopwatch()..start();
  LruGarbageCollectorResults gc = await store.collectGarbage(collector);
  record('pending: garbage collection run', sw.elapsedMicroseconds / 1000, 'ms',
      '${gc.targetsRemoved} targets, ${gc.documentsRemoved} documents removed');

  // --- Cache indexes.
  if (flags.contains('--index')) {
    final String group = shape == 'small' ? 'items' : 'c0';
    await store.configureFieldIndexes(<FieldIndex>[
      FieldIndex(
          FieldIndex.unknownId,
          group,
          <IndexSegment>[IndexSegment(f('a'), SegmentKind.ascending)],
          FieldIndex.initialState),
      FieldIndex(
          FieldIndex.unknownId,
          group,
          <IndexSegment>[IndexSegment(f('order'), SegmentKind.descending)],
          FieldIndex.initialState),
    ]);
    // One run as the scheduler does it (50 documents), then the rest in runs of 1,000.
    final IndexBackfiller backfiller = IndexBackfiller(persistence, store);
    sw = Stopwatch()..start();
    int processed = await backfiller.backfill();
    record('index fill, one scheduled run', sw.elapsedMicroseconds / 1000, 'ms',
        '$processed documents');
    if (flags.contains('--fill-once')) {
      return; // only the cost of one run (a complete fill can take hours)
    }
    backfiller.maxDocumentsToProcess = 1000;
    sw = Stopwatch()..start();
    int filled = 0;
    double lastRun = 0;
    while (true) {
      final Stopwatch one = Stopwatch()..start();
      final int p = await backfiller.backfill();
      if (p == 0) {
        break;
      }
      lastRun = one.elapsedMicroseconds / 1000;
      filled += p;
    }
    record(
        'index fill, rest in runs of 1,000',
        sw.elapsedMicroseconds / max(1, filled),
        'us/doc',
        '$filled documents, last run ${lastRun.toStringAsFixed(1)} ms');
    record('file size with 2 indexes', mb(fileSize(file)), 'MB');
    await queries('pending, index');
    // One more pending write in the indexed collection: queries read it as changed after the index offset.
    await store.writeLocally(<Mutation>[
      SetMutation(
          DocumentKey.fromPath(collectionPath(0).appendSegment(autoId())),
          dataOf(7),
          Precondition.none)
    ]);
    await timeQuery(
        'pending, index + 1 newer write: a == 7 on $where', store, equality);
  }

  // --- The mixed case: acknowledge everything, sync the queries once, read offline.
  if (flags.contains('--ack')) {
    await store.deleteAllFieldIndexes();
    int clock = 1000;
    int acked = 0;
    final int ackReport = max(window, n ~/ 10);
    final Stopwatch all = Stopwatch()..start();
    sw = Stopwatch()..start();
    while (true) {
      final MutationBatch? batch = await store.getNextMutationBatch(-1);
      if (batch == null) {
        break;
      }
      clock++;
      await store.acknowledgeBatch(MutationBatchResult.create(
          batch,
          version(clock),
          <MutationResult>[
            for (int i = 0; i < batch.mutations.length; i++)
              MutationResult(version(clock)),
          ],
          Uint8List.fromList(<int>[1])));
      acked++;
      if (acked == window) {
        record('acknowledge, first $window', sw.elapsedMicroseconds / window,
            'us/ack');
      }
      if (acked % ackReport == 0) {
        print(
            '  $acked acknowledged, ${(sw.elapsedMicroseconds / ackReport).toStringAsFixed(0)} us/ack');
        sw = Stopwatch()..start();
      }
    }
    record('acknowledge, all ($acked)', all.elapsedMicroseconds / acked,
        'us/ack', '${(all.elapsedMilliseconds / 1000).toStringAsFixed(0)} s');
    record('file size after the acknowledgements', mb(fileSize(file)), 'MB');

    // Listen once to the queries: one global snapshot of watch sends their documents as the backend has them (no
    // longer "committed mutations") and marks every target current; the views are then in sync.
    final Map<int, List<Document>> results = <int, List<Document>>{};
    for (final Query q in <Query>[equality, ordered, smallWhole, base]) {
      final QueryData target = await store.allocateTarget(q.toTarget());
      final List<Document> all = <Document>[
        for (final MapEntry<DocumentKey, Document> e
            in (await store.executeQuery(q, false)).documents)
          e.value
      ]..sort(q.comparator);
      results[target.targetId] =
          q.hasLimit ? all.take(q.getLimit()).toList() : all;
    }
    clock++;
    await store.applyRemoteEvent(RemoteEvent(
      documentUpdates: <DocumentKey, MaybeDocument>{
        for (final List<Document> docs in results.values)
          for (final Document d in docs)
            d.key:
                Document(d.key, version(clock), DocumentState.synced, d.data),
      },
      resolvedLimboDocuments: const <DocumentKey>{},
      snapshotVersion: version(clock),
      targetChanges: <int, TargetChange>{
        for (final MapEntry<int, List<Document>> e in results.entries)
          e.key: TargetChange(
            resumeToken: Uint8List.fromList(<int>[1]),
            current: true,
            addedDocuments:
                keys(<DocumentKey>[for (final Document d in e.value) d.key]),
            modifiedDocuments: DocumentKey.emptyKeySet,
            removedDocuments: DocumentKey.emptyKeySet,
          ),
      },
    ));
    await store.notifyLocalViewChanges(<LocalViewChanges>[
      for (final int id in results.keys)
        LocalViewChanges(
            id, false, DocumentKey.emptyKeySet, DocumentKey.emptyKeySet)
    ]);
    await queries('acknowledged, in sync once');
    sw = Stopwatch()..start();
    for (final DocumentKey key in sample) {
      await store.readDocument(key);
    }
    record('acknowledged: one document by key (avg of ${sample.length})',
        sw.elapsedMicroseconds / sample.length, 'us/doc');
    final LruGarbageCollector defaults = LruGarbageCollector(
        persistence.referenceDelegate,
        const LruGarbageCollectorParams(minBytesThreshold: 1));
    sw = Stopwatch()..start();
    gc = await store.collectGarbage(defaults);
    record(
        'acknowledged: garbage collection run (defaults, threshold 1 byte)',
        sw.elapsedMicroseconds / 1000,
        'ms',
        '${gc.targetsRemoved} targets, ${gc.documentsRemoved} documents removed');
  }

  await persistence.shutdown();
  deleteFiles(file);
}

// ---------------------------------------------------------------------------------------------------------------------
// hot

Future<void> hot(int updates, bool transform, String dir) async {
  final String file = '$dir/offline_forever_hot_$updates.db';
  deleteFiles(file);
  print(
      'hot: one document updated $updates times${transform ? ' with a serverTimestamp' : ''}');
  SQLitePersistence persistence = await openPersistence(file);
  LocalStore store = LocalStore(persistence, User.unauthenticated);
  await store.start();

  final ResourcePath collection = ResourcePath.fromString('hot');
  final DocumentKey key = DocumentKey.fromPath(collection.appendSegment('doc'));
  final List<FieldTransform> transforms = transform
      ? <FieldTransform>[
          FieldTransform(f('updatedAt'), ServerTimestampOperation())
        ]
      : const <FieldTransform>[];
  await store.writeLocally(
      <Mutation>[SetMutation(key, dataOf(0), Precondition.none, transforms)]);
  const int window = 1000;
  Stopwatch sw = Stopwatch()..start();
  final Stopwatch total = Stopwatch()..start();
  for (int i = 1; i <= updates; i++) {
    await store.writeLocally(<Mutation>[
      PatchMutation(
          key,
          ObjectValue.fromMap(
              <String, FieldValue>{'n': IntegerValue.valueOf(i)}),
          FieldMask(<FieldPath>{f('n')}),
          Precondition(exists: true),
          transforms)
    ]);
    if (i == min(window, updates)) {
      record('update, first ${min(window, updates)}',
          sw.elapsedMicroseconds / min(window, updates), 'us/write');
    }
    if (i == updates - window) {
      sw = Stopwatch()..start();
    }
  }
  if (updates > window) {
    record('update, last $window', sw.elapsedMicroseconds / window, 'us/write');
  }
  record('update, all ($updates)', total.elapsedMicroseconds / updates,
      'us/write');
  record('file size', mb(fileSize(file)), 'MB');

  await persistence.shutdown();
  sw = Stopwatch()..start();
  persistence = await openPersistence(file);
  store = LocalStore(persistence, User.unauthenticated);
  await store.start();
  record('reopen', sw.elapsedMicroseconds / 1000, 'ms',
      '${updates + 1} pending batches');

  sw = Stopwatch()..start();
  for (int i = 0; i < 100; i++) {
    await store.readDocument(key);
  }
  record('read the document by key (avg of 100)', sw.elapsedMicroseconds / 100,
      'us');
  await timeQuery(
      'query n >= 0 on its collection',
      store,
      Query(collection).filter(FieldFilter(
          f('n'), FilterOperator.graterThanOrEqual, IntegerValue.valueOf(0))));
  await timeQuery('query whole collection', store, Query(collection));

  // A write that the backend rejects (the newest one): its overlay is computed again from all pending batches.
  final int newest = await store.getHighestUnacknowledgedBatchId();
  sw = Stopwatch()..start();
  await store.rejectBatch(newest);
  record('reject the newest batch', sw.elapsedMicroseconds / 1000, 'ms');

  // Acknowledgements, in order. With a transform every acknowledgement recalculates the overlay of the document
  // from its remaining batches; bounded to 60 seconds, the rest is extrapolated.
  int clock = 1000;
  int acked = 0;
  final List<double> times = <double>[];
  final Stopwatch all = Stopwatch()..start();
  while (all.elapsed < const Duration(seconds: 60)) {
    final MutationBatch? batch = await store.getNextMutationBatch(-1);
    if (batch == null) {
      break;
    }
    clock++;
    final Stopwatch one = Stopwatch()..start();
    await store.acknowledgeBatch(MutationBatchResult.create(
        batch,
        version(clock),
        <MutationResult>[
          for (final Mutation m in batch.mutations)
            MutationResult(version(clock), <FieldValue>[
              for (int t = 0; t < m.fieldTransforms.length; t++)
                TimestampValue.valueOf(Timestamp(clock, 0)),
            ]),
        ],
        Uint8List.fromList(<int>[1])));
    times.add(one.elapsedMicroseconds / 1000);
    acked++;
  }
  final int remaining = updates - acked;
  record('acknowledge, first', times.first, 'ms', '$updates batches pending');
  record(
      'acknowledge, average of the first $acked',
      times.reduce((double a, double b) => a + b) / acked,
      'ms',
      '$remaining left after 60 s');
  if (acked > 1) {
    record('acknowledge, last measured', times.last, 'ms');
  }
  await persistence.shutdown();
  deleteFiles(file);
}

// ---------------------------------------------------------------------------------------------------------------------
// drain (public API, emulator)

Future<void> drain(bool hotDocument, int n, bool transform, String dir) async {
  final String emulator =
      Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '127.0.0.1:8391';
  if (emulator.endsWith(':8080')) {
    throw StateError('8080 is the shared emulator; use a private one');
  }
  final int colon = emulator.lastIndexOf(':');
  final String file =
      '$dir/offline_forever_drain_${hotDocument ? 'hot' : 'docs'}_$n.db';
  deleteFiles(file);
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:dart:bench',
      projectId: 'demo-test',
    ),
    name: 'bench',
  );
  final api.FirebaseFirestore firestore = api.FirebaseFirestore.instanceFor(
    app: app,
    openDatabase: BenchDatabase.opener(file),
    settings: api.Settings(
      cacheSettings: api.PersistentCacheSettings(),
    ).withEmulator(
        emulator.substring(0, colon), int.parse(emulator.substring(colon + 1))),
  );
  await firestore.disableNetwork();
  final String run = DateTime.now().microsecondsSinceEpoch.toString();
  print(
      'drain: ${hotDocument ? 'one document updated $n times' : '$n documents'}${transform ? ' with a serverTimestamp' : ''}, run $run');

  final List<Future<void>> writes = <Future<void>>[];
  late api.DocumentReference<Map<String, Object?>> last;
  final Stopwatch sw = Stopwatch()..start();
  if (hotDocument) {
    final api.DocumentReference<Map<String, Object?>> doc =
        firestore.collection('bench/$run/hot').doc('doc');
    writes.add(doc.set(<String, Object?>{'n': 0, 'payload': payload}));
    for (int i = 1; i <= n; i++) {
      writes.add(doc.update(<String, Object?>{
        'n': i,
        if (transform) 'updatedAt': api.FieldValue.serverTimestamp(),
      }));
      if (i % 1000 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    last = doc;
  } else {
    for (int i = 0; i < n; i++) {
      last = firestore.collection('bench/$run/c${i ~/ 1000}').doc();
      writes.add(last.set(<String, Object?>{
        'a': i % 100,
        'order': random.nextInt(1 << 30),
        'payload': payload,
        if (transform) 'updatedAt': api.FieldValue.serverTimestamp(),
      }));
      if (i % 1000 == 0) {
        // Let the queue run, so that the writes are applied as they are made.
        await Future<void>.delayed(Duration.zero);
      }
    }
  }
  // All writes are applied locally once a cache read after them completes.
  await last.get(const api.GetOptions(source: api.Source.cache));
  record(
      'offline writes through the public API',
      sw.elapsedMicroseconds / (n + (hotDocument ? 1 : 0)),
      'us/write',
      'file ${mb(fileSize(file)).toStringAsFixed(0)} MB');

  final Stopwatch drainTime = Stopwatch()..start();
  await firestore.enableNetwork();
  await firestore.waitForPendingWrites().timeout(const Duration(hours: 3));
  record(
      'drain: enableNetwork until waitForPendingWrites completes',
      drainTime.elapsedMicroseconds / 1000000,
      's',
      '${(drainTime.elapsedMicroseconds / (n + (hotDocument ? 1 : 0))).toStringAsFixed(0)} us per write');
  await Future.wait(writes);
  await firestore.terminate();
  deleteFiles(file);
}

// Client-side index engine benchmark on a SQLite cache: N documents in one collection, five query shapes run as a
// full scan, from field indexes, and with automatic index creation; plus backfill time and memory.
//
//   dart run index_bench.dart <documents> [<directory for the database file>] [--profile] [--reps=<n>]
//     [--no-scan] [--no-auto] [--cache-mb=<SQLite page cache>] [--mmap-mb=<SQLite memory-mapped I/O>]
//     [--journal=<journal mode set by the opener>]
//
// Results: notes/perf/local_store_bench.md ("client-side index engine").

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/index_backfiller.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/target_change.dart';

import 'local_store_bench.dart'
    show BenchDatabase, keys, openPersistence, record, results, version;

const int eventSize = 1000;

FieldPath f(String name) => FieldPath.fromSingleSegment(name);

/// `a`: i % 100 (equality and IN), `r`: i (range), `tags`: [i % 100, (i + 1) % 100] (array-contains), `order`: i.
Document docOf(int i, int clock) {
  return Document(
    DocumentKey.fromPathString('coll/doc${i.toString().padLeft(7, '0')}'),
    version(clock),
    DocumentState.synced,
    ObjectValue.fromMap(<String, FieldValue>{
      'a': IntegerValue.valueOf(i % 100),
      'r': IntegerValue.valueOf(i),
      'tags': ArrayValue.fromList(<FieldValue>[
        IntegerValue.valueOf(i % 100),
        IntegerValue.valueOf((i + 1) % 100),
      ]),
      'order': IntegerValue.valueOf(i),
      'payload': StringValue.valueOf('y' * 64),
    }),
  );
}

final Query coll = Query(ResourcePath.fromString('coll'));

Map<String, Query> queries(int n) => <String, Query>{
      'equality a == 7 (1%)': coll.filter(
          FieldFilter(f('a'), FilterOperator.equal, IntegerValue.valueOf(7))),
      'range r in [N/2, N/2 + N/100) (1%)': coll
          .filter(FieldFilter(f('r'), FilterOperator.graterThanOrEqual,
              IntegerValue.valueOf(n ~/ 2)))
          .filter(FieldFilter(f('r'), FilterOperator.lessThan,
              IntegerValue.valueOf(n ~/ 2 + n ~/ 100))),
      'IN a in [1, 2, 3] (3%)': coll.filter(FieldFilter(
          f('a'),
          FilterOperator.IN,
          ArrayValue.fromList(<FieldValue>[
            IntegerValue.valueOf(1),
            IntegerValue.valueOf(2),
            IntegerValue.valueOf(3),
          ]))),
      'array-contains tags 7 (2%)': coll.filter(FieldFilter(
          f('tags'), FilterOperator.arrayContains, IntegerValue.valueOf(7))),
      'orderBy order desc limit 10': coll
          .orderBy(OrderBy.getInstance(OrderByDirection.descending, f('order')))
          .limitToFirst(10),
    };

List<FieldIndex> indexes() => <FieldIndex>[
      for (final (String field, SegmentKind kind) in <(String, SegmentKind)>[
        ('a', SegmentKind.ascending),
        ('r', SegmentKind.ascending),
        ('tags', SegmentKind.contains),
        ('order', SegmentKind.descending),
      ])
        FieldIndex(
            FieldIndex.unknownId,
            'coll',
            <IndexSegment>[IndexSegment(f(field), kind)],
            FieldIndex.initialState),
    ];

double mb(int bytes) => bytes / (1024 * 1024);

Future<void> main(List<String> args) async {
  BenchDatabase.profiling = args.contains('--profile');
  final bool autoIndex = !args.contains('--no-auto');
  for (final String arg
      in args.where((String a) => a.startsWith('--cache-mb='))) {
    BenchDatabase.cacheSizeKb = int.parse(arg.substring(11)) * 1024;
  }
  for (final String arg in args.where((String a) => a.startsWith('--mmap-mb='))) {
    BenchDatabase.mmapSizeBytes = int.parse(arg.substring(10)) * 1024 * 1024;
  }
  for (final String arg in args.where((String a) => a.startsWith('--journal='))) {
    BenchDatabase.journalMode = arg.substring(10);
  }
  final bool scans = !args.contains('--no-scan');
  final int reps = int.parse(args
      .firstWhere((String a) => a.startsWith('--reps='),
          orElse: () => '--reps=5')
      .substring(7));
  args = args.where((String arg) => !arg.startsWith('--')).toList();
  final int n = int.parse(args.isEmpty ? '10000' : args[0]);
  final String dir = args.length > 1 ? args[1] : Directory.systemTemp.path;
  final String file = '$dir/index_bench_$n.db';
  for (final String suffix in <String>['', '-journal', '-wal', '-shm']) {
    final File file0 = File('$file$suffix');
    if (file0.existsSync()) {
      file0.deleteSync();
    }
  }
  print('index bench: $n documents in one collection, $reps reps');

  final SQLitePersistence persistence = await openPersistence(file);
  final LocalStore store = LocalStore(persistence, User.unauthenticated);
  await store.start();

  // --- Fill. ---
  int clock = 1000;
  final QueryData target = await store.allocateTarget(coll.toTarget());
  final Stopwatch fill = Stopwatch()..start();
  for (int start = 0; start < n; start += eventSize) {
    final Map<DocumentKey, MaybeDocument> updates =
        <DocumentKey, MaybeDocument>{};
    for (int i = start; i < min(start + eventSize, n); i++) {
      final Document doc = docOf(i, clock);
      updates[doc.key] = doc;
    }
    clock++;
    await store.applyRemoteEvent(RemoteEvent(
      documentUpdates: updates,
      resolvedLimboDocuments: const <DocumentKey>{},
      snapshotVersion: version(clock),
      targetChanges: <int, TargetChange>{
        target.targetId: TargetChange(
          resumeToken: Uint8List.fromList(<int>[1]),
          current: true,
          addedDocuments: keys(updates.keys),
          modifiedDocuments: DocumentKey.emptyKeySet,
          removedDocuments: DocumentKey.emptyKeySet,
        ),
      },
    ));
  }
  record('fill cache', fill.elapsedMicroseconds / n, 'us/doc');
  record('database size, no index', mb(File(file).lengthSync()), 'MB');

  final Map<String, Query> qs = queries(n);

  /// Median time of [count] runs (default `--reps`); the size of the last result is in [lastSize].
  int lastSize = 0;
  Future<double> time(Query query, [int? count]) async {
    final List<double> times = <double>[];
    for (int i = 0; i < (count ?? reps); i++) {
      final Stopwatch sw = Stopwatch()..start();
      lastSize = (await store.executeQuery(query, false)).documents.length;
      times.add(sw.elapsedMicroseconds / 1000);
    }
    times.sort();
    return times[times.length ~/ 2];
  }

  Future<int> size(Query query) async => lastSize;

  final Map<String, double> scan = <String, double>{};
  for (final MapEntry<String, Query> q in qs.entries) {
    if (!scans) {
      scan[q.key] = double.nan;
      continue;
    }
    final int before = ProcessInfo.currentRss;
    scan[q.key] = await time(q.value);
    record('scan: ${q.key}', scan[q.key]!, 'ms',
        '${await size(q.value)} results, rss +${mb(ProcessInfo.currentRss - before).toStringAsFixed(0)} MB');
  }

  // --- Field indexes: configure, backfill everything, query. ---
  Future<(int, double, int)> backfillAll() async {
    final IndexBackfiller backfiller = IndexBackfiller(persistence, store)
      ..maxDocumentsToProcess = 1000;
    final int rssBefore = ProcessInfo.currentRss;
    int peak = rssBefore;
    final Stopwatch sw = Stopwatch()..start();
    int total = 0;
    while (true) {
      final int processed = await backfiller.backfill();
      peak = max(peak, ProcessInfo.currentRss);
      if (processed == 0) {
        break;
      }
      total += processed;
    }
    return (total, sw.elapsedMicroseconds / 1000, peak - rssBefore);
  }

  await store.configureFieldIndexes(indexes());
  final (int indexed, double backfillMs, int backfillRss) = await backfillAll();
  record(
      'configure + backfill 4 field indexes (5 entries per document)',
      backfillMs * 1000 / max(1, indexed),
      'us/doc',
      '$indexed documents, ${(backfillMs / 1000).toStringAsFixed(1)} s, rss +${mb(backfillRss).toStringAsFixed(0)} MB');
  record('database size, 4 field indexes', mb(File(file).lengthSync()), 'MB');

  final Map<String, double> indexedTimes = <String, double>{};
  final Map<String, int> sizes = <String, int>{};
  // The fixed part of an indexed query: no index entry matches, so what remains is the read of the documents changed
  // after the index offset (none here), which walks the collection.
  record(
      'index: equality a == -1 (no results)',
      await time(coll.filter(
          FieldFilter(f('a'), FilterOperator.equal, IntegerValue.valueOf(-1)))),
      'ms');
  for (final MapEntry<String, Query> q in qs.entries) {
    indexedTimes[q.key] = await time(q.value);
    sizes[q.key] = lastSize;
    record('index: ${q.key}', indexedTimes[q.key]!, 'ms',
        '${await size(q.value)} results, scan / index = ${(scan[q.key]! / indexedTimes[q.key]!).toStringAsFixed(1)}');
  }

  // Measured relative cost of reading a document through the index against a document of a full scan; Android's
  // default is 2 (`relativeIndexReadCostPerDocument`), JS 4 to 8.
  for (final MapEntry<String, Query> q in qs.entries.take(4)) {
    final int results = sizes[q.key]!;
    final double perIndexed = indexedTimes[q.key]! / results;
    final double perScanned = scan[q.key]! / n;
    record('relative index read cost: ${q.key}', perIndexed / perScanned, 'x');
  }

  // --- Partly indexed: N/10 documents changed after the backfill; the query merges index results with them. ---
  {
    final Map<DocumentKey, MaybeDocument> updates =
        <DocumentKey, MaybeDocument>{};
    clock++;
    for (int i = 0; i < n; i += 10) {
      final Document doc = docOf(i, clock);
      updates[doc.key] = doc;
    }
    for (final List<MapEntry<DocumentKey, MaybeDocument>> chunk
        in _chunks(updates.entries.toList(), eventSize)) {
      clock++;
      await store.applyRemoteEvent(RemoteEvent(
        documentUpdates: <DocumentKey, MaybeDocument>{
          for (final MapEntry<DocumentKey, MaybeDocument> e in chunk)
            e.key: Document(e.key, version(clock), DocumentState.synced,
                (e.value as Document).data),
        },
        resolvedLimboDocuments: const <DocumentKey>{},
        snapshotVersion: version(clock),
        targetChanges: const <int, TargetChange>{},
      ));
    }
    for (final MapEntry<String, Query> q in qs.entries) {
      final double t = await time(q.value);
      record('index + 10% not yet indexed: ${q.key}', t, 'ms',
          '${await size(q.value)} results');
    }
    await backfillAll();
  }

  // --- Automatic index creation. ---
  await store.deleteAllFieldIndexes();
  store.indexAutoCreationEnabled = true;
  for (final MapEntry<String, Query> q
      in autoIndex ? qs.entries : const <MapEntry<String, Query>>[]) {
    final int before = store.getFieldIndexes().length;
    final double first = await time(q.value, 1);
    final int created = store.getFieldIndexes().length - before;
    final (int docs, double ms, _) = await backfillAll();
    final double second = await time(q.value);
    record('auto index: ${q.key}', second, 'ms',
        'first run ${first.toStringAsFixed(1)} ms, $created index created, backfill $docs docs in ${ms.toStringAsFixed(0)} ms');
  }

  await persistence.shutdown();
  record('peak resident set size of the process', mb(ProcessInfo.maxRss), 'MB');
  print('\n=== index bench, $n documents ===');
  results.forEach(print);
}

Iterable<List<T>> _chunks<T>(List<T> list, int size) sync* {
  for (int i = 0; i < list.length; i += size) {
    yield list.sublist(i, min(i + size, list.length));
  }
}

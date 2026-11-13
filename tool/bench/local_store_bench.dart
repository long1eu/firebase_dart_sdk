// Local store benchmark on a SQLite cache: fills the cache with N documents in several collections and measures
// queries (previous results vs full scan), document reads, writes, restart (with and without the overlay data
// migration), acknowledgements and garbage collection.
//
//   dart run local_store_bench.dart <documents> [<directory for the database file>] [--profile] [--fsync]
//     [--cache-mb=<SQLite page cache in MB>] [--mmap-mb=<SQLite memory-mapped I/O in MB>] [--journal=<mode>]
//
// --profile prints, after every measurement, the SQL statements that took the most time in it. --fsync keeps SQLite's
// default `synchronous` setting (commits wait for the disk); by default it is OFF so that runs are comparable.
//
// Everything version dependent lives in local_store_bench_compat.dart, so the same benchmark can be built against an
// older commit. Results: notes/perf/local_store_bench.md.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_view_changes.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import 'local_store_bench_compat.dart';

const int collections = 10;
const int pendingWrites = 500;
const int gcPendingMutations = 1000;
const int eventSize = 1000;
final DatabaseId databaseId = DatabaseId.forProject('bench');

/// A file backed [Database] on the `sqlite3` package, the same as the one the unit tests use (statements are prepared
/// for every call).
class BenchDatabase extends Database {
  BenchDatabase._(this._db, this.path);

  final sql.Database _db;

  @override
  final String path;

  static OpenDatabase opener(String file) {
    return (String name,
        {int? version,
        OnConfigure? onConfigure,
        OnCreate? onCreate,
        OnVersionChange? onUpgrade,
        OnVersionChange? onDowngrade,
        OnOpen? onOpen}) async {
      final int targetVersion = version ?? 1;
      final bool create = !File(file).existsSync();
      final sql.Database database = sql.sqlite3.open(file);
      if (!fsync) {
        // Commits dominate (and randomize) the write measurements otherwise; the engine work is what is compared.
        database.execute('PRAGMA synchronous = OFF');
      }
      if (cacheSizeKb != null) {
        // SQLite's default page cache is 2 MB (2000 pages, 8 MB, in the library of macOS).
        database.execute('PRAGMA cache_size = -$cacheSizeKb');
      }
      if (journalMode != null) {
        // A rollback journal mode other than `delete` is kept by the persistence (which switches `delete` to WAL).
        database.select('PRAGMA journal_mode = $journalMode');
      }
      if (mmapSizeBytes != null) {
        // Memory-mapped reads (off by default): pages come from the OS file cache instead of the page cache.
        database.select('PRAGMA mmap_size = $mmapSizeBytes');
      }
      final BenchDatabase db = BenchDatabase._(database, file);
      await onConfigure?.call(db);
      if (create) {
        await onCreate?.call(db, targetVersion);
      } else if (database.userVersion < targetVersion) {
        await onUpgrade?.call(db, database.userVersion, targetVersion);
      }
      database.userVersion = targetVersion;
      await onOpen?.call(db);
      return db;
    };
  }

  /// Total time and number of calls per statement since the last [resetProfile] (only with `--profile`).
  static final Map<String, List<int>> profile = <String, List<int>>{};
  static bool profiling = false;

  /// Whether commits wait for the disk (`--fsync`); off by default.
  static bool fsync = false;

  /// The SQLite page cache in KiB (`--cache-mb=<n>` of index_bench.dart); the library's default (2 MB, or 8 MB on macOS) when null.
  static int? cacheSizeKb;

  /// `PRAGMA mmap_size` in bytes (`--mmap-mb=`); off by default.
  static int? mmapSizeBytes;

  /// `PRAGMA journal_mode` set by the opener (`--journal=`), for example `truncate` to compare with WAL.
  static String? journalMode;

  static void resetProfile() => profile.clear();

  /// Prints the statements that took the most time since the last [resetProfile].
  static void printProfile(String title, [int top = 6]) {
    if (!profiling) {
      return;
    }
    final List<MapEntry<String, List<int>>> entries = profile.entries.toList()
      ..sort((MapEntry<String, List<int>> a, MapEntry<String, List<int>> b) =>
          b.value[0].compareTo(a.value[0]));
    print('  -- SQL profile: $title');
    for (MapEntry<String, List<int>> entry in entries.take(top)) {
      print('     ${(entry.value[0] / 1000).toStringAsFixed(1).padLeft(9)} ms '
          '${entry.value[1].toString().padLeft(7)} calls  ${entry.key}');
    }
    resetProfile();
  }

  T _timed<T>(String statement, T Function() body) {
    if (!profiling) {
      return body();
    }
    final Stopwatch sw = Stopwatch()..start();
    try {
      return body();
    } finally {
      final String key = statement
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'(\?, ?)+\?'), '?..')
          .trim();
      final List<int> entry = profile.putIfAbsent(
          key.length > 110 ? key.substring(0, 110) : key, () => <int>[0, 0]);
      entry[0] += sw.elapsedMicroseconds;
      entry[1]++;
    }
  }

  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) async {
    return _timed(statement, () {
      _db.execute(statement, arguments ?? const <Object?>[]);
      return _db.updatedRows;
    });
  }

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) async {
    _timed(statement,
        () => _db.execute(statement, arguments ?? const <Object?>[]));
  }

  @override
  Future<List<Map<String, dynamic>>> query(String statement,
      [List<Object?>? arguments]) async {
    return _timed(
        statement,
        () => _db
            .select(statement, arguments ?? const <Object?>[])
            .map(Map<String, dynamic>.of)
            .toList());
  }

  @override
  void close() => _db.dispose();
}

final List<String> results = <String>[];

void record(String name, double value, String unit, [String note = '']) {
  final String line =
      '${name.padRight(58)} ${value.toStringAsFixed(value < 10 ? 3 : 1).padLeft(10)} $unit${note.isEmpty ? '' : '  ($note)'}';
  results.add(line);
  print(line);
  BenchDatabase.printProfile(name);
}

/// Runs [body] [reps] times and records the median in milliseconds.
Future<void> median(String name, int reps, Future<Object?> Function() body,
    [String note = '']) async {
  final List<double> times = <double>[];
  Object? last;
  for (int i = 0; i < reps; i++) {
    final Stopwatch sw = Stopwatch()..start();
    last = await body();
    times.add(sw.elapsedMicroseconds / 1000);
  }
  times.sort();
  record(name, times[reps ~/ 2], 'ms',
      <String>[if (note.isNotEmpty) note, if (last != null) '$last'].join(', '));
}

SnapshotVersion version(int micros) =>
    SnapshotVersion(Timestamp(micros ~/ 1000000, (micros % 1000000) * 1000));

DocumentKey keyOf(int collection, int i) =>
    DocumentKey.fromPathString('c$collection/doc${i.toString().padLeft(7, '0')}');

final String payload = 'x' * 200;

Document docOf(int collection, int i, int v) {
  return Document(
    keyOf(collection, i),
    version(v),
    DocumentState.synced,
    ObjectValue.fromMap(<String, FieldValue>{
      'matches': BoolValue.valueOf(i % 10 == 0),
      'order': IntegerValue.valueOf(i),
      'payload': StringValue.valueOf(payload),
    }),
  );
}

Query collectionQuery(int collection) =>
    Query(ResourcePath.fromString('c$collection'));

Query filteredQuery(int collection) => collectionQuery(collection).filter(
    FieldFilter(FieldPath.fromSingleSegment('matches'), FilterOperator.equal,
        BoolValue.trueValue));

Future<SQLitePersistence> openPersistence(String file,
    [LruGarbageCollectorParams params =
        const LruGarbageCollectorParams()]) async {
  final SQLitePersistence persistence = await SQLitePersistence.create(
    'bench',
    databaseId,
    LocalSerializer(RemoteSerializer(databaseId)),
    BenchDatabase.opener(file),
    params,
  );
  await persistence.start();
  return persistence;
}

ImmutableSortedSet<DocumentKey> keys(Iterable<DocumentKey> keys) {
  ImmutableSortedSet<DocumentKey> set = DocumentKey.emptyKeySet;
  for (DocumentKey key in keys) {
    set = set.insert(key);
  }
  return set;
}

Future<void> main(List<String> args) async {
  BenchDatabase.profiling = args.contains('--profile');
  BenchDatabase.fsync = args.contains('--fsync');
  for (final String arg in args.where((String a) => a.startsWith('--cache-mb='))) {
    BenchDatabase.cacheSizeKb = int.parse(arg.substring(11)) * 1024;
  }
  for (final String arg in args.where((String a) => a.startsWith('--mmap-mb='))) {
    BenchDatabase.mmapSizeBytes = int.parse(arg.substring(10)) * 1024 * 1024;
  }
  for (final String arg in args.where((String a) => a.startsWith('--journal='))) {
    BenchDatabase.journalMode = arg.substring(10);
  }
  args = args.where((String arg) => !arg.startsWith('--')).toList();
  final int n = int.parse(args.isEmpty ? '10000' : args[0]);
  final String dir = args.length > 1 ? args[1] : Directory.systemTemp.path;
  final String file = '$dir/local_store_bench_$n.db';
  for (final String suffix in <String>['', '-journal', '-wal', '-shm']) {
    final File f = File('$file$suffix');
    if (f.existsSync()) {
      f.deleteSync();
    }
  }
  final int perCollection = n ~/ collections;
  final Random random = Random(42);
  print('engine: $engineName, documents: $n in $collections collections');

  SQLitePersistence persistence = await openPersistence(file);
  LocalStore store = LocalStore(persistence, User.unauthenticated);
  await store.start();

  // --- Fill: one target per collection, plus a filtered target on c0. ---
  int clock = 1000;
  final List<int> targetIds = <int>[];
  final QueryData filtered = await store.allocateTarget(filteredQuery(0).toTarget());
  final Stopwatch fill = Stopwatch()..start();
  for (int c = 0; c < collections; c++) {
    final QueryData target = await store.allocateTarget(collectionQuery(c).toTarget());
    targetIds.add(target.targetId);
    for (int start = 0; start < perCollection; start += eventSize) {
      final Map<DocumentKey, MaybeDocument> updates = <DocumentKey, MaybeDocument>{};
      final List<DocumentKey> matching = <DocumentKey>[];
      for (int i = start; i < min(start + eventSize, perCollection); i++) {
        final Document doc = docOf(c, i, clock);
        updates[doc.key] = doc;
        if (i % 10 == 0) {
          matching.add(doc.key);
        }
      }
      clock++;
      await store.applyRemoteEvent(RemoteEvent(
        documentUpdates: updates,
        resolvedLimboDocuments: const <DocumentKey>{},
        snapshotVersion: version(clock),
        targetChanges: <int, TargetChange>{
          target.targetId: TargetChange(
            resumeToken: Uint8List.fromList(<int>[1, 2, 3]),
            current: true,
            addedDocuments: keys(updates.keys),
            modifiedDocuments: DocumentKey.emptyKeySet,
            removedDocuments: DocumentKey.emptyKeySet,
          ),
          if (c == 0)
            filtered.targetId: TargetChange(
              resumeToken: Uint8List.fromList(<int>[1, 2, 3]),
              current: true,
              addedDocuments: keys(matching),
              modifiedDocuments: DocumentKey.emptyKeySet,
              removedDocuments: DocumentKey.emptyKeySet,
            ),
        },
      ));
    }
  }
  record('fill cache (remote events of $eventSize documents)',
      fill.elapsedMicroseconds / n, 'us/doc');
  await store.notifyLocalViewChanges(<LocalViewChanges>[
    syncedViewChanges(filtered.targetId),
    for (int id in targetIds) syncedViewChanges(id),
  ]);
  record('database size', File(file).lengthSync() / (1024 * 1024), 'MB');

  Stopwatch sw;

  // --- Queries without pending writes. ---
  await median('query matches==true (10% of c0), previous results', 7,
      () => runQuery(store, filteredQuery(0), usePreviousResults: true),
      '${perCollection ~/ 10} of $perCollection documents');
  await median('query matches==true (10% of c0), full scan', 7,
      () => runQuery(store, filteredQuery(0), usePreviousResults: false));
  await median('query whole collection c0', 7,
      () => runQuery(store, collectionQuery(0), usePreviousResults: true));

  await median('remote keys of the whole-collection target (c0)', 7,
      () async => (await store.getRemoteDocumentKeys(targetIds[0])).length);

  // --- Field index on a collection without previous results (c3 has no filtered target). ---
  await median('query matches==true on c3, no previous results (scan)', 7,
      () => runQuery(store, filteredQuery(3), usePreviousResults: true));
  sw = Stopwatch()..start();
  final int? indexed = await createFieldIndex(persistence, store, 'c3', 'matches');
  if (indexed != null) {
    record('configure + backfill a field index on c3',
        sw.elapsedMicroseconds / indexed, 'us/doc', '$indexed documents');
    await median('query matches==true on c3, field index', 7,
        () => runQuery(store, filteredQuery(3), usePreviousResults: true));
  }

  // --- Document reads. ---
  final List<DocumentKey> readKeys = <DocumentKey>[
    for (int i = 0; i < 1000; i++)
      keyOf(random.nextInt(collections), random.nextInt(perCollection)),
  ];
  sw = Stopwatch()..start();
  for (DocumentKey key in readKeys) {
    await store.readDocument(key);
  }
  record('readDocument (1000 random documents)',
      sw.elapsedMicroseconds / readKeys.length, 'us/doc');

  // --- Writes: single-mutation batches on c0 (half sets, half patches), one large batch on c1. ---
  final List<Mutation> single = <Mutation>[
    for (int i = 0; i < pendingWrites; i++)
      if (i.isEven)
        SetMutation(
            keyOf(0, i * (perCollection ~/ pendingWrites)),
            ObjectValue.fromMap(<String, FieldValue>{
              'matches': BoolValue.trueValue,
              'order': IntegerValue.valueOf(-i),
            }),
            Precondition.none)
      else
        PatchMutation(
            keyOf(0, i * (perCollection ~/ pendingWrites)),
            ObjectValue.fromMap(
                <String, FieldValue>{'matches': BoolValue.trueValue}),
            FieldMask(<FieldPath>{FieldPath.fromSingleSegment('matches')}),
            Precondition(exists: true)),
  ];
  sw = Stopwatch()..start();
  for (Mutation mutation in single) {
    await store.writeLocally(<Mutation>[mutation]);
  }
  record('writeLocally, 1 mutation per batch ($pendingWrites batches)',
      sw.elapsedMicroseconds / pendingWrites, 'us/write');

  sw = Stopwatch()..start();
  await store.writeLocally(<Mutation>[
    for (int i = 0; i < pendingWrites; i++)
      PatchMutation(
          keyOf(1, i),
          ObjectValue.fromMap(
              <String, FieldValue>{'order': IntegerValue.valueOf(-1)}),
          FieldMask(<FieldPath>{FieldPath.fromSingleSegment('order')}),
          Precondition(exists: true)),
  ]);
  record('writeLocally, 1 batch of $pendingWrites patches',
      sw.elapsedMicroseconds / 1000, 'ms');

  // --- Reads and queries with pending writes. ---
  await median('query matches==true on c0, $pendingWrites pending writes, previous', 7,
      () => runQuery(store, filteredQuery(0), usePreviousResults: true));
  await median('query matches==true on c0, $pendingWrites pending writes, full scan', 7,
      () => runQuery(store, filteredQuery(0), usePreviousResults: false));
  await median('query whole collection c1, batch of $pendingWrites patches', 7,
      () => runQuery(store, collectionQuery(1), usePreviousResults: true));
  await median('query whole collection c2 (no writes in it)', 7,
      () => runQuery(store, collectionQuery(2), usePreviousResults: true));
  sw = Stopwatch()..start();
  for (Mutation mutation in single) {
    await store.readDocument(mutation.key);
  }
  record('readDocument with a pending write ($pendingWrites documents)',
      sw.elapsedMicroseconds / pendingWrites, 'us/doc');

  // --- Restart with pending mutations. ---
  await persistence.shutdown();
  sw = Stopwatch()..start();
  persistence = await openPersistence(file);
  store = LocalStore(persistence, User.unauthenticated);
  await store.start();
  record('restart, ${pendingWrites + 1} pending batches',
      sw.elapsedMicroseconds / 1000, 'ms');

  if (hasOverlays) {
    // ignore: invalid_use_of_visible_for_testing_member
    await makeOverlayMigrationPending(persistence.database);
    await persistence.shutdown();
    sw = Stopwatch()..start();
    persistence = await openPersistence(file);
    store = LocalStore(persistence, User.unauthenticated);
    await store.start();
    record(
        'restart + overlay data migration (${pendingWrites * 2} documents)',
        sw.elapsedMicroseconds / 1000,
        'ms');
  }

  // The targets are active again after the restart (as after a listen).
  for (int c = 0; c < collections; c++) {
    await store.allocateTarget(collectionQuery(c).toTarget());
  }
  final QueryData relistened =
      await store.allocateTarget(filteredQuery(0).toTarget());
  // The limbo free snapshot version of a target is persisted when the target is released or every few minutes, so it
  // is gone after the restart: the views sync again.
  await store.notifyLocalViewChanges(
      <LocalViewChanges>[syncedViewChanges(relistened.targetId)]);

  // --- Acknowledge everything. ---
  sw = Stopwatch()..start();
  int acked = 0;
  int largeBatchMicros = 0;
  while (true) {
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
          for (int i = 0; i < batch.mutations.length; i++)
            MutationResult(version(clock)),
        ],
        Uint8List.fromList(<int>[1])));
    if (batch.mutations.length > 1) {
      largeBatchMicros = one.elapsedMicroseconds;
    } else {
      acked++;
    }
  }
  record('acknowledgeBatch, 1 mutation per batch ($acked batches)',
      (sw.elapsedMicroseconds - largeBatchMicros) / acked, 'us/ack');
  record('acknowledgeBatch, 1 batch of $pendingWrites patches',
      largeBatchMicros / 1000, 'ms');

  await median('query matches==true on c0 after acks, previous results', 7,
      () => runQuery(store, filteredQuery(0), usePreviousResults: true));

  // --- Subcollections: N/10 documents below one document of c5 (in their own target); a query of c5 must skip them.
  await median('query whole collection c5 (no subcollection)', 7,
      () => runQuery(store, collectionQuery(5), usePreviousResults: false));
  final Query subcollection =
      Query(keyOf(5, 0).path.appendSegment('sub'));
  final QueryData subTarget = await store.allocateTarget(subcollection.toTarget());
  for (int start = 0; start < perCollection; start += eventSize) {
    final Map<DocumentKey, MaybeDocument> updates = <DocumentKey, MaybeDocument>{};
    for (int i = start; i < min(start + eventSize, perCollection); i++) {
      final Document doc = docOf(5, i, clock);
      final Document sub = Document(
          DocumentKey.fromPath(subcollection.path.appendSegment(doc.key.path.getLastSegment())),
          doc.version,
          DocumentState.synced,
          doc.data);
      updates[sub.key] = sub;
    }
    clock++;
    await store.applyRemoteEvent(RemoteEvent(
      documentUpdates: updates,
      resolvedLimboDocuments: const <DocumentKey>{},
      snapshotVersion: version(clock),
      targetChanges: <int, TargetChange>{
        subTarget.targetId: TargetChange(
          resumeToken: Uint8List.fromList(<int>[1, 2, 3]),
          current: true,
          addedDocuments: keys(updates.keys),
          modifiedDocuments: DocumentKey.emptyKeySet,
          removedDocuments: DocumentKey.emptyKeySet,
        ),
      },
    ));
  }
  await median('query whole collection c5, $perCollection documents in a subcollection', 7,
      () => runQuery(store, collectionQuery(5), usePreviousResults: false));

  // --- Garbage collection: release collection targets, then collect; once without and once with pending mutations.
  final LruGarbageCollector collector = LruGarbageCollector(
      persistence.referenceDelegate,
      const LruGarbageCollectorParams(
          minBytesThreshold: 1,
          percentileToCollect: 100,
          maximumSequenceNumbersToCollect: 1 << 30));
  Future<void> collect(String name, List<int> releasedCollections) async {
    for (int c in releasedCollections) {
      await store.releaseTarget(targetIds[c]);
    }
    final Stopwatch sw = Stopwatch()..start();
    final LruGarbageCollectorResults gc = await store.collectGarbage(collector);
    record(name, sw.elapsedMicroseconds / max(1, gc.documentsRemoved), 'us/doc',
        '${gc.targetsRemoved} targets, ${gc.documentsRemoved} documents removed');
  }

  await collect('LRU garbage collection, no pending mutations', <int>[0, 2, 4]);
  await store.writeLocally(<Mutation>[
    for (int i = 0; i < gcPendingMutations; i++)
      PatchMutation(
          keyOf(1, i % perCollection),
          ObjectValue.fromMap(
              <String, FieldValue>{'order': IntegerValue.valueOf(-2)}),
          FieldMask(<FieldPath>{FieldPath.fromSingleSegment('order')}),
          Precondition(exists: true)),
  ]);
  await collect(
      'LRU garbage collection, $gcPendingMutations pending mutations',
      <int>[6, 8]);

  await persistence.shutdown();
  record('peak resident set size of the process', ProcessInfo.maxRss / (1024 * 1024), 'MB');
  print('\n=== $engineName, $n documents ===');
  results.forEach(print);
}

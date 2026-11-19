// Where the time of a cache read goes on a SQLite cache: SQLite itself, decoding the stored bytes, the query work above
// the store, and the rest. Results: docs/spikes/cache_read_profile.md.
//
// The cache has 100,000 documents in one collection (`c0`: `a` = i % 100, `order` random, a 200 character string) and
// 1,000 small collections of 10 documents (`m<n>`), in one of two shapes:
//   acked    the documents were delivered by a remote event (remote document cache, no pending writes)
//   pending  the documents exist only as pending writes (document overlays, empty remote document cache)
//
//   dart compile exe cache_read_profile_bench.dart -o cache_read_profile_bench
//   cache_read_profile_bench fill <acked|pending> <file>         creates the database
//   cache_read_profile_bench index <file> <file with indexes>    copies it and adds a cache index on `a` and `order`
//   cache_read_profile_bench time <acked|pending> <file> [<file with indexes>] [--reps=7] [--no-statement-cache]
//   --big=N --small=N (all modes): documents in c0 and number of small collections, for a smaller cache (the web
//       numbers of cache_read_profile.md use --big=20000 --small=100)
//       warm timings of every case: the whole path, with the time inside SQLite measured in the database adapter
//   cache_read_profile_bench raw <acked|pending> <file> [--reps=7]
//       the layers alone: raw SQL with package:sqlite3 (nothing decoded), decode on the blobs in memory, query work
//   cache_read_profile_bench cold <acked|pending> <file> <point|whole|eq|ord>
//       the first read after opening the file, in this process
//   dart --enable-vm-service=0 --disable-service-auth-codes --profile-period=250 cache_read_profile_bench.dart \
//     profile <acked|pending> <file> <point|whole|eq|ord> [<reps>]
//       the CPU profile of a case, attributed to SQLite / decoding / query work / other by the frames of each sample
//       (also works on `dart compile aot-snapshot` run with `dartaotruntime` and the same flags)
//
// Cases: point (read one document by key), whole (c0), eq (`a == 7`), ord (`orderBy(order desc).limit(20)`); on a
// file with indexes eq and ord are the indexed ones.

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/encoded_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/index_backfiller.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
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
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:vm_service/vm_service.dart' as vms;
import 'package:vm_service/vm_service_io.dart' as vms_io;

/// 100,000 and 1,000 unless `--big=N` and `--small=N` say otherwise (same on every mode that opens the file).
int bigDocs = 100000;
int smallCollections = 1000;
const int smallDocs = 10;
const int limit = 20;
final DatabaseId databaseId = DatabaseId.forProject('bench');
final String payload = 'x' * 200;

// ---------------------------------------------------------------------------------------------------------------------
// The database adapter, with timers.

/// The adapter of `cloud_firestore_dart_sqlite` (the `sqlite3` package, the prepared statements of the last 64 queries
/// kept, the rows copied to maps), with the time of the two parts kept apart: `select` (prepare unless cached, step,
/// copy the columns out) and the copy of every row into a `Map`. With `--no-statement-cache` a statement is prepared
/// for every call (the adapter before the statement cache).
class TimedDatabase extends Database {
  TimedDatabase._(this._db, this.path);

  final sql.Database _db;

  @override
  final String path;

  static int selectUs = 0;
  static int mapUs = 0;
  static int calls = 0;
  static int rows = 0;
  static int bytes = 0;

  /// Whether to record the statements and the blob sizes (a regular expression per call: off while timing).
  static bool collect = false;

  /// Time and calls per statement since [reset].
  static final Map<String, List<int>> statements = <String, List<int>>{};

  /// Whether to keep prepared statements, as the adapter of `cloud_firestore_dart_sqlite` does.
  static bool statementCache = true;

  final Map<String, sql.PreparedStatement> _statements =
      <String, sql.PreparedStatement>{};

  sql.ResultSet _select(String statement, List<Object?> arguments) {
    if (!statementCache) {
      return _db.select(statement, arguments);
    }
    sql.PreparedStatement? prepared = _statements.remove(statement);
    prepared ??= _db.prepare(statement, persistent: true, checkNoTail: true);
    final sql.ResultSet result = prepared.select(arguments);
    _statements[statement] = prepared;
    if (_statements.length > 64) {
      _statements.remove(_statements.keys.first)!.dispose();
    }
    return result;
  }

  static void reset() {
    selectUs = mapUs = calls = rows = bytes = 0;
    statements.clear();
  }



  static OpenDatabase opener(String file, {bool fill = false}) {
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
      if (fill) {
        database.execute('PRAGMA synchronous = OFF');
      }
      final TimedDatabase db = TimedDatabase._(database, file);
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

  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) async {
    _db.execute(statement, arguments ?? const <Object?>[]);
    return _db.updatedRows;
  }

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) async {
    _db.execute(statement, arguments ?? const <Object?>[]);
  }

  @override
  Future<List<Map<String, dynamic>>> query(String statement,
      [List<Object?>? arguments]) async {
    final Stopwatch sw = Stopwatch()..start();
    final sql.ResultSet result =
        _select(statement, arguments ?? const <Object?>[]);
    final int us = sw.elapsedMicroseconds;
    selectUs += us;
    String? key;
    if (collect) {
      key = statement.replaceAll(RegExp(r'\s+'), ' ').trim();
      final List<int> entry = statements.putIfAbsent(
          key.length > 150 ? key.substring(0, 150) : key, () => <int>[0, 0]);
      entry[0] += us;
      entry[1] += result.length;
    }
    sw.reset();
    final List<Map<String, dynamic>> maps =
        result.map(Map<String, dynamic>.of).toList();
    mapUs += sw.elapsedMicroseconds;
    calls++;
    rows += maps.length;
    if (collect) {
      for (final Map<String, dynamic> row in maps) {
        final Object? blob = row['contents'] ?? row['overlay_mutation'];
        if (blob is Uint8List) {
          bytes += blob.length;
        }
      }
    }
    return maps;
  }

  @override
  void close() {
    for (final sql.PreparedStatement statement in _statements.values) {
      statement.dispose();
    }
    _statements.clear();
    _db.dispose();
  }
}

Future<(SQLitePersistence, LocalStore)> open(String file,
    {bool fill = false}) async {
  final SQLitePersistence persistence = await SQLitePersistence.create(
    'bench',
    databaseId,
    LocalSerializer(RemoteSerializer(databaseId)),
    TimedDatabase.opener(file, fill: fill),
    const LruGarbageCollectorParams(),
  );
  await persistence.start();
  final LocalStore store = LocalStore(persistence, User.unauthenticated);
  await store.start();
  return (persistence, store);
}

// ---------------------------------------------------------------------------------------------------------------------
// The data.

FieldPath f(String name) => FieldPath.fromSingleSegment(name);
DocumentKey bigKey(int i) =>
    DocumentKey.fromPathString('c0/doc${i.toString().padLeft(7, '0')}');
DocumentKey smallKey(int c, int j) => DocumentKey.fromPathString('m$c/doc$j');

ObjectValue dataOf(int i, Random random) =>
    ObjectValue.fromMap(<String, FieldValue>{
      'a': IntegerValue.valueOf(i % 100),
      'order': IntegerValue.valueOf(random.nextInt(1 << 30)),
      'payload': StringValue.valueOf(payload),
    });

/// Every document of the cache, in the order they are written.
Iterable<(DocumentKey, int)> allKeys() sync* {
  // The small collections first: the cache index of c0 then has the last documents of the cache behind it, as an
  // index that is up to date has.
  for (int c = 0; c < smallCollections; c++) {
    for (int j = 0; j < smallDocs; j++) {
      yield (smallKey(c, j), c * smallDocs + j);
    }
  }
  for (int i = 0; i < bigDocs; i++) {
    yield (bigKey(i), i);
  }
}

SnapshotVersion version(int micros) =>
    SnapshotVersion(Timestamp(micros ~/ 1000000, (micros % 1000000) * 1000));

ImmutableSortedSet<DocumentKey> keySet(Iterable<DocumentKey> keys) {
  ImmutableSortedSet<DocumentKey> set = DocumentKey.emptyKeySet;
  for (final DocumentKey key in keys) {
    set = set.insert(key);
  }
  return set;
}

Query wholeQuery() => Query(ResourcePath.fromString('c0'));
Query eqQuery() => wholeQuery().filter(
    FieldFilter(f('a'), FilterOperator.equal, IntegerValue.valueOf(7)));
Query ordQuery() => wholeQuery()
    .orderBy(OrderBy.getInstance(OrderByDirection.descending, f('order')))
    .limitToFirst(limit);
Query queryOf(String which) => switch (which) {
      'whole' => wholeQuery(),
      'eq' => eqQuery(),
      'ord' => ordQuery(),
      _ => throw ArgumentError('case $which'),
    };

void deleteFiles(String file) {
  for (final String suffix in <String>['', '-journal', '-wal', '-shm']) {
    final File x = File('$file$suffix');
    if (x.existsSync()) {
      x.deleteSync();
    }
  }
}

Future<void> fill(String shape, String file, {bool listened = false}) async {
  deleteFiles(file);
  final (SQLitePersistence persistence, LocalStore store) =
      await open(file, fill: true);
  final Random random = Random(42);
  final Stopwatch sw = Stopwatch()..start();
  if (shape == 'acked') {
    // One target holds every document (the cache keeps them while a target refers to them). By default it is the
    // target of a query that the cases do not run; with `--listened` it is the one of the whole collection c0, so that
    // reading c0 also reads the 110,000 keys of its target, as for a collection that has been listened to.
    final target = await store.allocateTarget(
        (listened ? wholeQuery() : Query(ResourcePath.fromString('seed')))
            .toTarget());
    int clock = 1000;
    final List<(DocumentKey, int)> keys = allKeys().toList();
    for (int start = 0; start < keys.length; start += 1000) {
      final Map<DocumentKey, MaybeDocument> updates =
          <DocumentKey, MaybeDocument>{};
      for (final (DocumentKey key, int i)
          in keys.sublist(start, min(keys.length, start + 1000))) {
        updates[key] = Document(
            key, version(clock), DocumentState.synced, dataOf(i, random));
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
            addedDocuments: keySet(updates.keys),
            modifiedDocuments: DocumentKey.emptyKeySet,
            removedDocuments: DocumentKey.emptyKeySet,
          ),
        },
      ));
    }
  } else {
    for (final (DocumentKey key, int i) in allKeys()) {
      await store.writeLocally(<Mutation>[
        SetMutation(key, dataOf(i, random), Precondition.none),
      ]);
    }
  }
  print('filled $shape in ${sw.elapsedMilliseconds / 1000} s');
  await persistence.shutdown();
  print('file ${File(file).lengthSync() / (1024 * 1024)} MB');
}

Future<void> addIndexes(String from, String to) async {
  deleteFiles(to);
  File(from).copySync(to);
  final (SQLitePersistence persistence, LocalStore store) =
      await open(to, fill: true);
  await store.configureFieldIndexes(<FieldIndex>[
    FieldIndex(
        FieldIndex.unknownId,
        'c0',
        <IndexSegment>[IndexSegment(f('a'), SegmentKind.ascending)],
        FieldIndex.initialState),
    FieldIndex(
        FieldIndex.unknownId,
        'c0',
        <IndexSegment>[IndexSegment(f('order'), SegmentKind.descending)],
        FieldIndex.initialState),
  ]);
  final IndexBackfiller backfiller = IndexBackfiller(persistence, store)
    ..maxDocumentsToProcess = 1000;
  int total = 0;
  final Stopwatch sw = Stopwatch()..start();
  while (true) {
    final int processed = await backfiller.backfill();
    if (processed == 0) {
      break;
    }
    total += processed;
  }
  print('indexed $total documents in ${sw.elapsedMilliseconds / 1000} s');
  await persistence.shutdown();
  print('file ${File(to).lengthSync() / (1024 * 1024)} MB');
}

// ---------------------------------------------------------------------------------------------------------------------
// Measuring the whole path.

double median(List<double> values) {
  final List<double> sorted = List<double>.of(values)..sort();
  return sorted[sorted.length ~/ 2];
}

class Sample {
  Sample(this.name);

  final String name;
  final List<double> store = <double>[];
  final List<double> view = <double>[];
  final List<double> select = <double>[];
  final List<double> map = <double>[];
  int calls = 0;
  int rows = 0;
  int bytes = 0;
  int results = 0;
  int viewResults = 0;
  List<MapEntry<String, List<int>>> statements = <MapEntry<String, List<int>>>[];
}

/// Runs the whole path of a query read from the cache (the local store, then the view that raises the snapshot, as
/// `getDocuments(source: cache)` does) [reps] times after one run that is dropped.
Future<Sample> measureQuery(String name, LocalStore store, Query query,
    {required int reps}) async {
  final Sample sample = Sample(name);
  for (int rep = 0; rep < reps + 1; rep++) {
    TimedDatabase.reset();
    final Stopwatch sw = Stopwatch()..start();
    final QueryResult queryResult = await store.executeQuery(query, true);
    final int storeUs = sw.elapsedMicroseconds;
    final int selectUs = TimedDatabase.selectUs;
    final int mapUs = TimedDatabase.mapUs;
    sample
      ..calls = TimedDatabase.calls
      ..rows = TimedDatabase.rows
      ..results = queryResult.documents.length;
    sw.reset();
    final View view = View(query, queryResult.remoteKeys);
    final ViewDocumentChanges changes =
        view.computeDocChanges(queryResult.documents);
    final int snapshotDocs =
        view.applyChanges(changes).snapshot!.documents.length;
    final int viewUs = sw.elapsedMicroseconds;
    sample.viewResults = snapshotDocs;
    if (rep == 0) {
      continue; // the first run of a process is not warm; `cold` measures it
    }
    sample.store.add(storeUs / 1000);
    sample.view.add(viewUs / 1000);
    sample.select.add(selectUs / 1000);
    sample.map.add(mapUs / 1000);
  }
  // One more run that records the statements and the size of the blobs (its time is not used).
  TimedDatabase.collect = true;
  TimedDatabase.reset();
  await store.executeQuery(query, true);
  sample.bytes = TimedDatabase.bytes;
  sample.statements = TimedDatabase.statements.entries.toList()
    ..sort((MapEntry<String, List<int>> a, MapEntry<String, List<int>> b) =>
        b.value[0].compareTo(a.value[0]));
  TimedDatabase.collect = false;
  return sample;
}

List<DocumentKey> randomSmallKeys(int seed, int n) {
  final Random random = Random(seed);
  return <DocumentKey>[
    for (int i = 0; i < n; i++)
      smallKey(random.nextInt(smallCollections), random.nextInt(smallDocs)),
  ];
}

/// 1,000 random documents of the small collections read by key, [reps] times; per read in microseconds.
Future<Sample> measurePoint(String name, LocalStore store,
    {required int reps}) async {
  final Sample sample = Sample(name);
  final List<DocumentKey> keys = randomSmallKeys(7, 1000);
  for (int rep = 0; rep < reps + 1; rep++) {
    TimedDatabase.reset();
    final Stopwatch sw = Stopwatch()..start();
    int found = 0;
    for (final DocumentKey key in keys) {
      if (await store.readDocument(key) != null) {
        found++;
      }
    }
    final int totalUs = sw.elapsedMicroseconds;
    sample
      ..calls = TimedDatabase.calls ~/ keys.length
      ..rows = found;
    if (rep == 0) {
      continue;
    }
    sample.store.add(totalUs / keys.length);
    sample.view.add(0);
    sample.select.add(TimedDatabase.selectUs / keys.length);
    sample.map.add(TimedDatabase.mapUs / keys.length);
  }
  return sample;
}

Sample? lastSample;

void printStatements(Sample s, [int top = 4]) {
  for (final MapEntry<String, List<int>> e in s.statements.take(top)) {
    print('     ${(e.value[0] / 1000).toStringAsFixed(2).padLeft(8)} ms ${e.value[1].toString().padLeft(6)} rows  ${e.key}');
  }
}

String ms(double v) => v < 1 ? v.toStringAsFixed(3) : v.toStringAsFixed(1);

void printSample(Sample s, {String unit = 'ms'}) {
  final double store = median(s.store);
  final double view = median(s.view);
  final double select = median(s.select);
  final double map = median(s.map);
  print('${s.name.padRight(22)} total ${ms(store + view)} $unit '
      '(store ${ms(store)}, view ${ms(view)}); in the store: sqlite select ${ms(select)} (${(100 * select / store).toStringAsFixed(0)}%), '
      'row to map copy ${ms(map)}, ${s.calls} statements, ${s.rows} rows, ${(s.bytes / 1024).toStringAsFixed(0)} KiB of blobs; '
      '${s.results} documents out of the store, ${s.viewResults} in the snapshot; '
      'runs ${s.store.map((double v) => ms(v)).join(' ')}');
}

Future<void> timeAll(
    String shape, String file, String? indexFile, int reps) async {
  print(
      '=== time, $shape, Dart ${Platform.version.split(' ').first}, medians of $reps warm runs after one dropped run');
  final (SQLitePersistence persistence, LocalStore store) = await open(file);
  printSample(await measurePoint('point read (us/doc)', store, reps: reps),
      unit: 'us');
  printSample(await measureQuery('whole c0', store, wholeQuery(), reps: reps));
  printSample(await measureQuery('eq a == 7', store, eqQuery(), reps: reps));
  printSample(
      await measureQuery('ord desc limit $limit', store, ordQuery(), reps: reps));
  await persistence.shutdown();
  if (indexFile != null) {
    final (SQLitePersistence p2, LocalStore s2) = await open(indexFile);
    printSample(lastSample = await measureQuery('eq, index', s2, eqQuery(), reps: reps));
    printStatements(lastSample!);
    printSample(lastSample = await measureQuery('ord, index', s2, ordQuery(), reps: reps));
    printStatements(lastSample!);
    printSample(
        await measureQuery('whole, index file', s2, wholeQuery(), reps: reps));
    await p2.shutdown();
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Direct timing of the layers.

String _collectionPath(String collection) =>
    EncodedPath.encode(ResourcePath.fromString(collection));

/// The statement that scans a collection of the remote document cache (one page of it), as `SQLiteRemoteDocumentCache`
/// runs it.
const String scanSql =
    'SELECT contents, read_time_seconds, read_time_nanos, document_type, path '
    'FROM remote_documents WHERE path > ? AND path < ? AND path_length = ? '
    'AND (document_type IS NULL OR document_type = ?) ORDER BY path LIMIT 1000';

const String overlayScanSql = '''
          SELECT overlay_mutation, largest_batch_id
          FROM document_overlays
          WHERE uid = ? AND collection_path = ? AND +largest_batch_id > ?
        ''';

/// Reads the collection `c0` with the raw statements of the store through `package:sqlite3` and returns the blobs
/// (nothing is decoded).
List<Uint8List> rawScan(sql.Database db, String shape) {
  final List<Uint8List> blobs = <Uint8List>[];
  if (shape == 'acked') {
    final String prefix = _collectionPath('c0');
    final String successor = EncodedPath.prefixSuccessor(prefix);
    String last = prefix;
    while (true) {
      final sql.ResultSet page = db.select(scanSql, <Object>[last, successor, 2, 2]);
      for (final sql.Row row in page) {
        blobs.add(row['contents'] as Uint8List);
      }
      if (page.length < 1000) {
        break;
      }
      last = page.last['path'] as String;
    }
  } else {
    final sql.ResultSet rows =
        db.select(overlayScanSql, <Object>['', _collectionPath('c0'), -1]);
    for (final sql.Row row in rows) {
      blobs.add(row['overlay_mutation'] as Uint8List);
    }
  }
  return blobs;
}

/// Times [body] [reps] times (after one run that is dropped) and returns the median in milliseconds.
double timeIt(int reps, void Function() body) {
  body();
  final List<double> times = <double>[];
  for (int i = 0; i < reps; i++) {
    final Stopwatch sw = Stopwatch()..start();
    body();
    times.add(sw.elapsedMicroseconds / 1000);
  }
  return median(times);
}

typedef _Docs = ImmutableSortedMap<DocumentKey, Document>;

_Docs emptyDocs() =>
    _Docs.fromMap(<DocumentKey, Document>{}, DocumentKey.comparator);

Future<void> raw(String shape, String file, int reps) async {
  final sql.Database db = sql.sqlite3.open(file, mode: sql.OpenMode.readOnly);
  final LocalSerializer serializer =
      LocalSerializer(RemoteSerializer(databaseId));
  print('=== raw, $shape, collection c0 (100,000 documents), medians of $reps runs');

  List<Uint8List> blobs = <Uint8List>[];
  final double sqlMs = timeIt(reps, () => blobs = rawScan(db, shape));
  final int bytes = blobs.fold(0, (int s, Uint8List b) => s + b.length);
  print(
      'SQL alone (step every row, copy the blob out): ${ms(sqlMs)} ms, ${blobs.length} rows, '
      '${(bytes / 1024 / 1024).toStringAsFixed(1)} MiB of blobs, ${bytes ~/ max(1, blobs.length)} bytes per row');

  final List<(String, Query)> queries = <(String, Query)>[
    ('whole', wholeQuery()),
    ('eq', eqQuery()),
    ('ord', ordQuery()),
  ];
  // The decode and the query work, on the blobs in memory, a page of 1,000 rows at a time as the store reads them (so
  // that the documents that do not match are dropped at once, as in the store), each step timed alone.
  final Timestamp now = Timestamp.now();
  for (final (String name, Query q) in queries) {
    final List<List<double>> runs = <List<double>>[];
    int n = 0;
    for (int rep = 0; rep < reps + 1; rep++) {
      int parseUs = 0, modelUs = 0, applyUs = 0, matchUs = 0;
      final Map<DocumentKey, Document> results = <DocumentKey, Document>{};
      _Docs overlayResults = emptyDocs();
      final Stopwatch sw = Stopwatch();
      for (int start = 0; start < blobs.length; start += 1000) {
        final List<Uint8List> page =
            blobs.sublist(start, min(blobs.length, start + 1000));
        if (shape == 'acked') {
          sw
            ..reset()
            ..start();
          final List<proto.MaybeDocument> parsed = <proto.MaybeDocument>[
            for (final Uint8List b in page) proto.MaybeDocument.fromBuffer(b),
          ];
          parseUs += sw.elapsedMicroseconds;
          sw
            ..reset()
            ..start();
          final List<MaybeDocument> docs = <MaybeDocument>[
            for (final proto.MaybeDocument p in parsed)
              serializer.decodeMaybeDocument(p),
          ];
          modelUs += sw.elapsedMicroseconds;
          sw
            ..reset()
            ..start();
          for (final MaybeDocument d in docs) {
            if (d is Document && q.matches(d)) {
              results[d.key] = d;
            }
          }
          matchUs += sw.elapsedMicroseconds;
        } else {
          sw
            ..reset()
            ..start();
          final List<proto.Write> parsed = <proto.Write>[
            for (final Uint8List b in page) proto.Write.fromBuffer(b),
          ];
          parseUs += sw.elapsedMicroseconds;
          sw
            ..reset()
            ..start();
          final List<Mutation> mutations = <Mutation>[
            for (final proto.Write p in parsed) serializer.decodeOverlayMutation(p),
          ];
          modelUs += sw.elapsedMicroseconds;
          sw
            ..reset()
            ..start();
          final List<MaybeDocument?> docs = <MaybeDocument?>[
            for (final Mutation m in mutations) m.applyToLocalView(null, null, now),
          ];
          applyUs += sw.elapsedMicroseconds;
          sw
            ..reset()
            ..start();
          for (final MaybeDocument? d in docs) {
            if (d is Document && q.matches(d)) {
              overlayResults = overlayResults.insert(d.key, d);
            }
          }
          matchUs += sw.elapsedMicroseconds;
        }
      }
      sw
        ..reset()
        ..start();
      if (shape == 'acked') {
        n = _Docs.fromMap(results, DocumentKey.comparator).length;
      } else {
        n = overlayResults.length;
      }
      final int buildUs = sw.elapsedMicroseconds;
      if (rep > 0) {
        runs.add(<double>[parseUs / 1000, modelUs / 1000, applyUs / 1000, matchUs / 1000, buildUs / 1000]);
      }
    }
    double m(int i) => median(<double>[for (final List<double> r in runs) r[i]]);
    print(
        'layers, $name ($n results): protobuf parse ${ms(m(0))} ms, model decode ${ms(m(1))} ms'
        '${shape == 'pending' ? ', applyToLocalView ${ms(m(2))} ms' : ''}, '
        '${shape == 'acked' ? 'Query.matches (decodes the fields it reads) ${ms(m(3))} ms, ImmutableSortedMap.fromMap ${ms(m(4))} ms' : 'Query.matches + ImmutableSortedMap.insert per match ${ms(m(3))} ms'}');
  }
  // The view alone, on the documents the store returns.
  {
    final List<Document> allDocs = <Document>[];
    for (final Uint8List b in blobs) {
      if (shape == 'acked') {
        allDocs.add(serializer.decodeMaybeDocument(proto.MaybeDocument.fromBuffer(b)) as Document);
      } else {
        allDocs.add(serializer
            .decodeOverlayMutation(proto.Write.fromBuffer(b))
            .applyToLocalView(null, null, now) as Document);
      }
    }
    for (final (String name, Query q) in queries) {
      final _Docs map = _Docs.fromMap(<DocumentKey, Document>{
        for (final Document d in allDocs)
          if (q.matches(d)) d.key: d,
      }, DocumentKey.comparator);
      final List<double> v = <double>[];
      for (int i = 0; i < reps + 1; i++) {
        final Stopwatch sw = Stopwatch()..start();
        final View view = View(q, DocumentKey.emptyKeySet);
        view.applyChanges(view.computeDocChanges(map)).snapshot!;
        if (i > 0) {
          v.add(sw.elapsedMicroseconds / 1000);
        }
      }
      print('view, $name: View.computeDocChanges + applyChanges on ${map.length} documents ${ms(median(v))} ms');
    }
    // The two phases of View.computeDocChanges for a limit query, apart: every document added to the DocumentSet (kept in
    // the order of the query), then the documents beyond the limit removed one at a time.
    for (final (String name, Query q) in <(String, Query)>[
      ('whole', wholeQuery()),
      ('ord', ordQuery()),
    ]) {
      final Comparator<Document> comparator = q.comparator;
      final List<double> adds = <double>[];
      final List<double> removes = <double>[];
      for (int i = 0; i < reps + 1; i++) {
        DocumentSet set = DocumentSet.emptySet(comparator);
        final Stopwatch sw = Stopwatch()..start();
        for (final Document d in allDocs) {
          set = set.add(d);
        }
        final double addMs = sw.elapsedMicroseconds / 1000;
        sw.reset();
        if (q.hasLimit) {
          for (int n = set.length - q.getLimit(); n > 0; --n) {
            set = set.remove(set.getLastDocument()!.key);
          }
        }
        if (i > 0) {
          adds.add(addMs);
          removes.add(sw.elapsedMicroseconds / 1000);
        }
      }
      print('view phases, $name: DocumentSet.add of ${allDocs.length} documents ${ms(median(adds))} ms, '
          '${q.hasLimit ? 'DocumentSet.remove of ${allDocs.length - q.getLimit()} documents beyond the limit ${ms(median(removes))} ms' : 'no limit, nothing removed'}');
    }
  }

  // Point reads.
  final List<DocumentKey> keys = randomSmallKeys(7, 1000);
  final List<String> ids = <String>[
    for (final DocumentKey key in keys) EncodedPath.encode(key.path),
  ];
  const String docSql =
      'SELECT contents, read_time_seconds, read_time_nanos, document_type, path FROM remote_documents WHERE path = ?;';
  const String overlaySql =
      'SELECT overlay_mutation, largest_batch_id FROM document_overlays WHERE uid = ? AND collection_path = ? AND document_id = ?';
  final List<Uint8List> pointBlobs = <Uint8List>[];
  double pointSql(bool prepared) {
    final sql.PreparedStatement docStatement = db.prepare(docSql);
    final sql.PreparedStatement overlayStatement = db.prepare(overlaySql);
    final double t = timeIt(reps, () {
      pointBlobs.clear();
      for (int i = 0; i < keys.length; i++) {
        final DocumentKey key = keys[i];
        final List<Object> overlayArgs = <Object>[
          '',
          EncodedPath.encode(key.path.popLast()),
          key.path.getLastSegment(),
        ];
        final sql.ResultSet overlay = prepared
            ? overlayStatement.select(overlayArgs)
            : db.select(overlaySql, overlayArgs);
        if (shape == 'acked') {
          final sql.ResultSet r = prepared
              ? docStatement.select(<Object>[ids[i]])
              : db.select(docSql, <Object>[ids[i]]);
          pointBlobs.add(r.single['contents'] as Uint8List);
        } else {
          pointBlobs.add(overlay.single['overlay_mutation'] as Uint8List);
        }
      }
    });
    docStatement.dispose();
    overlayStatement.dispose();
    return t * 1000 / keys.length;
  }

  final double sqlUnprepared = pointSql(false);
  final double sqlPrepared = pointSql(true);
  print('--- point reads, $shape, per document, microseconds');
  print(
      'SQL alone, a statement prepared per call (as the store does): ${sqlUnprepared.toStringAsFixed(1)} us '
      '(${shape == 'acked' ? 'the overlay lookup that finds nothing + the document lookup' : 'the overlay lookup'}); '
      'statements prepared once: ${sqlPrepared.toStringAsFixed(1)} us');
  if (shape == 'acked') {
    final double dec = timeIt(reps, () {
      for (final Uint8List b in pointBlobs) {
        serializer.decodeMaybeDocument(proto.MaybeDocument.fromBuffer(b));
      }
    });
    print(
        'decode alone (parse + Document): ${(dec * 1000 / pointBlobs.length).toStringAsFixed(1)} us');
  } else {
    final Timestamp now = Timestamp.now();
    final double dec = timeIt(reps, () {
      for (final Uint8List b in pointBlobs) {
        serializer
            .decodeOverlayMutation(proto.Write.fromBuffer(b))
            .applyToLocalView(null, null, now);
      }
    });
    print(
        'decode alone (parse + SetMutation + applyToLocalView): ${(dec * 1000 / pointBlobs.length).toStringAsFixed(1)} us');
  }
  db.dispose();
}

// ---------------------------------------------------------------------------------------------------------------------
// Cold: the first read after opening the file.

Future<void> cold(String shape, String file, String which) async {
  final Stopwatch sw = Stopwatch()..start();
  TimedDatabase.reset();
  final (SQLitePersistence persistence, LocalStore store) = await open(file);
  final double openMs = sw.elapsedMicroseconds / 1000;
  final int openSelectUs = TimedDatabase.selectUs;
  TimedDatabase.reset();
  final String line;
  if (which == 'point') {
    final List<DocumentKey> keys = randomSmallKeys(11, 2);
    sw.reset();
    await store.readDocument(keys[0]);
    final double first = sw.elapsedMicroseconds / 1000;
    final int selectUs = TimedDatabase.selectUs;
    sw.reset();
    await store.readDocument(keys[1]);
    final double second = sw.elapsedMicroseconds / 1000;
    line =
        'open ${ms(openMs)} first read ${ms(first)} (sqlite ${ms(selectUs / 1000)}) second read, other key ${ms(second)}';
  } else {
    final Query q = queryOf(which.replaceAll('i', ''));
    sw.reset();
    final QueryResult r = await store.executeQuery(q, true);
    final double storeMs = sw.elapsedMicroseconds / 1000;
    final int selectUs = TimedDatabase.selectUs;
    sw.reset();
    final View view = View(q, r.remoteKeys);
    view.applyChanges(view.computeDocChanges(r.documents));
    final double viewMs = sw.elapsedMicroseconds / 1000;
    line =
        'open ${ms(openMs)} (sqlite ${ms(openSelectUs / 1000)}) store ${ms(storeMs)} (sqlite ${ms(selectUs / 1000)}) '
        'view ${ms(viewMs)} total ${ms(storeMs + viewMs)}';
  }
  print('COLD $shape $which: $line');
  await persistence.shutdown();
}

// ---------------------------------------------------------------------------------------------------------------------
// The CPU profile.

const String bSqlite = '1 SQLite: sqlite3 package (prepare, step, column copy)';
const String bProto = '2a decode: protobuf parse';
const String bModel = '2b decode: model build (Document, ObjectValue, values, keys)';
const String bQuery = '3 query work (match, sort, limit, view, overlay apply)';
const String bAdapter = '4a adapter: row to Map copy';
const String bAsync = '4b async and futures';
const String bGc = '4c garbage collection';
const String bOther = '4d other';
const String bGlue = '4e store glue (row access, paging, wrappers of the SQLite caches)';

String bucketOf(String name, String url) {
  // Comparing and hashing keys, paths and values is query work wherever the method lives.
  if (name == 'compareTo' ||
      name == 'compare' ||
      name == '==' ||
      name == 'hashCode' ||
      name == '_compareSegments' ||
      name == '_numericId' ||
      name == 'compareUtf8Strings' ||
      name == 'isPrefixOf') {
    return bQuery;
  }
  if (url.contains('package:sqlite3/') || url.contains('/sqlite3-') || url.contains('sdk/lib/ffi')) {
    return bSqlite;
  }
  if (url.contains('cache_read_profile_bench.dart')) {
    return bAdapter;
  }
  if (url.contains('package:protobuf/') || url.contains('/protobuf-') || url.contains('/src/proto/')) {
    return bProto;
  }
  if (url.contains('sqlite_remote_document_cache.dart') ||
      url.contains('sqlite_document_overlay_cache.dart') ||
      url.contains('sqlite_persistence.dart') ||
      url.contains('stored_proto.dart')) {
    return bGlue;
  }
  if (url.contains('local_serializer.dart') ||
      url.contains('remote_serializer.dart') ||
      url.contains('model/document.dart') ||
      url.contains('model/value/') ||
      url.contains('model/mutation/') ||
      url.contains('field_path.dart') ||
      url.contains('resource_path.dart') ||
      url.contains('document_key.dart') ||
      url.contains('encoded_path.dart') ||
      url.contains('timestamp.dart') ||
      url.contains('snapshot_version.dart')) {
    return bModel;
  }
  if (url.contains('core/query.dart') ||
      url.contains('core/filter/') ||
      url.contains('core/order_by.dart') ||
      url.contains('core/view.dart') ||
      url.contains('core/document_view') ||
      url.contains('document_set') ||
      url.contains('database_collection/') ||
      url.contains('default_query_engine.dart') ||
      url.contains('local_documents_view.dart') ||
      url.contains('local_store.dart') ||
      url.contains('view_snapshot.dart')) {
    return bQuery;
  }
  if (url.contains('sdk/lib/async') || url.contains('dart:async')) {
    return bAsync;
  }
  return bOther;
}

Future<void> profile(String shape, String file, String which, int reps) async {
  final developer.ServiceProtocolInfo info = await developer.Service.getInfo();
  // ignore: sdk_version_since
  final Uri? uri = info.serverWebSocketUri;
  if (uri == null) {
    throw StateError(
        'run with --enable-vm-service=0 --disable-service-auth-codes');
  }
  final vms.VmService service =
      await vms_io.vmServiceConnectUri(uri.toString());
  // ignore: sdk_version_since
  final String isolateId = developer.Service.getIsolateId(Isolate.current)!;
  final (SQLitePersistence persistence, LocalStore store) = await open(file);

  Future<void> body() async {
    if (which == 'point') {
      for (final DocumentKey key in randomSmallKeys(7, 1000)) {
        await store.readDocument(key);
      }
    } else {
      final Query q = queryOf(which);
      final QueryResult r = await store.executeQuery(q, true);
      final View view = View(q, r.remoteKeys);
      view.applyChanges(view.computeDocChanges(r.documents));
    }
  }

  for (int i = 0; i < 3; i++) {
    await body();
  }
  await service.clearCpuSamples(isolateId);
  final Stopwatch sw = Stopwatch()..start();
  for (int i = 0; i < reps; i++) {
    await body();
  }
  final double wallMs = sw.elapsedMicroseconds / 1000 / reps;
  final vms.CpuSamples samples =
      await service.getCpuSamples(isolateId, 0, 1 << 50);
  final int period = samples.samplePeriod ?? 1000;
  final Map<String, int> buckets = <String, int>{};
  final Map<String, int> self = <String, int>{};
  final Map<String, int> tags = <String, int>{};
  final Map<String, int> inclusive = <String, int>{};
  final List<(String, String, String)> functions = <(String, String, String)>[
    for (final vms.ProfileFunction pf in samples.functions!)
      (_nameOf(pf.function), pf.resolvedUrl ?? '', _ownerOf(pf.function)),
  ];
  int total = 0;
  for (final vms.CpuSample s in samples.samples!) {
    total++;
    final String tag = s.vmTag ?? '?';
    tags[tag] = (tags[tag] ?? 0) + 1;
    final List<int> stack = s.stack ?? const <int>[];
    String bucket = bOther;
    if (tag.startsWith('GC')) {
      bucket = bGc;
    } else {
      // The layer of the frame closest to the leaf that belongs to one (async frames only when nothing else does).
      bool async = false;
      bool found = false;
      for (final int index in stack) {
        final (String name, String url, String owner) = functions[index];
        final String b = bucketOf(name, url);
        if (b == bAsync) {
          async = true;
        } else if (b != bOther) {
          bucket = b;
          found = true;
          break;
        }
      }
      if (!found && async) {
        bucket = bAsync;
      }
    }
    buckets[bucket] = (buckets[bucket] ?? 0) + 1;
    final Set<String> seen = <String>{};
    for (final int index in stack) {
      final (String name, String url, String owner) = functions[index];
      if (url.contains('org-dartlang-sdk') || url.contains('/collection-')) {
        continue;
      }
      final String key = '$owner.$name  [${url.split('/').last}]';
      if (seen.add(key)) {
        inclusive[key] = (inclusive[key] ?? 0) + 1;
      }
    }
    if (stack.isNotEmpty) {
      final (String name, String url, String owner) = functions[stack.first];
      final String key = '$owner.$name  [${url.split('/').last}]${bucketOf(name, url) == bOther ? '  <${url}>' : ''}';
      self[key] = (self[key] ?? 0) + 1;
    }
  }
  double perRun(int n) => n * period / 1000 / reps;
  print(
      '=== profile $shape $which: $reps runs, wall ${ms(wallMs)} ms per run, $total samples at ${period} us '
      '(${ms(perRun(total))} ms sampled per run)');
  print('--- layers (the frame closest to the leaf that belongs to one)');
  for (final MapEntry<String, int> e in buckets.entries.toList()
    ..sort((MapEntry<String, int> a, MapEntry<String, int> b) =>
        a.key.compareTo(b.key))) {
    print(
        '${e.key.padRight(66)} ${ms(perRun(e.value)).padLeft(9)} ms ${(100 * e.value / total).toStringAsFixed(1).padLeft(5)} %');
  }
  print('--- vm tags');
  for (final MapEntry<String, int> e in tags.entries) {
    print('${e.key.padRight(20)} ${(100 * e.value / total).toStringAsFixed(1)} %');
  }
  print('--- top functions by inclusive time (the function or anything it calls; Dart SDK and collection frames left out)');
  for (final MapEntry<String, int> e in (inclusive.entries.toList()
        ..sort((MapEntry<String, int> a, MapEntry<String, int> b) =>
            b.value.compareTo(a.value)))
      .take(40)) {
    print(
        '${(100 * e.value / total).toStringAsFixed(1).padLeft(5)} %  ${ms(perRun(e.value)).padLeft(8)} ms  ${e.key}');
  }
  print('--- top self functions');
  for (final MapEntry<String, int> e in (self.entries.toList()
        ..sort((MapEntry<String, int> a, MapEntry<String, int> b) =>
            b.value.compareTo(a.value)))
      .take(30)) {
    print(
        '${(100 * e.value / total).toStringAsFixed(1).padLeft(5)} %  ${ms(perRun(e.value)).padLeft(8)} ms  ${e.key}');
  }
  await persistence.shutdown();
  await service.dispose();
}

String _nameOf(Object? function) {
  if (function is vms.FuncRef) {
    return function.name ?? '?';
  }
  if (function is vms.NativeFunction) {
    return function.name ?? '?';
  }
  return '$function';
}

String _ownerOf(Object? function) {
  if (function is vms.FuncRef) {
    final Object? owner = function.owner;
    if (owner is vms.ClassRef) {
      return owner.name ?? '?';
    }
    if (owner is vms.LibraryRef) {
      return owner.name ?? '';
    }
    if (owner is vms.FuncRef) {
      return _ownerOf(owner);
    }
  }
  return '';
}

Future<void> main(List<String> args) async {
  final List<String> flags =
      args.where((String a) => a.startsWith('--')).toList();
  final List<String> a =
      args.where((String a) => !a.startsWith('--')).toList();
  int reps = 7;
  TimedDatabase.statementCache = !flags.contains('--no-statement-cache');
  for (final String flag in flags) {
    if (flag.startsWith('--reps=')) {
      reps = int.parse(flag.substring(7));
    } else if (flag.startsWith('--big=')) {
      bigDocs = int.parse(flag.substring(6));
    } else if (flag.startsWith('--small=')) {
      smallCollections = int.parse(flag.substring(8));
    }
  }
  switch (a[0]) {
    case 'fill':
      await fill(a[1], a[2], listened: flags.contains('--listened'));
    case 'index':
      await addIndexes(a[1], a[2]);
    case 'time':
      await timeAll(a[1], a[2], a.length > 3 ? a[3] : null, reps);
    case 'raw':
      await raw(a[1], a[2], reps);
    case 'cold':
      await cold(a[1], a[2], a[3]);
    case 'profile':
      await profile(a[1], a[2], a[3], a.length > 4 ? int.parse(a[4]) : 5);
    default:
      throw ArgumentError('unknown mode ${a[0]}');
  }
  exit(0);
}

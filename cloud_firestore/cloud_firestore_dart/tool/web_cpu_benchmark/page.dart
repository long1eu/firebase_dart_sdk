// The page of the web CPU benchmark (run.dart starts it): measures the client
// work that does not wait for storage or the network, so that the same page
// compiled with dart2js and with dart2wasm can be compared. Reports one JSON
// object to the server that served it.
//
// Query parameters:
//   suite=cpu     serialization, queries on a memory cache, a batch of writes
//                 with its listeners, a remote event through the sync engine,
//                 and the memory after 50,000 documents
//   suite=sqlite  the same queries on a SQLite cache, `storage=indexeddb` or
//                 `storage=opfs`, `docs=<count>`
//   reps=<n>      measured repetitions of each case in the page (after one
//                 warm-up repetition); the page reports their median
//
// Every time is in milliseconds.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/database_collection/immutable_sorted_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto_v1;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:cloud_firestore_dart_sqlite/web.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:grpc/grpc.dart';
import 'package:web/web.dart' as web;

// The serializers, the user data reader and the shapes of the VM benchmark.
import '../../../../tool/bench/serialization_bench.dart'
    show deep, docKey, leaf, local, reader, remote;

const String projectId = 'demo-bench';
const bool isWasm = bool.fromEnvironment('dart.tool.dart2wasm');

late final int reps;
final Map<String, Object?> results = <String, Object?>{};

Future<void> main() async {
  final Map<String, String> query = Uri.base.queryParameters;
  reps = int.parse(query['reps'] ?? '5');
  try {
    switch (query['suite']) {
      case 'cpu':
        serialization();
        for (final int docs in <int>[1000, 10000, 50000]) {
          await memoryQueries(docs);
        }
        await writeFanOut(1);
        await writeFanOut(20);
        await remoteEvent(1000);
        await memoryAfterLoad(50000);
      case 'sqlite':
        await sqliteQueries(query['storage']!, int.parse(query['docs']!));
      default:
        throw ArgumentError('suite=${query['suite']}');
    }
    await report('result', results);
  } catch (error, stackTrace) {
    await report('error', <String, Object?>{
      ...results,
      'error': '$error',
      'stack': '$stackTrace',
    });
  }
}

Future<void> report(String kind, Map<String, Object?> body) async {
  await web.window
      .fetch(
        '/$kind'.toJS,
        web.RequestInit(
          method: 'POST',
          body: jsonEncode(<String, Object?>{
            'compiler': isWasm ? 'dart2wasm' : 'dart2js',
            ...body,
          }).toJS,
        ),
      )
      .toDart;
}

double median(List<double> values) {
  final List<double> sorted = values.toList()..sort();
  return sorted[sorted.length ~/ 2];
}

/// Runs [body] once to warm up, then [reps] times, and records the median.
Future<void> measure(String name, FutureOr<void> Function() body) async {
  await body();
  final List<double> samples = <double>[];
  for (int i = 0; i < reps; i++) {
    final Stopwatch watch = Stopwatch()..start();
    await body();
    samples.add(watch.elapsedMicroseconds / 1000);
  }
  results[name] = median(samples);
}

/// Like [measure] for an operation of a few microseconds: each sample runs it
/// as many times as fit in about 20 ms, and the result is the time of one
/// operation, in microseconds (`name` ends with `_us`).
void measureMicro(String name, void Function() body) {
  int iterations = 1;
  while (true) {
    final Stopwatch watch = Stopwatch()..start();
    for (int i = 0; i < iterations; i++) {
      body();
    }
    if (watch.elapsedMilliseconds >= 20) {
      break;
    }
    iterations *= 2;
  }
  final List<double> samples = <double>[];
  for (int r = 0; r < reps; r++) {
    final Stopwatch watch = Stopwatch()..start();
    for (int i = 0; i < iterations; i++) {
      body();
    }
    samples.add(watch.elapsedMicroseconds / iterations);
  }
  results[name] = median(samples);
}

// ---------------------------------------------------------------------------
// Serialization: a user map to the bytes sent to the backend and back, and a
// document to the bytes stored in a persistent cache and back.

final Map<String, Map<String, Object?> Function()> shapes =
    <String, Map<String, Object?> Function()>{
      'small': () => <String, Object?>{
        'name': 'Ada',
        'age': 36,
        'active': true,
        'score': 4.5,
      },
      '1kb': () => <String, Object?>{
        for (int i = 0; i < 6; i++) 'f$i': leaf(i),
        'text': 'x' * 300,
      },
      '50kb': () => <String, Object?>{
        for (int i = 0; i < 400; i++) 'f$i': leaf(i),
      },
      'deep20': () => deep(20),
    };

void serialization() {
  for (final MapEntry<String, Map<String, Object?> Function()> shape
      in shapes.entries) {
    final Map<String, Object?> input = shape.value();
    ObjectValue parse() =>
        (reader.parseSetData(input).toMutation(docKey, Precondition.none)
                as SetMutation)
            .value;
    final ObjectValue parsed = parse();
    final Uint8List bytes = remote.encodeValue(parsed).writeToBuffer();
    final Document document = Document(
      docKey,
      SnapshotVersion(Timestamp(1, 0)),
      DocumentState.synced,
      parsed,
    );
    final Uint8List stored = local
        .encodeMaybeDocument(document)
        .writeToBuffer();
    results['ser_${shape.key}_bytes'] = bytes.length;

    measureMicro('ser_${shape.key}_remote_encode_us', () {
      remote.encodeValue(parse()).writeToBuffer();
    });
    measureMicro('ser_${shape.key}_remote_decode_us', () {
      remote.decodeValue(proto_v1.Value.fromBuffer(bytes));
    });
    measureMicro('ser_${shape.key}_local_encode_us', () {
      local.encodeMaybeDocument(document).writeToBuffer();
    });
    measureMicro('ser_${shape.key}_local_decode_us', () {
      final MaybeDocument read = local.decodeMaybeDocument(
        proto.MaybeDocument.fromBuffer(stored),
      );
      (read as Document).data;
    });
  }
}

// ---------------------------------------------------------------------------
// A client with its network disabled, filled from a bundle.

int appCount = 0;

FirebaseFirestore newClient({OpenDatabase? openDatabase}) {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:dart:bench',
      projectId: projectId,
    ),
    name: 'bench${appCount++}',
  );
  return FirebaseFirestore.instanceFor(
    app: app,
    openDatabase: openDatabase,
    settings: Settings(
      cacheSettings: openDatabase == null
          ? const MemoryCacheSettings()
          : PersistentCacheSettings(sizeBytes: Settings.cacheSizeUnlimited),
    ).withEmulator('127.0.0.1', 9),
  );
}

/// About 250 bytes of fields per document.
String documentJson(String root, String collection, int i) {
  final Random random = Random(i);
  final String text = String.fromCharCodes(
    List<int>.generate(100, (_) => 97 + random.nextInt(26)),
  );
  return '{"document":{"name":"$root/$collection/d$i",'
      '"createTime":{"seconds":1,"nanos":0},'
      '"updateTime":{"seconds":1,"nanos":0},"fields":{'
      '"n":{"integerValue":"$i"},'
      '"g":{"integerValue":"${i % 10}"},'
      '"title":{"stringValue":"Document number $i"},'
      '"tags":{"arrayValue":{"values":[{"stringValue":"t${i % 7}"},'
      '{"stringValue":"u${i % 13}"}]}},'
      '"text":{"stringValue":"$text"}}}}';
}

/// A bundle of [docs] documents in [collection], in chunks of 1000.
List<List<int>> bundle(String collection, int docs) {
  const String root = 'projects/$projectId/databases/(default)/documents';
  const String readTime = '{"seconds":1000,"nanos":0}';
  String chunk(int from, int to) {
    final StringBuffer out = StringBuffer();
    for (int i = from; i < to; i++) {
      for (final String element in <String>[
        '{"documentMetadata":{"name":"$root/$collection/d$i",'
            '"readTime":$readTime,"exists":true}}',
        documentJson(root, collection, i),
      ]) {
        out
          ..write(utf8.encode(element).length)
          ..write(element);
      }
    }
    return out.toString();
  }

  final List<List<int>> chunks = <List<int>>[
    for (int i = 0; i < docs; i += 1000)
      utf8.encode(chunk(i, min(i + 1000, docs))),
  ];
  final int totalBytes = chunks.fold(
    0,
    (int sum, List<int> c) => sum + c.length,
  );
  final String metadata =
      '{"metadata":{"id":"bench-$collection-$docs",'
      '"createTime":{"seconds":1001,"nanos":0},'
      '"version":1,"totalDocuments":$docs,"totalBytes":$totalBytes}}';
  return <List<int>>[
    utf8.encode('${utf8.encode(metadata).length}$metadata'),
    ...chunks,
  ];
}

Future<void> load(FirebaseFirestore firestore, List<List<int>> data) async {
  final LoadBundleTaskSnapshot done = await firestore
      .loadBundleStream(Stream<List<int>>.fromIterable(data))
      .future;
  if (done.taskState != LoadBundleTaskState.success) {
    throw StateError('the bundle did not load: ${done.taskState}');
  }
}

/// The three queries of the memory and the SQLite caches, each read from the
/// cache: a filter that the cache answers by a scan, `orderBy` with `limit`,
/// and the first snapshot of a listener on a filter that matches a tenth.
Future<void> queries(
  String prefix,
  CollectionReference<Map<String, Object?>> coll,
  int docs,
) async {
  const GetOptions cache = GetOptions(source: Source.cache);
  await measure('${prefix}_filter', () async {
    final QuerySnapshot<Map<String, Object?>> s = await coll
        .where('n', isEqualTo: docs ~/ 2)
        .get(cache);
    if (s.size != 1) {
      throw StateError('the filter found ${s.size}');
    }
  });
  await measure('${prefix}_orderby_limit', () async {
    final QuerySnapshot<Map<String, Object?>> s = await coll
        .orderBy('n', descending: true)
        .limit(10)
        .get(cache);
    if (s.size != 10 || s.docs.first.data()['n'] != docs - 1) {
      throw StateError('orderBy and limit found ${s.size}');
    }
  });
  await measure('${prefix}_listener_first', () async {
    final QuerySnapshot<Map<String, Object?>> s = await coll
        .where('g', isEqualTo: 3)
        .snapshots()
        .first;
    if (s.size != docs ~/ 10 || s.docChanges.length != s.size) {
      throw StateError('the listener got ${s.size}');
    }
  });
}

Future<void> memoryQueries(int docs) async {
  final List<List<int>> data = bundle('q', docs);
  final FirebaseFirestore firestore = newClient();
  await firestore.disableNetwork();
  final Stopwatch watch = Stopwatch()..start();
  await load(firestore, data);
  results['mem_${docs}_bundle_load'] = watch.elapsedMicroseconds / 1000;
  await queries('mem_$docs', firestore.collection('q'), docs);
  await firestore.terminate();
}

// ---------------------------------------------------------------------------
// A batch of 500 writes and the snapshots it raises: from `commit()` to the
// moment every listener has seen all 500 documents (latency compensation; the
// commit itself never completes, the network is off). Each listener has its
// own query, so each has its own view to update.

Future<void> writeFanOut(int listeners) async {
  const int writes = 500;
  final List<double> samples = <double>[];
  for (int round = 0; round <= reps; round++) {
    // A new client every time, so that the queue of pending writes does not
    // grow from one repetition to the next. Setting it up is not measured.
    final FirebaseFirestore firestore = newClient();
    await firestore.disableNetwork();
    final CollectionReference<Map<String, Object?>> coll = firestore.collection(
      'w',
    );
    final List<Completer<void>> seen = <Completer<void>>[];
    final List<StreamSubscription<QuerySnapshot<Map<String, Object?>>>> subs =
        <StreamSubscription<QuerySnapshot<Map<String, Object?>>>>[];
    for (int j = 0; j < listeners; j++) {
      final Completer<void> first = Completer<void>();
      final Completer<void> all = Completer<void>();
      seen.add(all);
      subs.add(
        coll.where('n', isGreaterThanOrEqualTo: -1 - j).snapshots().listen((
          QuerySnapshot<Map<String, Object?>> s,
        ) {
          // What a screen reads: the changes of the snapshot.
          s.docChanges.length;
          if (!first.isCompleted) {
            first.complete();
          }
          if (s.size == writes && !all.isCompleted) {
            all.complete();
          }
        }),
      );
      await first.future;
    }
    final Stopwatch watch = Stopwatch()..start();
    final WriteBatch batch = firestore.batch();
    for (int i = 0; i < writes; i++) {
      batch.set(coll.doc('d$i'), <String, Object?>{
        'n': i,
        'round': round,
        'title': 'Document number $i',
        'tags': <String>['t${i % 7}', 'u${i % 13}'],
      });
    }
    unawaited(batch.commit());
    await Future.wait(seen.map((Completer<void> c) => c.future));
    final double ms = watch.elapsedMicroseconds / 1000;
    for (final StreamSubscription<Object?> sub in subs) {
      await sub.cancel();
    }
    await firestore.terminate();
    // The first round is the warm-up.
    if (round > 0) {
      samples.add(ms);
    }
  }
  results['write_500_fanout_$listeners'] = median(samples);
}

// ---------------------------------------------------------------------------
// A remote event that modifies 1,000 documents of a listened query, through
// the sync engine and the local store of a memory cache: what the client does
// when the backend sends a batch of changes (apply them to the cache, compute
// the view, raise the snapshot). The watch stream is not involved.

class _NoRemoteStore implements RemoteStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _Snapshots implements SyncEngineCallback {
  final List<ViewSnapshot> snapshots = <ViewSnapshot>[];

  @override
  Future<void> onViewSnapshots(List<ViewSnapshot> snapshotList) async {
    snapshots.addAll(snapshotList);
  }

  @override
  void onError(core.Query query, GrpcError error) {}

  @override
  void handleOnlineStateChange(OnlineState onlineState) {}
}

Future<void> remoteEvent(int docs) async {
  final MemoryPersistence persistence =
      MemoryPersistence.createEagerGcMemoryPersistence();
  await persistence.start();
  final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
  await localStore.start();
  final _Snapshots callback = _Snapshots();
  final SyncEngine syncEngine = SyncEngine(
    localStore,
    _NoRemoteStore(),
    User.unauthenticated,
  )..syncEngineListener = callback;
  final int targetId = await syncEngine.listen(
    core.Query(ResourcePath.fromString('r')),
  );

  final List<DocumentKey> keys = <DocumentKey>[
    for (int i = 0; i < docs; i++) DocumentKey.fromPathString('r/d$i'),
  ];
  ImmutableSortedSet<DocumentKey> added = DocumentKey.emptyKeySet;
  for (final DocumentKey key in keys) {
    added = added.insert(key);
  }

  int version = 1;
  RemoteEvent event({required bool first}) {
    final SnapshotVersion snapshotVersion = SnapshotVersion(
      Timestamp(version, 0),
    );
    final int round = version++;
    return RemoteEvent(
      snapshotVersion: snapshotVersion,
      targetChanges: <int, TargetChange>{
        targetId: TargetChange(
          resumeToken: Uint8List.fromList(<int>[round]),
          current: true,
          addedDocuments: first ? added : DocumentKey.emptyKeySet,
          modifiedDocuments: first ? DocumentKey.emptyKeySet : added,
          removedDocuments: DocumentKey.emptyKeySet,
        ),
      },
      documentUpdates: <DocumentKey, Document>{
        for (int i = 0; i < docs; i++)
          keys[i]: Document(
            keys[i],
            snapshotVersion,
            DocumentState.synced,
            (reader
                        .parseSetData(<String, Object?>{
                          'n': i,
                          'round': round,
                          'title': 'Document number $i',
                          'tags': <String>['t${i % 7}', 'u${i % 13}'],
                        })
                        .toMutation(keys[i], Precondition.none)
                    as SetMutation)
                .value,
          ),
      },
      resolvedLimboDocuments: const <DocumentKey>{},
    );
  }

  // The first event adds the documents; the measured ones modify all of them.
  await syncEngine.handleRemoteEvent(event(first: true));
  final List<double> samples = <double>[];
  for (int r = 0; r <= reps; r++) {
    final RemoteEvent next = event(first: false);
    final int before = callback.snapshots.length;
    final Stopwatch watch = Stopwatch()..start();
    await syncEngine.handleRemoteEvent(next);
    final double ms = watch.elapsedMicroseconds / 1000;
    if (callback.snapshots.length != before + 1 ||
        callback.snapshots.last.changes.length != docs) {
      throw StateError('the remote event raised no snapshot of $docs changes');
    }
    if (r > 0) {
      samples.add(ms);
    }
  }
  results['remote_event_$docs'] = median(samples);
  await persistence.shutdown();
}

// ---------------------------------------------------------------------------
// Memory: `performance.measureUserAgentSpecificMemory` (JavaScript heaps,
// which hold the WasmGC objects of a dart2wasm program too, plus array buffers
// and WebAssembly memories), before and after loading documents into a memory
// cache, with the client still holding them.

Future<int> memory() async {
  final JSObject performance = web.window.performance as JSObject;
  final JSObject result = await performance
      .callMethod<JSPromise<JSObject>>('measureUserAgentSpecificMemory'.toJS)
      .toDart;
  return (result['bytes']! as JSNumber).toDartInt;
}

Future<void> memoryAfterLoad(int docs) async {
  final List<List<int>> data = bundle('m', docs);
  final int before = await memory();
  final FirebaseFirestore firestore = newClient();
  await firestore.disableNetwork();
  await load(firestore, data);
  final int after = await memory();
  results['memory_before_mb'] = before / (1 << 20);
  results['memory_${docs}_mb'] = after / (1 << 20);
  results['memory_${docs}_delta_mb'] = (after - before) / (1 << 20);
  // Keeps the client (and its cache) alive until after the measurement.
  await firestore.terminate();
}

// ---------------------------------------------------------------------------
// The same queries on a SQLite cache, in IndexedDB or OPFS: the I/O-bound
// case next to the CPU-bound ones.

Future<void> sqliteQueries(String storage, int docs) async {
  OpenDatabase opener() => sqliteWebOpener(
    sqlite3Wasm: Uri.parse('sqlite3.wasm'),
    opfsWorker: storage == 'opfs' ? Uri.parse('sqlite_opfs_worker.js') : null,
  );
  final List<List<int>> data = bundle('q', docs);
  final FirebaseFirestore filler = newClient(openDatabase: opener());
  await filler.disableNetwork();
  final Stopwatch watch = Stopwatch()..start();
  await load(filler, data);
  results['${storage}_${docs}_bundle_load'] = watch.elapsedMicroseconds / 1000;
  await queries('${storage}_$docs', filler.collection('q'), docs);
  await filler.terminate();
}

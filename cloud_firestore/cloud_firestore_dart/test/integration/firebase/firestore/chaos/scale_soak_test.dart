// A scale soak: many clients, spread over worker isolates of this process, each with several listeners, do random
// writes, batched writes and transactions on a shared set of documents while their networks fail, are disabled and
// enabled, and while they are terminated and restarted on their SQLite files. Then everything is restored, and
//
//  * every listener of every client settles on the backend state, without a broken snapshot on the way;
//  * the cache of every client holds exactly the backend state;
//  * after terminate, no timer of the client is left and every worker isolate exits by itself (an isolate only exits
//    when nothing keeps it alive: no timer, no open socket or port, no pending stream).
//
// It is opt-in: it only runs with SCALE_SOAK_SECONDS set, against the emulator.
//
//   SCALE_SOAK_SECONDS    how long the random phase lasts (required)
//   SCALE_SOAK_ISOLATES   the number of worker isolates (default 1)
//   SCALE_SOAK_CLIENTS    the number of clients in each worker isolate (default 4)
//   SCALE_SOAK_LISTENERS  the number of listeners of each client, at least 1 (default 4)
//   SCALE_SOAK_DOCS       the number of documents the clients share (default 12)
//   SCALE_SOAK_SEED       the seed of the operations (default: taken from the clock and printed)
//
// The seed fixes the sequence of operations of each client, not their timing.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/internal.dart' show InternalLogLevel;
import 'package:test/test.dart';

import '../../../../unit/firebase/firestore/local/mock/database_mock.dart';
import '../../../../util/chaos_proxy.dart';
import '../../../../util/integration_test_util.dart';
import '../../../../util/test_backend.dart';
import 'chaos_util.dart';

int? _env(String name) => int.tryParse(Platform.environment[name] ?? '');

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/scale_soak';
  final int? seconds = _env('SCALE_SOAK_SECONDS');
  final _SoakConfig config = _SoakConfig(
    seconds: seconds ?? 0,
    isolates: _env('SCALE_SOAK_ISOLATES') ?? 1,
    clients: _env('SCALE_SOAK_CLIENTS') ?? 4,
    listeners: max(1, _env('SCALE_SOAK_LISTENERS') ?? 4),
    docs: _env('SCALE_SOAK_DOCS') ?? 12,
    seed:
        _env('SCALE_SOAK_SEED') ??
        DateTime.now().millisecondsSinceEpoch % 1000000,
    collection: uniqueName('scale-soak'),
  );

  test(
    'many clients in several isolates converge on the backend state',
    () async {
      final String logs = DatabaseMock.pathForName(
        'integration/scale_soak/${config.collection}_w*.log',
      ).path;
      // ignore: avoid_print
      print('scale soak: $config, logs in $logs');
      Never hung(String phase) => fail(
        'A worker hung in $phase (rerun with SCALE_SOAK_SEED=${config.seed} '
        '${config.describeEnv()}). The last line of each client in $logs '
        'shows where it stopped.',
      );
      final Firestore oracle = await IntegrationTestUtil.testFirestore();
      final List<_Worker> workers = <_Worker>[
        for (int i = 0; i < config.isolates; i++)
          await _Worker.spawn(i, config),
      ];
      try {
        // The random phase, then every worker drains its writes against a working network.
        final List<Map<String, Object?>> quiesced =
            await Future.wait(<Future<Map<String, Object?>>>[
              for (final _Worker worker in workers) worker.next(),
            ]).timeout(
              Duration(seconds: config.seconds + 240),
              onTimeout: () => hung('the random phase or the quiesce'),
            );
        final List<String> problems = <String>[
          for (final Map<String, Object?> message in quiesced)
            ...(message['problems']! as List<Object?>).cast<String>(),
        ];

        final Map<String, Map<String, Object?>> server = docsById(
          await oracle.collection(config.collection).get(Source.server),
        );
        // ignore: avoid_print
        print('scale soak: backend has ${server.length} documents');
        for (final _Worker worker in workers) {
          worker.send(server);
        }
        final List<Map<String, Object?>> results =
            await Future.wait(<Future<Map<String, Object?>>>[
              for (final _Worker worker in workers) worker.next(),
            ]).timeout(
              const Duration(seconds: 240),
              onTimeout: () => hung('the verification or the terminate'),
            );
        for (final Map<String, Object?> result in results) {
          problems.addAll(
            (result['problems']! as List<Object?>).cast<String>(),
          );
          // ignore: avoid_print
          print('scale soak: ${result['stats']}');
        }

        // Nothing keeps a worker alive once its clients are terminated.
        for (final _Worker worker in workers) {
          if (!await worker.exited(const Duration(seconds: 30))) {
            problems.add(
              'worker ${worker.id} did not exit within 30 s after '
              'terminating its clients: something (a timer, a socket, a port) '
              'keeps it alive',
            );
          }
        }

        if (problems.isNotEmpty) {
          // ignore: avoid_print
          print(
            'SCALE SOAK FAILED: rerun with SCALE_SOAK_SEED=${config.seed} '
            '${config.describeEnv()}\n'
            '${results.map((Map<String, Object?> r) => r['log']).join('\n')}',
          );
        }
        expect(problems, isEmpty);
      } finally {
        for (final _Worker worker in workers) {
          worker.kill();
        }
        await IntegrationTestUtil.tearDown();
      }
    },
    skip: seconds == null
        ? 'Opt-in: set SCALE_SOAK_SECONDS to run the scale soak'
        : chaosSkipReason,
    timeout: Timeout(Duration(seconds: (seconds ?? 0) + 600)),
  );
}

class _SoakConfig {
  const _SoakConfig({
    required this.seconds,
    required this.isolates,
    required this.clients,
    required this.listeners,
    required this.docs,
    required this.seed,
    required this.collection,
  });

  _SoakConfig.fromMap(Map<String, Object?> map)
    : this(
        seconds: map['seconds']! as int,
        isolates: map['isolates']! as int,
        clients: map['clients']! as int,
        listeners: map['listeners']! as int,
        docs: map['docs']! as int,
        seed: map['seed']! as int,
        collection: map['collection']! as String,
      );

  final int seconds;
  final int isolates;
  final int clients;
  final int listeners;
  final int docs;
  final int seed;
  final String collection;

  Map<String, Object?> toMap() => <String, Object?>{
    'seconds': seconds,
    'isolates': isolates,
    'clients': clients,
    'listeners': listeners,
    'docs': docs,
    'seed': seed,
    'collection': collection,
  };

  String describeEnv() =>
      'SCALE_SOAK_SECONDS=$seconds '
      'SCALE_SOAK_ISOLATES=$isolates SCALE_SOAK_CLIENTS=$clients '
      'SCALE_SOAK_LISTENERS=$listeners SCALE_SOAK_DOCS=$docs';

  @override
  String toString() => 'seed=$seed ${describeEnv()}';
}

/// A worker isolate, seen from the test.
class _Worker {
  _Worker._(this.id, this._isolate, this._messages, this._exit);

  static Future<_Worker> spawn(int id, _SoakConfig config) async {
    final ReceivePort messages = ReceivePort();
    final ReceivePort exit = ReceivePort();
    final Isolate isolate = await Isolate.spawn(
      _workerMain,
      <String, Object?>{
        'id': id,
        'port': messages.sendPort,
        'config': config.toMap(),
      },
      onExit: exit.sendPort,
      // An uncaught error ends the worker; it arrives as a [error, stack] list.
      onError: messages.sendPort,
      errorsAreFatal: true,
      debugName: 'scale-soak-$id',
    );
    final _Worker worker = _Worker._(
      id,
      isolate,
      StreamIterator<Object?>(messages),
      exit,
    );
    if (!await worker._messages.moveNext()) {
      throw StateError('worker $id stopped before it started');
    }
    worker._commands = worker._messages.current! as SendPort;
    return worker;
  }

  final int id;
  final Isolate _isolate;
  final StreamIterator<Object?> _messages;
  final ReceivePort _exit;
  late final SendPort _commands;

  void send(Object? message) => _commands.send(message);

  Future<Map<String, Object?>> next() async {
    if (!await _messages.moveNext()) {
      throw StateError('worker $id stopped');
    }
    final Object? message = _messages.current;
    if (message is String) {
      throw StateError('worker $id failed: $message');
    }
    if (message is List) {
      throw StateError(
        'worker $id crashed with an uncaught error: ${message.join('\n')}',
      );
    }
    return (message! as Map<Object?, Object?>).cast<String, Object?>();
  }

  Future<bool> exited(Duration timeout) async {
    final bool exited = await _exit.first
        .then((_) => true)
        .timeout(timeout, onTimeout: () => false);
    _exit.close();
    return exited;
  }

  void kill() {
    _exit.close();
    unawaited(_messages.cancel());
    _isolate.kill(priority: Isolate.immediate);
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// The worker isolate. It does not use the test framework: problems are collected as strings and sent to the test.

Future<void> _workerMain(Map<String, Object?> args) async {
  final SendPort out = args['port']! as SendPort;
  final ReceivePort commands = ReceivePort();
  out.send(commands.sendPort);
  final StreamIterator<Object?> inbox = StreamIterator<Object?>(commands);
  final _TimerTracker timers = _TimerTracker();
  try {
    await timers.run(
      () => _work(
        args['id']! as int,
        _SoakConfig.fromMap(
          (args['config']! as Map<Object?, Object?>).cast<String, Object?>(),
        ),
        out,
        inbox,
        timers,
      ),
    );
  } catch (e, s) {
    out.send('$e\n$s');
  } finally {
    await inbox.cancel();
  }
}

Future<void> _work(
  int workerId,
  _SoakConfig config,
  SendPort out,
  StreamIterator<Object?> inbox,
  _TimerTracker timers,
) async {
  final EmulatorAddress emulator = EmulatorAddress.parse(
    IntegrationTestUtil.emulatorHost!,
  );
  final List<String> log = <String>[];
  final Stopwatch clock = Stopwatch()..start();
  // The whole log also goes to a file as it is written, to see where a worker that hangs stopped.
  final File logFile = DatabaseMock.pathForName(
    'integration/scale_soak/${config.collection}_w$workerId.log',
  )..createSync(recursive: true);
  final RandomAccessFile logSink = logFile.openSync(mode: FileMode.write);
  void record(String message) {
    final String line =
        '${clock.elapsedMilliseconds.toString().padLeft(7)} w$workerId $message';
    log.add(line);
    if (log.length > 4000) {
      // The file has all of it; the test only prints the end.
      log.removeRange(0, 2000);
    }
    logSink.writeStringSync('$line\n');
  }

  record('log file ${logFile.path}');

  final List<_Client> clients = <_Client>[];
  for (int i = 0; i < config.clients; i++) {
    final ChaosProxy proxy = await ChaosProxy.start(
      emulator.host,
      emulator.port,
    );
    final _Client client = _Client(
      id: 'w${workerId}c$i',
      config: config,
      proxy: proxy,
      dbName: 'integration/scale_soak/${config.collection}_w${workerId}c$i.db',
      random: Random(config.seed * 7919 + workerId * 1009 + i),
      record: record,
    );
    DatabaseMock.deleteDatabaseFiles(client.dbName);
    await client.start();
    clients.add(client);
  }

  final List<String> problems = <String>[];
  try {
    final DateTime end = DateTime.now().add(Duration(seconds: config.seconds));
    await Future.wait(<Future<void>>[
      for (final _Client client in clients) client.run(end),
    ]);
    record('--- quiesce');
    (await Future.wait(<Future<List<String>>>[
      for (final _Client client in clients) client.quiesce(),
    ])).forEach(problems.addAll);
    record('--- quiesced');
  } catch (e, s) {
    problems.add('worker $workerId failed in the random phase: $e\n$s');
  }
  out.send(<String, Object?>{'problems': problems});

  if (!await inbox.moveNext()) {
    return;
  }
  final Map<String, Map<String, Object?>> server =
      <String, Map<String, Object?>>{
        for (final MapEntry<Object?, Object?> entry
            in (inbox.current! as Map<Object?, Object?>).entries)
          entry.key! as String: (entry.value! as Map<Object?, Object?>)
              .cast<String, Object?>(),
      };
  problems.clear();
  (await Future.wait(<Future<List<String>>>[
    for (final _Client client in clients) client.verify(server),
  ])).forEach(problems.addAll);
  final List<String> stats = <String>[
    for (final _Client client in clients) client.stats(),
  ];
  for (final _Client client in clients) {
    await client.stop();
  }
  // Every timer of the clients is cancelled or has fired by now: terminate stops the async queue, and the proxies
  // are closed.
  await Future<void>.delayed(const Duration(seconds: 2));
  final List<String> leaked = timers.active();
  if (leaked.isNotEmpty) {
    problems.add(
      'worker $workerId: ${leaked.length} timers are still active '
      'after terminate:\n${leaked.take(5).join('\n')}',
    );
  }
  record('--- done: ${problems.length} problems');
  logSink.closeSync();
  if (problems.isEmpty) {
    logFile.deleteSync();
  }
  out.send(<String, Object?>{
    'problems': problems,
    'stats': 'worker $workerId: ${stats.join('; ')}',
    'log': problems.isEmpty
        ? ''
        : log.skip(max(0, log.length - 400)).join('\n'),
  });
}

/// Tracks the timers created in its zone, to name the ones that are still active.
class _TimerTracker {
  final Map<Timer, StackTrace> _timers = <Timer, StackTrace>{};

  Future<T> run<T>(Future<T> Function() body) {
    return runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        createTimer:
            (
              Zone self,
              ZoneDelegate parent,
              Zone zone,
              Duration duration,
              void Function() callback,
            ) {
              final Timer timer = parent.createTimer(zone, duration, callback);
              _track(timer);
              return timer;
            },
        createPeriodicTimer:
            (
              Zone self,
              ZoneDelegate parent,
              Zone zone,
              Duration period,
              void Function(Timer timer) callback,
            ) {
              final Timer timer = parent.createPeriodicTimer(
                zone,
                period,
                callback,
              );
              _track(timer);
              return timer;
            },
      ),
    );
  }

  void _track(Timer timer) {
    if (_timers.length >= 20000) {
      // Most timers fired long ago: keep the memory bounded over a long run.
      _timers.removeWhere((Timer timer, _) => !timer.isActive);
    }
    _timers[timer] = StackTrace.current;
  }

  List<String> active() {
    _timers.removeWhere((Timer timer, _) => !timer.isActive);
    return <String>[
      for (final MapEntry<Timer, StackTrace> entry in _timers.entries)
        entry.value.toString().split('\n').take(12).join('\n'),
    ];
  }
}

/// One client: a Firestore instance on its own SQLite file behind its own proxy, with its listeners.
class _Client {
  _Client({
    required this.id,
    required this.config,
    required this.proxy,
    required this.dbName,
    required this.random,
    required void Function(String message) record,
  }) : _record = record;

  final String id;
  final _SoakConfig config;
  final ChaosProxy proxy;
  final String dbName;
  final Random random;
  final void Function(String message) _record;

  late Firestore db;
  late CollectionReference<Map<String, Object?>> collection;
  final List<_Listener> listeners = <_Listener>[];

  /// The writes and transactions of the current instance, with their errors logged.
  List<Future<void>> _pending = <Future<void>>[];
  int _outstanding = 0;

  /// Whether the writes that a restarted instance found in its SQLite file are still pending. Until they land the
  /// client issues no new writes, so that the backlog stays as small as [_maxOutstanding] across restarts.
  bool _restartBacklog = false;
  int _generation = 0;
  bool _networkEnabled = true;
  int _ops = 0;

  final List<String> problems = <String>[];
  int restarts = 0;
  int networkToggles = 0;
  int writes = 0;
  int transactions = 0;
  int listens = 0;

  /// More unacknowledged writes than this and the client only does other things.
  static const int _maxOutstanding = 20;

  void record(String message) => _record('$id $message');

  Future<void> start() async {
    db = await IntegrationTestUtil.testFirestoreInstance(
      IntegrationTestUtil.provider.projectId,
      InternalLogLevel.e,
      FirestoreSettings(host: proxy.host, port: proxy.port, sslEnabled: false),
      IntegrationTestUtil.currentDatabasePath,
      fixedDbName: dbName,
    );
    _generation++;
    _networkEnabled = true;
    collection = db.collection(config.collection);
    listeners.add(_QueryListener(collection, null));
    for (int i = 1; i < config.listeners; i++) {
      listeners.add(_newListener());
    }
  }

  _Listener _newListener() {
    listens++;
    switch (random.nextInt(4)) {
      case 0:
        final int from = random.nextInt(1000);
        final int limit = 1 + random.nextInt(4);
        return _QueryListener(
          collection
              .where('v', isGreaterThanOrEqualTo: from)
              .orderBy('v')
              .limit(limit),
          _Expectation.range(from, limit),
        );
      case 1:
        final int tag = random.nextInt(4);
        return _QueryListener(
          collection.where('tags', arrayContains: tag),
          _Expectation.tagged(tag),
        );
      case 2:
        final int limit = 1 + random.nextInt(4);
        return _QueryListener(
          collection.orderBy('v', Direction.descending).limit(limit),
          _Expectation.top(limit),
        );
      default:
        return _DocListener(collection.doc(_docId()));
    }
  }

  String _docId() => 'k${random.nextInt(config.docs)}';

  DocumentReference<Map<String, Object?>> _doc() => collection.doc(_docId());

  void _track(String what, Future<void> future) {
    final int op = _ops++;
    final int generation = _generation;
    record('#$op $what');
    writes++;
    _outstanding++;
    final Future<void> logged = future
        .then(
          (_) => record('#$op ok'),
          onError: (Object e) {
            record('#$op failed: ${e is FirestoreError ? e.code : e}');
          },
        )
        .whenComplete(() {
          if (generation == _generation) {
            _outstanding--;
          }
        });
    _pending.add(logged);
  }

  Future<void> run(DateTime end) async {
    while (DateTime.now().isBefore(end)) {
      await _step();
      await Future<void>.delayed(Duration(milliseconds: random.nextInt(60)));
    }
  }

  Future<void> _step() async {
    int roll = random.nextInt(100);
    if (roll < 70 && (_outstanding >= _maxOutstanding || _restartBacklog)) {
      roll = 70 + random.nextInt(30);
    }
    final DocumentReference<Map<String, Object?>> doc = _doc();
    final int value = random.nextInt(1000);
    if (roll < 15) {
      _track(
        'set ${doc.id} v=$value',
        doc.set(<String, Object?>{'v': value, 'by': id}),
      );
    } else if (roll < 24) {
      _track(
        'merge ${doc.id} v=$value',
        doc.set(<String, Object?>{'v': value}, SetOptions.mergeAllFields),
      );
    } else if (roll < 32) {
      _track(
        'update ${doc.id} v=$value',
        doc.update(<String, Object?>{'v': value}),
      );
    } else if (roll < 39) {
      _track(
        'increment ${doc.id}',
        doc.set(<String, Object?>{
          'c': FieldValue.increment(1),
        }, SetOptions.mergeAllFields),
      );
    } else if (roll < 46) {
      final int tag = random.nextInt(4);
      final bool add = random.nextBool();
      _track(
        '${add ? 'arrayUnion' : 'arrayRemove'} ${doc.id} $tag',
        doc.set(<String, Object?>{
          'tags': add
              ? FieldValue.arrayUnion(<Object?>[tag])
              : FieldValue.arrayRemove(<Object?>[tag]),
        }, SetOptions.mergeAllFields),
      );
    } else if (roll < 52) {
      _track('delete ${doc.id}', doc.delete());
    } else if (roll < 60) {
      final DocumentReference<Map<String, Object?>> second = _doc();
      final DocumentReference<Map<String, Object?>> third = _doc();
      _track(
        'batch set ${doc.id} v=$value, merge ${second.id}, delete ${third.id}',
        (db.batch()
              ..set(doc, <String, Object?>{'v': value, 'batch': id})
              ..set(second, <String, Object?>{
                'b': FieldValue.increment(1),
              }, SetOptions.mergeAllFields)
              ..delete(third))
            .commit(),
      );
    } else if (roll < 70) {
      _transaction(doc, _doc());
    } else if (roll < 80) {
      final int index = 1 + random.nextInt(max(1, listeners.length - 1));
      if (index < listeners.length) {
        final _Listener old = listeners[index];
        await old.cancel();
        problems.addAll(old.problems('$id listener $index (replaced)'));
        listeners[index] = _newListener();
        record('listener $index: ${listeners[index]}');
      }
    } else if (roll < 87) {
      _networkEnabled = !_networkEnabled;
      networkToggles++;
      record(_networkEnabled ? 'enableNetwork' : 'disableNetwork');
      await (_networkEnabled ? db.enableNetwork() : db.disableNetwork());
      record('network toggled');
    } else if (roll < 90) {
      await _restart();
    } else {
      _chaos(random.nextInt(6));
    }
  }

  void _transaction(
    DocumentReference<Map<String, Object?>> first,
    DocumentReference<Map<String, Object?>> second,
  ) {
    transactions++;
    _track(
      'transaction ${first.id} ${second.id}',
      db
          .runTransaction<void>((Transaction transaction) async {
            final DocumentSnapshot<Map<String, Object?>> a = await transaction
                .get(first);
            final DocumentSnapshot<Map<String, Object?>> b = await transaction
                .get(second);
            final Object? va = a.data?['v'];
            final Object? vb = b.data?['v'];
            transaction.set(first, <String, Object?>{
              'v': (va is int ? va : 0) + 1,
              'tx': id,
            });
            if (second.id != first.id) {
              transaction.set(second, <String, Object?>{
                'v': (vb is int ? vb : 0) + 1,
                'tx': id,
              }, SetOptions.mergeAllFields);
            }
          })
          .timeout(const Duration(seconds: 60)),
    );
  }

  /// Terminates the instance (its pending writes stay in the SQLite file) and starts a new one on the same file.
  Future<void> _restart() async {
    restarts++;
    record('restart ($_outstanding outstanding)');
    for (int i = 0; i < listeners.length; i++) {
      await listeners[i].cancel();
      problems.addAll(listeners[i].problems('$id listener $i (restart)'));
    }
    listeners.clear();
    record('terminating');
    await db.terminate();
    record('terminated');
    // The futures of a terminated instance never complete: nobody waits for them any more.
    _pending = <Future<void>>[];
    _outstanding = 0;
    await start();
    record('restarted');
    final int generation = _generation;
    _restartBacklog = true;
    unawaited(
      db.waitForPendingWrites().then(
        (_) {
          if (generation == _generation) {
            _restartBacklog = false;
          }
        },
        // The instance was terminated again: the next one waits for the backlog.
        onError: (Object _) {},
      ),
    );
  }

  void _chaos(int kind) {
    switch (kind) {
      case 0:
        record('cut');
        proxy.cut();
        break;
      case 1:
        final int ms = 100 + random.nextInt(600);
        record('disconnect for $ms ms');
        proxy.disconnect();
        unawaited(
          Future<void>.delayed(Duration(milliseconds: ms), proxy.restore),
        );
        break;
      case 2:
        final int ms = 100 + random.nextInt(400);
        record('stall for $ms ms, then cut');
        proxy.mode = ChaosMode.stall;
        unawaited(
          Future<void>.delayed(Duration(milliseconds: ms), () {
            proxy
              ..cut()
              ..restore();
          }),
        );
        break;
      case 3:
        record('cut on the next response');
        unawaited(proxy.cutOnNext(ChaosDirection.down, minBytes: 20));
        break;
      case 4:
        final int ms = 100 + random.nextInt(400);
        record('black hole for $ms ms');
        proxy.mode = ChaosMode.blackHole;
        unawaited(
          Future<void>.delayed(Duration(milliseconds: ms), () {
            proxy.mode = ChaosMode.forward;
          }),
        );
        break;
      default:
        final int ms = random.nextInt(3) * 10;
        record('latency $ms ms');
        proxy.delay = Duration(milliseconds: ms);
        break;
    }
  }

  /// Restores the network and waits for every write of the current instance to land.
  Future<List<String>> quiesce() async {
    final List<String> found = <String>[];
    // The disconnects, stalls and black holes above end on their own timers.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    proxy
      ..delay = Duration.zero
      ..mode = ChaosMode.forward
      ..restore();
    record('quiesce: enableNetwork');
    await db.enableNetwork();
    final Stopwatch waiting = Stopwatch()..start();
    final Timer progress = Timer.periodic(
      const Duration(seconds: 15),
      (_) => record('quiesce: still waiting after ${waiting.elapsed}'),
    );
    try {
      record('quiesce: waitForPendingWrites');
      await db.waitForPendingWrites().timeout(const Duration(seconds: 90));
      record('quiesce: wait for the ${_pending.length} operations');
      await Future.wait(_pending).timeout(const Duration(seconds: 90));
      record('quiesce: done');
    } on TimeoutException catch (e) {
      found.add(
        '$id: its writes did not land after the network came back '
        '($_outstanding outstanding): $e',
      );
    } finally {
      progress.cancel();
    }
    return found;
  }

  Future<List<String>> verify(Map<String, Map<String, Object?>> server) async {
    final List<String> found = List<String>.of(problems);
    for (int i = 0; i < listeners.length; i++) {
      final String? problem = await listeners[i].settlesOn(
        server,
        const Duration(seconds: 60),
      );
      if (problem != null) {
        found.add('$id listener $i ${listeners[i]}: $problem');
      }
      found.addAll(listeners[i].problems('$id listener $i'));
    }
    final QuerySnapshot<Map<String, Object?>> cached = await collection.get(
      Source.cache,
    );
    final String cache = _describe(docsById(cached));
    if (cache != _describe(server)) {
      found.add(
        '$id: the cache differs from the backend\n'
        '  cache:   $cache\n  backend: ${_describe(server)}',
      );
    }
    if (cached.metadata.hasPendingWrites) {
      found.add('$id: the cache still has pending writes');
    }
    return found;
  }

  Future<void> stop() async {
    for (final _Listener listener in listeners) {
      await listener.cancel();
    }
    await db.terminate();
    await proxy.close();
    DatabaseMock.deleteDatabaseFiles(dbName);
  }

  String stats() =>
      '$id writes=$writes transactions=$transactions '
      'restarts=$restarts toggles=$networkToggles listens=$listens '
      'cuts=${proxy.cuts}';
}

/// The documents as a string that does not depend on the order of the fields.
String _describe(Map<String, Map<String, Object?>> docs) => _canonical(docs);

String _canonical(Object? value) {
  if (value is Map) {
    final List<String> keys =
        value.keys.map((Object? key) => key.toString()).toList()..sort();
    return '{${keys.map((String key) => '$key: ${_canonical(value[key])}').join(', ')}}';
  }
  if (value is List) {
    return '[${value.map(_canonical).join(', ')}]';
  }
  return '$value';
}

/// What a query listener must show once everything settled, computed from the backend documents.
class _Expectation {
  _Expectation.range(int from, int limit)
    : _name = 'v >= $from order by v limit $limit',
      _select = ((Map<String, Map<String, Object?>> docs) => (_ordered(
        docs,
        (Map<String, Object?> d) => d['v'] is int && (d['v']! as int) >= from,
      )..sort(_byV)).take(limit).toList());

  _Expectation.tagged(int tag)
    : _name = 'tags contains $tag',
      _select = ((Map<String, Map<String, Object?>> docs) => _ordered(
        docs,
        (Map<String, Object?> d) =>
            d['tags'] is List && (d['tags']! as List<Object?>).contains(tag),
      ));

  _Expectation.top(int limit)
    : _name = 'order by v desc limit $limit',
      _select = ((Map<String, Map<String, Object?>> docs) => (_ordered(
        docs,
        (Map<String, Object?> d) => d['v'] is int,
      )..sort((_Entry a, _Entry b) => -_byV(a, b))).take(limit).toList());

  final String _name;
  final List<_Entry> Function(Map<String, Map<String, Object?>> docs) _select;

  List<String> ids(Map<String, Map<String, Object?>> docs) => <String>[
    for (final _Entry entry in _select(docs)) entry.key,
  ];

  static List<_Entry> _ordered(
    Map<String, Map<String, Object?>> docs,
    bool Function(Map<String, Object?> data) where,
  ) {
    return docs.entries.where((_Entry entry) => where(entry.value)).toList()
      ..sort((_Entry a, _Entry b) => a.key.compareTo(b.key));
  }

  static int _byV(_Entry a, _Entry b) {
    final int byV = (a.value['v']! as int).compareTo(b.value['v']! as int);
    return byV != 0 ? byV : a.key.compareTo(b.key);
  }

  @override
  String toString() => _name;
}

typedef _Entry = MapEntry<String, Map<String, Object?>>;

abstract class _Listener {
  Future<void> cancel();

  /// What was wrong with the snapshots so far, each prefixed with [who].
  List<String> problems(String who);

  /// Null once the listener shows [server] in sync and without pending writes, and still does a moment later; else
  /// what it shows.
  Future<String?> settlesOn(
    Map<String, Map<String, Object?>> server,
    Duration timeout,
  );
}

Future<String?> _settle(
  bool Function() settled,
  String Function() describe,
  Duration timeout,
) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!settled()) {
    if (watch.elapsed > timeout) {
      return 'did not settle within $timeout:\n${describe()}';
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  await Future<void>.delayed(const Duration(milliseconds: 300));
  return settled() ? null : 'moved away after it settled:\n${describe()}';
}

class _QueryListener implements _Listener {
  _QueryListener(Query<Map<String, Object?>> query, this._expectation)
    : _recording = RecordingListener(query);

  /// Null for the listener of the whole collection.
  final _Expectation? _expectation;
  final RecordingListener _recording;

  @override
  Future<void> cancel() => _recording.cancel();

  @override
  List<String> problems(String who) => <String>[
    for (final String violation in _recording.violations) '$who: $violation',
    for (final Object error in _recording.errors) '$who: listen error: $error',
  ];

  @override
  Future<String?> settlesOn(
    Map<String, Map<String, Object?>> server,
    Duration timeout,
  ) async {
    final List<String> ids =
        _expectation?.ids(server) ?? (server.keys.toList()..sort());
    bool settled() {
      if (_recording.events.isEmpty) {
        return false;
      }
      final QuerySnapshot<Map<String, Object?>> last = _recording.last;
      return !last.metadata.isFromCache &&
          !last.metadata.hasPendingWrites &&
          RecordingListener.idsOf(last).join(',') == ids.join(',') &&
          last.docs.every(
            (QueryDocumentSnapshot<Map<String, Object?>> doc) =>
                _describe(<String, Map<String, Object?>>{doc.id: doc.data}) ==
                _describe(<String, Map<String, Object?>>{
                  doc.id: server[doc.id]!,
                }),
          );
    }

    return _settle(
      settled,
      () => 'expected $ids\n${_recording.describe()}',
      timeout,
    );
  }

  @override
  String toString() => _expectation?.toString() ?? 'the whole collection';
}

class _DocListener implements _Listener {
  _DocListener(this.doc) {
    _subscription = doc
        .getSnapshotsWithOptions(
          const SnapshotListenOptions(metadataChanges: MetadataChanges.include),
        )
        .listen(_events.add, onError: _errors.add);
  }

  final DocumentReference<Map<String, Object?>> doc;
  final List<DocumentSnapshot<Map<String, Object?>>> _events =
      <DocumentSnapshot<Map<String, Object?>>>[];
  final List<Object> _errors = <Object>[];
  late final StreamSubscription<DocumentSnapshot<Map<String, Object?>>>
  _subscription;

  @override
  Future<void> cancel() => _subscription.cancel();

  @override
  List<String> problems(String who) => <String>[
    for (final Object error in _errors) '$who: listen error: $error',
  ];

  @override
  Future<String?> settlesOn(
    Map<String, Map<String, Object?>> server,
    Duration timeout,
  ) {
    final Map<String, Object?>? expected = server[doc.id];
    bool settled() {
      if (_events.isEmpty) {
        return false;
      }
      final DocumentSnapshot<Map<String, Object?>> last = _events.last;
      return !last.metadata.isFromCache &&
          !last.metadata.hasPendingWrites &&
          last.exists == (expected != null) &&
          (expected == null ||
              _describe(<String, Map<String, Object?>>{doc.id: last.data!}) ==
                  _describe(<String, Map<String, Object?>>{doc.id: expected}));
    }

    return _settle(
      settled,
      () =>
          'expected $expected, events: ${_events.reversed.take(4).map((DocumentSnapshot<Map<String, Object?>> s) => 'fromCache=${s.metadata.isFromCache} '
              'pending=${s.metadata.hasPendingWrites} ${s.data}').join(' | ')}',
      timeout,
    );
  }

  @override
  String toString() => 'document ${doc.id}';
}

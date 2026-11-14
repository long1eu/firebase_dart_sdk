// Property: the write ownership of a shared SQLite cache. Clients that share a
// cache but no state send only their own write batches and those of clients
// that are gone (see shared_cache_write_ownership_test.dart and
// docs/guides/multiple_clients.md).
//
// Seeded random interleavings, on a fake clock, of: writes from several
// clients, refreshes, lease handovers (network disabled and enabled),
// acknowledgements of a backend fake, time passing across the 60 s batch
// owner window (the live clients refresh every 4 s meanwhile, as their timers
// do), a client that terminates, one that crashes (it stops refreshing and
// never comes back) and a new client that opens the cache. Then the clients
// finish: each live client gets a turn as primary (a secondary keeps its own
// writes pending), and the window passes twice while the backend
// acknowledges everything that is sent.
//
// Invariants:
//  * the backend applies every batch exactly once, plus once for every
//    acknowledgement that reached a client which had just lost the lease
//    (it can not store it and sends the batch again, as the JS SDK does);
//  * a batch is sent only by its owner, or by another client once the owner
//    terminated or has not refreshed for SQLiteClientMetadata.maxBatchOwnerAgeMs;
//  * the batches of a client that crashed or terminated are sent in the end;
//  * every write future of a client that is still alive completes exactly
//    once, successfully, and after the backend applied its batch;
//  * the documents in the cache of every live client match the backend.
//
// A failure shows the seed, the shortest failing prefix of the interleaving
// and its trace. PROPERTY_SCALE=<n> runs n times as many interleavings,
// PROPERTY_SEED=<seed> reruns a failing one and PROPERTY_TRACE=1 prints every
// step.

@TestOn('vm')
library;

import 'dart:async';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/serial_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:grpc/grpc.dart';
import 'package:rxdart/subjects.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/property.dart';
import '../../../../util/test_util.dart';
import '../local/mock/database_mock.dart';
import '../local/persistence_test_helpers.dart';
import '../remote/mock_datastore.dart';

/// Forwards the callbacks of a remote store to the sync engine, which is
/// created after it.
class _Callback implements RemoteStoreCallback {
  late SyncEngine syncEngine;

  @override
  Future<void> handleRemoteEvent(RemoteEvent remoteEvent) =>
      syncEngine.handleRemoteEvent(remoteEvent);

  @override
  Future<void> handleRejectedListen(int targetId, GrpcError error) =>
      syncEngine.handleRejectedListen(targetId, error);

  @override
  Future<void> handleSuccessfulWrite(MutationBatchResult result) =>
      syncEngine.handleSuccessfulWrite(result);

  @override
  Future<void> handleRejectedWrite(int batchId, GrpcError error) =>
      syncEngine.handleRejectedWrite(batchId, error);

  @override
  Future<void> handleOnlineStateChange(OnlineState onlineState) =>
      syncEngine.handleOnlineStateChange(onlineState);

  @override
  ImmutableSortedSet<DocumentKey> Function(int) get getRemoteKeysForTarget =>
      syncEngine.getRemoteKeysForTarget;
}

enum _State { alive, terminated, crashed }

/// A client stack on the shared cache, as a Firestore instance builds it
/// (without shared client state).
class _Client {
  _Client._(
    this.id,
    this.queue,
    this.persistence,
    this.localStore,
    this.datastore,
    this.remoteStore,
    this.syncEngine,
  );

  static Future<_Client> start(
    String name,
    String id,
    int Function() clock,
  ) async {
    final SQLitePersistence persistence =
        await createSharedSQLitePersistenceForProject(
          'test-project',
          name,
          id,
          clock,
        );
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    final TaskScheduler scheduler = TaskScheduler(id);
    final MockDatastore datastore = MockDatastore(scheduler);
    final _Callback callback = _Callback();
    // As `FirestoreClient`: one queue for the remote store and for every call
    // into the sync engine, the remote store and the local store.
    final SerialQueue queue = SerialQueue();
    final RemoteStore remoteStore = RemoteStore(
      callback,
      localStore,
      datastore,
      BehaviorSubject<bool>.seeded(true),
      scheduler,
      queue: queue,
    );
    final SyncEngine syncEngine = SyncEngine(
      localStore,
      remoteStore,
      User.unauthenticated,
    );
    callback.syncEngine = syncEngine;
    EventManager(syncEngine);
    await queue.run<void>(() async {
      await localStore.start();
      await remoteStore.start();
      // As the client: the primary state is applied on the queue, after the
      // task that changed it.
      persistence.setPrimaryStateListener((bool isPrimary) {
        unawaited(
          remoteStore.enqueueRetryable(
            () => syncEngine.applyPrimaryState(isPrimary),
          ),
        );
      });
    });
    await _settle();
    return _Client._(
      id,
      queue,
      persistence,
      localStore,
      datastore,
      remoteStore,
      syncEngine,
    );
  }

  final String id;

  /// The queue of the client, see [start].
  final SerialQueue queue;
  final SQLitePersistence persistence;
  final LocalStore localStore;
  final MockDatastore datastore;
  final RemoteStore remoteStore;
  final SyncEngine syncEngine;
  _State state = _State.alive;
  bool networkEnabled = true;

  /// The fake time of the last write of this client's row in `clients`.
  int lastRefresh = 0;

  bool get isAlive => state == _State.alive;

  /// The refresh of the client's metadata timer, as `FirestoreClient` runs it.
  Future<void> refresh(int now) async {
    await queue.run<void>(() async {
      await persistence.refreshClientMetadata();
      await syncEngine.handleClientMetadataRefresh();
    });
    lastRefresh = now;
    await _settle();
  }

  /// As `FirestoreClient.disableNetwork` and `enableNetwork`.
  Future<void> setNetwork(bool enabled, int now) async {
    await queue.run<void>(() async {
      if (enabled) {
        await remoteStore.enableNetwork();
      } else {
        await remoteStore.disableNetwork();
      }
      await persistence.setNetworkEnabled(enabled);
    });
    networkEnabled = enabled;
    lastRefresh = now;
    await _settle();
  }

  /// Terminates the client: it releases the lease and removes its metadata.
  Future<void> terminate() async {
    state = _State.terminated;
    await remoteStore.shutdown();
    await persistence.shutdown();
    await _settle();
  }

  /// The client stops: no refresh, no network, nothing in the cache changes
  /// any more. Its writes in flight are lost; its row stays in `clients`.
  Future<void> crash() async {
    state = _State.crashed;
    await remoteStore.shutdown();
    await _settle();
  }
}

Future<void> _settle() async {
  // The mock streams open and answer on timers.
  for (int i = 0; i < 3; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// A write of the property: a set of `col/<doc>` to `{'w': tag}`. The tag
/// tells the backend fake which batch it applies.
class _Write {
  _Write(this.tag, this.owner, this.doc);

  final String tag;
  final _Client owner;
  final String doc;

  /// How often the backend applied it, and by which clients.
  final List<String> appliedBy = <String>[];

  /// How often its acknowledgement reached a client that had lost the lease
  /// meanwhile: the client can not store it, the batch stays in the queue and
  /// is sent again (as in the JS SDK, where `Acknowledge batch` is a
  /// primary-only transaction and the sync engine ignores the lease loss).
  int lostAcknowledgements = 0;

  /// How often the future of the owner completed, and the problems found.
  int completions = 0;
  final List<String> problems = <String>[];
}

/// What the interleavings did, over all seeds of a run.
class _Stats {
  int runs = 0;
  int writes = 0;
  int sentByAnother = 0;
  int lostAcknowledgements = 0;
  int crashes = 0;
  int terminations = 0;

  @override
  String toString() =>
      '$runs interleavings, $writes writes, $sentByAnother sent by another '
      'client than their owner, $lostAcknowledgements sent again after an '
      'acknowledgement was lost to a lease move, $crashes crashes, '
      '$terminations terminations';
}

class _Run {
  _Run(this.seed, this.name);

  final int seed;
  final String name;
  int now = 1700000000000;
  int _version = 1000;
  int _clientCount = 0;
  final List<_Client> clients = <_Client>[];
  final List<_Write> writes = <_Write>[];
  final Map<String, String?> backend = <String, String?>{};
  final List<String> trace = <String>[];
  final List<String> violations = <String>[];

  void log(String step) {
    final String line =
        '${(now - 1700000000000) ~/ 1000}s: $step '
        '[${clients.map(_describe).join(', ')}]';
    trace.add(line);
    if (traceProperties) {
      print('TRACE seed $seed $line');
    }
  }

  String _describe(_Client c) => switch (c.state) {
    _State.alive =>
      '${c.id}${c.syncEngine.isPrimaryClient ? '*' : ''}'
          '${c.networkEnabled ? '' : ' offline'}'
          '${c.datastore.writesSent == 0 ? '' : ' ${c.datastore.writesSent} in flight'}',
    _State.terminated => '${c.id} terminated',
    _State.crashed => '${c.id} crashed',
  };

  List<_Client> get alive => <_Client>[
    for (final _Client c in clients)
      if (c.isAlive) c,
  ];

  Future<_Client> open() async {
    final String id = String.fromCharCode('A'.codeUnitAt(0) + _clientCount++);
    final _Client client = await _Client.start(name, id, () => now);
    client.lastRefresh = now;
    clients.add(client);
    log('$id opens the cache');
    return client;
  }

  Future<void> write(_Client client, String doc) async {
    final _Write write = _Write('${client.id}${writes.length}', client, doc);
    writes.add(write);
    final Completer<void> userTask = Completer<void>();
    unawaited(
      userTask.future.then(
        (_) {
          write.completions++;
          if (write.appliedBy.isEmpty) {
            write.problems.add('completed before the backend applied it');
          }
        },
        onError: (Object error) {
          write.completions++;
          write.problems.add('failed: $error');
        },
      ),
    );
    await client.queue.run<void>(
      () => client.syncEngine.writeMutations(<Mutation>[
        setMutation('col/$doc', <String, Object?>{'w': write.tag}),
      ], userTask),
    );
    log('${client.id} writes ${write.tag} to $doc');
    await _settle();
  }

  /// The backend applies the oldest write that [client] sent and
  /// acknowledges it.
  Future<void> acknowledge(_Client client) async {
    final List<Mutation> mutations = client.datastore.waitForWriteSend();
    final List<MutationResult> results = <MutationResult>[];
    _version += 1000;
    for (final Mutation mutation in mutations) {
      final String tag =
          (mutation as SetMutation).value.get(field('w'))!.value as String;
      final _Write write = writes.firstWhere((_Write w) => w.tag == tag);
      _checkSender(write, client);
      write.appliedBy.add(client.id);
      backend[write.doc] = tag;
      results.add(MutationResult(version(_version), const <FieldValue>[]));
      log('the backend applies $tag sent by ${client.id}');
    }
    final bool wasPrimary = client.syncEngine.isPrimaryClient;
    await client.datastore.ackWrite(version(_version), results);
    await _settle();
    if (wasPrimary && !client.syncEngine.isPrimaryClient) {
      for (final Mutation mutation in mutations) {
        final String tag =
            (mutation as SetMutation).value.get(field('w'))!.value as String;
        writes.firstWhere((_Write w) => w.tag == tag).lostAcknowledgements++;
      }
      log(
        '${client.id} lost the lease and could not store the acknowledgement',
      );
    }
  }

  void _checkSender(_Write write, _Client sender) {
    final _Client owner = write.owner;
    if (owner == sender) {
      return;
    }
    final bool ownerGone =
        owner.state == _State.terminated ||
        now - owner.lastRefresh > SQLiteClientMetadata.maxBatchOwnerAgeMs;
    if (!ownerGone) {
      violations.add(
        '${write.tag} of ${owner.id} (${owner.state.name}, last refresh '
        '${(now - owner.lastRefresh) ~/ 1000}s ago) was sent by ${sender.id}',
      );
    }
  }

  Future<void> advance(int ms) async {
    now += ms;
    log('the clock moves ${ms}ms');
  }

  /// [ms] pass while the live clients refresh every
  /// [SQLiteClientMetadata.refreshInterval] (in a random order), as their
  /// timers do, and the backend acknowledges what they send when [acknowledge]
  /// is true. Only clients that crashed age.
  Future<void> passTime(int ms, Gen gen, {bool acknowledge = false}) async {
    final int interval = SQLiteClientMetadata.refreshInterval.inMilliseconds;
    log('${ms}ms pass');
    for (int left = ms; left > 0; left -= interval) {
      now += left < interval ? left : interval;
      final List<_Client> order = List<_Client>.of(alive);
      for (int i = order.length - 1; i > 0; i--) {
        final int j = gen.below(i + 1);
        final _Client t = order[i];
        order[i] = order[j];
        order[j] = t;
      }
      for (final _Client c in order) {
        await c.refresh(now);
      }
      if (acknowledge) {
        for (final _Client c in alive) {
          while (c.datastore.writesSent > 0) {
            await this.acknowledge(c);
          }
        }
      }
    }
    log('${ms}ms passed');
  }
}

/// One random step of an interleaving.
Future<void> _step(_Run run, Gen gen) async {
  final List<_Client> alive = run.alive;
  final _Client client = gen.pick(alive);
  final List<_Client> sending = <_Client>[
    for (final _Client c in alive)
      if (c.datastore.writesSent > 0) c,
  ];
  final int choice = gen.below(100);
  if (choice < 25) {
    await run.write(client, 'd${gen.below(4)}');
  } else if (choice < 45) {
    await client.refresh(run.now);
    run.log('${client.id} refreshes');
  } else if (choice < 65) {
    if (sending.isNotEmpty) {
      await run.acknowledge(gen.pick(sending));
    }
  } else if (choice < 77) {
    await run.advance(gen.between(500, 4500));
  } else if (choice < 85) {
    await client.setNetwork(!client.networkEnabled, run.now);
    run.log(
      '${client.id} ${client.networkEnabled ? 'enables' : 'disables'} '
      'its network',
    );
  } else if (choice < 89) {
    // Time passes across the batch owner window.
    await run.passTime(
      SQLiteClientMetadata.maxBatchOwnerAgeMs + gen.between(1, 5000),
      gen,
    );
  } else if (choice < 93) {
    if (alive.length > 1) {
      if (gen.chance(50)) {
        await client.crash();
        run.log('${client.id} crashes');
      } else {
        await client.terminate();
        run.log('${client.id} terminates');
      }
    }
  } else if (choice < 96) {
    if (run.clients.length < 5) {
      await run.open();
    }
  }
}

/// Lets the live clients finish. A secondary keeps its own writes pending
/// until it is primary, so every live client gets a turn as primary: the
/// others disable their network, which hands it the lease. Then all enable
/// their network, and twice the batch owner window passes while they refresh
/// and the backend acknowledges everything that is sent: the primary sends
/// the batches of the clients that crashed or terminated.
Future<void> _drain(_Run run, Gen gen) async {
  run.log('drain');
  for (final _Client turn in run.alive) {
    for (final _Client c in run.alive) {
      if (c.networkEnabled != (c == turn)) {
        await c.setNetwork(c == turn, run.now);
      }
    }
    run.log('${turn.id} has its turn');
    // The lease moves within a few refreshes (the holder hands it over at a
    // refresh after one of the client with network; that one takes it at its
    // next refresh), and the client then sends its writes.
    bool done() =>
        turn.syncEngine.isPrimaryClient &&
        run.writes.every(
          (_Write w) => w.owner != turn || w.appliedBy.isNotEmpty,
        );
    final int interval = SQLiteClientMetadata.refreshInterval.inMilliseconds;
    for (int i = 0; i < 10 && !done(); i++) {
      await run.passTime(interval, gen, acknowledge: true);
    }
    if (!done()) {
      run.violations.add(
        '${turn.id} did not get the lease and send its writes in 10 refreshes',
      );
    }
  }
  for (final _Client c in run.alive) {
    if (!c.networkEnabled) {
      await c.setNetwork(true, run.now);
    }
  }
  await run.passTime(
    2 * SQLiteClientMetadata.maxBatchOwnerAgeMs,
    gen,
    acknowledge: true,
  );
}

Future<List<String>> _check(_Run run) async {
  final List<String> failures = <String>[...run.violations];
  for (final _Write write in run.writes) {
    if (write.appliedBy.length != 1 + write.lostAcknowledgements) {
      failures.add(
        '${write.tag} of ${write.owner.id} (${write.owner.state.name}) was '
        'applied ${write.appliedBy.length} times, '
        '${write.lostAcknowledgements} acknowledgements were lost${write.appliedBy.isEmpty ? '' : ' (by ${write.appliedBy.join(', ')})'}',
      );
    }
    if (write.owner.isAlive) {
      if (write.completions != 1) {
        failures.add(
          'the future of ${write.tag} of ${write.owner.id} completed '
          '${write.completions} times',
        );
      }
      for (final String problem in write.problems) {
        failures.add(
          'the future of ${write.tag} of ${write.owner.id} $problem',
        );
      }
    }
  }
  for (final _Client c in run.alive) {
    for (int d = 0; d < 4; d++) {
      final MaybeDocument? doc = await c.queue.run<MaybeDocument?>(
        () => c.localStore.readDocument(key('col/d$d')),
      );
      final String? cached = doc is Document
          ? doc.getFieldValue(field('w')) as String?
          : null;
      final String? expected = run.backend['d$d'];
      if (cached != expected) {
        failures.add(
          'the cache of ${c.id} has d$d = $cached, the backend $expected',
        );
      }
    }
  }
  return failures;
}

/// Runs the interleaving of [seed] with [steps] steps; returns the failures
/// and the trace.
Future<(List<String>, List<String>)> _runSeed(
  int seed,
  int steps, [
  _Stats? stats,
]) async {
  final String name =
      'firebase/firestore/core/write_ownership_property_${const Uuid().v4()}';
  final _Run run = _Run(seed, name);
  final Gen gen = Gen(seed);
  try {
    for (int i = gen.between(2, 3); i > 0; i--) {
      await run.open();
    }
    for (int i = 0; i < steps; i++) {
      await _step(run, gen);
    }
    await _drain(run, gen);
    if (stats != null) {
      stats.runs++;
      for (final _Write write in run.writes) {
        stats.writes++;
        stats.lostAcknowledgements += write.lostAcknowledgements;
        if (write.appliedBy.any((String id) => id != write.owner.id)) {
          stats.sentByAnother++;
        }
      }
      for (final _Client c in run.clients) {
        if (c.state == _State.crashed) {
          stats.crashes++;
        } else if (c.state == _State.terminated) {
          stats.terminations++;
        }
      }
    }
    return (await _check(run), run.trace);
  } finally {
    for (final _Client c in run.clients) {
      if (c.state != _State.terminated) {
        await c.remoteStore.shutdown();
        await c.persistence.shutdown();
      }
    }
    DatabaseMock.deleteDatabaseFiles(name);
  }
}

void main() {
  const int steps = 40;

  test(
    'write ownership of a shared cache under random interleavings',
    () async {
      final _Stats stats = _Stats();
      for (int i = 0; i < cases(12); i++) {
        final int seed = caseSeed(i);
        final (List<String> failures, List<String> trace) = await _runSeed(
          seed,
          steps,
          stats,
        );
        if (failures.isEmpty) {
          continue;
        }
        // The shortest prefix of the same interleaving that still fails.
        int shortest = steps;
        List<String> shortestFailures = failures;
        List<String> shortestTrace = trace;
        for (int n = 0; n < steps; n += 2) {
          final (List<String> f, List<String> t) = await _runSeed(seed, n);
          if (f.isNotEmpty) {
            shortest = n;
            shortestFailures = f;
            shortestTrace = t;
            break;
          }
        }
        fail(
          'Property "write ownership of a shared cache" failed.\n'
          '  seed: $seed (rerun with PROPERTY_SEED=$seed), shortest failing '
          'prefix: $shortest of $steps steps, then the drain\n'
          '  failures:\n${shortestFailures.map((String f) => '    $f\n').join()}'
          '  trace:\n${shortestTrace.map((String t) => '    $t\n').join()}',
        );
      }
      print('write ownership property: $stats');
      // The interleavings must reach the cases the property is about.
      expect(stats.sentByAnother, greaterThan(0), reason: '$stats');
      expect(stats.crashes, greaterThan(0), reason: '$stats');
    },
    timeout: Timeout(Duration(minutes: 2 + 2 * cases(1))),
  );
}

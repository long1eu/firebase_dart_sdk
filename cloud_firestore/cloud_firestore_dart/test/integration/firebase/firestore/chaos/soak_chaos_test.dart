// A seeded randomized soak test: several clients do random operations on the same documents while their
// connections fail at random; then everything is restored and every client must show the state of the backend.
//
// Environment variables:
//   CHAOS_SOAK_SECONDS  how long the random phase lasts (default 4; the default run stays short)
//   CHAOS_SOAK_SEED     the seed of the operations (default: taken from the clock and printed)
//   CHAOS_SOAK_CLIENTS  the number of clients (default 3)
//   CHAOS_SOAK_SDK_LOG  1 to also keep the debug log of the SDK (all clients, on the clock of the test) and print
//                       its last lines when the test fails: for failures inside a client that the wire does not
//                       explain (a listener that stops getting snapshots). Off by default: it slows the clients.
//
// On failure the seed and the log of the operations are printed. The seed fixes the sequence of operations of each
// client, not their exact timing. So the failure output also holds what is needed to explain a failure without
// running it again, all on one clock: for the documents a client got wrong, their history in the snapshots of
// every client (fromCache, hasPendingWrites, fields), and what every client sent and received (WireRecorder): its
// write batches in order with the commit and update times of their acknowledgements, what watch delivered, and
// every start and end of a stream.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/internal.dart' show InternalLogLevel, Log;
import 'package:test/test.dart';

import '../../../../util/chaos_proxy.dart';
import '../../../../util/integration_test_util.dart';
import '../../../../util/wire_recorder.dart';
import 'chaos_util.dart';

int _env(String name, int fallback) =>
    int.tryParse(Platform.environment[name] ?? '') ?? fallback;

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/chaos_soak';

  final int seconds = _env('CHAOS_SOAK_SECONDS', 4);
  final int seed =
      _env('CHAOS_SOAK_SEED', DateTime.now().millisecondsSinceEpoch % 1000000);
  final int clientCount = _env('CHAOS_SOAK_CLIENTS', 3);

  final bool keepSdkLog = Platform.environment['CHAOS_SOAK_SDK_LOG'] == '1';

  /// The last lines of the debug log of the SDK, when it is kept.
  final List<String> sdkLog = <String>[];
  const int sdkLogLines = 60000;
  final RegExp sdkLogLine = RegExp(r'^[DIWE]:');

  Future<void> soak() async {
    final ChaosEnv env = await ChaosEnv.start();
    final List<String> log = <String>[];
    void record(String message) => log.add(
        '${chaosClock.elapsedMilliseconds.toString().padLeft(6)} $message');
    final WireRecorder wire = WireRecorder(chaosClock)..install();
    final List<_SoakClient> clients = <_SoakClient>[];
    // What the failure output needs: the state of the backend and the new listeners, once they exist.
    Map<String, Map<String, Object?>>? backend;
    final Map<int, RecordingListener> freshListeners =
        <int, RecordingListener>{};

    try {
      final String name = uniqueName('soak');
      for (int i = 0; i < clientCount; i++) {
        final ChaosProxy proxy = await env.newProxy();
        wire.names[proxy.port] = 'c$i';
        final Firestore db = await env.newClient(proxy: proxy);
        clients.add(_SoakClient(
            i, db, proxy, db.collection(name), Random(seed * 31 + i), record));
      }
      for (final _SoakClient client in clients) {
        await client.main.synced();
      }
      if (keepSdkLog) {
        // After the clients exist: creating one sets the level.
        Log.level = InternalLogLevel.d;
      }

      // ignore: avoid_print
      print('soak: seed=$seed clients=$clientCount seconds=$seconds');
      final DateTime end = DateTime.now().add(Duration(seconds: seconds));
      await Future.wait(<Future<void>>[
        for (final _SoakClient client in clients) client.run(end),
      ]);

      // Quiesce: a working network for everybody, and every write on its way.
      record('--- quiesce');
      for (final _SoakClient client in clients) {
        client.proxy
          ..delay = Duration.zero
          ..restore();
        await client.db.enableNetwork();
      }
      for (final _SoakClient client in clients) {
        await client.db
            .waitForPendingWrites()
            .timeout(const Duration(seconds: 40));
        await Future.wait(client.pending).timeout(const Duration(seconds: 40));
        await client.stopTransient();
      }

      final Map<String, Map<String, Object?>> server =
          await env.serverDocs(name);
      backend = server;
      final List<String> ids = server.keys.toList()..sort();
      record('--- backend: $server');
      for (final _SoakClient client in clients) {
        // The listener that lived through all of it.
        await client.main.settlesOn(ids, server);
        // A new listener.
        final RecordingListener fresh = RecordingListener(client.collection);
        freshListeners[client.id] = fresh;
        await fresh.settlesOn(ids, server);
        await fresh.cancel();
        // The cache alone, which the listeners kept up to date.
        final QuerySnapshot<Map<String, Object?>> cached =
            await client.collection.get(Source.cache);
        expect(docsById(cached), server,
            reason: 'cache of client ${client.id}');
        expect(cached.metadata.hasPendingWrites, isFalse);
        await client.main.cancel();
        expect(client.transientProblems, isEmpty,
            reason: 'short-lived listeners of client ${client.id}');
      }
      // ignore: avoid_print
      print('soak: ${log.length} log entries, ${server.length} documents, '
          'cuts: ${clients.map((_SoakClient c) => c.proxy.cuts).toList()}');
    } catch (_) {
      // ignore: avoid_print
      print('SOAK FAILED: rerun with CHAOS_SOAK_SEED=$seed '
          'CHAOS_SOAK_CLIENTS=$clientCount CHAOS_SOAK_SECONDS=$seconds\n'
          '${log.join('\n')}\n'
          '${_diagnostics(clients, freshListeners, backend, wire)}'
          '${keepSdkLog ? '--- debug log of the SDK (last ${sdkLog.length} lines)\n${sdkLog.join('\n')}\n' : ''}');
      rethrow;
    } finally {
      Log.level = InternalLogLevel.w;
      wire.uninstall();
      await env.close();
    }
  }

  test('random operations with random cuts converge on the backend state', () {
    if (!keepSdkLog) {
      return soak();
    }
    // The SDK logs with print: its lines are kept instead of printed.
    return runZoned(
      soak,
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          if (sdkLogLine.hasMatch(line)) {
            if (sdkLog.length >= sdkLogLines) {
              sdkLog.removeRange(0, sdkLogLines ~/ 4);
            }
            sdkLog.add(
                '${chaosClock.elapsedMilliseconds.toString().padLeft(6)} $line');
          } else {
            parent.print(zone, line);
          }
        },
      ),
    );
  }, skip: chaosSkipReason, timeout: Timeout(Duration(seconds: seconds + 120)));
}

/// The failure output beyond the log of the operations, see the top of this file.
String _diagnostics(
    List<_SoakClient> clients,
    Map<int, RecordingListener> freshListeners,
    Map<String, Map<String, Object?>>? backend,
    WireRecorder wire) {
  // The documents that the last snapshot of a listener has wrong; all of them when that is not what failed.
  final Set<String> wrong = <String>{};
  if (backend != null) {
    for (final _SoakClient client in clients) {
      for (final RecordingListener listener in <RecordingListener?>[
        client.main,
        freshListeners[client.id],
      ].whereType<RecordingListener>()) {
        if (listener.events.isEmpty) {
          continue;
        }
        final Map<String, Map<String, Object?>> shown =
            docsById(listener.last);
        for (final String id in <String>{...shown.keys, ...backend.keys}) {
          if ('${shown[id]}' != '${backend[id]}') {
            wrong.add(id);
          }
        }
      }
    }
  }
  final List<String> ids = wrong.isEmpty
      ? <String>[for (int i = 0; i < _SoakClient.documents; i++) 'k$i']
      : (wrong.toList()..sort());
  final StringBuffer buffer = StringBuffer()
    ..writeln('--- diagnostics for $ids '
        '(${wrong.isEmpty ? 'no listener ends on a wrong document' : 'wrong in the last snapshot of a listener'})')
    ..writeln('backend: ${backend == null ? 'not read yet' : <String, Object?>{
            for (final String id in ids) id: backend[id]
          }}');
  for (final _SoakClient client in clients) {
    buffer
      ..writeln('--- c${client.id}: history in the listener that lived through the run')
      ..write(client.main.history(ids));
    final RecordingListener? fresh = freshListeners[client.id];
    if (fresh != null) {
      buffer
        ..writeln('--- c${client.id}: history in the new listener')
        ..write(fresh.history(ids));
    }
  }
  buffer
    ..writeln('--- wire: these documents, and every start and end of a stream')
    ..writeln(wire.about(ids.toSet()).join('\n'))
    ..writeln('--- wire: everything')
    ..writeln(wire.log.join('\n'));
  return buffer.toString();
}

class _SoakClient {
  _SoakClient(
      this.id, this.db, this.proxy, this.collection, this.random, this._record)
      : main = RecordingListener(collection);

  final int id;
  final Firestore db;
  final ChaosProxy proxy;
  final CollectionReference<Map<String, Object?>> collection;
  final Random random;
  final void Function(String message) _record;

  /// The listener on the whole collection that stays for the whole run.
  final RecordingListener main;

  /// The writes and transactions that were issued, with their errors swallowed (and logged).
  final List<Future<void>> pending = <Future<void>>[];

  RecordingListener? _transient;
  bool _networkEnabled = true;
  int _ops = 0;

  /// The writes and transactions that are not acknowledged yet.
  int _outstanding = 0;

  /// More unacknowledged writes than this and the client only does other things: the backlog must stay small enough
  /// to be sent when the network is back (the emulator takes several milliseconds per write and per listener).
  static const int _maxOutstanding = 25;

  void record(String message) => _record('c$id $message');

  /// The clients write the documents k0 to k7.
  static const int documents = 8;

  DocumentReference<Map<String, Object?>> _doc() =>
      collection.doc('k${random.nextInt(documents)}');

  void _track(String what, Future<void> future) {
    final int op = _ops++;
    record('#$op $what');
    _outstanding++;
    pending.add(future.then((_) => record('#$op ok'), onError: (Object e) {
      record('#$op failed: ${e is FirestoreError ? e.code : e.runtimeType}');
    }).whenComplete(() => _outstanding--));
  }

  /// What was wrong with the snapshots of the short-lived listeners.
  final List<String> transientProblems = <String>[];

  Future<void> stopTransient() async {
    final RecordingListener? transient = _transient;
    _transient = null;
    if (transient != null) {
      await transient.cancel();
      transientProblems
        ..addAll(transient.violations)
        ..addAll(transient.errors.map((Object e) => 'listen error: $e'));
    }
  }

  Future<void> run(DateTime end) async {
    while (DateTime.now().isBefore(end)) {
      await _step();
      await Future<void>.delayed(Duration(milliseconds: random.nextInt(40)));
    }
  }

  Future<void> _step() async {
    int roll = random.nextInt(100);
    if (roll < 73 && _outstanding >= _maxOutstanding) {
      roll = 73 + random.nextInt(27);
    }
    final DocumentReference<Map<String, Object?>> doc = _doc();
    final int value = random.nextInt(1000);
    if (roll < 18) {
      _track('set ${doc.id} v=$value',
          doc.set(<String, Object?>{'v': value, 'by': id}));
    } else if (roll < 28) {
      _track('merge ${doc.id} v=$value',
          doc.set(<String, Object?>{'v': value}, SetOptions.mergeAllFields));
    } else if (roll < 38) {
      _track('update ${doc.id} v=$value',
          doc.update(<String, Object?>{'v': value}));
    } else if (roll < 46) {
      _track(
          'increment ${doc.id}',
          doc.set(<String, Object?>{'c': FieldValue.increment(1)},
              SetOptions.mergeAllFields));
    } else if (roll < 54) {
      final int tag = random.nextInt(4);
      final bool add = random.nextBool();
      _track(
          '${add ? 'arrayUnion' : 'arrayRemove'} ${doc.id} $tag',
          doc.set(<String, Object?>{
            'tags': add
                ? FieldValue.arrayUnion(<Object?>[tag])
                : FieldValue.arrayRemove(<Object?>[tag]),
          }, SetOptions.mergeAllFields));
    } else if (roll < 62) {
      _track('delete ${doc.id}', doc.delete());
    } else if (roll < 68) {
      final DocumentReference<Map<String, Object?>> other = _doc();
      _track(
          'batch set ${doc.id} v=$value, delete ${other.id}',
          (db.batch()
                ..set(doc, <String, Object?>{'v': value, 'batch': true})
                ..delete(other))
              .commit());
    } else if (roll < 73) {
      _track(
          'transaction ${doc.id}',
          db.runTransaction<void>((Transaction transaction) async {
            final DocumentSnapshot<Map<String, Object?>> snapshot =
                await transaction.get(doc);
            final Object? v = snapshot.data?['v'];
            transaction.set(
                doc, <String, Object?>{'v': (v is int ? v : 0) + 1, 'tx': id});
          }).timeout(const Duration(seconds: 30)));
    } else if (roll < 79) {
      await stopTransient();
      if (random.nextBool()) {
        record('listen v>=$value limit 3');
        _transient = RecordingListener(collection
            .where('v', isGreaterThanOrEqualTo: value)
            .orderBy('v')
            .limit(3));
      } else {
        record('stop listening');
      }
    } else if (roll < 84) {
      _networkEnabled = !_networkEnabled;
      record(_networkEnabled ? 'enableNetwork' : 'disableNetwork');
      await (_networkEnabled ? db.enableNetwork() : db.disableNetwork());
    } else {
      await _chaos(random.nextInt(7));
    }
  }

  Future<void> _chaos(int kind) async {
    switch (kind) {
      case 0:
        record('cut');
        proxy.cut();
        break;
      case 1:
        final int ms = 100 + random.nextInt(600);
        record('disconnect for $ms ms');
        proxy.disconnect();
        unawaited(Future<void>.delayed(Duration(milliseconds: ms), () {
          record('reconnect');
          proxy.restore();
        }));
        break;
      case 2:
        final int ms = 100 + random.nextInt(400);
        record('stall for $ms ms, then cut');
        proxy.mode = ChaosMode.stall;
        unawaited(Future<void>.delayed(Duration(milliseconds: ms), () {
          proxy
            ..cut()
            ..restore();
        }));
        break;
      case 3:
        final int ms = 50 + random.nextInt(300);
        record('stall for $ms ms, then resume');
        proxy.mode = ChaosMode.stall;
        unawaited(Future<void>.delayed(Duration(milliseconds: ms), () {
          proxy.mode = ChaosMode.forward;
        }));
        break;
      case 4:
        record('cut on the next response');
        unawaited(proxy.cutOnNext(ChaosDirection.down, minBytes: 20));
        break;
      case 6:
        final int ms = 100 + random.nextInt(400);
        record('black hole for $ms ms');
        proxy.mode = ChaosMode.blackHole;
        unawaited(Future<void>.delayed(Duration(milliseconds: ms), () {
          proxy.mode = ChaosMode.forward;
        }));
        break;
      case 5:
        final int ms = random.nextInt(3) * 10;
        record('latency $ms ms');
        proxy.delay = Duration(milliseconds: ms);
        break;
    }
  }
}

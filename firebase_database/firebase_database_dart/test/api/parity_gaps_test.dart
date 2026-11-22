// Parity rows built without a behaviour test (rtdb/from_boss/reports/round2/parity-refresh.md):
// inst.rootOnlyUrl, inst.lazyStart, listen.listenWarnings, query.indexBehaviour,
// txn.listenerCleanup, txn.priority, emu.cloudWorkstation, dart.estimatedServerTime,
// dart.persistenceEnabled and
// dart.databaseUrl. Each test asserts what a user sees through the public API; a test marked
// `skip: 'DEFECT: ...'` states what the JS SDK does and the client does not.
//
// The tests that build a real FirebaseDatabase run inside fakeTime and never move time, so the
// connection's first attempt (a timer) never runs and nothing reaches the network.

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart'
    show firebaseDatabaseWithConnection;
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/persistence/database_persistence.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine_opener.dart';
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/realtime/server_actions_factories.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:firebase_database_dart/testing.dart';
import 'package:test/test.dart';

import '../util/fake_ws.dart';
import 'support/fake_time.dart';
import 'support/harness.dart';

int _appCount = 0;

/// An app with [databaseURL] in its options and the project id `test-project`.
FirebaseApp _appWithUrl(String? databaseURL) => FirebaseApp.withOptions(
  FirebaseOptions(
    apiKey: 'test-key',
    appId: '1:1234567890:dart:test',
    projectId: 'test-project',
    databaseURL: databaseURL,
  ),
  name: 'rtdb-parity-gaps-${_appCount++}',
);

/// A database over a [FakeServerActions], for what the scripted server cannot show: the payload
/// of a listen answer, the data of a put and the server time offset.
final class _Wire {
  _Wire(this.time, {DateTime Function()? clock}) {
    db = firebaseDatabaseWithConnection(
      newTestApp(),
      connectionFactory: (ServerActionsDelegate delegate, DatabaseLogger? _) =>
          server..delegate = delegate,
      logger: (DatabaseLogLevel level, String message) =>
          logs.add('${level.name}: $message'),
      clock: clock,
    );
    time.elapse(Duration.zero);
    server.connect();
    time.elapse(Duration.zero);
  }

  final FakeTime time;
  final FakeServerActions server = FakeServerActions();
  final List<String> logs = <String>[];
  final List<String> log = <String>[];
  late final FirebaseDatabase db;

  void settle() => time.elapse(Duration.zero);

  /// The log entries of the `no_index` warning.
  List<String> get indexWarnings => logs
      .where((String l) => l.contains('Using an unspecified index'))
      .toList();

  /// Logs `name:<value>/<priority>` for every value event of [query].
  void listen(String name, Query query) => query.onValue.listen(
    (DatabaseEvent e) =>
        log.add('$name:${bare(e.snapshot.value)}/${e.snapshot.priority}'),
    onError: (Object e) => log.add('$name:${errorText(e)}'),
  );

  /// Logs `name:committed|aborted(<value>/<priority>)` or `name:E(code)`.
  void track(String name, Future<TransactionResult> future) {
    future.then<void>(
      (TransactionResult r) => log.add(
        '$name:${r.committed ? 'committed' : 'aborted'}'
        '(${bare(r.snapshot.value)}/${r.snapshot.priority})',
      ),
      onError: (Object e) => log.add('$name:${errorText(e)}'),
    );
  }
}

void main() {
  void scenario(String name, void Function(Harness h) body, {String? skip}) {
    test(name, () {
      fakeTime((FakeTime time) => body(Harness(time)));
    }, skip: skip);
  }

  void wired(
    String name,
    void Function(_Wire w) body, {
    DateTime Function()? clock,
    String? skip,
  }) {
    test(name, () {
      fakeTime((FakeTime time) => body(_Wire(time, clock: clock)));
    }, skip: skip);
  }

  group('inst.rootOnlyUrl', () {
    test(
      'a database URL with a path is refused (JS api/Database.ts:163-168)',
      () {
        fakeTime((FakeTime time) {
          expect(
            () => databaseWithFakeServer(
              _appWithUrl(
                'https://test-project-default-rtdb.firebaseio.com/a/b',
              ),
              FakeDatabaseServer(),
            ),
            throwsA(anyOf(isArgumentError, isFormatException)),
          );
        });
      },
      skip:
          'DEFECT: the constructor parses the URL with _ParsedUrl (firebase_database.dart:640), '
          'which drops the path; parseDatabaseUrl, which refuses it, has no caller in lib/.',
    );

    test('a URL that ends in / is the root and is accepted', () {
      fakeTime((FakeTime time) {
        final FirebaseDatabase db = databaseWithFakeServer(
          _appWithUrl('https://my-db.europe-west1.firebasedatabase.app/'),
          FakeDatabaseServer(),
        );
        expect(
          db.databaseUrl.toString(),
          'https://my-db.europe-west1.firebasedatabase.app',
        );
      });
    });
  });

  group('inst.lazyStart', () {
    test(
      'no connection before the first operation; the first one connects',
      () {
        fakeTime((FakeTime time) {
          final FakeDatabaseServer server = FakeDatabaseServer();
          final FirebaseDatabase db = databaseWithFakeServer(
            newTestApp(),
            server,
          );
          time.elapse(const Duration(minutes: 1));
          final DatabaseReference ref = db.ref('a');
          time.elapse(const Duration(minutes: 1));
          expect(server.connectionAttempts, 0);
          expect(server.requests, isEmpty);

          unawaited(ref.get().then((_) {}, onError: (Object _) {}));
          time.elapse(Duration.zero);
          expect(server.connectionAttempts, 1);
          expect(server.requests, <String>['g /a']);
        });
      },
      skip:
          'DEFECT: the Repo is started in the constructor (firebase_database.dart _setUp) and '
          'PersistentConnection.initialize connects at once (persistent_connection.dart:170); '
          'JS starts the repo on first use (api/Database.ts:249-259), the plan says "connects on '
          'the first operation".',
    );
  });

  group('listen.listenWarnings', () {
    wired('a no_index listen answer logs one warning naming the index', (
      _Wire w,
    ) {
      w.listen('S1', w.db.ref('l').orderByChild('n').limitToFirst(1));
      w.settle();
      final ServerCall listen = w.server.callsOf('listen').single;
      w.server.respond(
        listen,
        data: <String, Object?>{
          'w': <Object?>['no_index'],
        },
      );
      w.settle();
      expect(w.indexWarnings, hasLength(1));
      expect(
        w.indexWarnings.single,
        allOf(
          startsWith('warning: '),
          contains('".indexOn": "n"'),
          contains('/l'),
        ),
      );

      // A second listener on the same query sends no listen, so no second warning.
      w.listen('S2', w.db.ref('l').orderByChild('n').limitToFirst(1));
      w.settle();
      expect(w.server.callsOf('listen'), hasLength(1));
      expect(w.indexWarnings, hasLength(1));
    });

    wired('an answer without the warning logs nothing', (_Wire w) {
      w.listen('S1', w.db.ref('l').orderByChild('n').limitToFirst(1));
      w.settle();
      w.server.respond(w.server.callsOf('listen').single);
      w.settle();
      expect(w.indexWarnings, isEmpty);
    });

    test(
      'over the WebSocket connection one listen answer logs the warning once',
      () {
        fakeTime((FakeTime time) {
          final FakeWsConnector connector = FakeWsConnector(autoHello: true);
          final List<String> warnings = <String>[];
          final FirebaseDatabase db = firebaseDatabaseWithConnection(
            newTestApp(),
            connectionFactory: persistentConnectionFactory(
              const RepoInfo(
                host: 'test-project-default-rtdb.firebaseio.com',
                namespace: 'test-project-default-rtdb',
                secure: true,
              ),
              authProvider: null,
              appCheckProvider: null,
              random: () => 0.5,
              connector: connector.connect,
            ),
            logger: (DatabaseLogLevel level, String message) {
              if (message.contains('Using an unspecified index')) {
                warnings.add(message);
              }
            },
          );
          db.ref('l').orderByChild('n').limitToFirst(1).onValue.listen((_) {});
          time.elapse(const Duration(seconds: 1));
          final FakeWsChannel channel = connector.last;
          final List<Map<String, Object?>> listens = channel.sentRequests('q');
          expect(listens, hasLength(1));
          channel.serverResponse(
            listens.single['r']! as int,
            data: <String, Object?>{
              'w': <Object?>['no_index'],
            },
          );
          time.elapse(Duration.zero);
          expect(warnings, hasLength(1));
        });
      },
      skip:
          'DEFECT: the warning is logged twice per answer, by '
          'PersistentConnection._warnOnMissingIndex '
          '(persistent_connection.dart:280) and by RepoListenProvider._warnOnIndexWarnings '
          '(repo_listen_providers.dart:47), both to the same logger; JS logs it once, in '
          'PersistentConnection.ts:316-331.',
    );
  });

  group('query.indexBehaviour', () {
    scenario(
      'an unindexed ordered limit answered with all children is filtered on the client',
      (Harness h) {
        final Query q = h.ref('l').orderByChild('n').limitToFirst(1);
        h.listen('S1', q.onValue);
        h.listen('S2', q.onChildAdded);
        h.settle();
        expect(h.server.requests, contains('q /l {"i":"n","l":1,"vf":"l"}'));
        // Without .indexOn the server sends the whole node to the query.
        h.server.answerListen(
          'l',
          <String, Object?>{
            'a': <String, Object?>{'n': 3},
            'b': <String, Object?>{'n': 1},
            'c': <String, Object?>{'n': 2},
          },
          query: <String, Object?>{'i': 'n', 'l': 1, 'vf': 'l'},
        );
        h.settle();
        expect(h.named('S1'), <String>['S1:V({b:{n:1}})']);
        expect(h.named('S2'), <String>['S2:A(b,null)']);
      },
    );
  });

  group('txn.listenerCleanup', () {
    scenario('the listen a transaction opens is closed after it commits', (
      Harness h,
    ) {
      h.trackTransaction(
        'T',
        h.ref('c').runTransaction((Object? v) => const Transaction.success(1)),
      );
      h.settle();
      expect(h.server.requests, <String>['q /c', 'p /c']);
      h.server.answerListen('c', null);
      h.server.ackLastWrite();
      h.settle();
      expect(h.named('T'), <String>['T:committed(1)']);
      expect(h.server.requests, <String>['q /c', 'p /c', 'n /c']);
    });

    scenario('the listen a transaction opens is closed after it aborts', (
      Harness h,
    ) {
      h.trackTransaction(
        'T',
        h.ref('c').runTransaction((Object? v) => const Transaction.abort()),
      );
      h.settle();
      expect(h.named('T'), <String>['T:aborted(null)']);
      expect(h.server.requests, <String>['q /c', 'n /c']);
    });

    scenario('a user listener at the path keeps its listen after the commit', (
      Harness h,
    ) {
      h.listenAnswered('S1', h.ref('c').onValue, 'c', 0);
      h.trackTransaction(
        'T',
        h.ref('c').runTransaction((Object? v) => const Transaction.success(1)),
      );
      h.settle();
      h.server.ackLastWrite();
      h.settle();
      expect(h.named('T'), <String>['T:committed(1)']);
      expect(h.server.requests, isNot(contains('n /c')));
      h.server.push('c', 2);
      h.settle();
      expect(h.named('S1').last, 'S1:V(2)');
    });
  });

  group('txn.priority', () {
    void answerT(_Wire w, Object? value) {
      w.listen('S1', w.db.ref('t'));
      w.settle();
      w.server.deliverDataUpdate('/t', value);
      w.server.respond(w.server.callsOf('listen').single);
      w.settle();
      w.log.clear();
    }

    wired('Transaction.success with a priority writes and sends it', (_Wire w) {
      answerT(w, 1);
      w.track(
        'T',
        w.db
            .ref('t')
            .runTransaction(
              (Object? v) => const Transaction.success(2, priority: 'p5'),
            ),
      );
      w.settle();
      expect(w.server.callsOf('put').single.data, <String, Object?>{
        '.value': 2,
        '.priority': 'p5',
      });
      expect(w.log, <String>['S1:2/p5']);
      w.server.ackLastWrite();
      w.settle();
      expect(w.log, <String>['S1:2/p5', 'T:committed(2/p5)']);
    });

    wired('the handler sees the value only, without the priority', (_Wire w) {
      answerT(w, <String, Object?>{'.value': 1, '.priority': 'p7'});
      final List<Object?> seen = <Object?>[];
      unawaited(
        w.db
            .ref('t')
            .runTransaction((Object? v) {
              seen.add(v);
              return const Transaction.abort();
            })
            .then((_) {}),
      );
      w.settle();
      expect(seen, <Object?>[1]);
    });

    wired(
      'Transaction.success without a priority keeps the current one',
      (_Wire w) {
        answerT(w, <String, Object?>{'.value': 1, '.priority': 'p7'});
        w.track(
          'T',
          w.db
              .ref('t')
              .runTransaction((Object? v) => const Transaction.success(2)),
        );
        w.settle();
        expect(w.server.callsOf('put').single.data, <String, Object?>{
          '.value': 2,
          '.priority': 'p7',
        });
        expect(w.log, <String>['S1:2/p7']);
        w.server.ackLastWrite();
        w.settle();
        expect(w.log, <String>['S1:2/p7', 'T:committed(2/p7)']);
      },
      skip:
          'DEFECT: the new node is built with nodeFromJson(outcome.value) and no priority '
          '(repo_transactions.dart:116 first run, :331 rerun), so the priority is dropped; '
          'JS keeps '
          'the current priority when the value has no .priority (core/Repo.ts:996-1013 and '
          ':1303-1310).',
    );
  });

  group('emu.cloudWorkstation', () {
    test(
      'an emulator on *.cloudworkstations.dev is reached over TLS',
      () {
        fakeTime((FakeTime time) {
          final FirebaseDatabase db = FirebaseDatabase(
            newTestApp(),
            emulatorHost: '9000-x.cloudworkstations.dev:443',
          );
          expect(db.databaseUrl.scheme, 'https');
          expect(db.databaseUrl.host, '9000-x.cloudworkstations.dev');
        });
      },
      skip:
          'DEFECT: _Target.resolve sets secure: false for every emulatorHost '
          '(firebase_database.dart:721-731); emulatorDatabase in realtime/database_url.dart, which '
          'makes *.cloudworkstations.dev secure, has no caller in lib/. JS: isCloudWorkstation '
          'makes the emulator use TLS (api/Database.ts:393-396).',
    );
  });

  group('dart.estimatedServerTime', () {
    final DateTime device = DateTime.utc(2026, 1, 2, 3, 4, 5);

    wired(
      'device time until the server reports an offset, then corrected by it',
      (_Wire w) {
        expect(w.db.serverTimeOffset, Duration.zero);
        expect(w.db.estimatedServerTime.toUtc(), device);
        w.server.deliverServerTimeOffset(-1500);
        w.settle();
        expect(w.db.serverTimeOffset, const Duration(milliseconds: -1500));
        expect(
          w.db.estimatedServerTime.toUtc(),
          device.subtract(const Duration(milliseconds: 1500)),
        );
      },
      clock: () => device,
    );
  });

  group('dart.persistenceEnabled', () {
    test('false without persistence', () {
      fakeTime((FakeTime time) {
        final FirebaseDatabase db = databaseWithFakeServer(
          newTestApp(),
          FakeDatabaseServer(),
        );
        time.elapse(Duration.zero);
        expect(db.persistenceEnabled, isFalse);
      });
    });

    test('true while the store opens and once it is open; false after it '
        'degrades', () {
      fakeTime((FakeTime time) {
        final InMemoryPersistenceStorageEngine engine =
            InMemoryPersistenceStorageEngine();
        final FirebaseDatabase db = databaseWithFakeServer(
          newTestApp(),
          FakeDatabaseServer(),
          persistence: databasePersistence(
            opener: (PersistenceKey key, {DatabaseLogger? logger}) async =>
                engine,
          ),
        );
        expect(db.persistenceEnabled, isTrue);
        time.elapse(Duration.zero);
        expect(db.persistenceEnabled, isTrue);
        engine.degrade();
        expect(db.persistenceEnabled, isFalse);
      });
    });

    test('false when the store cannot be opened, with one warning', () {
      fakeTime((FakeTime time) {
        final List<String> warnings = <String>[];
        final FirebaseDatabase db = databaseWithFakeServer(
          newTestApp(),
          FakeDatabaseServer(),
          logger: (DatabaseLogLevel level, String message) {
            if (level == DatabaseLogLevel.warning) {
              warnings.add(message);
            }
          },
          persistence: databasePersistence(
            opener: (PersistenceKey key, {DatabaseLogger? logger}) async =>
                throw StateError('disk full'),
          ),
        );
        time.elapse(Duration.zero);
        expect(db.persistenceEnabled, isFalse);
        expect(warnings, hasLength(1));
        expect(warnings.single, contains('memory only'));
      });
    });
  });

  group('dart.databaseUrl', () {
    test('the app option databaseURL is used', () {
      fakeTime((FakeTime time) {
        final FirebaseDatabase db = databaseWithFakeServer(
          _appWithUrl('https://my-db.europe-west1.firebasedatabase.app'),
          FakeDatabaseServer(),
        );
        expect(
          db.databaseUrl.toString(),
          'https://my-db.europe-west1.firebasedatabase.app',
        );
      });
    });

    test('the databaseUrl argument wins over the app option', () {
      fakeTime((FakeTime time) {
        final FirebaseDatabase db = FirebaseDatabase(
          _appWithUrl('https://app-ns.firebaseio.com'),
          databaseUrl: 'https://arg-ns.firebaseio.com',
        );
        expect(db.databaseUrl.toString(), 'https://arg-ns.firebaseio.com');
      });
    });

    test('an emulator URL is plain http with the namespace in ns', () {
      fakeTime((FakeTime time) {
        final FirebaseDatabase db = FirebaseDatabase(
          newTestApp(),
          emulatorHost: '127.0.0.1:9000',
        );
        final Uri url = db.databaseUrl;
        expect(url.scheme, 'http');
        expect(url.host, '127.0.0.1');
        expect(url.port, 9000);
        expect(url.queryParameters, <String, String>{
          'ns': 'test-project-default-rtdb',
        });
      });
    });
  });
}

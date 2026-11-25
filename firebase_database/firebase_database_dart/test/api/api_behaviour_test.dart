// Behaviour of the public API that the scenario table does not cover: priorities, onDisconnect
// through the API, once() errors, construction errors, persistence that fails or is closed while
// it opens, the testing library's fakePersistence reused, refFromUrl on the emulator, limits and
// .info/authenticated. Each test was first seen failing on the defect or mutation it names
// (rtdb/from_helper/reports/test_quality_audit.md, section 6).

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart'
    show firebaseDatabaseWithConnection;
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/persistence/database_persistence.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine_opener.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:firebase_database_dart/testing.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

/// Persistence whose opener waits for [opened].
DatabasePersistence _waitingPersistence(
  Completer<PersistenceStorageEngine> opened,
) => databasePersistence(
  opener: (PersistenceKey key, {DatabaseLogger? logger}) => opened.future,
);

/// A database over a [FakeServerActions], for what the scripted server cannot send (auth status).
final class _Wire {
  _Wire(this.time) {
    db = firebaseDatabaseWithConnection(
      newTestApp(),
      connectionFactory: (ServerActionsDelegate delegate, DatabaseLogger? _) =>
          server..delegate = delegate,
    );
    time.elapse(Duration.zero);
    server.connect();
    time.elapse(Duration.zero);
  }

  final FakeTime time;
  final FakeServerActions server = FakeServerActions();
  late final FirebaseDatabase db;
}

void main() {
  void scenario(String name, void Function(Harness h) body, {String? skip}) {
    test(name, () {
      fakeTime((FakeTime time) => body(Harness(time)));
    }, skip: skip);
  }

  void timed(String name, void Function(FakeTime time) body) {
    test(name, () => fakeTime(body));
  }

  group('priorities', () {
    scenario('setPriority writes .priority and raises it locally (m01)', (
      Harness h,
    ) {
      h.listenAnswered(
        'S1',
        h.ref('a').onValue,
        'a',
        1,
        then: (DatabaseEvent e) => h.log.add('P:${e.snapshot.priority}'),
      );
      h.log.clear();

      h.track('W', h.ref('a').setPriority(3));
      h.settle();
      expect(h.server.requests.last, 'p /a/.priority');
      expect(h.log, <String>['S1:V(1)', 'P:3']);

      h.server.ackLastWrite();
      h.settle();
      expect(h.log, <String>['S1:V(1)', 'P:3', 'W:ok']);
    });

    scenario('setPriority refused by the server reverts with an event', (
      Harness h,
    ) {
      h.listenAnswered(
        'S1',
        h.ref('a').onValue,
        'a',
        1,
        then: (DatabaseEvent e) => h.log.add('P:${e.snapshot.priority}'),
      );
      h.log.clear();

      h.track('W', h.ref('a').setPriority(3));
      h.settle();
      h.server.failLastWrite('permission_denied');
      h.settle();
      expect(h.log, <String>[
        'S1:V(1)',
        'P:3',
        'S1:V(1)',
        'P:null',
        'W:E(permission-denied)',
      ]);
    });

    scenario('setPriority after close fails with database-closed', (Harness h) {
      h.db.close();
      h.track('W', h.ref('a').setPriority(3));
      h.settle();
      expect(h.log, <String>['W:E(database-closed)']);
    });

    scenario('set(priority:) writes the priority with the value (m03)', (
      Harness h,
    ) {
      h.listenAnswered(
        'S1',
        h.ref('a').onValue,
        'a',
        null,
        then: (DatabaseEvent e) => h.log.add('P:${e.snapshot.priority}'),
      );
      h.log.clear();

      h.track('W', h.ref('a').set(1, priority: 2));
      h.settle();
      expect(h.log, <String>['S1:V(1)', 'P:2']);
      expect(h.server.requests.last, 'p /a');
    });

    scenario('onDisconnect.set(priority:) applies the priority on a drop', (
      Harness h,
    ) {
      h.listenAnswered(
        'S1',
        h.ref('a').onValue,
        'a',
        1,
        then: (DatabaseEvent e) => h.log.add('P:${e.snapshot.priority}'),
      );
      h.track('F', h.ref('a').onDisconnect.set(2, priority: 5));
      h.settle();
      h.server.ackLastOnDisconnect();
      h.settle();
      h.log.clear();

      h.goDown();
      expect(h.log, <String>['S1:V(2)', 'P:5']);
    });
  });

  group('onDisconnect through the API', () {
    scenario(
      'purgeOutstandingWrites fails onDisconnect requests made offline; none is kept or sent',
      (Harness h) {
        h.listenAnswered('S1', h.ref('a').onValue, 'a', <String, Object?>{
          'x': 1,
        });
        h.goDown();
        h.log.clear();

        h.track('F', h.ref('a/x').onDisconnect.set(2));
        h.track('U', h.ref('a').onDisconnect.update(<String, Object?>{'y': 2}));
        h.track('C', h.ref('b').onDisconnect.cancel());
        h.settle();
        h.track('P', h.db.purgeOutstandingWrites());
        h.settle();
        expect(h.log.where((String e) => !e.startsWith('P:')), <String>[
          'F:E(write-canceled)',
          'U:E(write-canceled)',
          'C:E(write-canceled)',
        ]);
        expect(h.named('P'), <String>['P:ok']);

        final int before = h.server.requests.length;
        h.reconnect();
        expect(
          h.server.requests.skip(before).where((String r) => r.startsWith('o')),
          isEmpty,
        );
        h.log.clear();
        h.goDown();
        expect(h.log, isEmpty, reason: 'nothing registered locally');
      },
    );

    scenario(
      'purgeOutstandingWrites leaves sent onDisconnect requests, answered or not',
      (Harness h) {
        h.listenAnswered('S1', h.ref('a').onValue, 'a', <String, Object?>{
          'x': 1,
        });
        h.track('A', h.ref('a/x').onDisconnect.set(2));
        h.settle();
        h.server.ackLastOnDisconnect();
        h.track('F', h.ref('a/y').onDisconnect.set(2));
        h.settle();
        h.log.clear();

        h.track('P', h.db.purgeOutstandingWrites());
        h.settle();
        expect(h.log, <String>['P:ok']);
        h.server.ackLastOnDisconnect();
        h.settle();
        expect(h.named('F'), <String>['F:ok']);
        h.log.clear();

        h.goDown();
        expect(h.log, <String>['S1:V({x:2})', 'S1:V({x:2,y:2})']);
      },
    );

    scenario('update registers om and applies the children on a drop', (
      Harness h,
    ) {
      h.listenAnswered('S1', h.ref('a').onValue, 'a', <String, Object?>{
        'x': 1,
      });
      h.track('F', h.ref('a').onDisconnect.update(<String, Object?>{'y': 2}));
      h.settle();
      expect(h.server.requests.last, 'om /a');
      h.server.ackLastOnDisconnect();
      h.settle();
      expect(h.named('F'), <String>['F:ok']);
      h.log.clear();

      h.goDown();
      expect(h.log, <String>['S1:V({x:1,y:2})']);
    });

    scenario('remove registers o and removes the data on a drop', (Harness h) {
      h.listenAnswered('S1', h.ref('a').onValue, 'a', 1);
      h.track('F', h.ref('a').onDisconnect.remove());
      h.settle();
      expect(h.server.requests.last, 'o /a');
      h.server.ackLastOnDisconnect();
      h.settle();
      expect(h.named('F'), <String>['F:ok']);
      h.log.clear();

      h.goDown();
      expect(h.log, <String>['S1:V(null)']);
    });

    scenario('cancel sends oc and the drop then changes nothing (m07)', (
      Harness h,
    ) {
      h.listenAnswered('S1', h.ref('a').onValue, 'a', 1);
      h.track('F', h.ref('a').onDisconnect.set(2));
      h.settle();
      h.server.ackLastOnDisconnect();
      h.settle();

      h.track('C', h.ref('a').onDisconnect.cancel());
      h.settle();
      expect(h.server.requests.last, 'oc /a');
      expect(h.named('C'), isEmpty);
      h.server.ackLastOnDisconnect();
      h.settle();
      expect(h.named('C'), <String>['C:ok']);
      h.log.clear();

      h.goDown();
      expect(h.log, isEmpty);
    });

    scenario('cancel under .info throws before anything is sent', (Harness h) {
      final int sent = h.server.requests.length;
      for (final String path in <String>['.info', '.info/connected']) {
        expect(
          () => h.ref(path).onDisconnect.cancel(),
          throwsArgumentError,
          reason: path,
        );
        expect(() => h.ref(path).onDisconnect.set(1), throwsArgumentError);
      }
      h.settle();
      expect(h.server.requests.length, sent);
    });
  });

  group('once() errors', () {
    scenario('a refused listen fails once with permission-denied', (Harness h) {
      h.trackEvent('O', h.ref('a').once());
      h.settle();
      h.server.failListen('a', 'permission_denied');
      h.settle();
      expect(h.log, <String>['O:E(permission-denied)']);
    });

    scenario('a listen cancelled by the server fails once', (Harness h) {
      h.trackEvent('O', h.ref('a').once(DatabaseEventType.childAdded));
      h.settle();
      h.server.answerListen('a', null);
      h.settle();
      expect(h.log, isEmpty);
      h.server.cancelListen('a', 'permission_denied');
      h.settle();
      expect(h.log, <String>['O:E(permission-denied)']);
    });

    scenario('close while once waits fails it with database-closed', (
      Harness h,
    ) {
      h.trackEvent('O', h.ref('a').once());
      h.settle();
      h.db.close();
      h.settle();
      expect(h.log, <String>['O:E(database-closed)']);
    });
  });

  group('errors', () {
    scenario('serverStatus carries the server reason (m14)', (Harness h) {
      Object? error;
      h.ref('a').set(1).catchError((Object e) => error = e);
      h.settle();
      h.server.failLastWrite('permission_denied');
      h.settle();
      expect(
        error,
        isA<FirebaseDatabaseException>()
            .having(
              (FirebaseDatabaseException e) => e.code,
              'code',
              'permission-denied',
            )
            .having(
              (FirebaseDatabaseException e) => e.serverStatus,
              'serverStatus',
              'permission_denied: The fake server answered permission_denied.',
            ),
      );
    });

    /// The exception of a set the server answers with [status] and [reason].
    FirebaseDatabaseException failedSet(
      FakeTime time,
      String status, [
      String? reason,
    ]) {
      final _Wire w = _Wire(time);
      Object? error;
      w.db.ref('a').set(1).catchError((Object e) => error = e);
      time.elapse(Duration.zero);
      w.server.failLastWrite(status, reason);
      time.elapse(Duration.zero);
      return error! as FirebaseDatabaseException;
    }

    timed('an unknown status with a reason gives the reason as message', (
      FakeTime time,
    ) {
      const String reason =
          'Path specified exceeds the maximum length that can be written '
          '(768 bytes).';
      final FirebaseDatabaseException e = failedSet(
        time,
        'invalid_parameters',
        reason,
      );
      expect(e.code, 'unknown');
      expect(e.message, reason);
      expect(e.serverStatus, 'invalid_parameters: $reason');
    });

    timed('an unknown status without a reason keeps the generic message', (
      FakeTime time,
    ) {
      final FirebaseDatabaseException e = failedSet(time, 'internal_error');
      expect(e.code, 'unknown');
      expect(e.message, 'An unknown error occurred.');
      expect(e.serverStatus, 'internal_error');
    });

    timed('a known status keeps its own message and the reason', (
      FakeTime time,
    ) {
      final FirebaseDatabaseException e = failedSet(
        time,
        'permission_denied',
        'Permission denied',
      );
      expect(e.code, 'permission-denied');
      expect(
        e.message,
        'This client does not have permission to perform this operation.',
      );
      expect(e.serverStatus, 'permission_denied: Permission denied');
    });

    timed('a set answered datastale fails with data-stale', (FakeTime time) {
      final FirebaseDatabaseException e = failedSet(time, 'datastale');
      expect(e.code, 'data-stale');
      expect(e.serverStatus, 'datastale');
    });

    /// The error of a get of `a` whose server call [answer] completes.
    Object failedGet(
      FakeTime time,
      void Function(FakeServerActions server, ServerCall get) answer,
    ) {
      final _Wire w = _Wire(time);
      Object? error;
      w.db.ref('a').get().then<void>((_) {}, onError: (Object e) => error = e);
      time.elapse(Duration.zero);
      answer(w.server, w.server.callsOf('get').last);
      time.elapse(Duration.zero);
      return error!;
    }

    /// The exception of a get the server answers with [status] and [reason].
    FirebaseDatabaseException refusedGet(
      FakeTime time,
      String status, [
      String? reason,
    ]) =>
        failedGet(
              time,
              (FakeServerActions server, ServerCall get) =>
                  server.respond(get, status: status, data: reason),
            )
            as FirebaseDatabaseException;

    timed(
      'a get refused with an unknown status and a reason gives the reason',
      (FakeTime time) {
        final FirebaseDatabaseException e = refusedGet(
          time,
          'invalid_parameters',
          'Bad path.',
        );
        expect(e.code, 'unknown');
        expect(e.message, 'Bad path.');
        expect(e.serverStatus, 'invalid_parameters: Bad path.');
      },
    );

    timed('a get refused with an unknown status alone keeps the generic '
        'message', (FakeTime time) {
      final FirebaseDatabaseException e = refusedGet(time, 'internal_error');
      expect(e.code, 'unknown');
      expect(e.message, 'An unknown error occurred.');
      expect(e.serverStatus, 'internal_error');
    });

    timed('a get refused with a known status keeps its own message', (
      FakeTime time,
    ) {
      final FirebaseDatabaseException e = refusedGet(
        time,
        'permission_denied',
        'Permission denied',
      );
      expect(e.code, 'permission-denied');
      expect(
        e.message,
        'This client does not have permission to perform this operation.',
      );
      expect(e.serverStatus, 'permission_denied: Permission denied');
    });

    timed('a get answer the client cannot read is a local unknown', (
      FakeTime time,
    ) {
      final FirebaseDatabaseException e =
          failedGet(
                time,
                (FakeServerActions server, ServerCall get) =>
                    server.respond(get, data: Object()),
              )
              as FirebaseDatabaseException;
      expect(e.code, 'unknown');
      expect(e.message, 'The server answer to get() could not be read.');
      expect(e.cause, isA<ArgumentError>());
      expect(e.serverStatus, isNull);
    });

    timed('a get failed by the connection with another error is a local '
        'unknown', (FakeTime time) {
      final StateError boom = StateError('boom');
      final FirebaseDatabaseException e =
          failedGet(
                time,
                (FakeServerActions server, ServerCall get) =>
                    get.getCompleter!.completeError(boom),
              )
              as FirebaseDatabaseException;
      expect(e.code, 'unknown');
      expect(
        e.message,
        'get() failed with an error the client did not expect.',
      );
      expect(e.cause, same(boom));
      expect(e.serverStatus, isNull);
    });
  });

  group('construction', () {
    for (final bool persisted in <bool>[false, true]) {
      final String mode = persisted ? 'with' : 'without';

      timed('a plain http URL that is not the emulator throws at the '
          'constructor, $mode persistence', (FakeTime time) {
        expect(
          () => FirebaseDatabase(
            newTestApp(),
            databaseUrl: 'http://test-project-default-rtdb.firebaseio.com',
            persistence: persisted ? fakePersistence() : null,
          ),
          throwsArgumentError,
        );
        time.elapse(const Duration(seconds: 1));
      });

      timed('an unparsable URL throws at the constructor, $mode persistence', (
        FakeTime time,
      ) {
        expect(
          () => FirebaseDatabase(
            newTestApp(),
            databaseUrl: 'https://user@host.firebaseio.com',
            persistence: persisted ? fakePersistence() : null,
          ),
          throwsArgumentError,
        );
      });
    }

    timed('an empty emulatorHost throws', (FakeTime time) {
      expect(
        () => FirebaseDatabase(newTestApp(), emulatorHost: ''),
        throwsArgumentError,
      );
    });

    timed('no URL and no project id throws', (FakeTime time) {
      final FirebaseApp app = FirebaseApp.withOptions(
        const FirebaseOptions(apiKey: 'k', appId: '1:1:dart:1'),
        name: 'rtdb-api-behaviour-no-project',
      );
      expect(() => FirebaseDatabase(app), throwsArgumentError);
    });

    timed('a connection that fails to start throws at the constructor '
        'without persistence', (FakeTime time) {
      expect(
        () => firebaseDatabaseWithConnection(
          newTestApp(),
          connectionFactory: (ServerActionsDelegate d, DatabaseLogger? l) =>
              throw StateError('no connection'),
        ),
        throwsStateError,
      );
    });

    timed('with persistence, a connection that fails to start fails every '
        'call made before and after it', (FakeTime time) {
      final StateError failure = StateError('no connection');
      final FirebaseDatabase db = firebaseDatabaseWithConnection(
        newTestApp(),
        connectionFactory: (ServerActionsDelegate d, DatabaseLogger? l) =>
            throw failure,
        persistence: fakePersistence(),
      );
      final List<Object> errors = <Object>[];
      db.ref('a').set(1).catchError((Object e) => errors.add(e));
      db.ref('a').onValue.listen(null, onError: errors.add);
      time.elapse(Duration.zero);
      expect(errors, <Object>[failure, failure]);

      db.ref('b').get().then<void>((_) {}, onError: errors.add);
      db.ref('b').onValue.listen(null, onError: errors.add);
      db.purgeOutstandingWrites().catchError((Object e) => errors.add(e));
      time.elapse(Duration.zero);
      expect(errors, <Object>[failure, failure, failure, failure, failure]);
      expect(db.isConnected, isFalse);
      db.goOnline();
      db.goOffline();
      Object? closeError;
      db.close().catchError((Object e) => closeError = e);
      time.elapse(Duration.zero);
      expect(closeError, isNull);
    });
  });

  group('persistence', () {
    timed('a store that fails to open runs memory only: writes still work', (
      FakeTime time,
    ) {
      final FakeDatabaseServer server = FakeDatabaseServer();
      final FirebaseDatabase db = databaseWithFakeServer(
        newTestApp(),
        server,
        persistence: databasePersistence(
          opener: (PersistenceKey key, {DatabaseLogger? logger}) async =>
              throw StateError('disk full'),
        ),
      );
      final List<String> log = <String>[];
      db.ref('a').set(1).then<void>((_) => log.add('ok'));
      time.elapse(Duration.zero);
      expect(server.requests, contains('p /a'));
      server.ackLastWrite();
      time.elapse(Duration.zero);
      expect(log, <String>['ok']);
      expect(db.persistenceEnabled, isFalse);
    });

    timed('close while the store opens: no connection is ever made, and calls '
        'fail with database-closed (m06)', (FakeTime time) {
      final Completer<PersistenceStorageEngine> opened =
          Completer<PersistenceStorageEngine>();
      final FakeDatabaseServer server = FakeDatabaseServer();
      final FirebaseDatabase db = databaseWithFakeServer(
        newTestApp(),
        server,
        persistence: _waitingPersistence(opened),
      );
      final List<String> log = <String>[];
      db
          .ref('a')
          .set(1)
          .then<void>(
            (_) => log.add('W:ok'),
            onError: (Object e) => log.add('W:${errorText(e)}'),
          );
      db.close().then<void>((_) => log.add('closed'));
      time.elapse(Duration.zero);
      expect(log, <String>['W:E(database-closed)']);

      opened.complete(InMemoryPersistenceStorageEngine());
      time.elapse(const Duration(seconds: 5));
      expect(server.connectionAttempts, 0);
      expect(log, <String>['W:E(database-closed)', 'closed']);
    });

    timed('isConnected is false while the store opens (m19)', (FakeTime time) {
      final Completer<PersistenceStorageEngine> opened =
          Completer<PersistenceStorageEngine>();
      final FirebaseDatabase db = databaseWithFakeServer(
        newTestApp(),
        FakeDatabaseServer(),
        persistence: _waitingPersistence(opened),
      );
      time.elapse(Duration.zero);
      expect(db.isConnected, isFalse);
      expect(db.serverTimeOffset, Duration.zero);
    });

    timed('fakePersistence reused by a second database after the first '
        'closed keeps its data and accepts writes', (FakeTime time) {
      final DatabasePersistence persistence = fakePersistence();
      final FakeDatabaseServer first = FakeDatabaseServer();
      final FirebaseDatabase db1 = databaseWithFakeServer(
        newTestApp(),
        first,
        persistence: persistence,
      );
      final List<String> log = <String>[];
      db1.ref('a').set(1).then<void>((_) => log.add('1:ok'));
      time.elapse(Duration.zero);
      first.ackLastWrite();
      time.elapse(Duration.zero);
      db1.close();
      time.elapse(Duration.zero);

      final FakeDatabaseServer second = FakeDatabaseServer()
        ..acceptConnections = false;
      final FirebaseDatabase db2 = databaseWithFakeServer(
        newTestApp(),
        second,
        persistence: persistence,
      );
      db2
          .ref('b')
          .set(2)
          .then<void>(
            (_) => log.add('2:ok'),
            onError: (Object e) => log.add('2:${errorText(e)}'),
          );
      db2
          .ref('b')
          .onValue
          .listen(
            (DatabaseEvent e) => log.add('b:${e.snapshot.value}'),
            onError: (Object e) => log.add('b:${errorText(e)}'),
          );
      db2
          .ref('a')
          .onValue
          .listen(
            (DatabaseEvent e) => log.add('a:${e.snapshot.value}'),
            onError: (Object e) => log.add('a:${errorText(e)}'),
          );
      time.elapse(Duration.zero);
      expect(log, <String>['1:ok', 'b:2', 'a:1']);
      expect(db2.persistenceEnabled, isTrue);
    });
  });

  group('persistence key', () {
    /// The key the opener receives for a database of [app] built by [open].
    PersistenceKey keyOf(
      FakeTime time,
      FirebaseApp app,
      FirebaseDatabase Function(DatabasePersistence persistence) open,
    ) {
      final List<PersistenceKey> keys = <PersistenceKey>[];
      open(
        databasePersistence(
          opener: (PersistenceKey key, {DatabaseLogger? logger}) async {
            keys.add(key);
            return InMemoryPersistenceStorageEngine();
          },
        ),
      );
      time.flushMicrotasks();
      return keys.single;
    }

    PersistenceKey urlKey(FakeTime time, FirebaseApp app, String url) => keyOf(
      time,
      app,
      (DatabasePersistence p) =>
          FirebaseDatabase(app, databaseUrl: url, persistence: p),
    );

    PersistenceKey emulatorKey(FakeTime time, FirebaseApp app, String url) =>
        keyOf(
          time,
          app,
          (DatabasePersistence p) => FirebaseDatabase(
            app,
            databaseUrl: url,
            emulatorHost: '127.0.0.1:9000',
            persistence: p,
          ),
        );

    timed('two namespaces on one custom domain get two keys', (FakeTime t) {
      final FirebaseApp app = newTestApp();
      expect(
        urlKey(t, app, 'https://db.example.com?ns=a'),
        isNot(urlKey(t, app, 'https://db.example.com?ns=b')),
      );
      expect(
        urlKey(t, app, 'https://x.firebaseio.com'),
        isNot(urlKey(t, app, 'https://x.firebaseio.com?ns=y')),
      );
    });

    timed('two namespaces on one host never share a cache', (FakeTime t) {
      final FirebaseApp app = FirebaseApp.withOptions(
        const FirebaseOptions(
          apiKey: 'test-key',
          appId: '1:1234567890:dart:test',
          databaseURL: 'https://db.example.com?ns=a',
        ),
        name: 'rtdb-api-behaviour-ns-a',
      );
      final Map<PersistenceKey, InMemoryPersistenceStorageEngine> disk =
          <PersistenceKey, InMemoryPersistenceStorageEngine>{};
      final DatabasePersistence persistence = databasePersistence(
        opener: (PersistenceKey key, {DatabaseLogger? logger}) async {
          final InMemoryPersistenceStorageEngine engine = disk.putIfAbsent(
            key,
            InMemoryPersistenceStorageEngine.new,
          );
          if (engine.isClosed) {
            engine.reopen();
          }
          return engine;
        },
      );
      final FakeDatabaseServer first = FakeDatabaseServer();
      final FirebaseDatabase a = databaseWithFakeServer(
        app,
        first,
        persistence: persistence,
      );
      a.ref('k').set(1);
      t.elapse(Duration.zero);
      first.ackLastWrite();
      t.elapse(Duration.zero);
      a.close();
      app.delete();
      t.elapse(Duration.zero);
      final FirebaseApp other = FirebaseApp.withOptions(
        const FirebaseOptions(
          apiKey: 'test-key',
          appId: '1:1234567890:dart:test',
          databaseURL: 'https://db.example.com?ns=b',
        ),
        name: 'rtdb-api-behaviour-ns-a',
      );

      final FirebaseDatabase b = databaseWithFakeServer(
        other,
        FakeDatabaseServer()..acceptConnections = false,
        persistence: persistence,
      );
      final List<Object?> values = <Object?>[];
      b
          .ref('k')
          .onValue
          .listen((DatabaseEvent e) => values.add(e.snapshot.value));
      t.elapse(Duration.zero);
      expect(values, isEmpty);
      expect(disk, hasLength(2));
    });

    timed('the key is databaseUrl, so clearing a cache by it finds the cache', (
      FakeTime t,
    ) {
      final FirebaseApp app = newTestApp();
      for (final String url in <String>[
        'https://db.example.com?ns=A',
        'https://x.firebaseio.com?ns=y',
        'wss://X.firebaseio.com:443',
      ]) {
        late final FirebaseDatabase db;
        final PersistenceKey key = keyOf(t, app, (DatabasePersistence p) {
          return db = FirebaseDatabase(app, databaseUrl: url, persistence: p);
        });
        expect(key.databaseUrl, db.databaseUrl, reason: url);
      }
      expect(
        FirebaseDatabase(
          app,
          databaseUrl: 'https://db.example.com?ns=A',
        ).databaseUrl.toString(),
        'https://db.example.com?ns=a',
      );
    });

    timed('production and the emulator get two keys', (FakeTime t) {
      final FirebaseApp app = newTestApp();
      const String url = 'https://test-project-default-rtdb.firebaseio.com';
      expect(urlKey(t, app, url), isNot(emulatorKey(t, app, url)));
    });

    timed('every spelling of one database gets one key', (FakeTime t) {
      final FirebaseApp app = newTestApp();
      const String url = 'https://p-default-rtdb.firebaseio.com';
      final PersistenceKey key = urlKey(t, app, url);
      for (final String spelling in <String>[
        '$url/',
        'https://P-Default-RTDB.firebaseio.com',
        '$url:443',
        'wss://p-default-rtdb.firebaseio.com:443',
        'p-default-rtdb.firebaseio.com',
        '$url?ns=p-default-rtdb',
      ]) {
        expect(urlKey(t, app, spelling), key, reason: spelling);
      }
      final PersistenceKey emulator = emulatorKey(
        t,
        app,
        'http://127.0.0.1:9000?ns=p-default-rtdb',
      );
      for (final String spelling in <String>[
        'http://127.0.0.1:9000?ns=P-Default-Rtdb',
        'https://p-default-rtdb.firebaseio.com',
        url,
      ]) {
        expect(emulatorKey(t, app, spelling), emulator, reason: spelling);
      }
    });
  });

  group('refFromUrl', () {
    timed('on the emulator, any host is accepted and only the path is used '
        '(m10)', (FakeTime time) {
      final FirebaseDatabase db = FirebaseDatabase(
        newTestApp(),
        emulatorHost: '127.0.0.1:9000',
      );
      expect(
        db
            .refFromUrl('https://test-project-default-rtdb.firebaseio.com/a/b')
            .path,
        db.ref('a/b').path,
      );
      expect(
        db.refFromUrl('http://127.0.0.1:9000/c?ns=x').path,
        db.ref('c').path,
      );
    });
  });

  group('one URL parser (database_url.dart)', () {
    timed('an emulatorHost without a port is refused at construction', (
      FakeTime time,
    ) {
      for (final String host in <String>['localhost', '127.0.0.1', '[::1]']) {
        expect(
          () => FirebaseDatabase(newTestApp(), emulatorHost: host),
          throwsArgumentError,
          reason: host,
        );
      }
    });

    timed('refFromUrl refuses what parseDatabaseUrl refuses', (FakeTime time) {
      final FirebaseDatabase db = FirebaseDatabase(newTestApp());
      for (final String url in <String>[
        'https://user@test-project-default-rtdb.firebaseio.com/a',
        'http://test-project-default-rtdb.firebaseio.com/a',
        'https://test-project-default-rtdb.firebaseio.com:8443/a',
        'https://test-project-default-rtdb.firebaseio.com/a?x=1',
      ]) {
        expect(() => db.refFromUrl(url), throwsArgumentError, reason: url);
      }
      expect(
        db
            .refFromUrl(
              'https://Test-Project-Default-RTDB.firebaseio.com:443/a/b%20c',
            )
            .path,
        '/a/b c',
      );
      expect(
        db.refFromUrl('test-project-default-rtdb.firebaseio.com/a').path,
        '/a',
      );
    });

    timed('the databaseUrl of an emulator instance goes through the same '
        'parser', (FakeTime time) {
      expect(
        () => FirebaseDatabase(
          newTestApp(),
          databaseUrl: 'https://user@x.firebaseio.com',
          emulatorHost: '127.0.0.1:9000',
        ),
        throwsArgumentError,
      );
      expect(
        FirebaseDatabase(
          newTestApp(),
          databaseUrl: 'http://localhost:9000?ns=Ns-1',
          emulatorHost: '127.0.0.1:9000',
        ).databaseUrl.queryParameters['ns'],
        'ns-1',
      );
    });
  });

  group('limits', () {
    timed('limitToLast and limitToFirst refuse 0 and below (m17)', (
      FakeTime time,
    ) {
      final Harness h = Harness(time);
      for (final int limit in <int>[0, -1]) {
        expect(() => h.ref('a').limitToLast(limit), throwsArgumentError);
        expect(() => h.ref('a').limitToFirst(limit), throwsArgumentError);
      }
      expect(h.ref('a').limitToLast(1).ref.path, h.ref('a').path);
    });
  });

  group('.info/authenticated', () {
    timed('follows the auth status the server reports', (FakeTime time) {
      final _Wire w = _Wire(time);
      final List<Object?> values = <Object?>[];
      w.db
          .ref('.info/authenticated')
          .onValue
          .listen((DatabaseEvent e) => values.add(e.snapshot.value));
      time.elapse(Duration.zero);
      w.server.deliverAuthStatus('ok');
      time.elapse(Duration.zero);
      w.server.deliverAuthStatus('permission_denied', explanation: 'no');
      time.elapse(Duration.zero);
      expect(values, <Object?>[false, true, false]);
    });
  });
}

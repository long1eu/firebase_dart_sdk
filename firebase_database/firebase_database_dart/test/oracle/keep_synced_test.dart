// Oracle: Android androidTest/.../core/persistence/KeepSyncedTest.java, one test per upstream test, in
// upstream order, on the public API over a FakeDatabaseServer that answers what the real server would
// (listens with its current data, writes acknowledged in order).
//
// Upstream runs these with the integration test config, which has no persistence (memory only): with
// a persistent cache an unsynced query would still raise the old cached value offline, so
// assertNotKeptSynced only holds memory only. [runKeepSyncedOracle] therefore uses the engine only
// when one is given; main runs it memory only, as upstream.
import 'dart:async';
import 'dart:convert';

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/api/fake_database_server.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:test/test.dart';

import '../api/support/fake_time.dart';
import 'oracle_support.dart';

void main() => runKeepSyncedOracle();

/// One test's database, its fake server and the server's data.
final class _Env {
  _Env(this.time, OpenEngine? openEngine) : server = FakeDatabaseServer() {
    db = oracleDatabase(server, engine: openEngine?.call());
    time.elapse(Duration.zero);
  }

  final FakeTime time;
  final FakeDatabaseServer server;
  late final FirebaseDatabase db;

  /// The server's data as the real server would hold it.
  Node _data = ChildrenNode.empty;
  int _handledRequests = 0;
  final List<(Path, Object?)> _unacked = <(Path, Object?)>[];

  void settle() => time.elapse(Duration.zero);

  /// Android `IntegrationTestHelpers.getRandomNode`.
  DatabaseReference randomNode() => db.ref().child(db.ref().push().key!);

  /// `ref.set(value)` without waiting; the server acknowledges it at the next [serve].
  Future<void> set(DatabaseReference ref, Object? value) {
    _unacked.add((Path(ref.path), value));
    return ref.set(value);
  }

  /// Answers the listens sent since the last call with the server's data, then acknowledges the
  /// writes sent, as the real server does.
  void serve() {
    settle();
    final List<String> requests = server.requests;
    for (int i = _handledRequests; i < requests.length; i++) {
      final String request = requests[i];
      if (!request.startsWith('q ')) {
        continue;
      }
      final String rest = request.substring(2);
      final int space = rest.indexOf(' ');
      final String path = space < 0 ? rest : rest.substring(0, space);
      final Map<String, Object?>? query = space < 0
          ? null
          : jsonDecode(rest.substring(space + 1)) as Map<String, Object?>;
      try {
        server.answerListen(
          path,
          _data.getChild(Path(path)).toJson(exportFormat: true),
          query: query,
        );
      } on StateError {
        // Unlistened before the server answered.
      }
    }
    _handledRequests = requests.length;
    settle();
    while (_unacked.isNotEmpty) {
      try {
        server.ackLastWrite();
      } on StateError {
        break; // Not sent yet (offline).
      }
      final (Path path, Object? value) = _unacked.removeLast();
      _data = _data.updateChild(path, n(value));
      settle();
    }
    _handledRequests = server.requests.length;
  }

  /// Android `new WriteFuture(ref, value).timedGet()`.
  void writeAndWait(DatabaseReference ref, Object? value) {
    bool done = false;
    unawaited(set(ref, value).then((_) => done = true));
    serve();
    expect(done, isTrue, reason: 'write of $value at ${ref.path} not done');
  }

  void goOffline() {
    db.goOffline();
    settle();
  }

  void goOnline() {
    db.goOnline();
    time.elapse(const Duration(seconds: 2));
    serve();
  }

  /// Android `query.keepSynced(value)`; the server answers the listen it starts.
  void keepSynced(Query query, bool value) {
    unawaited(query.keepSynced(value));
    serve();
  }

  /// Listens to [query] until the first event (Android `ReadFuture` completing on its first
  /// event) and returns the events delivered by then.
  List<DatabaseEvent> readFirst(Query query, {void Function()? before}) {
    final List<DatabaseEvent> events = <DatabaseEvent>[];
    final StreamSubscription<DatabaseEvent> sub = query.onValue.listen(
      events.add,
    );
    settle();
    before?.call();
    settle();
    unawaited(sub.cancel());
    settle();
    return events;
  }
}

/// The KeepSyncedTest suite; memory only unless [openEngine] is given (see the file comment).
void runKeepSyncedOracle([OpenEngine? openEngine]) {
  int globalKeepSyncedTestCounter = 0;

  void oracle(String name, void Function(_Env env) body) => test(
    name,
    () => fakeTime<void>((FakeTime time) => body(_Env(time, openEngine))),
  );

  void assertIsKeptSynced(_Env env, Query query) {
    final DatabaseReference ref = query.ref;

    // First set a unique value to the value of a child.
    final int counter = globalKeepSyncedTestCounter++;
    final Map<String, Object?> value = <String, Object?>{'child': counter};
    env.writeAndWait(ref, value);

    // Next go offline, if it's kept synced we should have kept the value, after going offline no
    // way to get the value except from cache
    env.goOffline();

    final List<DatabaseEvent> events = env.readFirst(query);
    expect(events, isNotEmpty, reason: 'no event from the cache');
    expect(events[0].snapshot.value, value);

    // All good, go back online
    env.goOnline();
  }

  void assertNotKeptSynced(_Env env, Query query) {
    final DatabaseReference ref = query.ref;

    // First set a unique value to the value of a child.
    final int current = globalKeepSyncedTestCounter++;
    final Map<String, Object?> oldValue = <String, Object?>{'child': current};

    final int next = globalKeepSyncedTestCounter++;
    final Map<String, Object?> nextValue = <String, Object?>{'child': next};

    env.writeAndWait(ref, oldValue);

    // Next go offline, if it's kept synced we should have kept the value and we'll get an even
    // with the *old* value.
    env.goOffline();

    final List<DatabaseEvent> events = env.readFirst(
      query,
      // By now, if we had it synced we should have gotten an event with the wrong value
      // Write a new value so the value event listener will be triggered
      before: () => unawaited(env.set(ref, nextValue)),
    );
    // We expect this to get called with the next value, not the old value.
    expect(events, isNotEmpty, reason: 'no event');
    expect(events[0].snapshot.value, nextValue);

    // All good, go back online
    env.goOnline();
  }

  group('KeepSyncedTest', () {
    oracle('keepSynced', (_Env env) {
      final DatabaseReference ref = env.randomNode();
      env.keepSynced(ref, true);
      assertIsKeptSynced(env, ref);

      env.keepSynced(ref, false);
      assertNotKeptSynced(env, ref);
    });

    // NOTE: This is not ideal behavior and should be fixed in a future release
    oracle('keepSyncedAffectsQueries', (_Env env) {
      final DatabaseReference ref = env.randomNode();
      env.keepSynced(ref, true);
      final Query query = ref.limitToFirst(5);
      env.keepSynced(query, true);
      assertIsKeptSynced(env, ref);

      env.keepSynced(ref, false);
      assertNotKeptSynced(env, ref);
      // currently, setting false on the default query affects all queries at that location
      assertNotKeptSynced(env, query);
    });

    oracle('manyKeepSyncedCallsDontAccumulate', (_Env env) {
      final DatabaseReference ref = env.randomNode();

      env.keepSynced(ref, true);
      env.keepSynced(ref, true);
      env.keepSynced(ref, true);
      assertIsKeptSynced(env, ref);

      // If it were balanced, this would not be enough
      env.keepSynced(ref, false);
      env.keepSynced(ref, false);
      assertNotKeptSynced(env, ref);

      // If it were balanced, this would not be enough
      env.keepSynced(ref, true);
      assertIsKeptSynced(env, ref);

      // cleanup
      env.keepSynced(ref, false);
    });

    // NOTE: No RemoveAllListenersDoesNotAffectKeepSynced test, since JVM client doesn't have
    // removeAllListeners...

    oracle('removeSingleListenerDoesNotAffectKeepSynced', (_Env env) {
      final DatabaseReference ref = env.randomNode();

      env.keepSynced(ref, true);
      assertIsKeptSynced(env, ref);

      // This will add and remove a listener.
      expect(env.readFirst(ref), isNotEmpty);

      assertIsKeptSynced(env, ref);

      // cleanup
      env.keepSynced(ref, false);
    });

    oracle('keepSyncedNoDoesNotAffectExistingListener', (_Env env) {
      final DatabaseReference ref = env.randomNode();

      env.keepSynced(ref, true);
      assertIsKeptSynced(env, ref);

      final List<DatabaseEvent> events = <DatabaseEvent>[];
      final StreamSubscription<DatabaseEvent> sub = ref.onValue.listen(
        events.add,
      );
      env.serve();

      // cleanup
      env.keepSynced(ref, false);

      // Should trigger our listener.
      unawaited(env.set(ref, 'done'));
      env.serve();
      unawaited(sub.cancel());
      expect(events, isNotEmpty);
      expect(events.last.snapshot.value, 'done');
    });

    oracle('differentQueriesAreIndependent', (_Env env) {
      final DatabaseReference ref = env.randomNode();
      final Query query1 = ref.limitToFirst(1);
      final Query query2 = ref.limitToFirst(2);

      env.keepSynced(query1, true);
      assertIsKeptSynced(env, query1);
      assertNotKeptSynced(env, query2);

      env.keepSynced(query2, true);
      assertIsKeptSynced(env, query1);
      assertIsKeptSynced(env, query2);

      env.keepSynced(query1, false);
      assertIsKeptSynced(env, query2);
      assertNotKeptSynced(env, query1);

      env.keepSynced(query2, false);
      assertNotKeptSynced(env, query1);
      assertNotKeptSynced(env, query2);
    });

    oracle('childIsKeptSynced', (_Env env) {
      final DatabaseReference ref = env.randomNode();
      final DatabaseReference child = ref.child('random-child');

      env.keepSynced(ref, true);
      assertIsKeptSynced(env, child);

      // cleanup
      env.keepSynced(ref, false);
    });

    oracle('rootIsKeptSynced', (_Env env) {
      final DatabaseReference ref = env.randomNode().root;

      env.keepSynced(ref, true);
      assertIsKeptSynced(env, ref);

      // cleanup
      env.keepSynced(ref, false);
    });

    // TODO[offline]: Cancel listens for keep synced....
  });
}

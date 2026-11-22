// The harness of the scenario table (contract 14_api_contract.md, section 4.2), over FakeDatabaseServer and
// FakeTime.

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/testing.dart';

import 'fake_time.dart';

int _appCount = 0;

/// A new app with a unique name and a project id.
FirebaseApp newTestApp() => FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: 'test-key',
    appId: '1:1234567890:dart:test',
    projectId: 'test-project',
  ),
  name: 'rtdb-api-test-${_appCount++}',
);

/// JSON written with bare keys, as the scenario table writes it.
String bare(Object? value) => switch (value) {
  null => 'null',
  final Map<Object?, Object?> m =>
    '{${m.entries.map((MapEntry<Object?, Object?> e) => '${e.key}:${bare(e.value)}').join(',')}}',
  final List<Object?> l => '[${l.map(bare).join(',')}]',
  _ => '$value',
};

/// The log form of an event: `V(json)`, `A(key,prev)`, `C(key,prev)`, `M(key,prev)` or `R(key)`.
String eventText(DatabaseEvent e) => switch (e.type) {
  DatabaseEventType.value => 'V(${bare(e.snapshot.value)})',
  DatabaseEventType.childAdded => 'A(${e.snapshot.key},${e.previousChildKey})',
  DatabaseEventType.childChanged =>
    'C(${e.snapshot.key},${e.previousChildKey})',
  DatabaseEventType.childMoved => 'M(${e.snapshot.key},${e.previousChildKey})',
  DatabaseEventType.childRemoved => 'R(${e.snapshot.key})',
};

/// The log form of an error: `E(code)` for a FirebaseDatabaseException, else `E(<error>)`.
String errorText(Object error) =>
    error is FirebaseDatabaseException ? 'E(${error.code})' : 'E($error)';

/// One scenario: an app, a fake server, a database and a log.
final class Harness {
  /// Creates the database; [persisted] passes `fakePersistence(serverCache: persisted)`. With [settled]
  /// the setup starts connected.
  Harness(
    this.time, {
    Map<String, Object?>? persisted,
    bool acceptConnections = true,
    bool settled = true,
  }) : app = newTestApp(),
       server = FakeDatabaseServer()..acceptConnections = acceptConnections {
    db = databaseWithFakeServer(
      app,
      server,
      persistence: persisted == null
          ? null
          : fakePersistence(serverCache: persisted),
    );
    if (settled) {
      settle();
    }
  }

  final FakeTime time;
  final FirebaseApp app;
  final FakeDatabaseServer server;
  late final FirebaseDatabase db;
  final List<String> log = <String>[];

  void settle() => time.elapse(Duration.zero);

  void elapse(Duration duration) => time.elapse(duration);

  void goDown() {
    server
      ..acceptConnections = false
      ..dropConnection();
    settle();
  }

  void reconnect() {
    server.acceptConnections = true;
    elapse(const Duration(seconds: 1));
  }

  DatabaseReference ref(String path) => db.ref(path);

  /// Listens to [stream], logging `name:<event>`, `name:E(code)` and `name:done`; [then] runs after the
  /// event is logged.
  StreamSubscription<DatabaseEvent> listen(
    String name,
    Stream<DatabaseEvent> stream, {
    void Function(DatabaseEvent event)? then,
  }) => stream.listen(
    (DatabaseEvent e) {
      log.add('$name:${eventText(e)}');
      then?.call(e);
    },
    onError: (Object e) => log.add('$name:${errorText(e)}'),
    onDone: () => log.add('$name:done'),
  );

  /// [listen], then the server answers the listen at [path] with [value].
  StreamSubscription<DatabaseEvent> listenAnswered(
    String name,
    Stream<DatabaseEvent> stream,
    String path,
    Object? value, {
    void Function(DatabaseEvent event)? then,
  }) {
    final StreamSubscription<DatabaseEvent> s = listen(
      name,
      stream,
      then: then,
    );
    settle();
    server.answerListen(path, value);
    settle();
    return s;
  }

  /// Logs `name:ok` or `name:E(code)`.
  void track(String name, Future<void> future) {
    future.then<void>(
      (_) => log.add('$name:ok'),
      onError: (Object e) => log.add('$name:${errorText(e)}'),
    );
  }

  /// Logs `name:=<json>` or `name:E(code)`; [then] runs after the value is logged.
  void trackValue(
    String name,
    Future<DataSnapshot> future, {
    void Function(DataSnapshot snapshot)? then,
  }) {
    future.then<void>((DataSnapshot s) {
      log.add('$name:=${bare(s.value)}');
      then?.call(s);
    }, onError: (Object e) => log.add('$name:${errorText(e)}'));
  }

  /// Logs `name:<event>` or `name:E(code)`.
  void trackEvent(String name, Future<DatabaseEvent> future) {
    future.then<void>(
      (DatabaseEvent e) => log.add('$name:${eventText(e)}'),
      onError: (Object e) => log.add('$name:${errorText(e)}'),
    );
  }

  /// Logs `name:committed(json)`, `name:aborted(json)` or `name:E(...)`; [onError] sees the raw error.
  void trackTransaction(
    String name,
    Future<TransactionResult> future, {
    void Function(Object error)? onError,
  }) {
    future.then<void>(
      (TransactionResult r) => log.add(
        '$name:${r.committed ? 'committed' : 'aborted'}(${bare(r.snapshot.value)})',
      ),
      onError: (Object e) {
        log.add('$name:${errorText(e)}');
        onError?.call(e);
      },
    );
  }

  /// A handler that logs `H(json)` and returns [result] of the value.
  TransactionHandler handler(Transaction Function(Object? value) result) =>
      (Object? value) {
        log.add('H(${bare(value)})');
        return result(value);
      };

  /// The entries of [log] whose name is [name].
  List<String> named(String name) =>
      log.where((String e) => e.startsWith('$name:')).toList();
}

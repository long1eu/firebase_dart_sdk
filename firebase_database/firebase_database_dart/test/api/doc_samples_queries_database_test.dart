// The ```dart samples in the doc comments of query.dart, data_snapshot.dart, firebase_database.dart
// and mock_user_token.dart, each copied as it stands into a test body and run against
// FakeDatabaseServer. The test plays the server: it answers listens, gets and writes in the order
// they left. Where a sample prints a result, the test captures the print and checks it. A line
// that differs from the sample says so next to it.

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/testing.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

/// Runs [body] in fake time on a harness that is online; returns what the body printed.
void _sample(
  String name,
  void Function(Harness h, FirebaseDatabase db, List<String> printed) body,
) {
  test(name, () {
    fakeTime((FakeTime time) {
      final Harness h = Harness(time);
      final List<String> printed = <String>[];
      runZoned(
        () => body(h, h.db, printed),
        zoneSpecification: ZoneSpecification(
          print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
              printed.add(line),
        ),
      );
    });
  });
}

/// Starts [sample] and returns a function that says whether it has completed; an error from
/// [sample] fails the test.
bool Function() _start(Future<void> Function() sample) {
  bool done = false;
  sample().then<void>(
    (_) => done = true,
    onError: (Object e, StackTrace s) => fail('the sample failed: $e\n$s'),
  );
  return () => done;
}

/// Reads [path] with a get answered by the server with [value].
DataSnapshot _read(Harness h, String path, Object? value) {
  DataSnapshot? snapshot;
  h.db.ref(path).get().then((DataSnapshot s) => snapshot = s);
  h.settle();
  h.server.answerGet('/$path', value);
  h.settle();
  return snapshot!;
}

void main() {
  // Query (class doc), lib/src/api/query.dart.
  _sample('Query class doc: the top scores', (
    Harness h,
    FirebaseDatabase db,
    List<String> printed,
  ) {
    final Query top = db.ref('scores').orderByValue().limitToLast(10);
    top.onValue.listen((DatabaseEvent e) {
      for (final DataSnapshot s in e.snapshot.children) {
        print('${s.key}: ${s.value}');
      }
    });
    h.settle();
    h.server.answerListen('/scores', <String, Object?>{
      'ann': 7,
      'bob': 3,
      'cy': 5,
    });
    h.settle();
    expect(printed, <String>['bob: 3', 'cy: 5', 'ann: 7']);
  });

  // Query.orderByChild, lib/src/api/query.dart. The sample shows no result: it must build.
  _sample('Query.orderByChild: adults', (
    Harness h,
    FirebaseDatabase db,
    List<String> printed,
  ) {
    final Query adults = db.ref('users').orderByChild('age').startAt(18);
    expect(adults.path, '/users');
  });

  // Query.once, lib/src/api/query.dart.
  _sample('Query.once: config', (
    Harness h,
    FirebaseDatabase db,
    List<String> printed,
  ) {
    final bool Function() done = _start(() async {
      final DatabaseEvent e = await db.ref('config').once();
      print(e.snapshot.value);
    });
    h.settle();
    h.server.answerListen('/config', <String, Object?>{'theme': 'dark'});
    h.settle();
    expect(done(), isTrue);
    expect(printed, <String>['{theme: dark}']);
  });

  // Query.keepSynced, lib/src/api/query.dart.
  _sample('Query.keepSynced: the top scores', (
    Harness h,
    FirebaseDatabase db,
    List<String> printed,
  ) {
    final bool Function() done = _start(() async {
      await db.ref('scores').orderByValue().limitToLast(10).keepSynced(true);
    });
    h.settle();
    expect(done(), isTrue);
    expect(
      h.server.requests.where((String r) => r.startsWith('q /scores')),
      hasLength(1),
    );
  });

  // DataSnapshot (class doc), lib/src/api/data_snapshot.dart.
  _sample('DataSnapshot class doc: read with patterns', (
    Harness h,
    FirebaseDatabase db,
    List<String> printed,
  ) {
    final bool Function() done = _start(() async {
      final DataSnapshot snapshot = await db.ref('users/ada').get();
      if (snapshot.value case {'name': String name, 'age': num age}) {
        print('$name is $age');
      }
    });
    h.settle();
    h.server.answerGet('/users/ada', <String, Object?>{
      'name': 'Ada',
      'age': 36,
    });
    h.settle();
    expect(done(), isTrue);
    expect(printed, <String>['Ada is 36']);
  });

  // DataSnapshot.child, lib/src/api/data_snapshot.dart. `s` is a snapshot read first.
  _sample('DataSnapshot.child: profile/email', (
    Harness h,
    FirebaseDatabase db,
    List<String> printed,
  ) {
    final DataSnapshot s = _read(h, 'users/ada', <String, Object?>{
      'profile': <String, Object?>{'email': 'ada@example.com'},
    });
    if (s.hasChild('profile/email')) {
      print(s.child('profile/email').value);
    }
    expect(printed, <String>['ada@example.com']);
  });

  // DataSnapshot.children, lib/src/api/data_snapshot.dart. `snapshot` is a snapshot read first.
  _sample('DataSnapshot.children: the loop', (
    Harness h,
    FirebaseDatabase db,
    List<String> printed,
  ) {
    final DataSnapshot snapshot = _read(h, 'rooms', <String, Object?>{
      'b': 2,
      'a': 1,
    });
    for (final DataSnapshot child in snapshot.children) {
      print('${child.key}: ${child.value}');
    }
    expect(printed, <String>['a: 1', 'b: 2']);
  });

  // FirebaseDatabase (class doc), lib/src/api/firebase_database.dart. The first line builds the
  // database over the fake server: `FirebaseDatabase(app)` would connect to the network.
  test('FirebaseDatabase class doc: rooms', () {
    fakeTime((FakeTime time) {
      final FirebaseApp app = newTestApp();
      final FakeDatabaseServer server = FakeDatabaseServer();
      final List<String> printed = <String>[];
      late final FirebaseDatabase db;
      final bool Function() done = runZoned(
        () => _start(() async {
          db = databaseWithFakeServer(
            app,
            server,
          ); // The sample: FirebaseDatabase(app).
          db
              .ref('rooms/1/messages')
              .onChildAdded
              .listen((DatabaseEvent e) => print(e.snapshot.value));
          await db.ref('rooms/1/messages').push().set(<String, Object?>{
            'text': 'hello',
          });
          await db.close();
        }),
        zoneSpecification: ZoneSpecification(
          print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
              printed.add(line),
        ),
      );
      time.elapse(Duration.zero);
      server.answerListen('/rooms/1/messages', null);
      time.elapse(Duration.zero);
      expect(printed, <String>['{text: hello}']);
      expect(done(), isFalse, reason: 'the set waits for the server');
      server.ackNextWrite();
      time.elapse(Duration.zero);
      expect(done(), isTrue);
      expect(printed, <String>['{text: hello}']);
    });
  });

  // FirebaseDatabase.emulatorHostFromEnvironment, lib/src/api/firebase_database.dart. No
  // operation runs, so no connection is opened; the URL it gives depends on the environment.
  test('FirebaseDatabase.emulatorHostFromEnvironment: the constructor', () {
    fakeTime((FakeTime time) {
      final FirebaseApp app = newTestApp();
      final FirebaseDatabase db = FirebaseDatabase(
        app,
        emulatorHost: FirebaseDatabase.emulatorHostFromEnvironment,
      );
      expect(
        db.databaseUrl.queryParameters['ns'] ?? db.databaseUrl.host,
        isNotEmpty,
      );
      unawaited(db.close());
      time.elapse(Duration.zero);
    });
  });

  // mockUserTokenFor, lib/src/api/mock_user_token.dart. No operation runs, so no connection is
  // opened.
  test('mockUserTokenFor: the constructor', () {
    fakeTime((FakeTime time) {
      final FirebaseApp app = newTestApp();
      final FirebaseDatabase db = FirebaseDatabase(
        app,
        emulatorHost: '127.0.0.1:9000',
        mockUserToken: mockUserTokenFor('ada', projectId: 'demo-example'),
      );
      expect(
        '${db.databaseUrl}',
        'http://127.0.0.1:9000?ns=test-project-default-rtdb',
      );
      unawaited(db.close());
      time.elapse(Duration.zero);
    });
  });
}

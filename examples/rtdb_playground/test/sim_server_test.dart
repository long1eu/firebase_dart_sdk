// The simulated server of the page, driven as web/main.dart drives it, on the VM. The log lines
// checked here are the ones tool/smoke_gallery.mjs waits for in the browser.
import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/testing.dart';
import 'package:rtdb_playground/sim_server.dart';
import 'package:test/test.dart';

void main() {
  late FirebaseApp app;
  late FirebaseDatabase db;
  late SimServer sim;
  late List<String> log;
  late int rejections;

  setUp(() {
    log = <String>[];
    rejections = 0;
    final FakeDatabaseServer fake = FakeDatabaseServer();
    sim = SimServer(fake, log.add)
      ..data = <String, Object?>{
        'todos': <String, Object?>{
          'a': <String, Object?>{'title': 'Read the docs'},
        },
      }
      ..onReject = () => rejections++;
    app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'demo-key',
        appId: '1:1234567890:web:rtdbplayground',
        projectId: 'demo-rtdb-playground',
      ),
      name: 'sim-${DateTime.now().microsecondsSinceEpoch}',
    );
    db = databaseWithFakeServer(
      app,
      fake,
      reconnectDelay: const Duration(milliseconds: 50),
    );
    sim.start();
  });

  tearDown(() async {
    sim.stop();
    await db.close();
    await app.delete();
  });

  test('a set is applied and logged as "applied set"', () async {
    sim.expectWrite('set', 'todos/b', <String, Object?>{'x': 1});
    await db.ref('todos/b').set(<String, Object?>{'x': 1});

    expect(log, contains('applied set /todos/b'));
    expect((sim.data['todos']! as Map<String, Object?>)['b'], <String, Object?>{
      'x': 1,
    });
  });

  test('a refused set is logged as "refused set", is rolled back and resets '
      'rejectNext', () async {
    final List<Object?> seen = <Object?>[];
    final StreamSubscription<DatabaseEvent> sub = db
        .ref('todos/z')
        .onValue
        .listen((DatabaseEvent e) => seen.add(e.snapshot.value));
    await db.ref('todos/z').get();

    sim.rejectNext = true;
    sim.expectWrite('set', 'todos/z', <String, Object?>{'x': 1});
    await expectLater(
      db.ref('todos/z').set(<String, Object?>{'x': 1}),
      throwsA(
        isA<FirebaseDatabaseException>().having(
          (FirebaseDatabaseException e) => e.code,
          'code',
          'permission-denied',
        ),
      ),
    );
    await pumpEventQueue();
    await sub.cancel();

    expect(log, contains('refused set /todos/z: permission_denied'));
    expect(sim.rejectNext, isFalse);
    expect(rejections, 1);
    expect(seen, <Object?>[
      null,
      <String, Object?>{'x': 1},
      null,
    ]);
    expect(
      (sim.data['todos']! as Map<String, Object?>).containsKey('z'),
      isFalse,
    );
  });

  test('a refused update is logged as "refused update"', () async {
    sim.rejectNext = true;
    sim.expectWrite('update', 'todos/a', <String, Object?>{'done': true});
    await expectLater(
      db.ref('todos/a').update(<String, Object?>{'done': true}),
      throwsA(isA<FirebaseDatabaseException>()),
    );

    expect(log, contains('refused update /todos/a: permission_denied'));
    expect(sim.rejectNext, isFalse);
  });
}

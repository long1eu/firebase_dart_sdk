// The public API through the real connection against the Database emulator: the joint path of the
// two halves (listen, set, transaction, onDisconnect, a query, a mock user token).
//
// FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9100 dart test -t emulator -j 1 test/integration
@TestOn('vm')
@Tags(<String>['emulator'])
library;

import 'dart:async';
import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:test/test.dart';

int _apps = 0;

void main() {
  final String? host = Platform.environment['FIREBASE_DATABASE_EMULATOR_HOST'];
  final String root = 'public-api-${DateTime.now().microsecondsSinceEpoch}';

  FirebaseDatabase open({String? mockUserToken}) {
    final FirebaseDatabase db = FirebaseDatabase(
      FirebaseApp.withOptions(
        const FirebaseOptions(
          apiKey: 'test-key',
          appId: '1:1234567890:dart:test',
          projectId: 'demo-public-api',
        ),
        name: 'public-api-${_apps++}',
      ),
      emulatorHost: host,
      mockUserToken: mockUserToken,
    );
    addTearDown(db.close);
    return db;
  }

  group(
    'public API against the emulator',
    () {
      test('set, get and a listener see the value', () async {
        final FirebaseDatabase db = open();
        final DatabaseReference ref = db.ref('$root/a');
        final List<Object?> seen = <Object?>[];
        final StreamSubscription<DatabaseEvent> sub = ref.onValue.listen(
          (DatabaseEvent e) => seen.add(e.snapshot.value),
        );
        await ref.set(<String, Object?>{'x': 1, 'at': ServerValue.timestamp});
        final DataSnapshot got = await ref.get();
        final Map<String, Object?> value = got.value! as Map<String, Object?>;
        expect(value['x'], 1);
        expect(value['at'], isA<int>());
        await pumpEventQueue();
        expect(seen.last, value);
        await sub.cancel();
      });

      test('a second client receives the write of the first', () async {
        final FirebaseDatabase writer = open();
        final FirebaseDatabase reader = open();
        final Future<DatabaseEvent> event = reader
            .ref('$root/shared')
            .onValue
            .firstWhere((DatabaseEvent e) => e.snapshot.value == 'hello');
        await writer.ref('$root/shared').set('hello');
        expect((await event).snapshot.value, 'hello');
      });

      test('two clients increment one counter with transactions', () async {
        final FirebaseDatabase a = open();
        final FirebaseDatabase b = open();
        Future<void> add(FirebaseDatabase db) async {
          for (int i = 0; i < 10; i++) {
            final TransactionResult result = await db
                .ref('$root/counter')
                .runTransaction(
                  (Object? current) =>
                      Transaction.success(((current as int?) ?? 0) + 1),
                );
            expect(result.committed, isTrue);
          }
        }

        await Future.wait(<Future<void>>[add(a), add(b)]);
        expect((await a.ref('$root/counter').get()).value, 20);
      });

      test(
        'an onDisconnect write is applied when the client goes offline',
        () async {
          final FirebaseDatabase worker = open();
          final FirebaseDatabase watcher = open();
          final DatabaseReference status = worker.ref('$root/status');
          await status.onDisconnect.set('offline');
          await status.set('online');
          final Future<DatabaseEvent> offline = watcher
              .ref('$root/status')
              .onValue
              .firstWhere((DatabaseEvent e) => e.snapshot.value == 'offline');
          worker.goOffline();
          expect((await offline).snapshot.value, 'offline');
        },
      );

      test(
        'a limited ordered query returns the last children in order',
        () async {
          final FirebaseDatabase db = open();
          final DatabaseReference list = db.ref('$root/list');
          await list.set(<String, Object?>{
            'a': <String, Object?>{'n': 3},
            'b': <String, Object?>{'n': 1},
            'c': <String, Object?>{'n': 2},
          });
          // A listen works without an .indexOn rule (the client filters); get() is refused by the server.
          final Query query = list.orderByChild('n').limitToLast(2);
          final DataSnapshot snapshot = (await query.once()).snapshot;
          expect(snapshot.children.map((DataSnapshot c) => c.key), <String>[
            'c',
            'a',
          ]);
        },
      );

      test(
        'get() of an ordered query without .indexOn returns the children in order',
        () async {
          final FirebaseDatabase db = open();
          final DatabaseReference list = db.ref('$root/ordered');
          await list.set(<String, Object?>{
            'a': <String, Object?>{'n': 3},
            'b': <String, Object?>{'n': 1},
            'c': <String, Object?>{'n': 2},
          });
          // Sent as the default get and ordered on the client, as a listen is.
          final DataSnapshot snapshot = await list.orderByChild('n').get();
          expect(snapshot.children.map((DataSnapshot c) => c.key), <String>[
            'b',
            'c',
            'a',
          ]);
          // A limited one is sent as it is and refused.
          await expectLater(
            list.orderByChild('n').limitToLast(2).get(),
            throwsA(
              isA<FirebaseDatabaseException>().having(
                (FirebaseDatabaseException e) => e.code,
                'code',
                'index-not-defined',
              ),
            ),
          );
        },
      );

      test(
        '.info/connected turns true and a mock user token is accepted',
        () async {
          final FirebaseDatabase db = open(
            mockUserToken: mockUserTokenFor(
              'ada',
              projectId: 'demo-public-api',
            ),
          );
          expect(await db.onConnected.firstWhere((bool c) => c), isTrue);
          await db.ref('$root/by-ada').set(true);
          expect((await db.ref('$root/by-ada').get()).value, isTrue);
        },
      );
    },
    skip: host == null ? 'FIREBASE_DATABASE_EMULATOR_HOST is not set' : null,
  );
}

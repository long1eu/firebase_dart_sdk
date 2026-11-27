// The check of recreated_app_invariant.dart, on its own: the client lists
// that the code before "an instance is never replaced" produced (from the
// reviews of that change), the two lists the earlier check let through, a
// correct list, and settings changed through the official API before a
// client is created.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart/testing.dart';
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:firebase_database_dart_platform/src/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'recreated_app_invariant.dart';
import 'recreated_app_pinned_support.dart';

const String _db = databaseUrl;

const ClientShape _emu = (emulatorHost: 'localhost:9000', onDisk: false);
const ClientShape _emu9001 = (emulatorHost: 'localhost:9001', onDisk: false);
const ClientShape _prod = (emulatorHost: null, onDisk: false);
const ClientShape _disk = (emulatorHost: null, onDisk: true);

/// A client of app `a` for [database] whose instance asked for [expected].
RecordedClient _client(
  ClientShape expected,
  ClientShape actual, {
  String database = _db,
}) => (app: 'a', database: database, expected: expected, actual: actual);

void main() {
  registerForTests();
  checkClientsAfterEveryTest();

  group('flags', () {
    test('K1 and K2 (other apiKey, same URL): [emulator, production]', () {
      expect(
        clientProblems(<RecordedClient>[
          _client(_emu, _emu),
          _client(_emu, _prod),
        ]),
        <String>[
          'a|$_db: a client on production, its instance asked for '
              'localhost:9000',
        ],
      );
    });

    test('S1: [emulator, emulator, production, emulator]', () {
      expect(
        clientProblems(<RecordedClient>[
          _client(_emu, _emu),
          _client(_emu, _emu),
          _client(_emu, _prod),
          _client(_emu, _emu),
        ]),
        hasLength(1),
      );
    });

    test('S1p: persistence off, [memory, memory, disk, memory]', () {
      expect(
        clientProblems(<RecordedClient>[
          _client(_prod, _prod),
          _client(_prod, _prod),
          _client(_prod, _disk),
          _client(_prod, _prod),
        ]),
        <String>['a|$_db: a client on disk, its instance asked for memory'],
      );
    });

    test('S10: [emulator, production, emulator]', () {
      expect(
        clientProblems(<RecordedClient>[
          _client(_emu, _emu),
          _client(_emu, _prod),
          _client(_emu, _emu),
        ]),
        hasLength(1),
      );
    });

    test('a production client before the first emulator client', () {
      expect(
        clientProblems(<RecordedClient>[
          _client(_emu, _prod),
          _client(_emu, _emu),
        ]),
        hasLength(1),
      );
    });

    test('a changed emulator host: [9000, 9001]', () {
      expect(
        clientProblems(<RecordedClient>[
          _client(_emu, _emu),
          _client(_emu, _emu9001),
        ]),
        <String>[
          'a|$_db: a client on localhost:9001, its instance asked for '
              'localhost:9000',
        ],
      );
    });

    test('a client for a database not named', () {
      expect(
        clientProblems(<RecordedClient>[
          _client(_prod, _prod, database: 'https://x.firebaseio.com'),
        ]),
        <String>[
          'a|https://x.firebaseio.com: a client for a database not '
              'named',
        ],
      );
    });

    test('a client made with other settings than its instance has, through '
        'the client factory', () async {
      final FirebaseApp app = await newApp();
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(app: app)
        ..useDatabaseEmulator('localhost', 9000);
      await db.goOnline();
      DartFirebaseDatabase.clientFactory(
        FirebaseDatabaseDart.clientFor(app).app,
        DatabaseClientSettings(logger: (_, _) {}),
      );
      final List<String> problems = clientProblems();
      recordedClients.clear();
      expect(problems, <String>[
        '${app.name}|$_db: a client on production, its instance asked for '
            'localhost:9000',
      ]);
    });
  });

  group('passes', () {
    test('a correct list, the settings changed between clients', () {
      expect(
        clientProblems(<RecordedClient>[
          _client(_prod, _prod),
          _client(_emu, _emu),
          _client(_emu9001, _emu9001),
          _client(_disk, _disk),
          _client(_prod, _prod, database: otherUrl),
        ]),
        isEmpty,
      );
    });

    test('the emulator changed before the first use', () async {
      final FirebaseApp app = await newApp();
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(app: app)
        ..useDatabaseEmulator('localhost', 9000)
        ..useDatabaseEmulator('localhost', 9001);
      await db.goOnline();
      expect(hosts(), <String>['null|localhost:9001|memory']);
      expect(clientProblems(), isEmpty);
    });

    test('the emulator set after a delete and before the next use', () async {
      final FirebaseApp first = await Firebase.initializeApp(
        name: 'invariant-delete',
        options: options,
      );
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(app: first);
      await db.goOnline();
      await first.delete();
      await Firebase.initializeApp(name: 'invariant-delete', options: options);
      db.useDatabaseEmulator('localhost', 9001);
      await db.goOnline();
      expect(hosts(), <String>[
        'null|null|memory',
        'null|localhost:9001|memory',
      ]);
      expect(clientProblems(), isEmpty);
    });

    test(
      'persistence turned off before the first use, with a factory',
      () async {
        final DartDatabaseConfig previous = DartFirebaseDatabase.config;
        DartFirebaseDatabase.config = DartDatabaseConfig(
          tokenProviderFor: previous.tokenProviderFor,
          persistenceFor: (int size) => fakePersistence(),
        );
        try {
          final FirebaseDatabase db =
              FirebaseDatabase.instanceFor(app: await newApp())
                ..setPersistenceEnabled(true)
                ..setPersistenceEnabled(false);
          await db.goOnline();
        } finally {
          DartFirebaseDatabase.config = previous;
        }
        expect(hosts(), <String>['null|null|memory']);
        expect(clientProblems(), isEmpty);
      },
    );
  });
}

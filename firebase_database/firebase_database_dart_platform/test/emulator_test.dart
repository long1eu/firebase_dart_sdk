// A smoke run of the official firebase_database API through this package
// against a Realtime Database emulator: write, read, listen, transaction,
// onDisconnect registration.
//
// Needs FIREBASE_DATABASE_EMULATOR_HOST (for example 127.0.0.1:9000, started
// with tool/start_database_emulator.sh 9000 from the repository root);
// skipped without it. The namespace is demo-shim-smoke, which no rules file
// names, so the emulator's open default rules apply.

import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

final String? _emulator =
    Platform.environment['FIREBASE_DATABASE_EMULATOR_HOST'];

void main() {
  late FirebaseDatabase database;
  late DatabaseReference root;

  setUpAll(() async {
    if (_emulator == null) {
      return;
    }
    // flutter_test replaces the HTTP client (and so the WebSocket) with one
    // that answers 400.
    HttpOverrides.global = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FirebaseDatabaseDart.use(useDartCore: true);
    final FirebaseApp app = await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'emulator-api-key',
        appId: '1:1:web:1',
        messagingSenderId: '1',
        projectId: 'demo-shim-smoke',
        databaseURL: 'https://demo-shim-smoke-default-rtdb.firebaseio.com',
      ),
    );
    database = FirebaseDatabase.instanceFor(app: app);
    final List<String> hostAndPort = _emulator!.split(':');
    database.useDatabaseEmulator(hostAndPort[0], int.parse(hostAndPort[1]));
    root = database.ref(
      'tests/shim-smoke/run-${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  final Object? skip = _emulator == null
      ? 'Set FIREBASE_DATABASE_EMULATOR_HOST to run the emulator tests'
      : null;

  group('through firebase_database', skip: skip, () {
    test('set then get returns the value', () async {
      final DatabaseReference ref = root.child('value');
      await ref.set(<String, Object?>{'text': 'hello', 'n': 1});

      final DataSnapshot snapshot = await ref.get();
      expect(snapshot.value, <Object?, Object?>{'text': 'hello', 'n': 1});
    });

    test('onValue delivers the current value, then a change', () async {
      final DatabaseReference ref = root.child('listen');
      await ref.set(1);
      final List<Object?> values = <Object?>[];
      final Completer<void> changed = Completer<void>();
      final StreamSubscription<DatabaseEvent> subscription = ref.onValue.listen(
        (DatabaseEvent event) {
          values.add(event.snapshot.value);
          if (values.length == 2) {
            changed.complete();
          }
        },
      );
      addTearDown(subscription.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await ref.set(2);

      await changed.future.timeout(const Duration(seconds: 10));
      expect(values, <Object?>[1, 2]);
    });

    test('a transaction increments a counter', () async {
      final DatabaseReference ref = root.child('counter');
      await ref.set(41);

      final TransactionResult result = await ref.runTransaction(
        (Object? value) => Transaction.success(((value as int?) ?? 0) + 1),
      );
      expect(result.committed, isTrue);
      expect(result.snapshot.value, 42);
      expect((await ref.get()).value, 42);
    });

    test('a transaction abort leaves the value', () async {
      final DatabaseReference ref = root.child('abort');
      await ref.set('unchanged');

      final TransactionResult result = await ref.runTransaction(
        (Object? value) => Transaction.abort(),
      );
      expect(result.committed, isFalse);
      expect((await ref.get()).value, 'unchanged');
    });

    test('onDisconnect set and cancel are registered by the server', () async {
      final OnDisconnect onDisconnect = root.child('presence').onDisconnect();
      await onDisconnect.set('offline');
      await onDisconnect.cancel();
    });
  });
}

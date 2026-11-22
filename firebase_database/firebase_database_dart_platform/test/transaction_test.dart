// Transactions through the official firebase_database API, against the
// client's fake server: the handler's copy of the value, abort, a throwing
// handler, applyLocally, Transaction.success as a tear-off, a rejected
// write. The client's retry and rerun rules are tested in the client.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// The location every test runs its transaction on, `c`, with an `onValue`
/// listener answered with [value] (the client runs the handler on the value
/// it holds, as in the client's contract rows D34 to D41), and the values
/// that listener received.
Future<(DatabaseReference, List<Object?>)> listenedAt(Object? value) async {
  final FirebaseApp app = await newApp();
  final DatabaseReference ref = FirebaseDatabase.instanceFor(app: app).ref('c');
  final List<Object?> values = <Object?>[];
  final StreamSubscription<DatabaseEvent> subscription = ref.onValue.listen(
    (DatabaseEvent event) => values.add(event.snapshot.value),
  );
  addTearDown(subscription.cancel);
  await settle();
  server.answerListen('c', value);
  await settle();
  return (ref, values);
}

/// Whether the client sent a put of `c`.
bool wroteC() => server.requests.contains('p /c');

void main() {
  registerForTests();

  test('the handler gets a mutable Map<Object?, Object?> copy it may change '
      'and return', () async {
    final (DatabaseReference ref, List<Object?> values) = await listenedAt(
      <String, Object?>{'n': 1},
    );
    Object? seen;
    final Future<TransactionResult> result = ref.runTransaction((
      Object? value,
    ) {
      seen = value;
      final Map<Object?, Object?> map = value! as Map<Object?, Object?>;
      map['n'] = 2;
      return Transaction.success(map);
    });
    await settle();
    server.ackLastWrite();

    final TransactionResult done = await result;
    expect(seen, isA<Map<Object?, Object?>>());
    expect(done.committed, isTrue);
    expect(done.snapshot.value, <Object?, Object?>{'n': 2});
    expect(values.last, <Object?, Object?>{'n': 2});
  });

  test('each run gets a fresh copy of the value it runs on', () async {
    final (DatabaseReference ref, _) = await listenedAt(<String, Object?>{
      'n': 0,
    });
    final List<Map<Object?, Object?>> seen = <Map<Object?, Object?>>[];
    final Future<TransactionResult> result = ref.runTransaction((
      Object? value,
    ) {
      final Map<Object?, Object?> map = value! as Map<Object?, Object?>;
      seen.add(map);
      map['n'] = (map['n']! as int) + 1;
      return Transaction.success(map);
    });
    await settle();
    server.push('c', <String, Object?>{'n': 5});
    server.failLastWrite('datastale');
    await settle();
    server.ackLastWrite();

    final TransactionResult done = await result;
    expect(seen, hasLength(2));
    expect(identical(seen[0], seen[1]), isFalse);
    expect(seen[1], <Object?, Object?>{'n': 6});
    expect(done.snapshot.value, <Object?, Object?>{'n': 6});
  });

  test('aborts on the first run with the seen value and no write', () async {
    final (DatabaseReference ref, List<Object?> values) = await listenedAt(0);
    var runs = 0;
    final TransactionResult done = await ref.runTransaction((Object? value) {
      runs++;
      return Transaction.abort();
    });

    expect(runs, 1);
    expect(done.committed, isFalse);
    expect(done.snapshot.value, 0);
    expect(wroteC(), isFalse);
    expect(values, <Object?>[0]);
  });

  test('a handler that throws fails with the same object', () async {
    final (DatabaseReference ref, List<Object?> values) = await listenedAt(0);
    final StateError error = StateError('handler failed');

    await expectLater(
      ref.runTransaction((Object? value) => throw error),
      throwsA(same(error)),
    );
    expect(wroteC(), isFalse);
    expect(values, <Object?>[0]);
  });

  test('a success value has its map keys stringified', () async {
    final (DatabaseReference ref, _) = await listenedAt(null);
    final Future<TransactionResult> result = ref.runTransaction(
      (Object? value) => Transaction.success(<Object?, Object?>{
        7: <Object?, Object?>{true: 'x'},
      }),
    );
    await settle();
    server.ackLastWrite();

    final TransactionResult done = await result;
    expect(done.snapshot.value, <Object?, Object?>{
      '7': <Object?, Object?>{'true': 'x'},
    });
  });

  // 1.5 stringifies to '1.5', and a key may not contain a dot. The client
  // refuses it with an ArgumentError, which the shim passes on as itself (a
  // programmer error). FlutterFire's Android plugin catches the SDK's
  // exception inside the handler and aborts the transaction
  // (TransactionHandler.kt:75-77).
  test('a success value whose stringified key is invalid fails with the '
      'client ArgumentError and writes nothing', () async {
    final (DatabaseReference ref, List<Object?> values) = await listenedAt(0);

    await expectLater(
      ref.runTransaction(
        (Object? value) => Transaction.success(<Object?, Object?>{1.5: 'x'}),
      ),
      throwsArgumentError,
    );
    expect(wroteC(), isFalse);
    expect(values, <Object?>[0]);
  });

  test('applyLocally false raises no local event before the ack', () async {
    final (DatabaseReference ref, List<Object?> values) = await listenedAt(0);
    final Future<TransactionResult> result = ref.runTransaction(
      (Object? value) => Transaction.success(1),
      applyLocally: false,
    );
    await settle();
    expect(values, <Object?>[0]);
    expect(wroteC(), isTrue);

    server.ackLastWrite();
    final TransactionResult done = await result;
    await settle();
    expect(done.committed, isTrue);
    expect(values, <Object?>[0, 1]);
  });

  test(
    'Transaction.success as the handler writes the value unchanged',
    () async {
      final (DatabaseReference ref, _) = await listenedAt(<String, Object?>{
        'list': <Object?>['first', 'second'],
      });
      final Future<TransactionResult> result = ref.runTransaction(
        Transaction.success,
      );
      await settle();
      server.ackLastWrite();

      final TransactionResult done = await result;
      expect(wroteC(), isTrue);
      expect(done.committed, isTrue);
      expect(done.snapshot.value, <Object?, Object?>{
        'list': <Object?>['first', 'second'],
      });
    },
  );

  test('the result snapshot is of the transaction reference', () async {
    final (DatabaseReference ref, _) = await listenedAt(0);
    final Future<TransactionResult> result = ref.runTransaction(
      (Object? value) => Transaction.success(((value as int?) ?? 0) + 1),
    );
    await settle();
    server.ackLastWrite();

    final TransactionResult done = await result;
    expect(done.snapshot.key, 'c');
    expect(done.snapshot.ref.path, '/c');
    expect(done.snapshot.value, 1);
  });

  test('a rejected write is permission-denied of firebase_core', () async {
    final (DatabaseReference ref, List<Object?> values) = await listenedAt(0);
    final Future<TransactionResult> result = ref.runTransaction(
      (Object? value) => Transaction.success(1),
    );
    await settle();
    server.failLastWrite('permission_denied');

    await expectLater(result, throwsDatabaseCode('permission-denied'));
    await settle();
    expect(values.last, 0);
  });

  test('an invalid key fails the Future with the ArgumentError', () async {
    final FirebaseApp app = await newApp();
    final DatabaseReference ref = FirebaseDatabase.instanceFor(
      app: app,
    ).ref('a.b');

    await expectLater(
      ref.runTransaction((Object? value) => Transaction.success(1)),
      throwsArgumentError,
    );
  });
}

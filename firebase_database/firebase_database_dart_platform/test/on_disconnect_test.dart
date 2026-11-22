// onDisconnect through the official firebase_database API, against the
// client's fake server: what each operation sends, and what the location
// holds once the connection is lost (the client applies the registered
// writes locally then, contract row D42).
//
// The fake server's request names for an onDisconnect merge and cancel
// (`om`, `oc`) are the wire actions; the contract lists only `o`.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// The location `p` of a new app, with an `onValue` listener answered with
/// [value], and the snapshots that listener received.
Future<(DatabaseReference, List<DataSnapshot>)> listenedAt(
  Object? value,
) async {
  final FirebaseApp app = await newApp();
  final DatabaseReference ref = FirebaseDatabase.instanceFor(app: app).ref('p');
  final List<DataSnapshot> snapshots = <DataSnapshot>[];
  final StreamSubscription<DatabaseEvent> subscription = ref.onValue.listen(
    (DatabaseEvent event) => snapshots.add(event.snapshot),
  );
  addTearDown(subscription.cancel);
  await settle();
  server.answerListen('p', value);
  await settle();
  return (ref, snapshots);
}

/// Completes [operation] with the server's ack of the onDisconnect request
/// it sent, which must be [request].
Future<void> acked(Future<void> operation, String request) async {
  await settle();
  expect(server.requests.last, request);
  server.ackLastOnDisconnect();
  await operation;
}

/// Loses the connection and keeps the client offline.
Future<void> disconnect() async {
  server.acceptConnections = false;
  server.dropConnection();
  await settle();
}

void main() {
  registerForTests();

  test('onDisconnect() does not create the client', () async {
    final FirebaseApp app = await newApp();
    FirebaseDatabase.instanceFor(app: app).ref('p').onDisconnect();

    expect(createdClients, isEmpty);
  });

  test('set writes the value, with stringified keys, on disconnect', () async {
    final (DatabaseReference ref, List<DataSnapshot> snapshots) =
        await listenedAt('on');
    await acked(ref.onDisconnect().set(<Object?, Object?>{1.5: 'x'}), 'o /p');
    expect(snapshots.last.value, 'on');

    await disconnect();
    expect(snapshots.last.value, <Object?, Object?>{'1.5': 'x'});
  });

  test(
    'setWithPriority writes the value and the priority on disconnect',
    () async {
      final (DatabaseReference ref, List<DataSnapshot> snapshots) =
          await listenedAt('on');
      await acked(ref.onDisconnect().setWithPriority('off', 2), 'o /p');

      await disconnect();
      expect(snapshots.last.value, 'off');
      expect(snapshots.last.priority, 2);
    },
  );

  test('update writes the children, paths included, on disconnect', () async {
    final (DatabaseReference ref, List<DataSnapshot> snapshots) =
        await listenedAt(<String, Object?>{'keep': true, 'a': 0});
    await acked(
      ref.onDisconnect().update(<String, Object?>{'a': 1, 'b/c': 2}),
      'om /p',
    );

    await disconnect();
    expect(snapshots.last.value, <Object?, Object?>{
      'keep': true,
      'a': 1,
      'b': <Object?, Object?>{'c': 2},
    });
  });

  test('cancel drops what was registered', () async {
    final (DatabaseReference ref, List<DataSnapshot> snapshots) =
        await listenedAt('on');
    final OnDisconnect onDisconnect = ref.onDisconnect();
    await acked(onDisconnect.set('off'), 'o /p');
    await acked(onDisconnect.cancel(), 'oc /p');

    await disconnect();
    expect(snapshots.last.value, 'on');
  });

  test('remove is set(null): the location is gone on disconnect', () async {
    final (DatabaseReference ref, List<DataSnapshot> snapshots) =
        await listenedAt('on');
    await acked(ref.onDisconnect().remove(), 'o /p');

    await disconnect();
    expect(snapshots.last.exists, isFalse);
  });

  test('an invalid key fails the Future with the ArgumentError', () async {
    final FirebaseApp app = await newApp();
    final OnDisconnect onDisconnect = FirebaseDatabase.instanceFor(
      app: app,
    ).ref('a.b').onDisconnect();

    await expectLater(onDisconnect.set(1), throwsArgumentError);
  });
}

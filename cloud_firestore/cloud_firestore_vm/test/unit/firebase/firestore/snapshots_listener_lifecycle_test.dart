import 'dart:async';

import 'package:cloud_firestore_vm/cloud_firestore_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query_stream.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/timer_task.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

/// Counts the listeners that are registered with and removed from the client.
class _FakeClient extends Mock implements FirestoreClient {
  int registered = 0;
  int removed = 0;
  final List<QueryStream> streams = <QueryStream>[];
  Completer<void>? gate;

  @override
  Future<QueryStream> listen(core.Query query, ListenOptions options) async {
    await gate?.future;
    registered++;
    final QueryStream stream = QueryStream(query, options, stopListening);
    streams.add(stream);
    return stream;
  }

  @override
  Future<void> stopListening(QueryStream listener) async {
    removed++;
  }
}

void main() {
  late _FakeClient client;
  late Firestore firestore;

  setUp(() {
    client = _FakeClient();
    firestore = Firestore(
        DatabaseId.forProject('p'), null, client, TaskScheduler('test'));
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test('creating the stream registers nothing until it is listened to',
      () async {
    firestore.collection('a').snapshots; // ignore: unnecessary_statements
    firestore.doc('a/b').snapshots; // ignore: unnecessary_statements
    firestore.collection('a').getSnapshots(MetadataChanges.include);
    await settle();
    expect(client.registered, 0);
  });

  test('cancelling removes the listener', () async {
    final StreamSubscription<QuerySnapshot> sub =
        firestore.collection('a').snapshots.listen((_) {});
    await settle();
    expect(client.registered, 1);
    await sub.cancel();
    expect(client.removed, 1);
  });

  test('cancelling a document stream removes the listener', () async {
    final StreamSubscription<DocumentSnapshot> sub =
        firestore.doc('a/b').snapshots.listen((_) {});
    await settle();
    await sub.cancel();
    expect(client.registered, 1);
    expect(client.removed, 1);
  });

  test('cancelling before the registration completed still removes it',
      () async {
    client.gate = Completer<void>();
    final StreamSubscription<QuerySnapshot> sub =
        firestore.collection('a').snapshots.listen((_) {});
    await sub.cancel();
    expect(client.registered, 0);

    client.gate!.complete();
    await settle();
    expect(client.registered, 1);
    expect(client.removed, 1, reason: 'the late registration must be undone');
  });

  test('errors of the listener reach the stream', () async {
    final Completer<Object> error = Completer<Object>();
    final StreamSubscription<QuerySnapshot> sub = firestore
        .collection('a')
        .snapshots
        .listen((_) {}, onError: error.complete);
    await settle();
    client.streams.single
        .onError(FirestoreError('boom', FirestoreErrorCode.unavailable));
    expect(await error.future, isA<FirestoreError>());
    await sub.cancel();
  });
}

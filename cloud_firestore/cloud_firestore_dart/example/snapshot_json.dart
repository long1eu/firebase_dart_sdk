// Snapshots as JSON: serialize a snapshot in one process (for example while
// rendering on a server), rebuild it in another one, and resume listening from
// it so that the backend only sends what changed since.
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/snapshot_json.dart

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'common.dart';

Future<void> main() async {
  // Two instances stand in for the two processes.
  final Firestore server = await connect('server');
  final Firestore client = await connect('client');

  final CollectionReference<Map<String, Object?>> scores = server.collection(
    scratch('scores'),
  );
  await scores.doc('ada').set(<String, Object?>{'points': 10});
  await scores.doc('alan').set(<String, Object?>{'points': 7});

  // "Server": query, and send the snapshot as a JSON string.
  final Query<Map<String, Object?>> query = scores.orderBy(
    'points',
    Direction.descending,
  );
  final String wire = jsonEncode((await query.get()).toJson());
  print('JSON: ${wire.length} characters');

  // "Client": rebuild the snapshot without a request to the backend.
  final Map<String, Object?> json = jsonDecode(wire) as Map<String, Object?>;
  final QuerySnapshot<Map<String, Object?>> restored =
      QuerySnapshot<Map<String, Object?>>.fromJson(client, json);
  print('restored: ${<String>[for (final doc in restored.docs) doc.id]}');

  // ...and keep it up to date: the stream starts from the documents in the
  // JSON and then follows the query on the backend.
  final Completer<void> sawUpdate = Completer<void>();
  final StreamSubscription<QuerySnapshot<Map<String, Object?>>> subscription =
      client.querySnapshotsFromJson<Map<String, Object?>>(json).listen((
        QuerySnapshot<Map<String, Object?>> snapshot,
      ) {
        final String first = snapshot.docs.first.id;
        print(
          'listener: first is $first (from cache: '
          '${snapshot.metadata.isFromCache})',
        );
        if (first == 'alan' && !sawUpdate.isCompleted) {
          sawUpdate.complete();
        }
      });

  await scores.doc('alan').update(<String, Object?>{'points': 12});
  await sawUpdate.future;
  await subscription.cancel();

  // Single documents and references work the same way.
  final DocumentSnapshot<Map<String, Object?>> ada = await scores
      .doc('ada')
      .get();
  final DocumentSnapshot<Map<String, Object?>> adaOnClient =
      DocumentSnapshot<Map<String, Object?>>.fromJson(
        client,
        jsonDecode(jsonEncode(ada.toJson())) as Map<String, Object?>,
      );
  print('document: ${adaOnClient.id} ${adaOnClient.data}');
  final DocumentReference<Map<String, Object?>> reference =
      DocumentReference<Map<String, Object?>>.fromJson(
        client,
        scores.doc('ada').toJson(),
      );
  print('reference: ${reference.path == ada.ref.path}');

  await server.terminate();
  await client.terminate();
}

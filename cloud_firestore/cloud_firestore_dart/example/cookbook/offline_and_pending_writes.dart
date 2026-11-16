// Recipe: show the user that the app is offline and which changes have not
// reached the server yet, update the screen at once (optimistic UI), and wait
// for the pending writes before the program exits.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/offline_and_pending_writes.dart

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

Future<void> main() async {
  final FirebaseFirestore firestore = connect();
  final CollectionReference<Map<String, Object?>> todos = firestore.collection(
    scratch('todos'),
  );
  await todos.doc('milk').set(<String, Object?>{'title': 'Buy milk'});

  // Ask for metadata changes too: going offline or a write being confirmed
  // changes only the metadata, not the documents.
  final StreamController<String> screen = StreamController<String>();
  final StreamSubscription<QuerySnapshot<Map<String, Object?>>>
  subscription = todos.getSnapshots(MetadataChanges.include).listen((
    QuerySnapshot<Map<String, Object?>> snapshot,
  ) {
    final String status = snapshot.metadata.isFromCache
        ? 'offline or not synced yet'
        : 'up to date';
    final List<String> rows = <String>[
      for (final QueryDocumentSnapshot<Map<String, Object?>> doc in snapshot)
        // A document with a local change the server has not confirmed.
        '${doc['title']}${doc.metadata.hasPendingWrites ? ' (saving)' : ''}',
    ];
    screen.add('[$status] $rows');
  });
  final StreamIterator<String> frames = StreamIterator<String>(screen.stream);
  Future<void> waitFor(String text) async {
    while (await frames.moveNext()) {
      print(frames.current);
      if (frames.current.contains(text)) {
        return;
      }
    }
  }

  await waitFor('[up to date]');

  // Offline: the listener reports snapshots from the cache.
  await firestore.disableNetwork();
  await waitFor('[offline');

  // Do not await a write while offline: its future completes only when the
  // server confirms it. The listener shows the change at once.
  final Future<void> saved = todos.doc('eggs').set(<String, Object?>{
    'title': 'Buy eggs',
  });
  await waitFor('(saving)');

  // Back online: the write is sent and the "saving" mark goes away.
  await firestore.enableNetwork();
  await saved;
  await waitFor('[up to date] [Buy eggs, Buy milk]');

  // Before a command-line program exits, make sure every write is on the
  // server. waitForPendingWrites waits for the writes made so far.
  unawaited(todos.doc('tea').set(<String, Object?>{'title': 'Buy tea'}));
  await firestore.waitForPendingWrites();
  print('all writes confirmed');

  await subscription.cancel();
  await frames.cancel();
  await firestore.terminate();
}

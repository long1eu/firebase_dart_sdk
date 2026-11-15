// Recipe: stamp a document with the server's time, and read the field before
// the server has answered. Until then the local snapshot has no value for it;
// `ServerTimestampBehavior` chooses what you see instead.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/server_timestamps.dart

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

Future<void> main() async {
  final Firestore firestore = connect();
  final DocumentReference<Map<String, Object?>> note = firestore
      .collection(scratch('notes'))
      .doc('n1');
  await note.set(<String, Object?>{
    'text': 'first',
    'updatedAt': FieldValue.serverTimestamp(),
  });

  final Completer<void> confirmed = Completer<void>();
  final StreamSubscription<DocumentSnapshot<Map<String, Object?>>>
  subscription = note.getSnapshots(MetadataChanges.include).listen((
    DocumentSnapshot<Map<String, Object?>> snapshot,
  ) {
    if (snapshot['text'] != 'second') {
      return; // The state before the change below.
    }
    if (snapshot.metadata.hasPendingWrites) {
      // The local write, before the server has answered.
      print('pending, none:     ${snapshot['updatedAt']}');
      print(
        'pending, estimate: ${snapshot.get('updatedAt', ServerTimestampBehavior.estimate) is Timestamp}',
      );
      final Object? previous = snapshot.get(
        'updatedAt',
        ServerTimestampBehavior.previous,
      );
      print('pending, previous: ${previous is Timestamp}');
    } else {
      print('confirmed:         ${snapshot['updatedAt'] is Timestamp}');
      if (!confirmed.isCompleted) {
        confirmed.complete();
      }
    }
  });

  await note.update(<String, Object?>{
    'text': 'second',
    'updatedAt': FieldValue.serverTimestamp(),
  });
  await confirmed.future;
  await subscription.cancel();

  await firestore.terminate();
}

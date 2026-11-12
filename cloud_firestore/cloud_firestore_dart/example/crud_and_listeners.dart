// Create, read, update and delete documents, and listen to changes.
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/crud_and_listeners.dart

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'common.dart';

Future<void> main() async {
  final Firestore firestore = await connect();
  final CollectionReference<Map<String, Object?>> cities =
      firestore.collection(scratch('cities'));

  // A listener gets the current result first and then every change. Local
  // writes are delivered immediately with `hasPendingWrites: true`.
  final StreamSubscription<QuerySnapshot<Map<String, Object?>>> subscription =
      cities.snapshots.listen((QuerySnapshot<Map<String, Object?>> snapshot) {
    for (final DocumentChange<Map<String, Object?>> change
        in snapshot.docChanges) {
      print('listener: ${change.type.name} ${change.document.id}');
    }
  });

  // Create: `set` with an id of your choice, or `add` for a generated id.
  final DocumentReference<Map<String, Object?>> rome = cities.doc('rome');
  await rome.set(<String, Object?>{
    'name': 'Rome',
    'population': 2800000,
    'tags': <String>['capital'],
    'updatedAt': FieldValue.serverTimestamp(),
  });
  final DocumentReference<Map<String, Object?>> generated =
      await cities.add(<String, Object?>{'name': 'Paris'});
  print('generated id has ${generated.id.length} characters');

  // Read.
  final DocumentSnapshot<Map<String, Object?>> snapshot = await rome.get();
  print('exists: ${snapshot.exists}, name: ${snapshot.getString('name')}, '
      'population: ${snapshot['population']}');

  // Update: only the given fields change. Field transforms run on the server.
  await rome.update(<String, Object?>{
    'population': FieldValue.increment(1),
    'tags': FieldValue.arrayUnion(<Object?>['unesco']),
  });

  // `set` with merge creates the document or merges into the existing one.
  await rome.set(
    <String, Object?>{
      'geo': const GeoPoint(41.9, 12.5),
    },
    SetOptions.mergeAllFields,
  );
  print('after update: ${(await rome.get()).data?['tags']}');

  // Listen to one document, including metadata-only changes.
  final Completer<void> sawServerData = Completer<void>();
  final StreamSubscription<DocumentSnapshot<Map<String, Object?>>>
      documentSubscription = rome
          .getSnapshots(MetadataChanges.include)
          .listen((DocumentSnapshot<Map<String, Object?>> doc) {
    if (!doc.metadata.hasPendingWrites &&
        !doc.metadata.isFromCache &&
        !sawServerData.isCompleted) {
      sawServerData.complete();
    }
  });
  await sawServerData.future;
  await documentSubscription.cancel();

  // Delete a field, then the documents.
  await rome.update(<String, Object?>{'geo': FieldValue.delete()});
  await rome.delete();
  await generated.delete();
  print('exists after delete: ${(await rome.get()).exists}');

  await subscription.cancel();
  await firestore.terminate();
}

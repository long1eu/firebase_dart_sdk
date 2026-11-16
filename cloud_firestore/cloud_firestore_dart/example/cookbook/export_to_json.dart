// Recipe: save the result of a query to a JSON file and load it again later,
// without asking the backend, with `QuerySnapshot.toJson` and `fromJson`.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/export_to_json.dart

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

Future<void> main() async {
  final FirebaseFirestore firestore = connect();
  final CollectionReference<Map<String, Object?>> events = firestore.collection(
    scratch('events'),
  );
  await events.doc('launch').set(<String, Object?>{
    'title': 'Launch',
    'at': Timestamp.fromDate(DateTime.utc(2026, 11, 15, 9)),
    'where': const GeoPoint(51.5, -0.12),
  });
  await events.doc('review').set(<String, Object?>{
    'title': 'Review',
    'at': Timestamp.fromDate(DateTime.utc(2026, 11, 20, 14)),
  });

  // Export: the JSON keeps the Firestore types (timestamps, geo points,
  // references) and the query, so it can be loaded back exactly.
  final QuerySnapshot<Map<String, Object?>> snapshot = await events
      .orderBy('at')
      .get();
  final Directory dir = await Directory.systemTemp.createTemp('export');
  final File file = File('${dir.path}/events.json');
  await file.writeAsString(jsonEncode(snapshot.toJson()));
  print('wrote ${snapshot.length} documents, ${await file.length()} bytes');

  // Import: no request to the backend.
  final Map<String, Object?> json =
      jsonDecode(await file.readAsString()) as Map<String, Object?>;
  final QuerySnapshot<Map<String, Object?>> restored =
      QuerySnapshot<Map<String, Object?>>.fromJson(firestore, json);
  for (final QueryDocumentSnapshot<Map<String, Object?>> doc in restored) {
    print(
      '${doc.id}: ${doc['title']} at ${(doc.get('at') as Timestamp?)!.toDate().toUtc()}',
    );
  }
  print('geo point kept: ${restored.docs.first['where'] is GeoPoint}');

  await dir.delete(recursive: true);
  await firestore.terminate();
}

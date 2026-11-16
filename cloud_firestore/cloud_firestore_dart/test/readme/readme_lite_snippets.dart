// GENERATED from the README files by
// test/unit/api/readme_snippets_test.dart. Do not edit: change the README
// and regenerate (see that file).
//
// This file is only analyzed, never run.

// ignore_for_file: type=lint, unused_local_variable, unused_import
// ignore_for_file: unused_element

import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore_dart/lite.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

late FirebaseApp app;
late Firestore firestore;

// ../../docs/guides/lite.md:33
Future<void> liteGuideLine33() async {
  // Synchronous, and nothing is sent until the first call.
  final Firestore firestore = Firestore.instanceFor(app: app);

  final CollectionReference<Map<String, Object?>> cities = firestore.collection('cities');
  await cities.doc('LA').set({'name': 'Los Angeles', 'state': 'CA', 'population': 3900000});

  final QuerySnapshot<Map<String, Object?>> californian =
      await cities.where('state', isEqualTo: 'CA').get();
  print(californian.docs.map((QueryDocumentSnapshot<Map<String, Object?>> doc) => doc.id).toList());

  final WriteBatch batch = firestore.batch()
    ..update(cities.doc('LA'), {'population': FieldValue.increment(1000)})
    ..delete(cities.doc('old'));
  await batch.commit();

  final AggregateQuerySnapshot count = await cities.count().get();
  print(count.getCount());

  await firestore.terminate();
}

// ../../docs/guides/server.md:340
Future<void> serverGuideLine340() async {
  final HttpServer server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
  await for (final HttpRequest request in server) {
    final String id = request.uri.pathSegments.isEmpty ? '' : request.uri.pathSegments.last;
    try {
      final DocumentSnapshot<Map<String, Object?>> task =
          await firestore.collection('tasks').doc(id.isEmpty ? 'none' : id).get();
      request.response
        ..statusCode = task.exists ? HttpStatus.ok : HttpStatus.notFound
        ..write(jsonEncode(task.data ?? <String, Object?>{}));
    } on FirestoreError catch (error) {
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..write('${error.code}');
    }
    await request.response.close();
  }
}

// ../../docs/guides/web.md:254
Future<void> webGuideLine254() async {
  final Firestore firestore = Firestore.instanceFor(app: app);
  final QuerySnapshot<Map<String, Object?>> notes =
      await firestore.collection('notes').limit(20).get();
}

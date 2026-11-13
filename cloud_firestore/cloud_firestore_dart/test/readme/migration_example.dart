// Before/after of every rename and breaking change from cloud_firestore_vm
// 0.0.7 and firebase_core_vm 0.0.4 to cloud_firestore_dart and
// firebase_app_dart 0.1.0, in the order of docs/migrating_from_vm_packages.md.
//
// Each "Before" comment is the 0.0.7 code (it cannot be compiled any more: the
// old packages do not resolve on Dart 3); the code under it is the "after",
// which `dart analyze test/readme` compiles against the current API (see
// test/unit/api/readme_snippets_test.dart, which also checks that every
// numbered section of the guide has a `// Section N` marker here).
//
// This file is only analyzed, never run.

// ignore_for_file: unused_local_variable, avoid_print, unused_element

// Section 1. Packages and imports.
// Before:
//   import 'package:cloud_firestore_vm/cloud_firestore_vm.dart';
//   import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

// Section 2. Dart 3.8 and null safety.
Future<void> nullSafety(Firestore firestore) async {
  // Before:
  //   final DocumentSnapshot snapshot =
  //       await firestore.collection('users').document('ada').get();
  //   final int age = snapshot.data['age'];
  final DocumentSnapshot<Map<String, Object?>> snapshot = await firestore
      .collection('users')
      .doc('ada')
      .get();
  final Map<String, Object?>? data = snapshot.data; // null: no document
  final int? age = data?['age'] as int?;

  // Before: every option was a non-nullable String.
  const FirebaseOptions options = FirebaseOptions(
    apiKey: 'key', // required
    applicationId: '1:1:dart:1', // required
    projectId: 'my-project',
  );
  final String? projectId = options.projectId; // nullable
  final String? storageBucket = options.storageBucket; // nullable
}

// Section 3. Creating the app.
void creatingTheApp(FirebaseApp app) {
  // Before: app.setDataCollectionDefaultEnabled(); // meant "disable"
  app.setDataCollectionDefaultEnabled(enabled: false);

  // URL-safe base64 without padding now; keys of 0.0.4 differ.
  final String key = app.persistenceKey;
}

// Section 4. Creating the Firestore instance.
void creatingTheInstance(FirebaseApp app) {
  // Before:
  //   final Firestore firestore = await Firestore.getInstance(app,
  //       settings: FirestoreSettings(persistenceEnabled: true));
  final Firestore firestore = Firestore.instanceFor(
    app: app, // returns at once, no Future
    settings: FirestoreSettings(cacheSettings: PersistentCacheSettings()),
  );

  // Before: FirestoreSettings(host: '127.0.0.1:8080', sslEnabled: false)
  final Firestore emulated = Firestore.instanceFor(
    app: app,
    database: 'other',
    settings: FirestoreSettings().withEmulator('127.0.0.1', 8080),
  );
}

// Section 5. The SQLite opener.
// Before:
//   class MyDatabase extends Database {
//     @override
//     File get file => _file;
//     @override
//     Future<void> execute(String statement, [List<dynamic> arguments]);
//   }
class _MyDatabase implements Database {
  _MyDatabase(this.path);

  @override
  final String path; // replaces `File get file`

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) async {}

  @override
  Future<List<Map<String, dynamic>>> query(
    String statement, [
    List<Object?>? arguments,
  ]) async => <Map<String, dynamic>>[];

  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) async => 0;

  @override
  void close() {}
}

// Section 6. Renamed members (the old names are deprecated and still work).
Future<void> renamedMembers(Firestore firestore) async {
  // Before:
  //   final QuerySnapshot result = await firestore
  //       .collection('users')
  //       .whereEqualTo(FieldPath.documentId(), 'ada')
  //       .get(Source.defaultSource);
  //   for (final DocumentSnapshot doc in result.documents) print(doc.reference.path);
  //   result.documentChanges;
  //   firestore.document('users/ada');
  //   await firestore.shutdown();
  final QuerySnapshot<Map<String, Object?>> result = await firestore
      .collection('users')
      .where(FieldPath.documentIdField, isEqualTo: 'ada')
      .get(Source.serverAndCache);
  for (final QueryDocumentSnapshot<Map<String, Object?>> doc in result.docs) {
    print(doc.ref.path);
  }
  final List<DocumentChange<Map<String, Object?>>> changes = result.docChanges;
  final DocumentReference<Map<String, Object?>> ada = firestore.doc(
    'users/ada',
  );
  await firestore.terminate();
}

// Section 7. Generic references and snapshots.
Future<void> generics(Firestore firestore) async {
  // Before:
  //   final DocumentReference ref = firestore.collection('users').document('ada');
  //   final DocumentSnapshot snapshot = await ref.get();
  final DocumentReference<Map<String, Object?>> ref = firestore
      .collection('users')
      .doc('ada');
  final DocumentSnapshot<Map<String, Object?>> snapshot = await ref.get();

  // New: a typed view of the same document.
  final DocumentReference<String> names = ref.withConverter<String>(
    FirestoreDataConverter<String>.from(
      fromFirestore: (DocumentSnapshot<Map<String, Object?>> s, _) =>
          s.data!['name']! as String,
      toFirestore: (String name, _) => <String, Object?>{'name': name},
    ),
  );
}

// Section 8. Members that are no longer public.
void noLongerPublic(Firestore firestore) {
  // Before: firestore.databaseId.projectId, firestore.databaseId.databaseId
  final String projectId = firestore.projectId;
  final String database = firestore.databaseId; // a String now

  // Before: FieldPath(['a', 'b']), FieldPath.documentIdInstance
  final FieldPath path = FieldPath.of(<String>['a', 'b']);
  final FieldPath id = FieldPath.documentIdField;

  // Before: FirestoreErrorCode.fromValue(grpcError); now read FirestoreError.code.
  // Before: Firestore.newInstance(...), firestore.client, query.query,
  //   snapshot.document, reference.key, fieldValue.isDelete, SetOptions.fieldMask,
  //   Timestamp.validateRange, ConflictAlgorithm: no replacement.
}

// Section 9. Behaviour changes without a compile error.
Future<void> behaviour(Firestore firestore) async {
  final DocumentReference<Map<String, Object?>> configRef = firestore.doc(
    'config/plans',
  );
  final DocumentReference<Map<String, Object?>> userRef = firestore.doc(
    'users/ada',
  );

  // Before: a document read in a transaction had to be written back.
  //   tx.set(configRef, config.data); // only to satisfy the rule
  // Default attempts went from 6 to 5; pass maxAttempts to keep 6.
  await firestore.runTransaction<void>((Transaction tx) async {
    final DocumentSnapshot<Map<String, Object?>> config = await tx.get(
      configRef,
    );
    tx.update(userRef, <String, Object?>{'plan': config.data!['plan']});
  }, options: TransactionOptions(maxAttempts: 6));

  // A read after a write fails (invalidArgument) and now also fails the
  // commit when the error is caught; do all reads first.
  await firestore.runTransaction<void>((Transaction tx) async {
    final DocumentSnapshot<Map<String, Object?>> user = await tx.get(userRef);
    tx.set(configRef, <String, Object?>{'seen': true});
  });

  // Before: an ArgumentError "The client has already been shutdown".
  await firestore.terminate();
  try {
    await userRef.get();
  } on FirestoreError catch (e) {
    print(e.code == FirestoreErrorCode.failedPrecondition);
  }

  // Microseconds are kept (0.0.7 truncated to milliseconds).
  final DateTime date = Timestamp.fromDate(DateTime.now()).toDate();

  // A copy: changing it no longer changes the blob.
  final Uint8List bytes = Blob(Uint8List.fromList(<int>[1, 2])).bytes;

  // Checked in every build mode (they were asserts): these throw ArgumentError.
  //   firestore.collection('users/ada');  // even number of segments
  //   firestore.doc('');
  //   firestore.collectionGroup('');
  //   FirestoreSettings(host: 'a.example@b.example');
  //   FirestoreSettings(sslEnabled: false); // with the production host
}

// firebase_app_dart: the token is no longer in toString().
String tokenResult(GetTokenResult result) => '$result'; // prints <redacted>

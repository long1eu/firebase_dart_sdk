// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_vm/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/source.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';

// Port of the upstream LargeDocumentTest (documents of ~15.9 MB, the 16 MiB limit of the current backend).
//
// The Firestore emulator does not accept documents that large: its write rejects them (see EMULATOR_LIMIT below), so
// the whole suite is skipped when it runs against the emulator and meant to run against a production database.
void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/large_document';

  // Set RUN_LARGE_DOCUMENT_TESTS=1 to run against the emulator anyway (they fail there).
  final String? emulatorLimit = IntegrationTestUtil.emulatorHost == null ||
          Platform.environment['RUN_LARGE_DOCUMENT_TESTS'] == '1'
      ? null
      : 'EMULATOR_LIMIT: the Firestore emulator rejects documents larger than 1 MiB (INVALID_ARGUMENT), so the '
          '15.9 MB documents of the upstream test can not be written; run against a production database.';

  const Timeout largeTimeout = Timeout(Duration(minutes: 3));
  final int targetBytes = (15.9 * 1024 * 1024).floor();

  String generateUnicodeString(int targetUtf8Bytes) {
    final StringBuffer sb = StringBuffer();
    int bytes = 0;
    while (bytes < targetUtf8Bytes) {
      if (bytes % 2 == 0 && bytes + 4 <= targetUtf8Bytes) {
        sb.write('\u{1F680}'); // 4 bytes in UTF-8
        bytes += 4;
      } else {
        sb.write('a');
        bytes += 1;
      }
    }
    return sb.toString();
  }

  String generateAsciiString(int sizeInBytes) => 'a' * sizeInBytes;

  late String seedCollection;
  late String unicodePayload;
  late String asciiPayload;
  late Firestore db;

  setUpAll(() async {
    if (emulatorLimit != null) {
      return;
    }
    db = await IntegrationTestUtil.testFirestore();
    seedCollection = 'large_doc_tests_${DateTime.now().millisecondsSinceEpoch}';
    unicodePayload = generateUnicodeString(targetBytes);
    asciiPayload = generateAsciiString(targetBytes);

    final CollectionReference col = db.collection(seedCollection);
    await col.document('doc_15_9MB_unicode').set(<String, Object?>{
      'chunk': unicodePayload,
      'tag': 'unicode_large_doc',
    });
    final Map<String, Object?> dataAscii = <String, Object?>{
      'chunk': asciiPayload,
      'tag': 'ascii_large_doc',
    };
    await col.document('doc_a').set(dataAscii);
    await col.document('doc_b').set(dataAscii);
  });

  tearDownAll(() async {
    if (emulatorLimit != null) {
      return;
    }
    final CollectionReference col = db.collection(seedCollection);
    for (final String id in <String>['doc_15_9MB_unicode', 'doc_a', 'doc_b']) {
      try {
        await col.document(id).delete();
      } catch (_) {
        // Suppress cleanup exceptions.
      }
    }
    await IntegrationTestUtil.tearDown();
  });

  test('testReadAndCacheLargeUnicodeDocument', () async {
    final DocumentReference docRef =
        db.collection(seedCollection).document('doc_15_9MB_unicode');

    final DocumentSnapshot serverSnapshot = await docRef.get(Source.server);
    expect(serverSnapshot.exists, isTrue);

    await db.disableNetwork();
    final DocumentSnapshot cacheSnapshot = await docRef.get(Source.cache);
    expect(cacheSnapshot.exists, isTrue);
    expect(cacheSnapshot.data, serverSnapshot.data);
    await db.enableNetwork();
  }, skip: emulatorLimit, timeout: largeTimeout);

  test('testCacheIntegrityWithMultipleLargeDocuments', () async {
    final CollectionReference colRef = db.collection(seedCollection);
    final DocumentReference docA = colRef.document('doc_a');
    final DocumentReference docB = colRef.document('doc_b');

    await docA.get(Source.server);
    await docB.get(Source.server);

    await db.disableNetwork();
    final DocumentSnapshot cacheA = await docA.get(Source.cache);
    final DocumentSnapshot cacheB = await docB.get(Source.cache);

    expect(cacheA.exists, isTrue, reason: 'docA should exist in cache');
    expect(cacheB.exists, isTrue, reason: 'docB should exist in cache');
    expect(cacheA.getString('chunk'), asciiPayload);
    expect(cacheB.getString('chunk'), asciiPayload);
    await db.enableNetwork();
  }, skip: emulatorLimit, timeout: largeTimeout);

  test('testWatchStreamInitializationAndDiff', () async {
    final DocumentReference docRef =
        db.collection(seedCollection).document('doc_15_9MB_unicode');
    final String expectedValue =
        'updated_val_${DateTime.now().millisecondsSinceEpoch}';

    // The initial snapshot of a large document must arrive without stream cancellation loops, and the update must be
    // delivered.
    final Completer<void> updated = Completer<void>();
    final StreamSubscription<DocumentSnapshot> registration =
        docRef.snapshots.listen((DocumentSnapshot snapshot) {
      if (snapshot.exists &&
          snapshot.getString('differential_field') == expectedValue &&
          !updated.isCompleted) {
        updated.complete();
      }
    });

    try {
      final DocumentSnapshot first = await docRef.get(Source.server);
      expect(first.exists, isTrue);

      await docRef
          .update(<String, Object?>{'differential_field': expectedValue});
      await updated.future.timeout(const Duration(seconds: 60));
    } finally {
      await registration.cancel();
    }
  }, skip: emulatorLimit, timeout: largeTimeout);

  test('testOversizedPayloadRejection', () async {
    final DocumentReference docRef =
        db.collection(seedCollection).document('temp_oversized_doc');
    // 16.1 MB payload.
    final int oversizedPayloadBytes = 16 * 1024 * 1024 + 102400;

    await expectLater(
        docRef.set(<String, Object?>{
          'largeField': generateAsciiString(oversizedPayloadBytes)
        }),
        throwsA(isA<FirestoreError>().having((FirestoreError e) => e.code,
            'code', FirestoreErrorCode.invalidArgument)));
  }, skip: emulatorLimit, timeout: largeTimeout);

  test('testWriteValidLargeDocument', () async {
    final DocumentReference docRef = db.collection(seedCollection).document(
        'temp_valid_large_doc_${DateTime.now().millisecondsSinceEpoch}');
    try {
      final String largePayload = generateAsciiString(targetBytes);
      await docRef.set(<String, Object?>{'chunk': largePayload});

      final DocumentSnapshot snapshot = await docRef.get(Source.server);
      expect(snapshot.exists, isTrue);
      expect(snapshot.getString('chunk'), largePayload);
    } finally {
      try {
        await docRef.delete();
      } catch (_) {
        // Suppress cleanup exceptions.
      }
    }
  }, skip: emulatorLimit, timeout: largeTimeout);

  test('testTransactionReadModifyWrite', () async {
    final DocumentReference docRef =
        db.collection(seedCollection).document('doc_15_9MB_unicode');
    final int timestamp = DateTime.now().millisecondsSinceEpoch;

    await db.runTransaction<void>((transaction) async {
      final DocumentSnapshot snapshot = await transaction.get(docRef);
      expect(snapshot.exists, isTrue);
      transaction.update(
          docRef, <String, Object?>{'transaction_timestamp': timestamp});
    });

    final DocumentSnapshot updated = await docRef.get(Source.server);
    expect(updated.exists, isTrue);
    expect(updated.getInt('transaction_timestamp'), timestamp);
    expect(updated.getString('chunk'), unicodePayload);
  }, skip: emulatorLimit, timeout: largeTimeout);

  test('testQueryLargeDocuments', () async {
    final CollectionReference colRef = db.collection(seedCollection);
    final Query query = colRef
        .whereInField(FieldPath.documentId(), <Object?>['doc_a', 'doc_b']);

    final QuerySnapshot serverSnapshot = await query.get(Source.server);
    expect(serverSnapshot.documents.length, 2,
        reason: 'Query should return exactly 2 large documents from server');

    await db.disableNetwork();
    final QuerySnapshot cacheSnapshot = await query.get(Source.cache);
    expect(cacheSnapshot.documents.length, 2,
        reason: 'Query should return exactly 2 large documents from cache');

    for (final DocumentSnapshot serverDoc in serverSnapshot.documents) {
      final DocumentSnapshot cacheDoc = cacheSnapshot.documents
          .firstWhere((DocumentSnapshot d) => d.id == serverDoc.id);
      expect(cacheDoc.data, serverDoc.data,
          reason: 'Payload for ${serverDoc.id} in cache should match server');
    }
    await db.enableNetwork();
  }, skip: emulatorLimit, timeout: largeTimeout);

  test('testQueryLargeDocumentsForcesLocalScan', () async {
    final CollectionReference colRef = db.collection(seedCollection);
    await colRef.document('doc_a').get(Source.server);
    await colRef.document('doc_b').get(Source.server);

    await db.disableNetwork();

    final Query query = colRef
        .whereEqualTo('tag', 'ascii_large_doc')
        .orderByField(FieldPath.documentId())
        .limit(2);
    final QuerySnapshot cacheSnapshot = await query.get(Source.cache);

    expect(cacheSnapshot.documents.length, 2,
        reason: 'Query should find and return exactly 2 large documents');
    final List<DocumentSnapshot> docs = cacheSnapshot.documents;
    expect(docs[0].id, 'doc_a');
    expect(docs[1].id, 'doc_b');
    expect(docs[0].getString('chunk'), asciiPayload);
    expect(docs[1].getString('chunk'), asciiPayload);
    await db.enableNetwork();
  }, skip: emulatorLimit, timeout: largeTimeout);
}

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

// Reads of documents near the size limit of the emulator (1 MiB), many of them in one response, over every transport.
// One response stream carries well over the 4 MB that is the default inbound limit of gRPC in other languages (grpc-java,
// grpc-node), which the Android and JS SDKs raise to 17 MiB. Documents of up to 16 MiB (a single message larger than 4
// MB) are covered by large_document_test.dart, against a production database only: the emulator rejects them.

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';

/// Close to the 1 MiB limit of the emulator: the document name and the field names count too.
const int _payloadBytes = 1024 * 1024 - 4 * 1024;

/// About 12 MiB in one response stream.
const int _documentCount = 12;

/// A payload of [length] UTF-8 bytes that differs per [seed]: random ASCII letters with a multi-byte character every
/// 1000 bytes, so that a mix-up of documents or a broken UTF-8 boundary shows.
String _payload(int seed, int length) {
  final Random random = Random(seed);
  final StringBuffer buffer = StringBuffer();
  int bytes = 0;
  while (bytes < length) {
    if (bytes % 1000 == 999 && bytes + 3 <= length) {
      buffer.write('€'); // 3 bytes in UTF-8
      bytes += 3;
    } else {
      buffer.writeCharCode(0x61 + random.nextInt(26));
      bytes += 1;
    }
  }
  return buffer.toString();
}

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/transport_limits';
  const Timeout timeout = Timeout(Duration(minutes: 3));

  late Firestore firestore;
  late CollectionReference<Map<String, Object?>> collection;
  late Map<String, String> payloads;

  setUp(() async {
    firestore = await IntegrationTestUtil.testFirestore();
    collection = firestore.collection(
      'limits-${DateTime.now().microsecondsSinceEpoch}',
    );
    payloads = <String, String>{
      for (int i = 0; i < _documentCount; i++)
        'doc${i.toString().padLeft(2, '0')}': _payload(i, _payloadBytes),
    };
    // One write per document: a batch of them would exceed the request size limit.
    await Future.wait(<Future<void>>[
      for (final MapEntry<String, String> entry in payloads.entries)
        collection.doc(entry.key).set(<String, Object?>{
          'chunk': entry.value,
          'id': entry.key,
        }),
    ]);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  void expectAllDocuments(
    Iterable<DocumentSnapshot<Map<String, Object?>>> docs,
  ) {
    final Map<String, DocumentSnapshot<Map<String, Object?>>> byId =
        <String, DocumentSnapshot<Map<String, Object?>>>{
          for (final DocumentSnapshot<Map<String, Object?>> doc in docs)
            doc.id: doc,
        };
    expect(byId.keys.toSet(), payloads.keys.toSet());
    for (final MapEntry<String, String> entry in payloads.entries) {
      final Map<String, Object?> data = byId[entry.key]!.data!;
      expect(data['id'], entry.key);
      // Not `expect(.., entry.value)`: a mismatch would print megabytes.
      expect(
        data['chunk'] == entry.value,
        isTrue,
        reason: 'payload of ${entry.key}',
      );
    }
  }

  test(
    'a query returns many documents near the size limit in one response',
    () async {
      final QuerySnapshot<Map<String, Object?>> snapshot = await collection.get(
        Source.server,
      );
      expect(snapshot.metadata.isFromCache, isFalse);
      expectAllDocuments(snapshot.docs);

      // The cache holds them as well.
      final QuerySnapshot<Map<String, Object?>> cached = await collection.get(
        Source.cache,
      );
      expectAllDocuments(cached.docs);
    },
    timeout: timeout,
  );

  test('a listener gets many documents near the size limit', () async {
    // A new instance, so that the documents come from the watch stream and not from the cache of the writes.
    final Firestore reader = await IntegrationTestUtil.testFirestore();
    final CollectionReference<Map<String, Object?>> readerCollection = reader
        .collection(collection.path);
    final QuerySnapshot<Map<String, Object?>> snapshot = await readerCollection
        .snapshots
        .firstWhere(
          (QuerySnapshot<Map<String, Object?>> s) => !s.metadata.isFromCache,
        )
        .timeout(const Duration(minutes: 1));
    expectAllDocuments(snapshot.docs);
  }, timeout: timeout);

  test('a transaction reads many documents near the size limit', () async {
    final Firestore reader = await IntegrationTestUtil.testFirestore();
    final List<DocumentSnapshot<Map<String, Object?>>> docs = await reader
        .runTransaction(
          (Transaction transaction) =>
              Future.wait(<Future<DocumentSnapshot<Map<String, Object?>>>>[
                for (final String id in payloads.keys)
                  transaction.get(reader.collection(collection.path).doc(id)),
              ]),
        );
    expectAllDocuments(docs);
  }, timeout: timeout);

  for (final int window in <int>[65535, 1024 * 1024]) {
    test('a query with a flow-control window of $window bytes', () async {
      // The gRPC transport only; the web transport ignores the setting.
      final Firestore reader = await IntegrationTestUtil.testFirestore(
        IntegrationTestUtil.newTestSettings().copyWith(
          grpcFlowControlWindow: window,
        ),
      );
      final QuerySnapshot<Map<String, Object?>> snapshot = await reader
          .collection(collection.path)
          .get(Source.server);
      expectAllDocuments(snapshot.docs);
    }, timeout: timeout);
  }

  test('a lookup of one document near the size limit', () async {
    final Firestore reader = await IntegrationTestUtil.testFirestore();
    final DocumentSnapshot<Map<String, Object?>> doc = await reader
        .collection(collection.path)
        .doc('doc03')
        .get(Source.server);
    expect(doc.get('chunk') == payloads['doc03'], isTrue);
  }, timeout: timeout);
}

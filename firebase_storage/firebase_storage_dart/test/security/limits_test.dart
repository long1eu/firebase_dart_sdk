// Threat model: storage_threat_model.md, "Memory, time and loops" (T9, T10, T11).
import 'dart:async';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'security_support.dart';

void main() {
  group('getBytes(maxSize:)', () {
    test('asks for maxSize + 1 bytes with a Range header', () async {
      final RecordingClient client = RecordingClient(
        (SentRequest r) => respond(206, body: 'abc'),
      );
      final FirebaseStorage storage = securityStorage(securityApp(), client);
      addTearDown(storage.close);
      await storage.ref('x').getBytes(maxSize: 10);
      expect(client.sent.single.headers['Range'], 'bytes=0-10');
    });

    test('stops reading when a server ignores Range and sends more', () async {
      // 64 MiB offered with a 200; the client must give up after maxSize + 1 bytes.
      final LazyBody body = LazyBody(chunkSize: 64 * 1024, chunkCount: 1024);
      final FirebaseStorage storage = securityStorage(
        securityApp(),
        RecordingClient(
          (SentRequest r) => http.StreamedResponse(body.stream(), 200),
        ),
      );
      addTearDown(storage.close);
      await expectLater(
        storage.ref('x').getBytes(maxSize: 1024),
        throwsStorageCode('download-size-exceeded'),
      );
      expect(
        body.pulled,
        lessThan(4),
        reason: 'pulled ${body.pulled} chunks of 64 KiB',
      );
    });

    test('a negative maxSize is invalid-argument and sends nothing', () async {
      final RecordingClient client = RecordingClient(
        (SentRequest r) => respond(200),
      );
      final FirebaseStorage storage = securityStorage(securityApp(), client);
      addTearDown(storage.close);
      await expectLater(
        storage.ref('x').getBytes(maxSize: -1),
        throwsStorageCode('invalid-argument'),
      );
      expect(client.sent, isEmpty);
    });
  });

  test(
    'a server that never answers is bounded by requestTimeout and the retry time',
    () async {
      final RecordingClient client = RecordingClient(
        (SentRequest r) => Completer<http.StreamedResponse>().future,
      );
      final FirebaseStorage storage = securityStorage(
        securityApp(),
        client,
        requestTimeout: const Duration(milliseconds: 50),
        retry: const StorageRetryPolicy(operation: Duration.zero),
      );
      addTearDown(storage.close);
      await expectLater(
        storage.ref('x').metadata().timeout(const Duration(seconds: 5)),
        throwsStorageCode('retry-limit-exceeded'),
      );
    },
  );

  test('a body that stalls half way is bounded by requestTimeout', () async {
    final RecordingClient client = RecordingClient((SentRequest r) {
      final StreamController<List<int>> stalled = StreamController<List<int>>()
        ..add(<int>[1, 2, 3]);
      return http.StreamedResponse(stalled.stream, 200);
    });
    final FirebaseStorage storage = securityStorage(
      securityApp(),
      client,
      requestTimeout: const Duration(milliseconds: 50),
      retry: const StorageRetryPolicy(download: Duration.zero),
    );
    addTearDown(storage.close);
    await expectLater(
      storage.ref('x').getBytes().timeout(const Duration(seconds: 5)),
      throwsA(isA<FirebaseStorageException>()),
    );
  });

  test('listAll stops when the server repeats a page token', () async {
    int calls = 0;
    final RecordingClient client = RecordingClient((SentRequest r) {
      // A buggy or hostile server: always "one more page", always the same token.
      if (++calls > 50) {
        return respondJson(<String, Object?>{'items': <Object?>[]});
      }
      return respondJson(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{'name': 'a/x', 'bucket': 'b'},
        ],
        'nextPageToken': 'same',
      });
    });
    final FirebaseStorage storage = securityStorage(securityApp(), client);
    addTearDown(storage.close);
    try {
      await storage.ref('a').listAll();
    } on FirebaseStorageException {
      // Failing is fine; looping is not.
    }
    expect(client.sent.length, lessThanOrEqualTo(3));
  });
}

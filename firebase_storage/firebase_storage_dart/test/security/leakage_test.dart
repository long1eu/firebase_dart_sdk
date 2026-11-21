// Threat model: storage_threat_model.md, "Secrets in errors and logs" (T7, T8).
import 'dart:convert';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'security_support.dart';

const List<String> _secrets = <String>[
  secretIdToken,
  secretAppCheckToken,
  secretDownloadToken,
];

void main() {
  test('invalid-url does not repeat the download token of the URL', () {
    final FirebaseStorage storage = securityStorage(
      securityApp(),
      RecordingClient((SentRequest r) => respond(200)),
    );
    addTearDown(storage.close);
    for (final String url in <String>[
      'https://firebasestorage.googleapis.com/v0/b/b/o/%ZZ?alt=media&token=$secretDownloadToken',
      'https://evil.example/v0/b/b/o/x?alt=media&token=$secretDownloadToken',
      'https://evil.example/x#token=$secretDownloadToken',
    ]) {
      expect(
        () => storage.refFromUrl(url),
        throwsWithout(_secrets),
        reason: url,
      );
    }
  });

  for (final int status in <int>[400, 401, 403, 404, 500]) {
    test('an HTTP $status error carries no request token', () async {
      final FirebaseStorage storage = securityStorage(
        securityApp(),
        RecordingClient(
          (SentRequest r) => respondJson(<String, Object?>{
            'error': <String, Object?>{'code': status, 'message': 'no'},
          }, status: status),
        ),
        retry: const StorageRetryPolicy(operation: Duration.zero),
      );
      addTearDown(storage.close);
      await expectLater(storage.ref('x').metadata(), throwsWithout(_secrets));
    });
  }

  test(
    'a network error keeps the request headers out of the exception',
    () async {
      final FirebaseStorage storage = securityStorage(
        securityApp(),
        RecordingClient(
          (SentRequest r) => throw http.ClientException(
            'Connection reset; sent ${r.url}',
            r.url,
          ),
        ),
        retry: const StorageRetryPolicy(operation: Duration(seconds: 5)),
      );
      addTearDown(storage.close);
      await expectLater(
        storage.ref('x').metadata(),
        allOf(
          throwsStorageCode('retry-limit-exceeded'),
          throwsWithout(_secrets),
        ),
      );
    },
  );

  test('FullMetadata and Reference never print download tokens', () async {
    final FirebaseStorage storage = securityStorage(
      securityApp(),
      RecordingClient((SentRequest r) => respondJson(objectResource('x'))),
    );
    addTearDown(storage.close);
    final Reference ref = storage.ref('x');
    final FullMetadata metadata = await ref.metadata();
    expect(metadata.downloadTokens, <String>[secretDownloadToken]);
    expect(metadata.toString(), isNot(contains(secretDownloadToken)));
    expect(ref.toString(), isNot(contains(secretDownloadToken)));
  });

  test(
    'serverResponse is capped at 16 KiB and the rest of the error body is not read',
    () async {
      final LazyBody body = LazyBody(chunkSize: 4096, chunkCount: 4096);
      final FirebaseStorage storage = securityStorage(
        securityApp(),
        RecordingClient(
          (SentRequest r) => http.StreamedResponse(body.stream(), 400),
        ),
      );
      addTearDown(storage.close);
      Object? error;
      try {
        await storage.ref('x').metadata();
      } on FirebaseStorageException catch (e) {
        error = e;
      }
      final FirebaseStorageException e = error! as FirebaseStorageException;
      expect(
        utf8.encode(e.serverResponse!).length,
        lessThanOrEqualTo(16 * 1024),
      );
      expect(
        body.pulled,
        lessThan(16),
        reason: 'read ${body.pulled} chunks of 4 KiB',
      );
    },
  );
}

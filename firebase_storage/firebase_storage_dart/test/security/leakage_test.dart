// Threat model: storage_threat_model.md, "Secrets in errors and logs" (T7, T8).
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
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

  test(
    'a failing token provider leaves its message out; it is kept as the cause',
    () async {
      final FirebaseApp app = securityApp(signedIn: false);
      final _LeakyAuth auth = _LeakyAuth();
      app.authProvider = auth;
      final RecordingClient client = RecordingClient(
        (SentRequest r) => respondJson(objectResource('x')),
      );
      final FirebaseStorage storage = securityStorage(app, client);
      addTearDown(storage.close);
      Object? caught;
      try {
        await storage.ref('x').metadata();
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isA<FirebaseStorageException>());
      final FirebaseStorageException e = caught! as FirebaseStorageException;
      expect(e.code, 'unauthenticated');
      expect(everythingPrinted(e), isNot(contains(_LeakyAuth.secret)));
      expect(e.message, contains('_ProviderError'));
      expect(e.cause, same(auth.thrown));
      expect(e.stackTrace, isNotNull);
      expect(client.sent, isEmpty);
    },
  );
}

class _ProviderError implements Exception {
  _ProviderError(this.detail);

  final String detail;

  @override
  String toString() => '_ProviderError: $detail';
}

class _LeakyAuth extends AuthTokenProvider {
  static const String secret = 'REFRESH-TOKEN-SECRET-ab12';

  _ProviderError? thrown;

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
    final _ProviderError error = _ProviderError(
      'refresh with refresh_token=$secret failed',
    );
    thrown = error;
    throw error;
  }

  @override
  String? get uid => 'u1';

  @override
  Stream<AuthTokenChange> get onTokenChanged =>
      const Stream<AuthTokenChange>.empty();
}

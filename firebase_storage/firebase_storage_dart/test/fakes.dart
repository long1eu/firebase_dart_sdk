import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

int _appCount = 0;

/// A new app with a unique name; delete it in a tearDown.
FirebaseApp newApp({
  String? storageBucket = 'b',
  String appId = '1:123:dart:abc',
}) {
  return FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: 'key',
      appId: appId,
      projectId: 'demo-test',
      storageBucket: storageBucket,
    ),
    name: 'storage-test-${_appCount++}',
  );
}

/// An auth provider that hands out [tokens] in turn (the last one repeats) and records the `forceRefresh`
/// of each call. A null token means nobody is signed in.
class FakeAuth extends AuthTokenProvider {
  FakeAuth(this.tokens, {this.error});

  final List<String?> tokens;
  final Object? error;
  final List<bool> calls = <bool>[];

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
    calls.add(forceRefresh);
    final Object? failure = error;
    if (failure != null) {
      return Future<Never>.error(failure);
    }
    final String? token =
        tokens[(calls.length - 1).clamp(0, tokens.length - 1)];
    if (token == null) {
      throw const FirebaseNoSignedInUserException('No user.');
    }
    return GetTokenResult(token);
  }

  @override
  String? get uid => null;

  @override
  Stream<AuthTokenChange> get onTokenChanged =>
      const Stream<AuthTokenChange>.empty();
}

/// An App Check provider with a fixed result, or one that throws [error].
class FakeAppCheck extends AppCheckTokenProvider {
  FakeAppCheck(this.result, {this.error});

  final AppCheckTokenResult result;
  final Object? error;
  final List<bool> calls = <bool>[];

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async {
    calls.add(forceRefresh);
    final Object? failure = error;
    if (failure != null) {
      return Future<Never>.error(failure);
    }
    return result;
  }

  @override
  Stream<AppCheckTokenResult> get onTokenChanged =>
      const Stream<AppCheckTokenResult>.empty();
}

/// A fake clock whose [delay] advances it at once and records the waits.
class FakeTime {
  DateTime now = DateTime.utc(2026, 11, 21);
  final List<Duration> delays = <Duration>[];

  DateTime clock() => now;

  Future<void> delay(Duration duration) async {
    delays.add(duration);
    now = now.add(duration);
  }
}

/// The requests a [MockClient] received.
final class Recorded {
  Recorded(this.method, this.url, this.headers, this.bodyBytes);

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final List<int> bodyBytes;

  String get body => utf8.decode(bodyBytes, allowMalformed: true);
}

/// A [FirebaseStorage] whose requests go to [handler] and are recorded in [requests]. The random number is
/// always 0.5 and the time is [time] (a new [FakeTime] by default).
FirebaseStorage storageWith(
  FirebaseApp app,
  Future<http.Response> Function(Recorded request) handler, {
  List<Recorded>? requests,
  FakeTime? time,
  String? bucket,
  String? emulatorHost,
  String? mockUserToken,
  StorageRetryPolicy retry = const StorageRetryPolicy(),
  Duration requestTimeout = const Duration(minutes: 1),
}) {
  final FakeTime clock = time ?? FakeTime();
  return FirebaseStorage(
    app,
    bucket: bucket,
    emulatorHost: emulatorHost,
    mockUserToken: mockUserToken,
    retry: retry,
    requestTimeout: requestTimeout,
    httpClient: MockClient((http.Request request) {
      final Recorded recorded = Recorded(
        request.method,
        request.url,
        request.headers,
        request.bodyBytes,
      );
      requests?.add(recorded);
      return handler(recorded);
    }),
    clock: clock.clock,
    random: () => 0.5,
    delay: clock.delay,
  );
}

/// A JSON response.
Future<http.Response> json(Object? body, {int status = 200}) async =>
    http.Response(
      jsonEncode(body),
      status,
      headers: <String, String>{'content-type': 'application/json'},
    );

/// The metadata resource of the JS SDK's requests test.
const Map<String, Object?> serverResource = <String, Object?>{
  'bucket': 'b',
  'generation': '1',
  'metageneration': '2',
  'name': 'foo/bar/baz.png',
  'size': '10',
  'timeCreated': '2026-11-20T10:00:00.000Z',
  'updated': '2026-11-21T11:30:00.500Z',
  'md5Hash': 'deadbeef',
  'cacheControl': 'max-age=604800',
  'contentDisposition': 'Attachment; filename=baz.png',
  'contentLanguage': 'en-US',
  'contentType': 'application/jason',
  'downloadTokens': 'a,b,c',
  'metadata': <String, Object?>{'foo': 'bar'},
};

/// Throws a [FirebaseStorageException] with [code].
Matcher throwsStorageCode(String code) => throwsA(
  isA<FirebaseStorageException>()
      .having((FirebaseStorageException e) => e.code, 'code', code)
      .having(
        (FirebaseStorageException e) => e.plugin,
        'plugin',
        'firebase_storage',
      ),
);

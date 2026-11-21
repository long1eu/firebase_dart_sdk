import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// The ID token the fake auth provider hands out; it must never show up in an exception or a log line.
const String secretIdToken = 'ID-TOKEN-SECRET-7f3a';

/// The App Check token of the fake provider.
const String secretAppCheckToken = 'APP-CHECK-SECRET-91bc';

/// A download token, a bearer credential for one object.
const String secretDownloadToken = 'DOWNLOAD-TOKEN-SECRET-c0de';

int _appCount = 0;

/// A new app with bucket `b`, a signed-in user ([secretIdToken]) and App Check ([secretAppCheckToken]).
FirebaseApp securityApp({bool signedIn = true, bool appCheck = true}) {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'key',
      appId: '1:123:dart:abc',
      projectId: 'demo-test',
      storageBucket: 'b',
    ),
    name: 'storage-security-${_appCount++}',
  );
  if (signedIn) {
    app.authProvider = _StaticAuth(secretIdToken);
  }
  if (appCheck) {
    app.appCheckProvider = _StaticAppCheck(secretAppCheckToken);
  }
  return app;
}

class _StaticAuth extends AuthTokenProvider {
  _StaticAuth(this.token);

  final String token;

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async =>
      GetTokenResult(token);

  @override
  String? get uid => 'u1';

  @override
  Stream<AuthTokenChange> get onTokenChanged =>
      const Stream<AuthTokenChange>.empty();
}

class _StaticAppCheck extends AppCheckTokenProvider {
  _StaticAppCheck(this.token);

  final String token;

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async =>
      AppCheckTokenResult(token);

  @override
  Stream<AppCheckTokenResult> get onTokenChanged =>
      const Stream<AppCheckTokenResult>.empty();
}

/// A request as the client saw it.
final class SentRequest {
  SentRequest(this.request, this.bodyBytes);

  /// The request; read `followRedirects`, `url`, `headers` from it.
  final http.BaseRequest request;

  /// The whole body that was sent.
  final Uint8List bodyBytes;

  Uri get url => request.url;

  Map<String, String> get headers => request.headers;

  String get body => latin1.decode(bodyBytes);
}

/// Answers a request.
typedef SecurityHandler =
    FutureOr<http.StreamedResponse> Function(SentRequest request);

/// An [http.Client] that records every request (with its redirect settings) and answers with [handler].
final class RecordingClient extends http.BaseClient {
  RecordingClient(this.handler);

  final SecurityHandler handler;

  /// Every request, in order.
  final List<SentRequest> sent = <SentRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final Uint8List body = await request.finalize().toBytes();
    final SentRequest recorded = SentRequest(request, body);
    sent.add(recorded);
    return handler(recorded);
  }
}

/// A fake clock whose delays advance it at once.
final class FakeTime {
  DateTime now = DateTime.utc(2026, 11, 21);

  DateTime clock() => now;

  Future<void> delay(Duration duration) async {
    now = now.add(duration);
  }
}

/// A [FirebaseStorage] for bucket `b` that sends through [client], with a fake clock.
FirebaseStorage securityStorage(
  FirebaseApp app,
  RecordingClient client, {
  String? emulatorHost,
  String? mockUserToken,
  StorageRetryPolicy retry = const StorageRetryPolicy(),
  Duration requestTimeout = const Duration(minutes: 1),
}) {
  final FakeTime time = FakeTime();
  return FirebaseStorage(
    app,
    emulatorHost: emulatorHost,
    mockUserToken: mockUserToken,
    retry: retry,
    requestTimeout: requestTimeout,
    httpClient: client,
    // ignore: invalid_use_of_visible_for_testing_member
    clock: time.clock,
    // ignore: invalid_use_of_visible_for_testing_member
    random: () => 0.5,
    // ignore: invalid_use_of_visible_for_testing_member
    delay: time.delay,
  );
}

/// A complete response.
http.StreamedResponse respond(
  int status, {
  String body = '',
  Map<String, String> headers = const <String, String>{},
}) {
  final List<int> bytes = utf8.encode(body);
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    status,
    contentLength: bytes.length,
    headers: headers,
  );
}

/// A JSON response.
http.StreamedResponse respondJson(Object? body, {int status = 200}) => respond(
  status,
  body: jsonEncode(body),
  headers: const <String, String>{'content-type': 'application/json'},
);

/// The metadata resource of object [name] in bucket `b`, with [secretDownloadToken].
Map<String, Object?> objectResource(String name, {int size = 10}) =>
    <String, Object?>{
      'bucket': 'b',
      'name': name,
      'generation': '1',
      'metageneration': '1',
      'size': '$size',
      'contentType': 'application/octet-stream',
      'timeCreated': '2026-11-20T10:00:00.000Z',
      'updated': '2026-11-20T10:00:00.000Z',
      'downloadTokens': secretDownloadToken,
    };

/// A body of [chunkCount] chunks of [chunkSize] bytes produced only when pulled; [pulled] counts the
/// chunks handed out, so a test can tell whether the client stopped reading.
final class LazyBody {
  LazyBody({required this.chunkSize, required this.chunkCount});

  final int chunkSize;
  final int chunkCount;
  int pulled = 0;

  int get totalBytes => chunkSize * chunkCount;

  Stream<List<int>> stream() async* {
    final Uint8List chunk = Uint8List(chunkSize);
    for (int i = 0; i < chunkCount; i++) {
      pulled++;
      yield chunk;
    }
  }
}

/// The string forms of [error] a log line could show.
String everythingPrinted(Object error) {
  final StringBuffer out = StringBuffer(error.toString());
  if (error is FirebaseStorageException) {
    out
      ..write('\n')
      ..write(error.message)
      ..write('\n')
      ..write(error.serverResponse);
  }
  return out.toString();
}

/// Throws a [FirebaseStorageException] with [code].
Matcher throwsStorageCode(String code) => throwsA(
  isA<FirebaseStorageException>().having(
    (FirebaseStorageException e) => e.code,
    'code',
    code,
  ),
);

/// Throws something whose printed forms contain none of [secrets].
Matcher throwsWithout(List<String> secrets) => throwsA(
  predicate<Object>(
    (Object error) {
      final String printed = everythingPrinted(error);
      return secrets.every((String secret) => !printed.contains(secret));
    },
    'an error whose message, toString and serverResponse hold none of $secrets',
  ),
);

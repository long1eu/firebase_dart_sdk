// Helpers of the Installations security tests (spec v4 11.7, group fis_sec). No dart:io here: the
// browser runs numbers_test.dart, which imports this file.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/src/record.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// The API key sentinel: matches `^A[A-Za-z0-9_-]{38}$`, so the constructor accepts it.
const String fisSecApiKey = 'AIzaSENTINELapiKEY_0123456789abcdefghij';

/// The refresh token sentinel the fake server hands out.
const String fisSecRefreshToken = 'RTSENTINEL-refresh-7f3a9c';

/// The auth token sentinel the fake server hands out.
const String fisSecAuthToken = 'ATSENTINEL-auth-91bc04';

/// The project id of the test apps.
const String fisSecProjectId = 'demo-fis-sec';

/// The app id of the test apps.
const String fisSecAppId = '1:1234567890:web:fissec';

/// A FID that matches the FID pattern.
const String fisSecFid = 'cAAAAAAAAAAAAAAAAAAAAA';

/// A second valid FID (the server may assign another one).
const String fisSecServerFid = 'dBBBBBBBBBBBBBBBBBBBBB';

/// The time of the fake clock at the start of each test.
final DateTime fisSecNow = DateTime.utc(2026, 11, 28, 12);

int _appCounter = 0;

/// A new app with a unique name and the sentinel API key, deleted after the test.
FirebaseApp fisSecApp({
  String apiKey = fisSecApiKey,
  String? projectId = fisSecProjectId,
  String appId = fisSecAppId,
}) {
  _appCounter++;
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(apiKey: apiKey, appId: appId, projectId: projectId),
    name: 'fis-sec-$_appCounter',
  );
  addTearDown(app.delete);
  return app;
}

/// The store key of the installation record of [app].
String fisSecRecordKey(FirebaseApp app) =>
    'installations/${app.persistenceKey}';

/// 17 bytes that become the FID `fisSecFid`-like value `cAAA…` (all zero bytes give `cAAA…A`).
Uint8List fisSecZeroBytes(int length) => Uint8List(length);

/// A request as the fake client saw it.
final class FisSecRequest {
  FisSecRequest._(
    this.method,
    this.url,
    this.headers,
    this.body,
    this.followRedirects,
    this.abortTrigger,
  ) {
    abortTrigger?.then((_) => aborted = true);
  }

  /// The HTTP method.
  final String method;

  /// The URL.
  final Uri url;

  /// The headers as the client set them.
  final Map<String, String> headers;

  /// The body, decoded as UTF-8.
  final String body;

  /// The request's `followRedirects`.
  final bool followRedirects;

  /// The abort trigger of an `AbortableRequest`, or null.
  final Future<void>? abortTrigger;

  /// True once [abortTrigger] fired.
  bool aborted = false;

  /// `create`, `generate`, `delete` or `other`.
  String get route {
    final String last = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
    if (method == 'POST' && last == 'installations') {
      return 'create';
    }
    if (method == 'POST' && last == 'authTokens:generate') {
      return 'generate';
    }
    if (method == 'DELETE') {
      return 'delete';
    }
    return 'other';
  }

  /// Every text of the request a secret could hide in: URL, header names and values, body.
  String get allText =>
      '$method $url ${headers.entries.map((MapEntry<String, String> e) => '${e.key}: ${e.value}').join('\n')}\n$body';
}

/// Answers one request.
typedef FisSecHandler =
    FutureOr<http.StreamedResponse> Function(FisSecRequest request);

/// An `http.Client` that records each request (headers, body, `followRedirects`, abort trigger) and
/// answers it with [handler].
final class FisSecClient extends http.BaseClient {
  /// A client answering with [handler].
  FisSecClient(this.handler);

  /// Answers each request.
  FisSecHandler handler;

  /// Every request sent, in order.
  final List<FisSecRequest> requests = <FisSecRequest>[];

  /// True once [close] was called.
  bool closed = false;

  /// The requests of [route].
  List<FisSecRequest> of(String route) =>
      requests.where((FisSecRequest r) => r.route == route).toList();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final Uint8List bytes = await request.finalize().toBytes();
    final FisSecRequest recorded = FisSecRequest._(
      request.method,
      request.url,
      Map<String, String>.of(request.headers),
      utf8.decode(bytes, allowMalformed: true),
      request.followRedirects,
      request is http.Abortable ? request.abortTrigger : null,
    );
    requests.add(recorded);
    return handler(recorded);
  }

  @override
  void close() {
    closed = true;
  }
}

/// A response with [status], [body] bytes and [headers].
http.StreamedResponse fisSecBytes(
  int status,
  List<int> body, {
  Map<String, String> headers = const <String, String>{},
}) => http.StreamedResponse(
  Stream<List<int>>.value(body),
  status,
  headers: headers,
);

/// A response with [status] whose [body] arrives in chunks of [chunkSize] bytes.
http.StreamedResponse fisSecChunked(
  int status,
  List<int> body, {
  required int chunkSize,
}) => http.StreamedResponse(
  Stream<List<int>>.fromIterable(<List<int>>[
    for (int i = 0; i < body.length; i += chunkSize)
      body.sublist(
        i,
        i + chunkSize > body.length ? body.length : i + chunkSize,
      ),
  ]),
  status,
);

/// A response with [status] and the UTF-8 [text].
http.StreamedResponse fisSecText(
  int status,
  String text, {
  Map<String, String> headers = const <String, String>{},
}) => fisSecBytes(status, utf8.encode(text), headers: headers);

/// A JSON response.
http.StreamedResponse fisSecJson(int status, Object? json) => fisSecText(
  status,
  jsonEncode(json),
  headers: const <String, String>{'content-type': 'application/json'},
);

/// The JSON of a create answer.
Map<String, Object?> fisSecCreateJson({
  String? fid,
  String refreshToken = fisSecRefreshToken,
  String token = fisSecAuthToken,
  Object? expiresIn = '604800s',
}) => <String, Object?>{
  'name': 'projects/$fisSecProjectId/installations/${fid ?? fisSecFid}',
  'fid': ?fid,
  'refreshToken': refreshToken,
  'authToken': <String, Object?>{'token': token, 'expiresIn': expiresIn},
};

/// A 200 create answer.
http.StreamedResponse fisSecCreateOk({
  String? fid,
  String token = fisSecAuthToken,
  Object? expiresIn = '604800s',
}) => fisSecJson(
  200,
  fisSecCreateJson(fid: fid, token: token, expiresIn: expiresIn),
);

/// A 200 generate answer.
http.StreamedResponse fisSecGenerateOk({
  String token = fisSecAuthToken,
  Object? expiresIn = '604800s',
}) =>
    fisSecJson(200, <String, Object?>{'token': token, 'expiresIn': expiresIn});

/// A Google error body with [status].
http.StreamedResponse fisSecError(
  int status, {
  String serverStatus = 'FAILED',
  String message = 'The request failed.',
}) => fisSecJson(status, <String, Object?>{
  'error': <String, Object?>{
    'code': status,
    'status': serverStatus,
    'message': message,
  },
});

/// A handler answering create, generate and delete with success.
FisSecHandler fisSecHappyHandler() =>
    (FisSecRequest r) => switch (r.route) {
      'create' => fisSecCreateOk(),
      'generate' => fisSecGenerateOk(),
      _ => fisSecJson(200, <String, Object?>{}),
    };

/// The JSON text of a registered record.
String fisSecRegisteredRecord({
  String fid = fisSecFid,
  String refreshToken = fisSecRefreshToken,
  String token = fisSecAuthToken,
  DateTime? tokenCreatedAt,
  Duration tokenExpiresIn = const Duration(days: 7),
}) => InstallationRecord.registered(
  fid: fid,
  refreshToken: refreshToken,
  token: token,
  tokenCreatedAt: tokenCreatedAt ?? fisSecNow,
  tokenExpiresIn: tokenExpiresIn,
).encode();

/// The JSON object of a registered record, to change fields of.
Map<String, Object?> fisSecRegisteredJson({DateTime? tokenCreatedAt}) =>
    jsonDecode(fisSecRegisteredRecord(tokenCreatedAt: tokenCreatedAt))
        as Map<String, Object?>;

/// An endless response body that counts the chunks taken from it.
final class FisSecEndless {
  /// Chunks of [chunkSize] bytes of [byte].
  FisSecEndless({this.chunkSize = 1024, this.byte = 0x20});

  /// The size of each chunk.
  final int chunkSize;

  /// The byte each chunk is filled with (a space keeps a JSON prefix valid).
  final int byte;

  /// The chunks taken so far.
  int pulled = 0;

  /// True once the consumer cancelled the stream.
  bool cancelled = false;

  /// The bytes taken so far.
  int get bytes => pulled * chunkSize;

  /// A response with [status] whose body never ends.
  http.StreamedResponse response(int status) =>
      http.StreamedResponse(_stream(), status);

  Stream<List<int>> _stream() async* {
    final List<int> chunk = List<int>.filled(chunkSize, byte);
    try {
      while (true) {
        await Future<void>.value();
        pulled++;
        yield chunk;
      }
    } finally {
      cancelled = true;
    }
  }
}

/// [json] encoded and padded with trailing spaces (still valid JSON) to exactly [length] bytes.
String fisSecPaddedJson(Object? json, int length) {
  final String text = jsonEncode(json);
  final int size = utf8.encode(text).length;
  if (size > length) {
    throw ArgumentError.value(
      length,
      'length',
      'is shorter than the JSON ($size bytes)',
    );
  }
  return text + ' ' * (length - size);
}

/// Log lines collected from a logger.
final class FisSecLog {
  /// Every line, as `level: message`.
  final List<String> lines = <String>[];

  /// The logger to pass to constructors.
  void call(InstallationsLogLevel level, String message) =>
      lines.add('${level.name}: $message');
}

/// A [FirebaseInstallations] for [app] with fake time (fixed at [fisSecNow] unless [clock] is given),
/// no real delays, zero FID bytes and the given [client].
FirebaseInstallations fisSecInstallations(
  FirebaseApp app, {
  required KeyValueStore store,
  required http.Client client,
  DateTime Function()? clock,
  InstallationsLogger? logger,
  Uri? serverOrigin,
  Map<String, String> headers = const <String, String>{},
  Future<void> Function(Duration duration)? delay,
}) {
  final FirebaseInstallations installations = FirebaseInstallations(
    app,
    store: store,
    httpClient: client,
    headers: headers,
    logger: logger,
    serverOrigin: serverOrigin ?? fisSecOrigin,
    clock: clock ?? () => fisSecNow,
    random: () => 0.5,
    randomBytes: fisSecZeroBytes,
    delay: delay ?? (Duration _) async {},
  );
  addTearDown(installations.close);
  return installations;
}

/// The default `serverOrigin` of [fisSecInstallations].
final Uri fisSecOrigin = Uri.parse('https://fis.test.example');

/// Matches a future failing with a [FirebaseInstallationsException] of [code].
Matcher throwsFisCode(String code) => throwsA(isFisCode(code));

/// Matches a [FirebaseInstallationsException] of [code].
TypeMatcher<FirebaseInstallationsException> isFisCode(String code) =>
    isA<FirebaseInstallationsException>().having(
      (FirebaseInstallationsException e) => e.code,
      'code',
      code,
    );

/// Runs [action] and returns the error it throws, or null.
Future<Object?> fisSecErrorOf(Future<Object?> Function() action) async {
  try {
    await action();
  } on Object catch (error) {
    return error;
  }
  return null;
}

/// Every text of [error] that reaches a caller: `toString`, and for an installations exception its
/// message, server status and server message.
String fisSecErrorText(Object? error) {
  if (error == null) {
    return '';
  }
  if (error is FirebaseInstallationsException) {
    return <String?>[
      error.toString(),
      error.message,
      error.serverStatus,
      error.serverMessage,
      error.code,
    ].whereType<String>().join('\n');
  }
  return error.toString();
}

/// Runs [action], expects it to fail with a [FirebaseInstallationsException], and returns it.
Future<FirebaseInstallationsException> fisSecFailure(
  Future<Object?> Function() action,
) async {
  final Object? error = await fisSecErrorOf(action);
  expect(error, isA<FirebaseInstallationsException>());
  return error! as FirebaseInstallationsException;
}

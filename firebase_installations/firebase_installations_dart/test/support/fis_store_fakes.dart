import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An API key of the shape the constructor accepts (`^A[A-Za-z0-9_-]{38}$`).
final String fakeApiKey = 'A${'b' * 38}';

/// The project id the fake apps use.
const String fakeProjectId = 'demo-markers';

int _appCounter = 0;

/// A new app with valid options and a name no other test uses.
FirebaseApp newFakeApp() => FirebaseApp.withOptions(
  FirebaseOptions(
    apiKey: fakeApiKey,
    appId: '1:1234567890:dart:abc',
    projectId: fakeProjectId,
  ),
  name: 'fis-store-${_appCounter++}',
);

/// The store key of [app]'s installation record (5.3).
String recordKey(FirebaseApp app) => 'installations/${app.persistenceKey}';

/// The JSON text of an installation record as 5.3 defines it; null fields are left out.
String recordJson({
  required String fid,
  required String status,
  DateTime? registrationStartedAt,
  String? refreshToken,
  String? token,
  DateTime? tokenCreatedAt,
  Duration? tokenExpiresIn,
  DateTime? tokenRequestStartedAt,
}) => jsonEncode(<String, Object?>{
  'v': 1,
  'fid': fid,
  'status': status,
  if (registrationStartedAt != null)
    'registrationStartedAt': registrationStartedAt.millisecondsSinceEpoch,
  'refreshToken': ?refreshToken,
  'token': ?token,
  if (tokenCreatedAt != null)
    'tokenCreatedAt': tokenCreatedAt.millisecondsSinceEpoch,
  if (tokenExpiresIn != null) 'tokenExpiresIn': tokenExpiresIn.inMilliseconds,
  if (tokenRequestStartedAt != null)
    'tokenRequestStartedAt': tokenRequestStartedAt.millisecondsSinceEpoch,
});

/// The JSON object stored as [text], or null when [text] is null.
Map<String, Object?>? decodeRecord(String? text) =>
    text == null ? null : jsonDecode(text) as Map<String, Object?>;

/// A FID built from [seed]: valid (`^[cdef][A-Za-z0-9_-]{21}$`) and distinct per seed below 26.
String fakeFid(int seed) => 'f${String.fromCharCode(0x61 + seed)}${'A' * 20}';

/// A `randomBytes` seam that returns 17 bytes filled with [seed], then [seed] + 1, and so on.
Uint8List Function(int length) countingBytes(int seed) {
  int next = seed;
  return (int length) => Uint8List(length)..fillRange(0, length, next++);
}

/// One request the fake server received.
final class FisRequest {
  /// A request of [kind] for [fid] with its decoded JSON [body].
  const FisRequest(this.kind, this.fid, this.body);

  /// `create`, `generate` or `delete`.
  final String kind;

  /// The FID in the body (create) or the path (generate, delete).
  final String fid;

  /// The decoded body, or null when the request had none.
  final Map<String, Object?>? body;
}

/// A fake Firebase Installations server behind a [MockClient].
///
/// Create answers with the FID it was sent, refresh token `rt-<fid>` and token `create-<fid>`;
/// generate answers with `gen-<fid>-<n>`. Every token lives 7 days. [createDelay] and
/// [generateDelay] hold each answer (use them under `fake_async`).
final class FakeFisServer {
  /// A server whose answers wait [createDelay] and [generateDelay].
  FakeFisServer({
    this.createDelay = Duration.zero,
    this.generateDelay = Duration.zero,
  });

  /// How long each create answer waits.
  Duration createDelay;

  /// How long each generate answer waits.
  Duration generateDelay;

  /// Every request received, in order.
  final List<FisRequest> requests = <FisRequest>[];

  int _generated = 0;

  /// The requests of [kind].
  List<FisRequest> of(String kind) =>
      requests.where((FisRequest r) => r.kind == kind).toList();

  /// The HTTP client to give to `FirebaseInstallations`.
  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final List<String> segments = request.url.pathSegments;
    final Map<String, Object?>? body = request.body.isEmpty
        ? null
        : (jsonDecode(request.body) as Map<String, Object?>);
    if (request.method == 'POST' && segments.last == 'installations') {
      final String fid = body!['fid']! as String;
      requests.add(FisRequest('create', fid, body));
      await Future<void>.delayed(createDelay);
      return _json(<String, Object?>{
        'name': 'projects/$fakeProjectId/installations/$fid',
        'fid': fid,
        'refreshToken': 'rt-$fid',
        'authToken': <String, Object?>{
          'token': 'create-$fid',
          'expiresIn': '604800s',
        },
      });
    }
    if (request.method == 'POST' && segments.last == 'authTokens:generate') {
      final String fid = segments[segments.length - 2];
      requests.add(FisRequest('generate', fid, body));
      final int n = _generated++;
      await Future<void>.delayed(generateDelay);
      return _json(<String, Object?>{
        'token': 'gen-$fid-$n',
        'expiresIn': '604800s',
      });
    }
    if (request.method == 'DELETE') {
      requests.add(FisRequest('delete', segments.last, body));
      return _json(<String, Object?>{});
    }
    return http.Response('{}', 404);
  }

  static http.Response _json(Map<String, Object?> body) => http.Response(
    jsonEncode(body),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

// Owner R. Test doubles for the RestClient tests: a token source with fixed tokens, a recording
// logger, the targets and specs the tests read, and a scripted MockClient.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/core/util/logger.dart';
import 'package:firebase_database_dart/src/realtime/auth_session.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';
import 'package:firebase_database_dart/src/realtime/rest_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An ID token marker that must never appear in a log line or an error.
const String authMarker = 'AUTH-MARKER-7f3a';

/// An App Check token marker that must never appear in a log line or an error.
const String appCheckMarker = 'APPCHECK-MARKER-91c2';

/// A [RealtimeTokenSource] with fixed tokens (null or empty: none), or failing fetches.
final class FixedTokenSource implements RealtimeTokenSource {
  /// Creates the source.
  FixedTokenSource({
    this.auth,
    this.appCheck,
    this.authError,
    this.appCheckError,
  });

  /// The auth token handed out.
  final String? auth;

  /// The App Check token handed out.
  final String? appCheck;

  /// The error of every auth fetch, when set.
  final Exception? authError;

  /// The error of every App Check fetch, when set.
  final Exception? appCheckError;

  /// The `forceRefresh` of each auth fetch.
  final List<bool> authCalls = <bool>[];

  /// The `forceRefresh` of each App Check fetch.
  final List<bool> appCheckCalls = <bool>[];

  @override
  Future<String?> authToken({required bool forceRefresh}) async {
    authCalls.add(forceRefresh);
    final Exception? error = authError;
    if (error != null) {
      throw error;
    }
    return auth;
  }

  @override
  Future<String?> appCheckToken({required bool forceRefresh}) async {
    appCheckCalls.add(forceRefresh);
    final Exception? error = appCheckError;
    if (error != null) {
      throw error;
    }
    return appCheck;
  }

  @override
  Stream<String?> get authChanges => const Stream<String?>.empty();

  @override
  Stream<String?> get appCheckChanges => const Stream<String?>.empty();

  @override
  void notifyInvalid(TokenKind kind) {}
}

/// A [DatabaseLogger] that keeps every line.
final class RecordingLogger {
  /// Every line as `<level>: <message>`.
  final List<String> lines = <String>[];

  /// The lines at [DatabaseLogLevel.warning].
  List<String> get warnings =>
      lines.where((String line) => line.startsWith('warning:')).toList();

  /// The logger to pass.
  void call(DatabaseLogLevel level, String message) {
    lines.add('${level.name}: $message');
  }
}

/// The emulator at `127.0.0.1:9000`, namespace `demo-test-default-rtdb`.
RealtimeTarget emulatorTarget({bool useHeaders = true}) => RealtimeTarget(
  const RepoInfo(
    host: '127.0.0.1:9000',
    namespace: 'demo-test-default-rtdb',
    secure: false,
    isUsingEmulator: true,
  ),
  useHeaders: useHeaders,
);

/// A production database over TLS.
RealtimeTarget productionTarget({bool useHeaders = true}) => RealtimeTarget(
  const RepoInfo(
    host: 'demo-db.firebaseio.com',
    namespace: 'demo-db',
    secure: true,
  ),
  useHeaders: useHeaders,
);

/// A production host reached over plain HTTP: tokens may not go there (threat model T3).
RealtimeTarget plainHttpTarget({bool useHeaders = true}) => RealtimeTarget(
  const RepoInfo(
    host: 'demo-db.firebaseio.com',
    namespace: 'demo-db',
    secure: false,
  ),
  useHeaders: useHeaders,
);

/// A default spec at [path].
ListenSpec defaultSpecAt(String path) => ListenSpec(
  path: path,
  queryObject: const <String, Object?>{},
  queryIdentifier: 'default',
  isDefault: true,
  loadsAllData: true,
  indexName: '.priority',
  restParams: const <String, String>{},
);

/// A request the [ScriptedServer] received.
final class ReceivedRequest {
  /// Records [request].
  ReceivedRequest(this.request);

  /// The request as sent by the client under test.
  final http.BaseRequest request;

  /// Its URL.
  Uri get url => request.url;
}

/// Answers the requests of a [MockClient] with [handler] and records them.
final class ScriptedServer {
  /// Creates the server; [handler] answers each request.
  ScriptedServer(this.handler);

  /// Creates a server answering every request with [status] and [body].
  ScriptedServer.always(int status, String body)
    : handler = ((http.BaseRequest _) async => respond(status, body));

  /// The answer of a request.
  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;

  /// The requests received, in order.
  final List<ReceivedRequest> received = <ReceivedRequest>[];

  /// The client to give to the RestClient.
  late final http.Client client = MockClient.streaming((
    http.BaseRequest request,
    http.ByteStream _,
  ) {
    received.add(ReceivedRequest(request));
    return handler(request);
  });
}

/// A response with [status] and the UTF-8 [body].
http.StreamedResponse respond(int status, String body) {
  final List<int> bytes = utf8.encode(body);
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    status,
    contentLength: bytes.length,
  );
}

/// A stream of [chunks] chunks of [chunkSize] bytes each that counts how many it produced
/// in [produced] (it stops producing when its listener cancels).
final class CountingBody {
  /// Creates the body.
  CountingBody({required this.chunks, required this.chunkSize});

  /// How many chunks the body holds.
  final int chunks;

  /// The size of each chunk.
  final int chunkSize;

  /// How many chunks were produced.
  int produced = 0;

  /// The body as a stream of `x` bytes.
  Stream<List<int>> get stream async* {
    for (int i = 0; i < chunks; i++) {
      produced++;
      yield List<int>.filled(chunkSize, 0x78);
    }
  }
}

/// A [RestClient] over [server] with the given tokens and limits. [useHeaders] false is the web
/// form (App Check in `ac`); it is also given to the default target.
RestClient restClientFor(
  ScriptedServer server, {
  required ServerActionsDelegate delegate,
  RealtimeTarget? target,
  RealtimeTokenSource? tokens,
  RecordingLogger? logger,
  int maxResponseBytes = 1 << 20,
  Duration requestTimeout = const Duration(seconds: 60),
  int maxJsonDepth = 64,
  bool useHeaders = true,
}) => RestClient(
  target: target ?? emulatorTarget(useHeaders: useHeaders),
  tokens: tokens ?? FixedTokenSource(),
  delegate: delegate,
  logger: logger?.call,
  httpClient: server.client,
  maxResponseBytes: maxResponseBytes,
  requestTimeout: requestTimeout,
  maxJsonDepth: maxJsonDepth,
  useHeaders: useHeaders,
);

/// The result of a listen, once it completes.
final class ListenResult {
  /// Status and data of the completion.
  ({String status, Object? data})? completion;

  /// The callback to pass as `onComplete`.
  void call(String status, Object? data) {
    if (completion != null) {
      throw StateError('onComplete called twice');
    }
    completion = (status: status, data: data);
  }
}

/// Waits until [condition] holds, pumping the event queue (at most [rounds] times).
Future<void> pumpUntil(bool Function() condition, {int rounds = 50}) async {
  for (int i = 0; i < rounds && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

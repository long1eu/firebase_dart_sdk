/// A small fake of the Installations and Remote Config routes for the `rc_unit` tests.
///
/// It uses no `dart:io`, so it runs on the VM and in browsers.
library;

import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// True when compiled to JavaScript or WebAssembly.
const bool isWebCompiled = bool.fromEnvironment('dart.library.js_interop');

/// The fixed clock of the tests that read times back from `info`.
final DateTime fixedNow = DateTime.utc(2026, 11, 28, 12);

/// One request that reached the fake.
final class RecordedRequest {
  /// Records [method], [url], [headers] (names in lower case) and the body bytes.
  RecordedRequest(this.method, this.url, this.headers, this.bodyBytes);

  /// The HTTP method.
  final String method;

  /// The full URL.
  final Uri url;

  /// The headers, with lower-case names.
  final Map<String, String> headers;

  /// The body as sent.
  final List<int> bodyBytes;

  /// The body as UTF-8 text.
  String get bodyText => utf8.decode(bodyBytes);

  /// The body as a JSON object.
  Map<String, Object?> get json => jsonDecode(bodyText) as Map<String, Object?>;

  /// True for the fetch route.
  bool get isFetch => url.path.endsWith('/namespaces/firebase:fetch');

  /// True for the realtime route.
  bool get isRealtime =>
      url.path.endsWith('/namespaces/firebase:streamFetchInvalidations');

  /// True for the Installations routes.
  bool get isInstallations => url.path.contains('/installations');
}

/// What the fake answers to a fetch.
final class FetchReply {
  /// A reply with [status], [headers] and [body].
  const FetchReply(this.status, this.body, {this.headers = const {}});

  /// A 200 with a template of [entries].
  factory FetchReply.template(
    Map<String, String> entries, {
    int? version,
    String? etag,
  }) {
    return FetchReply(
      200,
      jsonEncode(<String, Object?>{
        'entries': entries,
        'templateVersion': ?version?.toString(),
      }),
      headers: <String, String>{'etag': ?etag},
    );
  }

  /// The HTTP status.
  final int status;

  /// The body text.
  final String body;

  /// The response headers.
  final Map<String, String> headers;
}

int _counter = 0;

/// An app, an Installations instance and a store, all answered by one fake client.
final class RcUnitEnv {
  /// Creates the environment. Nothing is sent until a call needs the network.
  ///
  /// [installationsHeaders] are the restricted-key headers of Installations.
  RcUnitEnv({
    this.appId = '1:1234567890:web:0123456789abcdef',
    this.messagingSenderId,
    Map<String, String> installationsHeaders = const <String, String>{},
  }) {
    app = FirebaseApp.withOptions(
      FirebaseOptions(
        apiKey: 'A${'x' * 38}',
        appId: appId,
        projectId: 'rc-unit-project',
        messagingSenderId: messagingSenderId,
      ),
      name: 'rc-unit-${_counter++}',
    );
    client = MockClient.streaming(_handle);
    installations = FirebaseInstallations(
      app,
      store: store,
      httpClient: client,
      headers: installationsHeaders,
    );
  }

  /// The app id of the app.
  final String appId;

  /// The messaging sender id of the app, when it has one.
  final String? messagingSenderId;

  /// The store shared by Installations and every Remote Config of this environment.
  final MemoryKeyValueStore store = MemoryKeyValueStore();

  /// What the fetch route answers next.
  FetchReply fetchReply = FetchReply.template(
    <String, String>{'welcome': 'hello'},
    version: 3,
    etag: 'etag-abc',
  );

  /// Every request, in order.
  final List<RecordedRequest> requests = <RecordedRequest>[];

  /// The body of the realtime response; push text with [sendRealtime].
  final StreamController<List<int>> realtimeBody =
      StreamController<List<int>>();

  final Completer<RecordedRequest> _realtimeSeen = Completer<RecordedRequest>();
  final List<FirebaseRemoteConfig> _created = <FirebaseRemoteConfig>[];

  /// The app.
  late final FirebaseApp app;

  /// The HTTP client of the fake.
  late final http.Client client;

  /// The Installations instance.
  late final FirebaseInstallations installations;

  /// The fetch requests.
  List<RecordedRequest> get fetches =>
      requests.where((RecordedRequest r) => r.isFetch).toList();

  /// The Installations requests.
  List<RecordedRequest> get installationRequests =>
      requests.where((RecordedRequest r) => r.isInstallations).toList();

  /// The first realtime request, once it arrives.
  Future<RecordedRequest> get realtimeRequest =>
      _realtimeSeen.future.timeout(const Duration(seconds: 10));

  /// The store key of the record [name].
  String key(String name) => 'remote_config/${app.persistenceKey}/$name';

  /// A new Remote Config of the app; [dispose] closes it.
  FirebaseRemoteConfig newRemoteConfig({
    Map<String, Object> defaults = const <String, Object>{},
    String languageCode = 'en-US',
    DateTime Function()? clock,
    Duration minimumFetchInterval = const Duration(hours: 12),
    Future<void> Function(Duration duration)? delay,
  }) {
    final FirebaseRemoteConfig created = FirebaseRemoteConfig(
      app,
      installations: installations,
      defaults: defaults,
      languageCode: languageCode,
      httpClient: client,
      clock: clock,
      minimumFetchInterval: minimumFetchInterval,
      delay: delay,
    );
    _created.add(created);
    return created;
  }

  /// Sends [text] on the realtime stream.
  void sendRealtime(String text) => realtimeBody.add(utf8.encode(text));

  /// Closes everything this environment created.
  Future<void> dispose() async {
    for (final FirebaseRemoteConfig created in _created) {
      await created.close();
    }
    await installations.close();
    if (!realtimeBody.isClosed) {
      // close() completes only once a listener received the done event; a test that never opened the
      // realtime stream has no listener, so the future is not awaited.
      unawaited(realtimeBody.close());
    }
    await app.delete();
  }

  Future<http.StreamedResponse> _handle(
    http.BaseRequest request,
    http.ByteStream body,
  ) async {
    final List<int> bytes = await body.toBytes();
    final RecordedRequest recorded =
        RecordedRequest(request.method, request.url, <String, String>{
          for (final MapEntry<String, String> e in request.headers.entries)
            e.key.toLowerCase(): e.value,
        }, bytes);
    requests.add(recorded);
    if (recorded.isRealtime) {
      if (!_realtimeSeen.isCompleted) {
        _realtimeSeen.complete(recorded);
      }
      return http.StreamedResponse(realtimeBody.stream, 200);
    }
    if (recorded.isFetch) {
      final FetchReply reply = fetchReply;
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(reply.body)),
        reply.status,
        headers: reply.headers,
      );
    }
    final String path = request.url.path;
    final String answer = path.endsWith('authTokens:generate')
        ? jsonEncode(<String, Object?>{
            'token': 'auth-token-2',
            'expiresIn': '604800s',
          })
        : jsonEncode(<String, Object?>{
            'refreshToken': 'refresh-token-1',
            'authToken': <String, Object?>{
              'token': 'auth-token-1',
              'expiresIn': '604800s',
            },
          });
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(answer)),
      200,
    );
  }
}

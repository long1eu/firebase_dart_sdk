// Shared fixtures of the Remote Config security tests (test/security/). No dart:io, so the browser
// copy of numbers_test.dart can use it.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The refresh token the fake Installations server issues.
const String refreshTokenSentinel = 'SENTINELrefreshTOKEN0001';

/// The auth token the fake Installations server issues.
const String authTokenSentinel = 'SENTINELauthTOKEN0002';

/// An API key that passes the Installations format check (`^A[A-Za-z0-9_-]{38}$`).
const String apiKeySentinel = 'ASENTINELapiKEY0003xxxxxxxxxxxxxxxxxxxx';

/// The key of a custom signal.
const String signalKeySentinel = 'SENTINELsignalKEY0004';

/// The value of a custom signal.
const String signalValueSentinel = 'SENTINELsignalVALUE0005';

/// Every sentinel that must never appear in a message, a `toString` or a log line (5.11 rule 6).
const List<String> allSentinels = <String>[
  refreshTokenSentinel,
  authTokenSentinel,
  apiKeySentinel,
  signalKeySentinel,
  signalValueSentinel,
];

/// The project of the fixtures.
const String rcSecProjectId = 'rc-sec-project';

/// The project number in [rcSecAppId].
const String rcSecProjectNumber = '123456789';

/// An app id whose second field is the project number (5.9).
const String rcSecAppId = '1:$rcSecProjectNumber:web:0a1b2c3d4e5f';

/// The default origins of the fixtures.
final Uri rcSecFisOrigin = Uri.parse('https://fis.test');

/// The Remote Config fetch origin of the fixtures.
final Uri rcSecServerOrigin = Uri.parse('https://rc.test');

/// The realtime origin of the fixtures.
final Uri rcSecRealtimeOrigin = Uri.parse('https://realtime.test');

/// A fixed instant used by the fixtures that take a clock.
final DateTime rcSecNow = DateTime.utc(2026, 6, 1, 12);

/// One request the fake backend received.
final class RcSecCall {
  /// Records [request] with its [body].
  RcSecCall(this.request, this.body);

  /// The request, as the client sent it.
  final http.BaseRequest request;

  /// The request body.
  final Uint8List body;

  /// The request URL.
  Uri get url => request.url;

  /// The request body as text.
  String get bodyText => utf8.decode(body, allowMalformed: true);

  /// The abort trigger of an [http.Abortable] request.
  Future<void>? get abortTrigger {
    final http.BaseRequest request = this.request;
    return request is http.Abortable ? request.abortTrigger : null;
  }

  /// True for the Remote Config fetch.
  bool get isFetch =>
      url.pathSegments.isNotEmpty && url.pathSegments.last == 'firebase:fetch';

  /// True for the realtime stream.
  bool get isRealtime =>
      url.pathSegments.isNotEmpty &&
      url.pathSegments.last == 'firebase:streamFetchInvalidations';

  /// True for an Installations call.
  bool get isInstallations => url.pathSegments.contains('installations');

  /// Every header value and the body, joined, for searching.
  String get everything => <String>[
    url.toString(),
    for (final MapEntry<String, String> header in request.headers.entries)
      '${header.key}: ${header.value}',
    bodyText,
  ].join('\n');
}

/// Answers one request.
typedef RcSecHandler = FutureOr<http.StreamedResponse> Function(RcSecCall call);

/// A `MockClient` backend for Installations, fetch and realtime, with recorded requests.
///
/// `MockClient` does not abort by itself; every body this backend returns honours the request's
/// `abortTrigger` (see [abortable]).
final class RcSecBackend {
  /// Creates a backend; handlers left null answer as a healthy server would.
  RcSecBackend({this.onFetch, this.onRealtime, this.onInstallations});

  /// Answers fetch requests; default: [templateResponse].
  RcSecHandler? onFetch;

  /// Answers realtime requests; default: an open, silent stream.
  RcSecHandler? onRealtime;

  /// Answers Installations requests; default: [installationsResponse].
  RcSecHandler? onInstallations;

  /// The `expiresIn` of the token returned by the create call.
  String createExpiresIn = '604800s';

  /// Every request received, in order.
  final List<RcSecCall> calls = <RcSecCall>[];

  /// The fetch requests.
  List<RcSecCall> get fetchCalls =>
      calls.where((RcSecCall call) => call.isFetch).toList();

  /// The realtime requests.
  List<RcSecCall> get realtimeCalls =>
      calls.where((RcSecCall call) => call.isRealtime).toList();

  /// The client to give to Installations and Remote Config.
  late final http.Client client = MockClient.streaming(_handle);

  Future<http.StreamedResponse> _handle(
    http.BaseRequest request,
    http.ByteStream body,
  ) async {
    final RcSecCall call = RcSecCall(request, await body.toBytes());
    calls.add(call);
    if (call.isFetch) {
      return (onFetch ?? (RcSecCall call) => templateResponse(call))(call);
    }
    if (call.isRealtime) {
      return (onRealtime ?? silentStream)(call);
    }
    if (call.isInstallations) {
      return (onInstallations ?? installationsResponse)(call);
    }
    return jsonResponse(call, 404, <String, Object?>{});
  }

  /// The healthy Installations answers: create echoes the FID, generate returns a token.
  http.StreamedResponse installationsResponse(RcSecCall call) {
    if (call.url.pathSegments.last == 'authTokens:generate') {
      return jsonResponse(call, 200, <String, Object?>{
        'token': authTokenSentinel,
        'expiresIn': '604800s',
      });
    }
    if (call.request.method == 'POST') {
      final Object? fid =
          (jsonDecode(call.bodyText) as Map<String, Object?>)['fid'];
      return jsonResponse(call, 200, <String, Object?>{
        'name': 'projects/$rcSecProjectId/installations/$fid',
        'fid': fid,
        'refreshToken': refreshTokenSentinel,
        'authToken': <String, Object?>{
          'token': authTokenSentinel,
          'expiresIn': createExpiresIn,
        },
      });
    }
    return jsonResponse(call, 200, <String, Object?>{});
  }
}

/// A response with [json] as its body.
http.StreamedResponse jsonResponse(
  RcSecCall call,
  int status,
  Object? json, {
  Map<String, String> headers = const <String, String>{},
}) => bytesResponse(
  call,
  status,
  utf8.encode(jsonEncode(json)),
  headers: headers,
);

/// A response with [text] as its body.
http.StreamedResponse textResponse(
  RcSecCall call,
  int status,
  String text, {
  Map<String, String> headers = const <String, String>{},
}) => bytesResponse(call, status, utf8.encode(text), headers: headers);

/// A response with [bytes] as its body, delivered in chunks of 64 KiB.
http.StreamedResponse bytesResponse(
  RcSecCall call,
  int status,
  List<int> bytes, {
  Map<String, String> headers = const <String, String>{},
}) {
  return http.StreamedResponse(
    abortable(call, _chunked(bytes)),
    status,
    headers: <String, String>{'content-type': 'application/json', ...headers},
    request: call.request,
  );
}

Stream<List<int>> _chunked(List<int> bytes) async* {
  const int size = 64 * 1024;
  for (int start = 0; start < bytes.length; start += size) {
    final int end = start + size < bytes.length ? start + size : bytes.length;
    yield bytes.sublist(start, end);
  }
}

/// A 200 template: `UPDATE` with [entries] and [version].
http.StreamedResponse templateResponse(
  RcSecCall call, {
  Map<String, String> entries = const <String, String>{'k': 'remote'},
  Object? version = '1',
  Map<String, String> headers = const <String, String>{},
}) {
  return jsonResponse(call, 200, <String, Object?>{
    'state': 'UPDATE',
    'entries': entries,
    'templateVersion': ?version,
  }, headers: headers);
}

/// A 200 realtime response that stays open and sends nothing until aborted.
http.StreamedResponse silentStream(RcSecCall call) => http.StreamedResponse(
  abortable(call, StreamController<List<int>>().stream),
  200,
  request: call.request,
);

/// A response that never arrives; it fails with `RequestAbortedException` when the request is aborted.
Future<http.StreamedResponse> pendingResponse(RcSecCall call) {
  final Future<void>? trigger = call.abortTrigger;
  if (trigger == null) {
    return Completer<http.StreamedResponse>().future;
  }
  return trigger.then<http.StreamedResponse>(
    (void _) => throw http.RequestAbortedException(call.url),
  );
}

/// [source] wrapped so that the request's abort trigger ends it with `RequestAbortedException` and
/// cancels [source], as `IOClient` and `BrowserClient` do.
Stream<List<int>> abortable(RcSecCall call, Stream<List<int>> source) {
  final Future<void>? trigger = call.abortTrigger;
  if (trigger == null) {
    return source;
  }
  late final StreamController<List<int>> controller;
  StreamSubscription<List<int>>? subscription;
  bool done = false;
  controller = StreamController<List<int>>(
    onListen: () {
      subscription = source.listen(
        controller.add,
        onError: controller.addError,
        onDone: () {
          if (!done) {
            done = true;
            unawaited(controller.close());
          }
        },
      );
      unawaited(
        trigger.then((void _) {
          if (done) {
            return;
          }
          done = true;
          unawaited(subscription?.cancel());
          controller.addError(http.RequestAbortedException(call.url));
          unawaited(controller.close());
        }),
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () {
      done = true;
      // Not returned: after the source finished, its cancel() future belongs to the root zone, and the
      // controller would hold its done event until that future completes, which fakeAsync never runs.
      unawaited(subscription?.cancel());
    },
  );
  return controller.stream;
}

/// An endless body that counts the bytes it handed out and notices when its reader cancels.
final class EndlessBody {
  /// A body of [prefix] then [chunk] repeated forever.
  EndlessBody(this.chunk, {this.prefix});

  /// The repeated chunk.
  final List<int> chunk;

  /// Sent once before the first chunk.
  final List<int>? prefix;

  /// The bytes handed to the reader so far.
  int emitted = 0;

  /// True once the reader cancelled (the client stopped reading).
  bool cancelled = false;

  /// The body; listen once.
  Stream<List<int>> stream() async* {
    try {
      final List<int>? prefix = this.prefix;
      if (prefix != null) {
        emitted += prefix.length;
        yield prefix;
      }
      while (true) {
        // A turn of the event loop per chunk, so the reader can cancel.
        await Future<void>.delayed(Duration.zero);
        emitted += chunk.length;
        yield chunk;
      }
    } finally {
      cancelled = true;
    }
  }

  /// A response with this body.
  http.StreamedResponse response(RcSecCall call, int status) =>
      http.StreamedResponse(
        abortable(call, stream()),
        status,
        request: call.request,
      );
}

/// A store over [MemoryKeyValueStore] whose writes of Remote Config keys can be made to fail.
final class RcSecFlakyStore implements KeyValueStore {
  /// Creates a store that fails when [failRemoteConfigWrites] is set, throwing [error].
  RcSecFlakyStore({required this.error});

  final MemoryKeyValueStore _inner = MemoryKeyValueStore();

  /// Builds the error a failing call throws.
  final Exception Function() error;

  /// When true, `write` and `update` of `remote_config/` keys throw.
  bool failRemoteConfigWrites = false;

  bool _fails(String key) =>
      failRemoteConfigWrites && key.startsWith('remote_config/');

  @override
  Future<String?> read(String key) => _inner.read(key);

  @override
  Future<void> write(String key, String? value) async {
    if (_fails(key)) {
      throw error();
    }
    await _inner.write(key, value);
  }

  @override
  Future<String?> update(
    String key,
    String? Function(String? current) transform,
  ) async {
    if (_fails(key)) {
      throw error();
    }
    return _inner.update(key, transform);
  }

  @override
  Stream<String> get changes => _inner.changes;

  @override
  Future<void> close() => _inner.close();
}

/// An app, its Installations and a Remote Config instance over one backend.
final class RcSecFixture {
  RcSecFixture._(
    this.app,
    this.store,
    this.installations,
    this.remoteConfig,
    this.logs,
  );

  static int _apps = 0;

  /// The app.
  final FirebaseApp app;

  /// The store shared by Installations and Remote Config.
  final KeyValueStore store;

  /// The Installations instance.
  final FirebaseInstallations installations;

  /// The instance under test.
  final FirebaseRemoteConfig remoteConfig;

  /// Every log line of both packages, as `level: message`.
  final List<String> logs;

  /// Creates the app (named [name], else a fresh name), writes [seed] (record name → stored text) into
  /// [store] under the Remote Config keys of the app, then creates Installations and Remote Config.
  static Future<RcSecFixture> open({
    http.Client? client,
    RcSecBackend? backend,
    KeyValueStore? store,
    String? name,
    String appId = rcSecAppId,
    String? messagingSenderId,
    Map<String, String> seed = const <String, String>{},
    Map<String, Object> defaults = const <String, Object>{'k': 'default'},
    Map<String, String> headers = const <String, String>{},
    Uri? fisOrigin,
    Uri? serverOrigin,
    Uri? realtimeOrigin,
    DateTime Function()? clock,
    Duration fetchTimeout = const Duration(seconds: 60),
  }) async {
    final FirebaseApp app = FirebaseApp.withOptions(
      FirebaseOptions(
        apiKey: apiKeySentinel,
        appId: appId,
        projectId: rcSecProjectId,
        messagingSenderId: messagingSenderId,
      ),
      name: name ?? 'rc-sec-${_apps++}',
    );
    final KeyValueStore kv = store ?? MemoryKeyValueStore();
    for (final MapEntry<String, String> entry in seed.entries) {
      await kv.write(recordKey(app, entry.key), entry.value);
    }
    final List<String> logs = <String>[];
    final http.Client httpClient = client ?? backend!.client;
    final FirebaseInstallations installations = FirebaseInstallations(
      app,
      store: kv,
      headers: headers,
      httpClient: httpClient,
      serverOrigin: fisOrigin ?? rcSecFisOrigin,
      logger: (InstallationsLogLevel level, String message) =>
          logs.add('${level.name}: $message'),
      clock: clock,
      random: () => 0,
      delay: (Duration _) async {},
    );
    final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig(
      app,
      installations: installations,
      defaults: defaults,
      fetchTimeout: fetchTimeout,
      languageCode: 'en-US',
      httpClient: httpClient,
      logger: (RemoteConfigLogLevel level, String message) =>
          logs.add('${level.name}: $message'),
      serverOrigin: serverOrigin ?? rcSecServerOrigin,
      realtimeOrigin: realtimeOrigin ?? rcSecRealtimeOrigin,
      clock: clock,
      random: () => 0,
      delay: (Duration _) async {},
    );
    return RcSecFixture._(app, kv, installations, remoteConfig, logs);
  }

  /// The store key of the Remote Config record [name] (5.10).
  static String recordKey(FirebaseApp app, String name) =>
      'remote_config/${app.persistenceKey}/$name';

  /// The store key of this fixture's record [name].
  String key(String name) => recordKey(app, name);

  /// Closes Remote Config and Installations and deletes the app.
  Future<void> dispose() async {
    await remoteConfig.close();
    await installations.close();
    await app.delete();
  }
}

/// Runs [action] and returns what it threw; fails the test when it completes.
Future<Object> thrownBy(Future<Object?> Function() action) async {
  try {
    await action();
  } catch (error) {
    return error;
  }
  throw StateError('Expected the call to throw; it completed.');
}

/// [action]'s error as a [FirebaseRemoteConfigException]; fails the test for anything else.
Future<FirebaseRemoteConfigException> rcErrorOf(
  Future<Object?> Function() action,
) async {
  final Object error = await thrownBy(action);
  if (error is FirebaseRemoteConfigException) {
    return error;
  }
  throw StateError(
    'Expected a FirebaseRemoteConfigException, got ${error.runtimeType}.',
  );
}

/// Waits (polling, real time) until [condition] holds, failing after [timeout].
Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String reason = 'condition',
}) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      throw TimeoutException('Timed out waiting for $reason', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Listens to `onConfigUpdated` and collects its events and errors until [cancel].
final class RealtimeProbe {
  /// Starts listening to [remoteConfig].
  RealtimeProbe(FirebaseRemoteConfig remoteConfig) {
    _subscription = remoteConfig.onConfigUpdated.listen(
      updates.add,
      onError: (Object error) => errors.add(error),
      onDone: () => done = true,
    );
  }

  late final StreamSubscription<RemoteConfigUpdate> _subscription;

  /// Updates received.
  final List<RemoteConfigUpdate> updates = <RemoteConfigUpdate>[];

  /// Errors received.
  final List<Object> errors = <Object>[];

  /// True once the stream ended.
  bool done = false;

  /// Waits for the first error and returns it as a [FirebaseRemoteConfigException].
  Future<FirebaseRemoteConfigException> firstError() async {
    await waitUntil(() => errors.isNotEmpty, reason: 'a realtime error');
    return errors.first as FirebaseRemoteConfigException;
  }

  /// Stops listening.
  Future<void> cancel() => _subscription.cancel();
}

/// Text of [length] UTF-8 bytes of JSON: `{"v":1, ...fields, "pad":"aaa…"}`.
String paddedJson(Map<String, Object?> fields, int length) {
  final String base = jsonEncode(<String, Object?>{...fields, 'pad': ''});
  final int missing = length - utf8.encode(base).length;
  if (missing < 0) {
    throw ArgumentError('The fields alone are longer than $length bytes.');
  }
  return jsonEncode(<String, Object?>{...fields, 'pad': 'a' * missing});
}

/// [depth] nested JSON arrays: `[[…]]`.
String nestedArrays(int depth) => '${'[' * depth}${']' * depth}';

/// Fakes shared by the Remote Config tests (spec 11.7, infrastructure row).
///
/// * [FakeBackend]: a `MockClient` that routes the Installations and Remote Config requests
///   ([FakeRoute]), records each one ([RecordedRequest]) and answers from per-route queues of
///   [FakeAnswer]s, else from a default (Installations routes succeed; fetch and realtime fail with a
///   transport error and are listed in [FakeBackend.unscripted]).
/// * [FakeAnswer]: JSON, bytes, error statuses, Remote Config fetch bodies (with an `ETag` header),
///   Installations bodies, transport errors, answers that wait for a gate, answers that never come
///   (until the request is aborted), and streamed realtime bodies ([FakeStreamBody]).
/// * Every waiting answer and every [FakeStreamBody] honours the request's `abortTrigger` as
///   `IOClient` does: before the headers `send` throws `RequestAbortedException`; during the body the
///   stream emits it and closes.
/// * [ScriptedStore]: a [KeyValueStore] whose calls can be delayed or failed.
/// * [RcEnv]: an app with a unique name, an Installations instance and Remote Config instances over one
///   backend and store, with an injectable clock.
/// * [FakeAsyncSettle]: waits for a future inside `fakeAsync` without moving the clock.
///
/// ```dart
/// fakeAsync((FakeAsync async) {
///   final DateTime start = DateTime.utc(2026, 11, 28, 12);
///   final RcEnv env = async.settle(RcEnv.create(clock: () => start.add(async.elapsed)));
///   env.backend.enqueue(FakeRoute.fetch, FakeAnswer.fetch(entries: {'a': '1'}, etag: 'e1'));
///   expect(async.settle(env.remoteConfig.fetch()), FetchResult.updated);
///   async.settle(env.dispose());
/// });
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// An API key of the shape Installations checks (`^A[A-Za-z0-9_-]{38}$`).
const String fakeApiKey = 'AIzaSyFakeKey_0123456789-abcdefghijklmn';

/// The project id of [fakeOptions].
const String fakeProjectId = 'demo-rc-test';

/// The project number of [fakeOptions] (the second field of [fakeAppId], and the sender id).
const String fakeProjectNumber = '1234567890';

/// The app id of [fakeOptions].
const String fakeAppId = '1:$fakeProjectNumber:web:0123456789abcdef';

/// Options that pass the checks of Installations and Remote Config.
const FirebaseOptions fakeOptions = FirebaseOptions(
  apiKey: fakeApiKey,
  appId: fakeAppId,
  projectId: fakeProjectId,
  messagingSenderId: fakeProjectNumber,
);

/// The refresh token the default Installations create answer hands out.
const String fakeRefreshToken = 'fake-refresh-token';

/// The routes the backend tells apart, by method and path.
enum FakeRoute {
  /// `POST /v1/projects/{project}/installations`.
  installationsCreate,

  /// `POST /v1/projects/{project}/installations/{fid}/authTokens:generate`.
  installationsGenerate,

  /// `DELETE /v1/projects/{project}/installations/{fid}`.
  installationsDelete,

  /// `POST /v1/projects/{project}/namespaces/firebase:fetch`.
  fetch,

  /// `POST /v1/projects/{project}/namespaces/firebase:streamFetchInvalidations`.
  realtime,

  /// Anything else.
  unknown,
}

/// The [FakeRoute] of a request with [method] to [url].
FakeRoute routeOf(String method, Uri url) {
  final List<String> segments = url.pathSegments;
  if (segments.length < 4 || segments[0] != 'v1' || segments[1] != 'projects') {
    return FakeRoute.unknown;
  }
  final List<String> rest = segments.sublist(3);
  if (rest.first == 'installations') {
    if (rest.length == 1 && method == 'POST') {
      return FakeRoute.installationsCreate;
    }
    if (rest.length == 3 && rest[2] == 'authTokens:generate') {
      return FakeRoute.installationsGenerate;
    }
    if (rest.length == 2 && method == 'DELETE') {
      return FakeRoute.installationsDelete;
    }
  }
  if (rest.length == 2 && rest[0] == 'namespaces') {
    if (rest[1] == 'firebase:fetch') {
      return FakeRoute.fetch;
    }
    if (rest[1] == 'firebase:streamFetchInvalidations') {
      return FakeRoute.realtime;
    }
  }
  return FakeRoute.unknown;
}

/// One request the backend received.
final class RecordedRequest {
  RecordedRequest._({
    required this.route,
    required this.method,
    required this.url,
    required this.headers,
    required this.bodyBytes,
    required this.followRedirects,
    required this.abortTrigger,
  }) {
    abortTrigger?.then<void>((void _) => _aborted = true);
  }

  /// The route of the request.
  final FakeRoute route;

  /// The HTTP method.
  final String method;

  /// The full URL.
  final Uri url;

  /// The headers, names in lowercase.
  final Map<String, String> headers;

  /// The body as sent.
  final Uint8List bodyBytes;

  /// The request's `followRedirects` (the clients set it to false).
  final bool followRedirects;

  /// The request's `abortTrigger`, when it is an `AbortableRequest`.
  final Future<void>? abortTrigger;

  bool _aborted = false;

  /// True once the client completed [abortTrigger].
  bool get aborted => _aborted;

  /// The body as UTF-8 text.
  String get body => utf8.decode(bodyBytes);

  /// The body decoded as a JSON object; throws when it is not one.
  Map<String, Object?> get json => jsonDecode(body) as Map<String, Object?>;

  @override
  String toString() => 'RecordedRequest($method ${url.path})';
}

/// Produces the response to one request.
typedef FakeResponder =
    Future<http.StreamedResponse> Function(RecordedRequest request);

/// A scripted answer. The named constructors cover the usual answers; [FakeAnswer.new] takes any
/// [FakeResponder].
final class FakeAnswer {
  /// An answer computed by [respond].
  const FakeAnswer(this.respond);

  /// A JSON [body] (encoded with `jsonEncode`) with [status].
  factory FakeAnswer.json(
    Object? body, {
    int status = 200,
    Map<String, String> headers = const <String, String>{},
  }) => FakeAnswer.bytes(
    utf8.encode(jsonEncode(body)),
    status: status,
    headers: <String, String>{'content-type': 'application/json', ...headers},
  );

  /// A text [body] with [status], as UTF-8.
  factory FakeAnswer.text(
    String body, {
    int status = 200,
    Map<String, String> headers = const <String, String>{},
  }) => FakeAnswer.bytes(utf8.encode(body), status: status, headers: headers);

  /// A raw [body] with [status].
  factory FakeAnswer.bytes(
    List<int> body, {
    int status = 200,
    Map<String, String> headers = const <String, String>{},
  }) => FakeAnswer(
    (RecordedRequest request) async =>
        _response(status, headers, Stream<List<int>>.value(body)),
  );

  /// A Google error body `{"error": {"code", "status", "message"}}` with [status].
  factory FakeAnswer.status(
    int status, {
    String serverStatus = 'FAKE_STATUS',
    String message = 'fake server message',
    Map<String, String> headers = const <String, String>{},
  }) => FakeAnswer.json(
    <String, Object?>{
      'error': <String, Object?>{
        'code': status,
        'status': serverStatus,
        'message': message,
      },
    },
    status: status,
    headers: headers,
  );

  /// A Remote Config fetch answer. Fields that are null are left out of the body; [etag] becomes the
  /// `ETag` header; [extra] is merged into the body (metadata, or fields that override the others).
  factory FakeAnswer.fetch({
    String? state = 'UPDATE',
    Map<String, String>? entries,
    Object? templateVersion,
    String? etag,
    Map<String, Object?> extra = const <String, Object?>{},
    int status = 200,
  }) => FakeAnswer.json(
    <String, Object?>{
      'state': ?state,
      'entries': ?entries,
      'templateVersion': ?templateVersion,
      ...extra,
    },
    status: status,
    headers: <String, String>{'etag': ?etag},
  );

  /// An Installations create answer. A null [fid] echoes the FID of the request; [token] defaults to a
  /// new `fake-auth-token-<n>`.
  factory FakeAnswer.installationsCreate({
    String? fid,
    String refreshToken = fakeRefreshToken,
    String? token,
    String expiresIn = '604800s',
  }) => FakeAnswer((RecordedRequest request) async {
    final String id = fid ?? request.json['fid']! as String;
    return _jsonResponse(<String, Object?>{
      'name': 'projects/$fakeProjectId/installations/$id',
      'fid': id,
      'refreshToken': refreshToken,
      'authToken': <String, Object?>{
        'token': token ?? _nextToken(),
        'expiresIn': expiresIn,
      },
    });
  });

  /// An Installations generate answer; [token] defaults to a new `fake-auth-token-<n>`.
  factory FakeAnswer.installationsToken({
    String? token,
    String expiresIn = '604800s',
  }) => FakeAnswer(
    (RecordedRequest request) async => _jsonResponse(<String, Object?>{
      'token': token ?? _nextToken(),
      'expiresIn': expiresIn,
    }),
  );

  /// A streamed body (realtime). [body] serves one request.
  factory FakeAnswer.stream(
    FakeStreamBody body, {
    int status = 200,
    Map<String, String> headers = const <String, String>{},
  }) => FakeAnswer((RecordedRequest request) async {
    body._attach(request);
    return _response(status, headers, body._controller.stream);
  });

  /// `send` throws [error] (default: a `ClientException`), as a refused connection does.
  factory FakeAnswer.transportError([Exception? error]) => FakeAnswer(
    (RecordedRequest request) async =>
        throw error ?? http.ClientException('fake connection refused'),
  );

  /// No answer until the request is aborted; then `send` throws `RequestAbortedException`. Without an
  /// `abortTrigger` it never answers.
  factory FakeAnswer.hang() => FakeAnswer((RecordedRequest request) async {
    await _waitOrAbort(Completer<void>().future, request);
    throw StateError('unreachable');
  });

  /// Produces the response for one request.
  final FakeResponder respond;

  /// This answer, sent once [gate] completes. An abort first makes `send` throw
  /// `RequestAbortedException`.
  FakeAnswer after(Future<void> gate) =>
      FakeAnswer((RecordedRequest request) async {
        await _waitOrAbort(gate, request);
        return respond(request);
      });

  static int _tokens = 0;

  static String _nextToken() => 'fake-auth-token-${++_tokens}';

  static http.StreamedResponse _jsonResponse(Object? body) => _response(
    200,
    const <String, String>{'content-type': 'application/json'},
    Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
  );

  static http.StreamedResponse _response(
    int status,
    Map<String, String> headers,
    Stream<List<int>> body,
  ) => http.StreamedResponse(
    body,
    status,
    headers: <String, String>{
      for (final MapEntry<String, String> header in headers.entries)
        header.key.toLowerCase(): header.value,
    },
  );

  static Future<void> _waitOrAbort(
    Future<void> gate,
    RecordedRequest request,
  ) async {
    final Future<void>? abort = request.abortTrigger;
    if (abort == null) {
      return gate;
    }
    bool aborted = false;
    await Future.any(<Future<void>>[
      gate,
      abort.then<void>((void _) => aborted = true),
    ]);
    if (aborted) {
      throw http.RequestAbortedException(request.url);
    }
  }
}

/// A response body the test writes while the client reads it (realtime). It serves one request.
///
/// When the request's `abortTrigger` completes, the body emits `RequestAbortedException` and closes,
/// as `IOClient` does, and [aborted] completes.
final class FakeStreamBody {
  /// An empty open body.
  FakeStreamBody() {
    _controller.onCancel = () => _cancelled = true;
  }

  final StreamController<List<int>> _controller = StreamController<List<int>>();
  final Completer<void> _aborted = Completer<void>();
  bool _cancelled = false;
  bool _wroteMessage = false;

  /// Sends [text] as one UTF-8 chunk.
  void addText(String text) => addBytes(utf8.encode(text));

  /// Sends [bytes] as one chunk. Ignored once the body is closed.
  void addBytes(List<int> bytes) {
    if (!_controller.isClosed) {
      _controller.add(bytes);
    }
  }

  /// Sends [message] in the server's shape (appendix A): `[` before the first message, `,` before the
  /// others, each pretty-printed and followed by a newline, in one chunk.
  void addMessage(Map<String, Object?> message) {
    final String prefix = _wroteMessage ? ',' : '[';
    _wroteMessage = true;
    addText('$prefix${const JsonEncoder.withIndent('  ').convert(message)}\n');
  }

  /// Makes the body fail with [error] (a broken connection).
  void addError(Object error) {
    if (!_controller.isClosed) {
      _controller.addError(error);
    }
  }

  /// Ends the body cleanly. Add `]` first for the server's shape.
  void close() {
    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
  }

  /// Completes when the client aborts the request.
  Future<void> get aborted => _aborted.future;

  /// True once the client aborted the request.
  bool get isAborted => _aborted.isCompleted;

  /// True once the client stopped listening to the body.
  bool get isCancelled => _cancelled;

  /// True once the body ended (closed, aborted).
  bool get isClosed => _controller.isClosed;

  /// True while the client listens to the body.
  bool get hasListener => _controller.hasListener;

  void _attach(RecordedRequest request) {
    request.abortTrigger?.then<void>((void _) {
      if (!_aborted.isCompleted) {
        _aborted.complete();
      }
      if (!_controller.isClosed) {
        _controller.addError(http.RequestAbortedException(request.url));
        unawaited(_controller.close());
      }
    });
  }
}

/// A `MockClient` for the Installations and Remote Config routes with recorded requests and scripted
/// answers.
///
/// Answers come from the queue of the request's route ([enqueue]), else from the route's default
/// ([setDefault]). Defaults: Installations create echoes the FID with a new token, generate returns a
/// new token, delete returns 200; fetch, realtime and unknown routes throw a `ClientException` and are
/// added to [unscripted].
final class FakeBackend {
  /// A backend with the defaults above.
  FakeBackend() {
    client = MockClient.streaming(_handle);
  }

  /// The client to give to `FirebaseInstallations` and `FirebaseRemoteConfig`.
  late final http.Client client;

  /// Every request, in arrival order.
  final List<RecordedRequest> requests = <RecordedRequest>[];

  /// Requests that found no scripted answer and no default.
  final List<RecordedRequest> unscripted = <RecordedRequest>[];

  final Map<FakeRoute, List<FakeAnswer>> _queues =
      <FakeRoute, List<FakeAnswer>>{};
  final Map<FakeRoute, FakeAnswer> _defaults = <FakeRoute, FakeAnswer>{
    FakeRoute.installationsCreate: FakeAnswer.installationsCreate(),
    FakeRoute.installationsGenerate: FakeAnswer.installationsToken(),
    FakeRoute.installationsDelete: FakeAnswer.json(<String, Object?>{}),
  };

  /// The recorded requests of [route], in arrival order.
  List<RecordedRequest> requestsTo(FakeRoute route) => <RecordedRequest>[
    for (final RecordedRequest request in requests)
      if (request.route == route) request,
  ];

  /// Adds [answer] to the queue of [route], [times] times.
  void enqueue(FakeRoute route, FakeAnswer answer, {int times = 1}) {
    final List<FakeAnswer> queue = _queues.putIfAbsent(
      route,
      () => <FakeAnswer>[],
    );
    for (int i = 0; i < times; i++) {
      queue.add(answer);
    }
  }

  /// Answers of [route] still queued.
  int pending(FakeRoute route) => _queues[route]?.length ?? 0;

  /// Makes [answer] the answer of [route] when its queue is empty; null restores "unscripted".
  void setDefault(FakeRoute route, FakeAnswer? answer) {
    if (answer == null) {
      _defaults.remove(route);
    } else {
      _defaults[route] = answer;
    }
  }

  /// Forgets the recorded requests (queues and defaults stay).
  void clearRequests() {
    requests.clear();
    unscripted.clear();
  }

  Future<http.StreamedResponse> _handle(
    http.BaseRequest request,
    http.ByteStream bodyStream,
  ) async {
    final Uint8List body = await bodyStream.toBytes();
    final RecordedRequest recorded = RecordedRequest._(
      route: routeOf(request.method, request.url),
      method: request.method,
      url: request.url,
      headers: <String, String>{
        for (final MapEntry<String, String> header in request.headers.entries)
          header.key.toLowerCase(): header.value,
      },
      bodyBytes: body,
      followRedirects: request.followRedirects,
      abortTrigger: request is http.Abortable ? request.abortTrigger : null,
    );
    requests.add(recorded);
    final List<FakeAnswer>? queue = _queues[recorded.route];
    final FakeAnswer? answer = queue != null && queue.isNotEmpty
        ? queue.removeAt(0)
        : _defaults[recorded.route];
    if (answer == null) {
      unscripted.add(recorded);
      throw http.ClientException(
        'FakeBackend: no answer scripted for ${recorded.route.name}',
        request.url,
      );
    }
    return answer.respond(recorded);
  }
}

/// The store operations [ScriptedStore.before] sees.
enum StoreOp {
  /// [KeyValueStore.read].
  read,

  /// [KeyValueStore.write].
  write,

  /// [KeyValueStore.update].
  update,
}

/// A [KeyValueStore] over [inner] (a [MemoryKeyValueStore] by default) whose calls pass through
/// [before] first: when it throws, the call fails with that error and changes nothing; when it returns
/// a future, the call waits for it.
final class ScriptedStore implements KeyValueStore {
  /// A store over [inner].
  ScriptedStore([KeyValueStore? inner])
    : inner = inner ?? MemoryKeyValueStore();

  /// The store that keeps the values.
  final KeyValueStore inner;

  /// Runs before each call with its operation and key. Null lets every call through.
  FutureOr<void> Function(StoreOp op, String key)? before;

  @override
  Future<String?> read(String key) async {
    await before?.call(StoreOp.read, key);
    return inner.read(key);
  }

  @override
  Future<void> write(String key, String? value) async {
    await before?.call(StoreOp.write, key);
    return inner.write(key, value);
  }

  @override
  Future<String?> update(
    String key,
    String? Function(String? current) transform,
  ) async {
    await before?.call(StoreOp.update, key);
    return inner.update(key, transform);
  }

  @override
  Stream<String> get changes => inner.changes;

  @override
  Future<void> close() => inner.close();
}

/// An app, an Installations instance and Remote Config instances over one [FakeBackend] and one store.
final class RcEnv {
  RcEnv._({
    required this.backend,
    required this.store,
    required this.app,
    required this.installations,
    required this.clock,
  });

  static int _apps = 0;

  /// Creates the app (unique name, [options]), the Installations instance over [store] (a
  /// [MemoryKeyValueStore] by default) and [remoteConfig].
  ///
  /// With [register] (the default) the installation is registered first (one create request), so
  /// creating the FID does not mark the first fetch stale (5.5) and the token is ready. [clock] (default
  /// `DateTime.now`) is given to both instances; inside `fakeAsync` pass
  /// `() => start.add(async.elapsed)`. The other arguments are those of `FirebaseRemoteConfig`;
  /// [languageCode] defaults to `en-US` so requests do not depend on the machine (pass null for the
  /// derived language).
  static Future<RcEnv> create({
    FakeBackend? backend,
    KeyValueStore? store,
    DateTime Function()? clock,
    bool register = true,
    FirebaseOptions options = fakeOptions,
    Map<String, Object> defaults = const <String, Object>{},
    Duration minimumFetchInterval = const Duration(hours: 12),
    Duration fetchTimeout = const Duration(seconds: 60),
    String? languageCode = 'en-US',
    double Function()? random,
    Future<void> Function(Duration duration)? delay,
    RemoteConfigLogger? logger,
  }) async {
    final FakeBackend server = backend ?? FakeBackend();
    final KeyValueStore keyValueStore = store ?? MemoryKeyValueStore();
    final DateTime Function() now = clock ?? DateTime.now;
    final FirebaseApp app = FirebaseApp.withOptions(
      options,
      name: 'rc-test-${_apps++}',
    );
    final FirebaseInstallations installations = FirebaseInstallations(
      app,
      store: keyValueStore,
      httpClient: server.client,
      clock: now,
      delay: delay,
    );
    if (register) {
      await installations.getIdAndToken();
    }
    final RcEnv env = RcEnv._(
      backend: server,
      store: keyValueStore,
      app: app,
      installations: installations,
      clock: now,
    );
    env.remoteConfig = env.newRemoteConfig(
      defaults: defaults,
      minimumFetchInterval: minimumFetchInterval,
      fetchTimeout: fetchTimeout,
      languageCode: languageCode,
      random: random,
      delay: delay,
      logger: logger,
    );
    return env;
  }

  /// The backend every instance talks to.
  final FakeBackend backend;

  /// The store of [installations] and of every Remote Config instance.
  final KeyValueStore store;

  /// The app; [dispose] deletes it.
  final FirebaseApp app;

  /// The Installations instance.
  final FirebaseInstallations installations;

  /// The clock given to [installations] and, unless overridden, to each Remote Config instance.
  final DateTime Function() clock;

  /// The first Remote Config instance.
  late final FirebaseRemoteConfig remoteConfig;

  final List<FirebaseRemoteConfig> _instances = <FirebaseRemoteConfig>[];

  /// Another Remote Config instance on the same app, Installations instance and store (another
  /// "process" sharing the records). [dispose] closes it.
  FirebaseRemoteConfig newRemoteConfig({
    DateTime Function()? clock,
    Map<String, Object> defaults = const <String, Object>{},
    Duration minimumFetchInterval = const Duration(hours: 12),
    Duration fetchTimeout = const Duration(seconds: 60),
    String? languageCode = 'en-US',
    double Function()? random,
    Future<void> Function(Duration duration)? delay,
    RemoteConfigLogger? logger,
  }) {
    final FirebaseRemoteConfig instance = FirebaseRemoteConfig(
      app,
      installations: installations,
      defaults: defaults,
      minimumFetchInterval: minimumFetchInterval,
      fetchTimeout: fetchTimeout,
      languageCode: languageCode,
      httpClient: backend.client,
      logger: logger,
      clock: clock ?? this.clock,
      random: random,
      delay: delay,
    );
    _instances.add(instance);
    return instance;
  }

  /// The store key of the Remote Config record [name] (`fetched`, `active`, `meta`, `throttle`,
  /// `signals`; 5.10).
  String recordKey(String name) => 'remote_config/${app.persistenceKey}/$name';

  /// The stored record [name] decoded as JSON, or null when absent.
  Future<Map<String, Object?>?> readRecord(String name) async {
    final String? text = await store.read(recordKey(name));
    return text == null ? null : jsonDecode(text) as Map<String, Object?>;
  }

  /// Closes every Remote Config instance and [installations], then deletes [app].
  Future<void> dispose() async {
    for (final FirebaseRemoteConfig instance in _instances) {
      await instance.close();
    }
    await installations.close();
    await app.delete();
  }
}

/// Waiting for futures inside `fakeAsync`.
extension FakeAsyncSettle on FakeAsync {
  /// Runs microtasks and zero-length timers until [future] completes, without moving the clock, then
  /// returns its value or throws its error. Fails the test when it does not complete.
  T settle<T>(Future<T> future) => _await(future, Duration.zero);

  /// Moves the clock in steps of [step] until [future] completes, at most [limit] in total, then returns
  /// its value or throws its error. Fails the test when it does not complete.
  T settleWithin<T>(
    Future<T> future,
    Duration limit, {
    Duration step = const Duration(milliseconds: 100),
  }) => _await(future, limit, step: step);

  T _await<T>(
    Future<T> future,
    Duration limit, {
    Duration step = const Duration(milliseconds: 100),
  }) {
    bool done = false;
    T? value;
    Object? error;
    StackTrace? stackTrace;
    future.then<void>(
      (T result) {
        done = true;
        value = result;
      },
      onError: (Object e, StackTrace s) {
        done = true;
        error = e;
        stackTrace = s;
      },
    );
    for (int i = 0; i < 10 && !done; i++) {
      flushMicrotasks();
      elapse(Duration.zero);
    }
    Duration moved = Duration.zero;
    while (!done && moved < limit) {
      final Duration next = moved + step > limit ? limit - moved : step;
      elapse(next);
      moved += next;
    }
    if (!done) {
      fail('The future did not complete within $limit of fake time.');
    }
    final Object? failure = error;
    if (failure != null) {
      Error.throwWithStackTrace(failure, stackTrace ?? StackTrace.current);
    }
    return value as T;
  }
}

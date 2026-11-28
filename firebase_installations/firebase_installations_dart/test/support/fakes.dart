/// Test doubles for `FirebaseInstallations`: a fake FIS server on a [MockClient], a fake clock for
/// `package:fake_async`, an app factory, and a probe for futures driven by fake time.
///
/// A typical test:
///
/// ```dart
/// fakeAsync((FakeAsync async) {
///   final FakeFis fis = FakeFis();
///   final FirebaseInstallations installations = newFisInstance(
///     fis: fis,
///     clock: FisClock(async),
///   );
///   fis.answer(FisRoute.create, FisAnswer.status(503));
///   final Outcome<String> token = Outcome<String>(installations.getToken());
///   async.flushMicrotasks();
///   expect(fis.count(FisRoute.create), 1);
///   ...
/// });
/// ```
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// An API key of the format `FirebaseInstallations` accepts (`^A[A-Za-z0-9_-]{38}$`).
final String fisApiKey = 'AIza${'k' * 35}';

/// The project id of every app made by [newFisApp].
const String fisProjectId = 'demo-fis';

/// The app id of every app made by [newFisApp].
const String fisAppId = '1:123456789:web:abcdef';

int _appCount = 0;
int _serial = 0;

/// A new app with valid Installations options and a unique name. Delete it (or let the test end).
FirebaseApp newFisApp() => FirebaseApp.withOptions(
  FirebaseOptions(apiKey: fisApiKey, appId: fisAppId, projectId: fisProjectId),
  name: 'fis-test-${_appCount++}',
);

/// A `FirebaseInstallations` talking to [fis].
///
/// Defaults: a new app from [newFisApp], a new [MemoryKeyValueStore], jitter [random] 0.5. Create it
/// inside `fakeAsync` so its timers use fake time; pass [clock] so its clock follows that time too.
FirebaseInstallations newFisInstance({
  required FakeFis fis,
  FirebaseApp? app,
  KeyValueStore? store,
  FisClock? clock,
  double random = 0.5,
  InstallationsLogger? logger,
}) => FirebaseInstallations(
  app ?? newFisApp(),
  store: store ?? MemoryKeyValueStore(),
  httpClient: fis.client,
  logger: logger,
  clock: clock?.call,
  random: () => random,
);

/// A clock for `fakeAsync`: [start] plus the fake time elapsed plus [offset].
///
/// Change [offset] to move the clock without firing timers (for example backwards, to make a stored
/// token look created in the future).
final class FisClock {
  /// A clock reading [start] (default 2026-01-01 UTC) when [async] has not elapsed any time.
  FisClock(this.async, {DateTime? start}) : start = start ?? DateTime.utc(2026);

  /// The fake time this clock follows.
  final FakeAsync async;

  /// The time when no fake time has elapsed.
  final DateTime start;

  /// Added to every reading.
  Duration offset = Duration.zero;

  /// The current time.
  DateTime call() => start.add(async.elapsed).add(offset);
}

/// The three endpoints of the Firebase Installations API.
enum FisRoute {
  /// `POST /v1/projects/{projectId}/installations`.
  create,

  /// `POST /v1/projects/{projectId}/installations/{fid}/authTokens:generate`.
  generate,

  /// `DELETE /v1/projects/{projectId}/installations/{fid}`.
  delete,
}

/// One request the fake received.
final class FisRequest {
  FisRequest._({
    required this.route,
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
    required this.fid,
  });

  /// The endpoint, or null when the request matched none (the fake then answers 404).
  final FisRoute? route;

  /// The HTTP method.
  final String method;

  /// The full URL.
  final Uri url;

  /// The request headers, names in lowercase.
  final Map<String, String> headers;

  /// The request body as text (empty when there was none).
  final String body;

  /// The FID the request is about: from the path for generate and delete, from the body for create.
  final String? fid;

  /// The body decoded as a JSON object, or null when it is empty or not an object.
  Map<String, Object?>? get json {
    if (body.isEmpty) {
      return null;
    }
    final Object? decoded = jsonDecode(body);
    return decoded is Map<String, Object?> ? decoded : null;
  }

  /// The `Authorization` header, or null.
  String? get authorization => headers['authorization'];

  @override
  String toString() => 'FisRequest($method ${url.path})';
}

/// What the fake answers to one request: a status and body, or a transport error, optionally held until
/// a gate completes.
final class FisAnswer {
  FisAnswer._(this._build, {this.gate});

  /// Answers [status] with [body] encoded as JSON.
  factory FisAnswer.json(int status, Object? body, {Future<void>? gate}) =>
      FisAnswer._((_) => _response(status, jsonEncode(body)), gate: gate);

  /// Answers [status] with the raw [body] text.
  factory FisAnswer.status(
    int status, {
    String body = '',
    Future<void>? gate,
  }) => FisAnswer._((_) => _response(status, body), gate: gate);

  /// Fails the request like a broken connection ([http.ClientException]).
  factory FisAnswer.transportError({Future<void>? gate}) => FisAnswer._(
    (FisRequest request) =>
        throw http.ClientException('connection refused (fake)', request.url),
    gate: gate,
  );

  /// A valid 200 answer to create: the request's FID (or [fid], a different one the server assigns), a
  /// refresh token and an auth token living [expiresIn]. Tokens default to unique values.
  factory FisAnswer.create({
    String? fid,
    String? refreshToken,
    String? token,
    String expiresIn = '604800s',
    Future<void>? gate,
  }) {
    final int n = _serial++;
    return FisAnswer._(
      (FisRequest request) => _response(
        200,
        jsonEncode(<String, Object?>{
          'name': 'projects/$fisProjectId/installations/${fid ?? request.fid}',
          'fid': fid ?? request.fid,
          'refreshToken': refreshToken ?? 'refresh-$n',
          'authToken': <String, Object?>{
            'token': token ?? 'auth-$n',
            'expiresIn': expiresIn,
          },
        }),
      ),
      gate: gate,
    );
  }

  /// A valid 200 answer to generate: [token] (default unique) living [expiresIn].
  factory FisAnswer.token({
    String? token,
    String expiresIn = '604800s',
    Future<void>? gate,
  }) {
    final int n = _serial++;
    return FisAnswer._(
      (_) => _response(
        200,
        jsonEncode(<String, Object?>{
          'token': token ?? 'auth-$n',
          'expiresIn': expiresIn,
        }),
      ),
      gate: gate,
    );
  }

  /// When set, the answer waits for it (or for the request's abort trigger, which fails the request
  /// with [http.RequestAbortedException]).
  final Future<void>? gate;

  final http.StreamedResponse Function(FisRequest request) _build;

  static http.StreamedResponse _response(int status, String body) =>
      http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(body)),
        status,
        headers: <String, String>{'content-type': 'application/json'},
      );
}

/// A fake Firebase Installations server behind [client].
///
/// It records every request in [requests] and answers each route from its queue ([answer]); an empty
/// queue gives the route's default ([answerAll]; initially a valid create answer echoing the FID, a
/// valid token, and 200 for delete). Unknown routes get 404.
final class FakeFis {
  /// A server with the default answers.
  FakeFis() {
    _client = _ClosingMockClient(this);
  }

  late final _ClosingMockClient _client;
  final Map<FisRoute, List<FisAnswer>> _queues = <FisRoute, List<FisAnswer>>{
    for (final FisRoute route in FisRoute.values) route: <FisAnswer>[],
  };
  final Map<FisRoute, FisAnswer Function()> _defaults =
      <FisRoute, FisAnswer Function()>{
        FisRoute.create: () => FisAnswer.create(),
        FisRoute.generate: () => FisAnswer.token(),
        FisRoute.delete: () => FisAnswer.status(200),
      };

  /// The HTTP client to give to `FirebaseInstallations(httpClient:)`.
  http.Client get client => _client;

  /// Every request received, in order.
  final List<FisRequest> requests = <FisRequest>[];

  /// Whether [client] was closed.
  bool get clientClosed => _client.closed;

  /// How many held answers were cut by the request's abort trigger.
  int aborted = 0;

  /// The requests to [route], in order.
  List<FisRequest> requestsTo(FisRoute route) => <FisRequest>[
    for (final FisRequest request in requests)
      if (request.route == route) request,
  ];

  /// How many requests [route] received.
  int count(FisRoute route) => requestsTo(route).length;

  /// Queues [first], then each of [more], for the next requests to [route].
  void answer(FisRoute route, FisAnswer first, [List<FisAnswer>? more]) {
    _queues[route]!
      ..add(first)
      ..addAll(more ?? const <FisAnswer>[]);
  }

  /// Makes [build] the answer to every request to [route] once its queue is empty.
  void answerAll(FisRoute route, FisAnswer Function() build) {
    _defaults[route] = build;
  }

  Future<http.StreamedResponse> _handle(
    http.BaseRequest original,
    http.ByteStream bodyStream,
  ) async {
    final String body = utf8.decode(await bodyStream.toBytes());
    final FisRequest request = _parse(original, body);
    requests.add(request);
    final FisRoute? route = request.route;
    if (route == null) {
      return FisAnswer._response(404, '{"error":{"code":404}}');
    }
    final List<FisAnswer> queue = _queues[route]!;
    final FisAnswer answer = queue.isEmpty
        ? _defaults[route]!()
        : queue.removeAt(0);
    final Future<void>? gate = answer.gate;
    if (gate != null) {
      await _hold(gate, original);
    }
    return answer._build(request);
  }

  Future<void> _hold(Future<void> gate, http.BaseRequest original) async {
    final Future<void>? abort = original is http.Abortable
        ? original.abortTrigger
        : null;
    bool cut = false;
    await Future.any(<Future<void>>[
      gate,
      if (abort != null) abort.then((_) => cut = true),
    ]);
    if (cut) {
      aborted++;
      throw http.RequestAbortedException(original.url);
    }
  }

  static FisRequest _parse(http.BaseRequest original, String body) {
    final List<String> path = original.url.pathSegments;
    final int at = path.indexOf('installations');
    final List<String> rest = at < 0 ? const <String>[] : path.sublist(at + 1);
    FisRoute? route;
    String? fid;
    if (at >= 0 && rest.isEmpty && original.method == 'POST') {
      route = FisRoute.create;
      final Object? json = body.isEmpty ? null : jsonDecode(body);
      final Object? sent = json is Map<String, Object?> ? json['fid'] : null;
      fid = sent is String ? sent : null;
    } else if (rest.length == 2 &&
        rest[1] == 'authTokens:generate' &&
        original.method == 'POST') {
      route = FisRoute.generate;
      fid = rest[0];
    } else if (rest.length == 1 && original.method == 'DELETE') {
      route = FisRoute.delete;
      fid = rest[0];
    }
    return FisRequest._(
      route: route,
      method: original.method,
      url: original.url,
      headers: <String, String>{
        for (final MapEntry<String, String> entry in original.headers.entries)
          entry.key.toLowerCase(): entry.value,
      },
      body: body,
      fid: fid,
    );
  }
}

final class _ClosingMockClient extends MockClient {
  _ClosingMockClient(FakeFis fis) : super.streaming(fis._handle);

  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}

/// The result of a future, readable synchronously after `async.flushMicrotasks()` or `async.elapse`.
final class Outcome<T> {
  /// Starts watching [future]; its error is captured, never unhandled.
  Outcome(Future<T> future) {
    future.then(
      (T value) {
        _value = value;
        _done = true;
      },
      onError: (Object error, StackTrace _) {
        _error = error;
        _done = true;
      },
    );
  }

  bool _done = false;
  T? _value;
  Object? _error;

  /// Whether the future completed (with a value or an error).
  bool get isDone => _done;

  /// The error, or null when the future has not failed.
  Object? get error => _error;

  /// The value; fails the test when the future has not completed with one.
  T get value {
    if (!_done) {
      fail('The future has not completed.');
    }
    if (_error != null) {
      fail('The future failed: $_error');
    }
    return _value as T;
  }
}

/// Matches a `FirebaseInstallationsException` with [code] (and [httpStatus] when given).
Matcher isFisException(String code, {int? httpStatus}) {
  Matcher matcher = isA<FirebaseInstallationsException>().having(
    (FirebaseInstallationsException e) => e.code,
    'code',
    code,
  );
  if (httpStatus != null) {
    matcher = allOf(
      matcher,
      isA<FirebaseInstallationsException>().having(
        (FirebaseInstallationsException e) => e.httpStatus,
        'httpStatus',
        httpStatus,
      ),
    );
  }
  return matcher;
}

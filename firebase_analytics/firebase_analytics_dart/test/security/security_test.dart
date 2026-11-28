// The secret and the tokens: where they may go, and that they never appear anywhere else.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_analytics_dart/firebase_analytics_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const String _secret = 'API-SECRET-5e1f';
const String _idToken = 'ID-TOKEN-SECRET-7f3a';
const String _appCheckToken = 'APP-CHECK-SECRET-91bc';

int _appCount = 0;

FirebaseApp _app({bool signedIn = true, bool appCheck = true}) {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'key',
      appId: '1:123:web:abc',
      projectId: 'demo-test',
    ),
    name: 'analytics-security-${_appCount++}',
  );
  if (signedIn) {
    app.authProvider = _StaticAuth(_idToken);
  }
  if (appCheck) {
    app.appCheckProvider = _StaticAppCheck(_appCheckToken);
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

class _FailingAuth extends AuthTokenProvider {
  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) =>
      Future<GetTokenResult>.error(StateError('refresh failed for $_idToken'));

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

/// A client with everything it says recorded: requests, warnings.
class _Rig {
  _Rig(
    AnalyticsTransport transport, {
    FirebaseApp? app,
    http.Client? client,
    int status = 204,
  }) {
    analytics = FirebaseAnalytics(
      app ?? _app(),
      measurementId: 'G-TEST1234',
      transport: transport,
      onWarning: warnings.add,
      httpClient:
          client ??
          MockClient((http.Request request) async {
            requests.add(request);
            return http.Response('', status);
          }),
    );
  }

  late final FirebaseAnalytics analytics;
  final List<http.Request> requests = <http.Request>[];
  final List<String> warnings = <String>[];

  Future<void> sendOne() async {
    await analytics.logEvent(
      name: 'level_up',
      parameters: <String, Object>{'level': 3},
    );
    await analytics.flush();
  }
}

/// Everything a request exposes, as one string to search.
String _requestText(http.Request request) => <String>[
  request.url.toString(),
  for (final MapEntry<String, String> h in request.headers.entries)
    '${h.key}: ${h.value}',
].join('\n');

void main() {
  group('direct transport', () {
    test('sends the secret only in the query of the collection URL', () async {
      final _Rig rig = _Rig(AnalyticsTransport.direct(apiSecret: _secret));
      await rig.sendOne();
      expect(rig.requests, hasLength(1));
      final http.Request request = rig.requests.single;
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'www.google-analytics.com');
      expect(request.url.queryParameters['api_secret'], _secret);
      expect(request.body, isNot(contains(_secret)));
      for (final String value in request.headers.values) {
        expect(value, isNot(contains(_secret)));
      }
    });

    test('never sends an ID token or an App Check token to Google', () async {
      final _Rig rig = _Rig(AnalyticsTransport.direct(apiSecret: _secret));
      await rig.sendOne();
      final String text =
          _requestText(rig.requests.single) + rig.requests.single.body;
      expect(text, isNot(contains(_idToken)));
      expect(text, isNot(contains(_appCheckToken)));
      expect(
        rig.requests.single.headers.keys.map((String k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
    });

    test('the EU region uses region1.google-analytics.com', () async {
      final List<http.Request> requests = <http.Request>[];
      final FirebaseAnalytics analytics = FirebaseAnalytics(
        _app(),
        measurementId: 'G-TEST1234',
        transport: AnalyticsTransport.direct(apiSecret: _secret),
        region: AnalyticsRegion.eu,
        onWarning: (_) {},
        httpClient: MockClient((http.Request request) async {
          requests.add(request);
          return http.Response('', 204);
        }),
      );
      await analytics.logEvent(name: 'level_up');
      await analytics.flush();
      expect(requests.single.url.host, 'region1.google-analytics.com');
      expect(requests.single.url.path, '/mp/collect');
    });

    test('toString hides the secret', () {
      final AnalyticsTransport transport = AnalyticsTransport.direct(
        apiSecret: _secret,
      );
      expect(transport.toString(), isNot(contains(_secret)));
      expect('$transport', contains('<hidden>'));
    });

    test(
      'a client error that quotes the URL does not reach a warning',
      () async {
        final _Rig rig = _Rig(
          AnalyticsTransport.direct(apiSecret: _secret),
          client: MockClient((http.Request request) async {
            throw http.ClientException('connection reset by peer', request.url);
          }),
        );
        await rig.sendOne();
        expect(rig.warnings, isNotEmpty);
        for (final String warning in rig.warnings) {
          expect(warning, isNot(contains(_secret)));
          expect(warning, isNot(contains('google-analytics.com')));
        }
      },
    );

    test(
      'an error body that echoes the secret does not reach a warning',
      () async {
        final List<String> warnings = <String>[];
        final FirebaseAnalytics analytics = FirebaseAnalytics(
          _app(),
          measurementId: 'G-TEST1234',
          transport: AnalyticsTransport.direct(apiSecret: _secret),
          onWarning: warnings.add,
          httpClient: MockClient(
            (http.Request request) async =>
                http.Response('bad request for ${request.url}', 400),
          ),
        );
        await analytics.logEvent(name: 'level_up');
        await analytics.flush();
        expect(warnings.join('\n'), contains('HTTP 400'));
        expect(warnings.join('\n'), isNot(contains(_secret)));
      },
    );

    test(
      'an empty secret or one with spaces is refused without quoting it',
      () {
        expect(
          () => AnalyticsTransport.direct(apiSecret: ''),
          throwsArgumentError,
        );
        expect(
          () => AnalyticsTransport.direct(apiSecret: 'has space'),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.toString(),
              'text',
              isNot(contains('has space')),
            ),
          ),
        );
      },
    );
  });

  group('relay transport', () {
    test('carries both tokens to an https relay, never the secret', () async {
      final _Rig rig = _Rig(
        AnalyticsTransport.relay(Uri.parse('https://relay.example/collect')),
      );
      await rig.sendOne();
      final http.Request request = rig.requests.single;
      expect(request.url.host, 'relay.example');
      expect(request.url.path, '/collect');
      expect(request.url.queryParameters, <String, String>{
        'measurement_id': 'G-TEST1234',
      });
      expect(request.headers['Authorization'], 'Bearer $_idToken');
      expect(request.headers['X-Firebase-AppCheck'], _appCheckToken);
      expect(request.headers['X-Firebase-GMPID'], '1:123:web:abc');
      expect(request.url.queryParameters.containsKey('api_secret'), isFalse);
    });

    test('carries the tokens to an http relay on a loopback host', () async {
      for (final String host in <String>['localhost', '127.0.0.1', '[::1]']) {
        final _Rig rig = _Rig(
          AnalyticsTransport.relay(Uri.parse('http://$host:8080/collect')),
        );
        await rig.sendOne();
        expect(
          rig.requests.single.headers['Authorization'],
          'Bearer $_idToken',
          reason: host,
        );
      }
    });

    test('refuses an http relay that is not on this machine', () {
      expect(
        () =>
            AnalyticsTransport.relay(Uri.parse('http://relay.example/collect')),
        throwsArgumentError,
      );
      expect(
        () =>
            AnalyticsTransport.relay(Uri.parse('ftp://relay.example/collect')),
        throwsArgumentError,
      );
    });

    test(
      'refuses user info and fragments in the relay URL without quoting them',
      () {
        expect(
          () => AnalyticsTransport.relay(
            Uri.parse('https://user:pw@relay.example/collect'),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.toString(),
              'text',
              isNot(contains('pw')),
            ),
          ),
        );
        expect(
          () => AnalyticsTransport.relay(
            Uri.parse('https://relay.example/collect#x'),
          ),
          throwsArgumentError,
        );
      },
    );

    test('keeps the query of the relay URL and adds measurement_id', () async {
      final _Rig rig = _Rig(
        AnalyticsTransport.relay(
          Uri.parse('https://relay.example/collect?site=a'),
        ),
      );
      await rig.sendOne();
      expect(rig.requests.single.url.queryParameters, <String, String>{
        'site': 'a',
        'measurement_id': 'G-TEST1234',
      });
    });

    test(
      'sends no Authorization without a signed-in user, and no App Check header without App Check',
      () async {
        final _Rig rig = _Rig(
          AnalyticsTransport.relay(Uri.parse('https://relay.example/collect')),
          app: _app(signedIn: false, appCheck: false),
        );
        await rig.sendOne();
        expect(
          rig.requests.single.headers.containsKey('Authorization'),
          isFalse,
        );
        expect(
          rig.requests.single.headers.containsKey('X-Firebase-AppCheck'),
          isFalse,
        );
      },
    );

    test(
      'a failing token provider sends the event without the token and does not leak the error',
      () async {
        final FirebaseApp app = _app(appCheck: false)
          ..authProvider = _FailingAuth();
        final _Rig rig = _Rig(
          AnalyticsTransport.relay(Uri.parse('https://relay.example/collect')),
          app: app,
        );
        await rig.sendOne();
        expect(rig.requests, hasLength(1));
        expect(
          rig.requests.single.headers.containsKey('Authorization'),
          isFalse,
        );
        expect(rig.warnings.join('\n'), isNot(contains(_idToken)));
      },
    );

    test('a token with a line break is not sent as a header', () async {
      final FirebaseApp app = _app(appCheck: false)
        ..authProvider = _StaticAuth('abc\r\nX-Evil: 1');
      final _Rig rig = _Rig(
        AnalyticsTransport.relay(Uri.parse('https://relay.example/collect')),
        app: app,
      );
      await rig.sendOne();
      expect(rig.requests.single.headers.containsKey('Authorization'), isFalse);
      expect(rig.requests.single.headers.containsKey('X-Evil'), isFalse);
    });

    test('toString shows neither the query nor user info of the relay URL', () {
      final AnalyticsTransport transport = AnalyticsTransport.relay(
        Uri.parse('https://relay.example/collect?key=K-123'),
      );
      expect('$transport', isNot(contains('K-123')));
    });
  });

  group('redirects', () {
    test('every request asks not to follow redirects', () async {
      final List<http.BaseRequest> seen = <http.BaseRequest>[];
      final FirebaseAnalytics analytics = FirebaseAnalytics(
        _app(),
        measurementId: 'G-TEST1234',
        transport: AnalyticsTransport.relay(
          Uri.parse('https://relay.example/collect'),
        ),
        onWarning: (_) {},
        httpClient: _RecordingClient(seen, 204),
      );
      await analytics.logEvent(name: 'level_up');
      await analytics.flush();
      expect(seen, hasLength(1));
      expect(seen.single.followRedirects, isFalse);
    });

    test(
      'a redirect answer drops the batch and sends nothing to the new location',
      () async {
        final List<http.BaseRequest> seen = <http.BaseRequest>[];
        final List<String> warnings = <String>[];
        final FirebaseAnalytics analytics = FirebaseAnalytics(
          _app(),
          measurementId: 'G-TEST1234',
          transport: AnalyticsTransport.direct(apiSecret: _secret),
          onWarning: warnings.add,
          httpClient: _RecordingClient(
            seen,
            302,
            location: 'https://elsewhere.example/',
          ),
        );
        await analytics.logEvent(name: 'level_up');
        await analytics.flush();
        await analytics.flush();
        expect(seen, hasLength(1));
        expect(seen.single.url.host, 'www.google-analytics.com');
        expect(warnings.join('\n'), contains('HTTP 302'));
      },
    );
  });

  group('the store', () {
    test('holds no secret and no token', () async {
      final _MapStore store = _MapStore();
      final List<String> warnings = <String>[];
      final FirebaseAnalytics analytics = FirebaseAnalytics(
        _app(),
        measurementId: 'G-TEST1234',
        transport: AnalyticsTransport.direct(apiSecret: _secret),
        store: store,
        onWarning: warnings.add,
        httpClient: MockClient(
          (http.Request request) async => http.Response('', 503),
        ),
      );
      await analytics.logEvent(name: 'level_up');
      await analytics.close();
      final String everything = store.values.values.join('\n');
      expect(everything, contains('level_up'));
      expect(everything, isNot(contains(_secret)));
      expect(everything, isNot(contains(_idToken)));
      expect(everything, isNot(contains(_appCheckToken)));
    });
  });

  test(
    'request bodies are JSON and carry no secret in any transport',
    () async {
      for (final AnalyticsTransport transport in <AnalyticsTransport>[
        AnalyticsTransport.direct(apiSecret: _secret),
        AnalyticsTransport.relay(Uri.parse('https://relay.example/collect')),
      ]) {
        final _Rig rig = _Rig(transport);
        await rig.sendOne();
        final Object? body = jsonDecode(rig.requests.single.body);
        expect(body, isA<Map<String, Object?>>());
        expect(rig.requests.single.body, isNot(contains(_secret)));
        expect(
          rig.requests.single.headers['Content-Type'],
          startsWith('application/json'),
        );
      }
    },
  );
}

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.seen, this.status, {this.location});

  final List<http.BaseRequest> seen;
  final int status;
  final String? location;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    seen.add(request);
    await request.finalize().drain<void>();
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('')),
      status,
      headers: <String, String>{'location': ?location},
    );
  }
}

class _MapStore implements AnalyticsStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

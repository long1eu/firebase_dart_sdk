// The client (firebase_analytics_dart with AnalyticsTransport.relay) against this relay, in one process, with a
// fake Google Analytics: what reaches Google, and what each answer of the relay makes the client do with the
// events.

import 'dart:convert';
import 'dart:math';

import 'package:analytics_relay/analytics_relay.dart';
import 'package:fake_async/fake_async.dart';
import 'package:firebase_analytics_dart/firebase_analytics_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relay_guard/relay_guard.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

/// A made-up value for the tests.
const String _secret = 'TESTSECRETnotreal0123';
const String _measurementId = 'G-TEST1234';
const String _appId = '1:1:web:a';

final class _Verifier implements CallerVerifier {
  @override
  Future<String> appIdOf(String token) async =>
      token == 'app-ok' ? _appId : throw const CallerRejected('bad');

  @override
  Future<String> uidOf(String token) async =>
      throw const CallerRejected('no users here');
}

final class _AppCheck extends AppCheckTokenProvider {
  _AppCheck(this.token);

  final String token;

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async =>
      AppCheckTokenResult(token);

  @override
  Stream<AppCheckTokenResult> get onTokenChanged =>
      const Stream<AppCheckTokenResult>.empty();
}

/// What one run produced.
typedef _Run = ({
  int queued,
  List<int> relayAnswers,
  List<http.Request> upstream,
  String? clientId,
});

int _apps = 0;

void main() {
  final DateTime start = DateTime.utc(2026, 11, 28, 12);

  /// Logs one event, flushes, and returns what happened. Google Analytics answers [upstream], or fails with
  /// a network error when [upstreamDown].
  _Run run({
    int upstream = 204,
    bool upstreamDown = false,
    String? appCheck = 'app-ok',
    bool requireUser = false,
    Set<String>? allowedAppIds,
  }) {
    late _Run result;
    fakeAsync((FakeAsync async) {
      final List<http.Request> sent = <http.Request>[];
      final List<int> answers = <int>[];
      final shelf.Handler relay = const shelf.Pipeline()
          .addMiddleware(
            relayGuard(
              verifier: _Verifier(),
              path: 'collect',
              requireUser: requireUser,
              maxBodyBytes: guardMaxBodyBytes,
              clock: () => start.add(async.elapsed),
            ),
          )
          .addHandler(
            analyticsRelay(
              measurementId: _measurementId,
              apiSecret: _secret,
              allowedAppIds: allowedAppIds,
              client: MockClient((http.Request request) async {
                sent.add(request);
                if (upstreamDown) {
                  throw http.ClientException('down', request.url);
                }
                return http.Response('', upstream);
              }),
            ),
          );
      // The client's HTTP requests go straight to the relay's handler.
      final http.Client bridge = MockClient((http.Request request) async {
        final shelf.Response response = await relay(
          shelf.Request(
            request.method,
            request.url,
            headers: request.headers,
            body: request.bodyBytes,
          ),
        );
        answers.add(response.statusCode);
        return http.Response.bytes(
          await response.read().expand((List<int> chunk) => chunk).toList(),
          response.statusCode,
          headers: response.headers,
        );
      });
      final FirebaseApp app = FirebaseApp.withOptions(
        const FirebaseOptions(
          apiKey: 'k',
          appId: _appId,
          projectId: 'demo-test',
          measurementId: _measurementId,
        ),
        name: 'analytics-contract-${_apps++}',
      );
      if (appCheck != null) {
        app.appCheckProvider = _AppCheck(appCheck);
      }
      final FirebaseAnalytics analytics = FirebaseAnalytics(
        app,
        transport: AnalyticsTransport.relay(
          Uri.parse('https://relay.test/collect'),
        ),
        httpClient: bridge,
        clock: () => start.add(async.elapsed),
        random: Random(1),
        onWarning: (_) {},
      );
      int? queued;
      String? clientId;
      analytics
          .logEvent(name: 'level_up', parameters: <String, Object?>{'level': 3})
          .then((_) => analytics.flush())
          .then((_) => analytics.appInstanceId)
          .then((String? id) => clientId = id)
          .then((_) => analytics.queuedEventCount)
          .then((int n) => queued = n);
      async.elapse(const Duration(seconds: 1));
      result = (
        queued: queued ?? (throw StateError('the run did not finish')),
        relayAnswers: answers,
        upstream: sent,
        clientId: clientId,
      );
    });
    return result;
  }

  test(
    'Google took it (relay 204): delivered, with the configured secret and no caller header',
    () {
      final _Run r = run();
      expect(r.relayAnswers, <int>[204]);
      expect(r.queued, 0);
      final http.Request upstream = r.upstream.single;
      expect(upstream.url.host, 'www.google-analytics.com');
      expect(upstream.url.path, '/mp/collect');
      expect(upstream.url.queryParametersAll, <String, List<String>>{
        'measurement_id': <String>[_measurementId],
        'api_secret': <String>[_secret],
      });
      expect(
        upstream.headers.keys.map((String k) => k.toLowerCase()).toSet(),
        <String>{'content-type'},
      );
      final Map<String, Object?> body =
          jsonDecode(upstream.body) as Map<String, Object?>;
      expect(body['client_id'], r.clientId);
      expect(body.containsKey('api_secret'), isFalse);
      final List<Object?> events = body['events']! as List<Object?>;
      expect(events, hasLength(1));
      expect((events.single! as Map<String, Object?>)['name'], 'level_up');
    },
  );

  test('an outage or a quota at Google (relay 503): kept', () {
    for (final int status in <int>[500, 503, 429]) {
      final _Run r = run(upstream: status);
      expect(r.relayAnswers, <int>[503], reason: '$status');
      expect(r.upstream, hasLength(1), reason: '$status');
      expect(r.queued, 1, reason: '$status');
    }
  });

  test('Google unreachable (relay 503): kept', () {
    final _Run r = run(upstreamDown: true);
    expect(r.relayAnswers, <int>[503]);
    expect(r.queued, 1);
  });

  test('Google refused the request (relay 400): dropped', () {
    final _Run r = run(upstream: 400);
    expect(r.relayAnswers, <int>[400]);
    expect(r.queued, 0);
  });

  test('no App Check token (guard 401): kept, nothing forwarded', () {
    final _Run r = run(appCheck: null);
    expect(r.relayAnswers, <int>[401]);
    expect(r.upstream, isEmpty);
    expect(r.queued, 1);
  });

  test('a forged App Check token (guard 401): kept, nothing forwarded', () {
    final _Run r = run(appCheck: 'forged');
    expect(r.relayAnswers, <int>[401]);
    expect(r.upstream, isEmpty);
    expect(r.queued, 1);
  });

  test('a user required and nobody signed in (guard 401): kept', () {
    final _Run r = run(requireUser: true);
    expect(r.relayAnswers, <int>[401]);
    expect(r.upstream, isEmpty);
    expect(r.queued, 1);
  });

  test('an app the relay does not allow (relay 403): kept', () {
    final _Run r = run(allowedAppIds: <String>{'1:1:web:other'});
    expect(r.relayAnswers.first, 403);
    expect(r.upstream, isEmpty);
    expect(r.queued, 1);
  });
}

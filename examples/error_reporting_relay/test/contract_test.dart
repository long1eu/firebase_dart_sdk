// The client (firebase_error_reporting_dart with the relay transport) against this relay, in one process: what
// each answer of the relay makes the client do with the event.

import 'dart:async';

import 'package:error_reporting_relay/error_reporting_relay.dart';
import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_error_reporting_dart/firebase_error_reporting_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relay_guard/relay_guard.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

final class _Verifier implements CallerVerifier {
  @override
  Future<String> appIdOf(String token) async =>
      token == 'app-ok' ? '1:1:windows:a' : throw const CallerRejected('bad');

  @override
  Future<String> uidOf(String token) async =>
      throw const CallerRejected('no users here');
}

final class _AppCheck extends AppCheckTokenProvider {
  _AppCheck(this.token);

  String token;

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async =>
      AppCheckTokenResult(token);

  @override
  Stream<AppCheckTokenResult> get onTokenChanged =>
      const Stream<AppCheckTokenResult>.empty();
}

int _apps = 0;

void main() {
  final DateTime start = DateTime.utc(2026, 11, 28, 12);

  /// Runs one error through client and relay, with Error Reporting answering [upstream], and returns the
  /// number of events the client still holds after [wait].
  int pendingAfter({
    required int upstream,
    String appCheck = 'app-ok',
    String service = 'notes-desktop',
    Duration wait = const Duration(seconds: 5),
  }) {
    int pending = -1;
    fakeAsync((FakeAsync async) {
      final shelf.Handler relay = const shelf.Pipeline()
          .addMiddleware(
            relayGuard(
              verifier: _Verifier(),
              path: 'errors',
              clock: () => start.add(async.elapsed),
            ),
          )
          .addHandler(
            errorReportingRelay(
              projectId: 'demo-test',
              services: <String>{'notes-desktop'},
              accessToken: ({bool forceRefresh = false}) async => 'relay-token',
              client: MockClient(
                (http.Request request) async => http.Response('{}', upstream),
              ),
              clock: () => start.add(async.elapsed),
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
        return http.Response.bytes(
          await response.read().expand((List<int> chunk) => chunk).toList(),
          response.statusCode,
          headers: response.headers,
        );
      });
      final FirebaseApp app = FirebaseApp.withOptions(
        const FirebaseOptions(
          apiKey: 'k',
          appId: '1:1:windows:a',
          projectId: 'demo-test',
        ),
        name: 'contract-${_apps++}',
      )..appCheckProvider = _AppCheck(appCheck);
      final ErrorReporter reporter = ErrorReporter(
        app,
        service: service,
        version: '1.0.0',
        transport: ErrorReportingTransport.relay(
          Uri.parse('https://relay.test/errors'),
        ),
        httpClient: bridge,
        clock: () => start.add(async.elapsed),
        onDiagnostic: (_) {},
      );
      reporter.recordError(
        StateError('x'),
        StackTrace.fromString('#0      main (package:notes/main.dart:1:1)\n'),
      );
      async.elapse(wait);
      pending = reporter.pendingCount;
    });
    return pending;
  }

  test('Error Reporting took it (relay 204): delivered', () {
    expect(pendingAfter(upstream: 200), 0);
  });

  test('Error Reporting refused the event (relay 400): dropped', () {
    expect(pendingAfter(upstream: 400), 0);
  });

  test(
    'a service the relay does not allow (relay 422): dropped, not paused',
    () {
      expect(pendingAfter(upstream: 200, service: 'other'), 0);
    },
  );

  test(
    'an outage, a wrong project or a refused relay credential (relay 503): kept',
    () {
      for (final int upstream in <int>[500, 429, 404, 403, 401]) {
        expect(pendingAfter(upstream: upstream), 1, reason: '$upstream');
      }
    },
  );

  test('App Check refused by the relay (401): kept, paused', () {
    expect(pendingAfter(upstream: 200, appCheck: 'forged'), 1);
  });
}

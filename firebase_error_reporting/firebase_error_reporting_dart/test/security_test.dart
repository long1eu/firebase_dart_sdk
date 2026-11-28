import 'package:fake_async/fake_async.dart';
import 'package:firebase_error_reporting_dart/firebase_error_reporting_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const String _key = 'AIzaVerySecretKey123';
const String _token = 'ya29.very-secret-token';

void main() {
  test(
    'the API key never reaches a diagnostic, even when the client error quotes the URL',
    () {
      fakeAsync((FakeAsync async) {
        final List<String> logs = <String>[];
        final http.Client client = MockClient((http.Request request) async {
          throw http.ClientException(
            'could not reach ${request.url}',
            request.url,
          );
        });
        final ErrorReporter reporter = ErrorReporter(
          newApp(),
          service: 's',
          transport: ErrorReportingTransport.direct(apiKey: _key),
          httpClient: client,
          onDiagnostic: logs.add,
        );
        reporter.recordError(StateError('x'), appStack);
        async.elapse(const Duration(minutes: 10));
        expect(logs, isNotEmpty);
        for (final String line in logs) {
          expect(line, isNot(contains(_key)));
        }
      });
    },
  );

  test('an access token never reaches a diagnostic', () {
    fakeAsync((FakeAsync async) {
      final List<String> logs = <String>[];
      final Server server = Server(<int>[403])
        ..responseBody = '{"error":"denied"}';
      final ErrorReporter reporter = ErrorReporter(
        newApp(),
        service: 's',
        transport: ErrorReportingTransport.direct(
          credentials: FakeAuth(<String>[_token]),
        ),
        httpClient: server.client,
        onDiagnostic: logs.add,
      );
      reporter.recordError(StateError('x'), appStack);
      async.elapse(const Duration(seconds: 3));
      expect(server.requests.single.headers['authorization'], 'Bearer $_token');
      expect(logs.join('\n'), isNot(contains(_token)));
    });
  });

  test(
    'the relay refuses clear text, so tokens and events never leave unencrypted',
    () {
      expect(
        () => ErrorReportingTransport.relay(
          Uri.parse('http://errors.example.com/collect'),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'the user is sent only after setUser, never taken from the signed-in user',
    () {
      fakeAsync((FakeAsync async) {
        final Server server = Server();
        final app = newApp()..authProvider = FakeAuth(<String>['id-token']);
        final ErrorReporter reporter = ErrorReporter(
          app,
          service: 's',
          transport: ErrorReportingTransport.relay(
            Uri.parse('https://example.com/errors'),
          ),
          httpClient: server.client,
          onDiagnostic: (_) {},
        );
        reporter.recordError(StateError('x'), appStack);
        async.elapse(const Duration(seconds: 3));
        final Map<String, Object?> context =
            server.requests.single.body['context']! as Map<String, Object?>;
        expect(context.containsKey('user'), isFalse);
      });
    },
  );
}

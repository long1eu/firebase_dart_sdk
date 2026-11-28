import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_error_reporting_dart/src/transport.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const Map<String, Object?> _body = <String, Object?>{
  'eventTime': '2026-11-28T10:00:00.000Z',
  'serviceContext': <String, Object?>{'service': 'svc'},
  'message': 'StateError: x',
};

void main() {
  late FirebaseApp app;
  setUp(() => app = newApp());

  group('relay', () {
    test('posts the event with the App Check and ID tokens', () async {
      app.appCheckProvider = FakeAppCheck(
        const AppCheckTokenResult('app-check-token'),
      );
      app.authProvider = FakeAuth(<String>['id-token']);
      final Server server = Server();
      final SendResult result = await ErrorReportingTransport.relay(
        Uri.parse('https://example.com/errors'),
      ).send(server.client, app, _body);
      expect(result, isA<Delivered>());
      final Received request = server.requests.single;
      expect(request.url, Uri.parse('https://example.com/errors'));
      expect(request.headers['x-firebase-appcheck'], 'app-check-token');
      expect(request.headers['authorization'], 'Bearer id-token');
      expect(request.headers['content-type'], startsWith('application/json'));
      expect(request.body, _body);
    });

    test('without providers, or when they fail, no token headers', () async {
      final Server server = Server();
      final ErrorReportingTransport relay = ErrorReportingTransport.relay(
        Uri.parse('https://example.com/errors'),
      );
      await relay.send(server.client, app, _body);
      app.appCheckProvider = FakeAppCheck(
        const AppCheckTokenResult(''),
        error: StateError('down'),
      );
      app.authProvider = FakeAuth(<String?>[null]);
      await relay.send(server.client, app, _body);
      for (final Received request in server.requests) {
        expect(request.headers.keys, isNot(contains('x-firebase-appcheck')));
        expect(request.headers.keys, isNot(contains('authorization')));
      }
    });

    test('the URL must be https or a loopback host', () {
      for (final String url in <String>[
        'http://example.com/errors',
        'ftp://example.com/errors',
        'https:///errors',
      ]) {
        expect(
          () => ErrorReportingTransport.relay(Uri.parse(url)),
          throwsArgumentError,
          reason: url,
        );
      }
      for (final String url in <String>[
        'http://localhost:8080/errors',
        'http://127.0.0.1:8080/errors',
        'http://[::1]:8080/errors',
      ]) {
        expect(
          ErrorReportingTransport.relay(Uri.parse(url)),
          isA<ErrorReportingTransport>(),
          reason: url,
        );
      }
    });
  });

  group('direct', () {
    test(
      'with an API key: the key query parameter and no Authorization',
      () async {
        final Server server = Server();
        await ErrorReportingTransport.direct(
          apiKey: 'AIzaTestKey_1-2',
        ).send(server.client, app, _body);
        final Received request = server.requests.single;
        expect(
          request.url,
          Uri.parse(
            'https://clouderrorreporting.googleapis.com/v1beta1/projects/demo-test/events:report?key=AIzaTestKey_1-2',
          ),
        );
        expect(request.headers.keys, isNot(contains('authorization')));
      },
    );

    test(
      'with credentials: a bearer token, and one refresh after a 401',
      () async {
        final FakeAuth credentials = FakeAuth(<String>['old', 'new']);
        final Server server = Server(<int>[401, 200]);
        final SendResult result = await ErrorReportingTransport.direct(
          credentials: credentials,
        ).send(server.client, app, _body);
        expect(result, isA<Delivered>());
        expect(credentials.calls, <bool>[false, true]);
        expect(
          server.requests.map((Received r) => r.headers['authorization']),
          <String>['Bearer old', 'Bearer new'],
        );
        expect(server.requests.first.url.queryParameters, isEmpty);
      },
    );

    test('a second 401 drops the event', () async {
      final Server server = Server(<int>[401]);
      final SendResult result = await ErrorReportingTransport.direct(
        credentials: FakeAuth(<String>['t']),
      ).send(server.client, app, _body);
      expect(
        result,
        isA<Dropped>().having((Dropped d) => d.status, 'status', 401),
      );
      expect(server.requests, hasLength(2));
    });

    test('credentials that fail: retry later, without their message', () async {
      final SendResult result = await ErrorReportingTransport.direct(
        credentials: FakeAuth(<String>[
          't',
        ], error: StateError('secret-in-message')),
      ).send(Server().client, app, _body);
      expect(result, isA<RetryLater>());
      expect(
        (result as RetryLater).reason,
        isNot(contains('secret-in-message')),
      );
    });

    test('exactly one of credentials and apiKey, and a plausible key', () {
      expect(() => ErrorReportingTransport.direct(), throwsArgumentError);
      expect(
        () => ErrorReportingTransport.direct(
          apiKey: 'k',
          credentials: FakeAuth(<String>['t']),
        ),
        throwsArgumentError,
      );
      for (final String key in <String>['', 'a b', 'a&b=c', 'a/b', 'k\n']) {
        expect(
          () => ErrorReportingTransport.direct(apiKey: key),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '$e',
              'text',
              isNot(contains(key.isEmpty ? '\u0000' : key)),
            ),
          ),
          reason: key,
        );
      }
    });
  });

  group('answers', () {
    final ErrorReportingTransport transport = ErrorReportingTransport.direct(
      apiKey: 'k',
    );

    for (final int status in <int>[200, 204]) {
      test('$status is delivered', () async {
        expect(
          await transport.send(Server(<int>[status]).client, app, _body),
          isA<Delivered>(),
        );
      });
    }
    for (final int status in <int>[408, 429, 500, 503]) {
      test('$status is retried', () async {
        expect(
          await transport.send(Server(<int>[status]).client, app, _body),
          isA<RetryLater>(),
        );
      });
    }
    for (final int status in <int>[301, 302, 400, 403, 404]) {
      test('$status is dropped', () async {
        expect(
          await transport.send(Server(<int>[status]).client, app, _body),
          isA<Dropped>().having((Dropped d) => d.status, 'status', status),
        );
      });
    }

    test('Retry-After is honoured and capped at an hour', () async {
      final Server server = Server(<int>[429])
        ..responseHeaders = <String, String>{'retry-after': '120'};
      expect(
        ((await transport.send(server.client, app, _body)) as RetryLater).after,
        const Duration(seconds: 120),
      );
      server.responseHeaders = <String, String>{'retry-after': '99999'};
      expect(
        ((await transport.send(server.client, app, _body)) as RetryLater).after,
        const Duration(hours: 1),
      );
      server.responseHeaders = <String, String>{
        'retry-after': 'Wed, 21 Oct 2026 07:28:00 GMT',
      };
      expect(
        ((await transport.send(server.client, app, _body)) as RetryLater).after,
        isNull,
      );
    });

    test('redirects are not followed', () async {
      bool followed = false;
      final http.Client client = MockClient((http.Request request) async {
        followed = request.followRedirects;
        return http.Response(
          '',
          302,
          headers: <String, String>{'location': 'https://elsewhere.example/'},
        );
      });
      await transport.send(client, app, _body);
      expect(followed, isFalse);
    });

    test('at most 64 KiB of an answer is read', () async {
      final Server server = Server(<int>[400])
        ..responseBody = 'x' * (200 * 1024);
      final Dropped dropped =
          (await transport.send(server.client, app, _body)) as Dropped;
      expect(utf8.encode(dropped.body).length, maxResponseBytes);
    });

    test(
      'a network error is retried, and its message (which may hold the URL) is not kept',
      () async {
        final http.Client client = MockClient((http.Request request) async {
          throw http.ClientException(
            'failed to reach ${request.url}',
            request.url,
          );
        });
        final RetryLater retry =
            (await transport.send(client, app, _body)) as RetryLater;
        expect(retry.reason, 'the request failed (ClientException)');
      },
    );

    test('no answer in time is retried', () {
      fakeAsync((FakeAsync async) {
        final http.Client client = MockClient(
          (http.Request request) => Completer<http.Response>().future,
        );
        SendResult? result;
        transport.send(client, app, _body).then((SendResult r) => result = r);
        async.elapse(requestTimeout - const Duration(seconds: 1));
        expect(result, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(result, isA<RetryLater>());
      });
    });
  });
}

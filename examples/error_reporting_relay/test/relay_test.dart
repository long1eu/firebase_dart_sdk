import 'dart:convert';

import 'package:error_reporting_relay/error_reporting_relay.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relay_guard/relay_guard.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

final class _Verifier implements CallerVerifier {
  @override
  Future<String> appIdOf(String token) async =>
      token == 'app-ok' ? '1:1:web:a' : throw const CallerRejected('bad');

  @override
  Future<String> uidOf(String token) async =>
      token == 'user-ok' ? 'verified-uid' : throw const CallerRejected('bad');
}

void main() {
  late List<http.Request> forwarded;
  late int status;
  late List<String> logs;
  final DateTime now = DateTime.utc(2026, 11, 28, 12);

  Handler relay({Future<String> Function()? token}) => const Pipeline()
      .addMiddleware(relayGuard(verifier: _Verifier(), clock: () => now))
      .addHandler(
        errorReportingRelay(
          projectId: 'demo-test',
          services: <String>{'notes-desktop'},
          accessToken: token ?? () async => 'relay-token',
          client: MockClient((http.Request request) async {
            forwarded.add(request);
            return http.Response('{}', status);
          }),
          clock: () => now,
          log: logs.add,
        ),
      );

  Request post(Map<String, Object?> event, {Map<String, String>? headers}) =>
      Request(
        'POST',
        Uri.parse('http://relay.test/errors'),
        body: jsonEncode(event),
        headers: <String, String>{
          'content-type': 'application/json',
          ...headers ??
              <String, String>{
                'x-firebase-appcheck': 'app-ok',
                'authorization': 'Bearer user-ok',
              },
        },
      );

  Map<String, Object?> event({
    Map<String, Object?> extra = const <String, Object?>{},
  }) => <String, Object?>{
    'eventTime': '2026-11-28T11:59:00.000Z',
    'serviceContext': <String, Object?>{
      'service': 'notes-desktop',
      'version': '1.4.0',
    },
    'message':
        'StateError: Bad state: x\n    at main (package:notes/main.dart:1:1)',
    'context': <String, Object?>{
      'user': 'spoofed',
      'reportLocation': <String, Object?>{
        'filePath': 'package:notes/main.dart',
        'lineNumber': 1,
        'functionName': 'main',
      },
      'httpRequest': <String, Object?>{
        'method': 'GET',
        'url': 'https://e.example/a',
        'remoteIp': '1.2.3.4',
        'responseStatusCode': 500,
      },
    },
    ...extra,
  };

  setUp(() {
    forwarded = <http.Request>[];
    status = 200;
    logs = <String>[];
  });

  test(
    'forwards a cleaned event with the relay\'s token and the verified user',
    () async {
      final Response response = await relay()(
        post(event(extra: <String, Object?>{'unknown': 'field'})),
      );
      expect(response.statusCode, 204);
      final http.Request request = forwarded.single;
      expect(
        request.url,
        Uri.parse(
          'https://clouderrorreporting.googleapis.com/v1beta1/projects/demo-test/events:report',
        ),
      );
      expect(request.headers['authorization'], 'Bearer relay-token');
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      expect(
        body.keys,
        unorderedEquals(<String>[
          'eventTime',
          'serviceContext',
          'message',
          'context',
        ]),
      );
      final Map<String, Object?> context =
          body['context']! as Map<String, Object?>;
      expect(context['user'], 'verified-uid');
      expect(
        (context['httpRequest']! as Map<String, Object?>).containsKey(
          'remoteIp',
        ),
        isFalse,
      );
    },
  );

  test(
    'without a signed-in user there is no user, whatever the caller wrote',
    () async {
      await relay()(
        post(
          event(),
          headers: <String, String>{'x-firebase-appcheck': 'app-ok'},
        ),
      );
      final Map<String, Object?> context =
          (jsonDecode(forwarded.single.body)
                  as Map<String, Object?>)['context']!
              as Map<String, Object?>;
      expect(context.containsKey('user'), isFalse);
    },
  );

  test('a service that is not allowed is 403 and not forwarded', () async {
    final Response response = await relay()(
      post(
        event(
          extra: <String, Object?>{
            'serviceContext': <String, Object?>{'service': 'evil'},
          },
        ),
      ),
    );
    expect(response.statusCode, 403);
    expect(forwarded, isEmpty);
  });

  test('a malformed event or version is 400', () async {
    expect(
      (await relay()(post(<String, Object?>{'message': 'x'}))).statusCode,
      403,
    );
    expect(
      (await relay()(
        post(event(extra: <String, Object?>{'message': ''})),
      )).statusCode,
      400,
    );
    expect(
      (await relay()(
        post(
          event(
            extra: <String, Object?>{
              'serviceContext': <String, Object?>{
                'service': 'notes-desktop',
                'version': 'x' * 100,
              },
            },
          ),
        ),
      )).statusCode,
      400,
    );
    final Response notJson = await relay()(
      Request(
        'POST',
        Uri.parse('http://relay.test/e'),
        body: '{not json',
        headers: <String, String>{
          'content-type': 'application/json',
          'x-firebase-appcheck': 'app-ok',
        },
      ),
    );
    expect(notJson.statusCode, 400);
    expect(forwarded, isEmpty);
  });

  test(
    'an eventTime out of range is left out; a long message is cut',
    () async {
      await relay()(
        post(
          event(
            extra: <String, Object?>{
              'eventTime': '2020-01-01T00:00:00Z',
              'message': 'm' * 40000,
            },
          ),
        ),
      );
      final Map<String, Object?> body =
          jsonDecode(forwarded.single.body) as Map<String, Object?>;
      expect(body.containsKey('eventTime'), isFalse);
      expect((body['message']! as String).length, maxMessageLength);
    },
  );

  test(
    'Error Reporting unavailable, or the relay\'s credential refused, is 503',
    () async {
      for (final int s in <int>[429, 500, 401, 403]) {
        status = s;
        final Response response = await relay()(post(event()));
        expect(response.statusCode, 503, reason: '$s');
        expect(response.headers['retry-after'], isNotNull);
      }
      status = 400;
      expect((await relay()(post(event()))).statusCode, 400);
    },
  );

  test('no access token is 503', () async {
    final Response response = await relay(
      token: () async => throw StateError('no credentials'),
    )(post(event()));
    expect(response.statusCode, 503);
    expect(forwarded, isEmpty);
  });

  test('without a valid App Check token nothing is forwarded', () async {
    expect(
      (await relay()(
        post(event(), headers: const <String, String>{}),
      )).statusCode,
      401,
    );
    expect(forwarded, isEmpty);
  });
}

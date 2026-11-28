import 'dart:convert';

import 'package:error_reporting_relay/error_reporting_relay.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relay_guard/relay_guard.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

final class _Verifier implements CallerVerifier {
  @override
  Future<String> appIdOf(String token) async => switch (token) {
    'app-ok' => '1:1:windows:a',
    'app-web' => '1:1:web:b',
    _ => throw const CallerRejected('bad'),
  };

  @override
  Future<String> uidOf(String token) async =>
      token == 'user-ok' ? 'verified-uid' : throw const CallerRejected('bad');
}

void main() {
  late List<http.Request> forwarded;
  late List<int> statuses;
  late List<bool> refreshes;
  late List<String> logs;
  final DateTime now = DateTime.utc(2026, 11, 28, 12);

  Handler relay({
    Future<String> Function({bool forceRefresh})? token,
    Map<String, Set<String>>? servicesByApp,
  }) => const Pipeline()
      .addMiddleware(relayGuard(verifier: _Verifier(), clock: () => now))
      .addHandler(
        errorReportingRelay(
          projectId: 'demo-test',
          services: <String>{'notes-desktop', 'notes-web'},
          servicesByApp: servicesByApp,
          accessToken:
              token ??
              ({bool forceRefresh = false}) async {
                refreshes.add(forceRefresh);
                return forceRefresh ? 'fresh-token' : 'relay-token';
              },
          client: MockClient((http.Request request) async {
            forwarded.add(request);
            final int status =
                statuses[(forwarded.length - 1).clamp(0, statuses.length - 1)];
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

  Map<String, Object?> sent() =>
      jsonDecode(forwarded.single.body) as Map<String, Object?>;

  setUp(() {
    forwarded = <http.Request>[];
    statuses = <int>[200];
    refreshes = <bool>[];
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
      final Map<String, Object?> body = sent();
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
      expect(
        (sent()['context']! as Map<String, Object?>).containsKey('user'),
        isFalse,
      );
    },
  );

  test('a service that is not allowed is 422 and not forwarded', () async {
    final Response response = await relay()(
      post(
        event(
          extra: <String, Object?>{
            'serviceContext': <String, Object?>{'service': 'evil'},
          },
        ),
      ),
    );
    expect(response.statusCode, 422);
    expect(forwarded, isEmpty);
  });

  test('with servicesByApp, an app reports only as its own services', () async {
    final Handler h = relay(
      servicesByApp: <String, Set<String>>{
        '1:1:windows:a': <String>{'notes-desktop'},
        '1:1:web:b': <String>{'notes-web'},
      },
    );
    expect((await h(post(event()))).statusCode, 204);
    final Response web = await h(
      post(
        event(),
        headers: <String, String>{'x-firebase-appcheck': 'app-web'},
      ),
    );
    expect(web.statusCode, 422);
    expect(forwarded, hasLength(1));
  });

  test('a malformed event or version is 400', () async {
    expect(
      (await relay()(
        post(event(extra: <String, Object?>{'message': ''})),
      )).statusCode,
      400,
    );
    expect(
      (await relay()(
        post(event(extra: <String, Object?>{'message': ' \t\n'})),
      )).statusCode,
      400,
    );
    expect(
      (await relay()(
        post(event(extra: <String, Object?>{'message': 42})),
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
        Uri.parse('http://relay.test/errors'),
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

  group('eventTime', () {
    Future<Object?> forwardedTime(String time) async {
      forwarded.clear();
      await relay()(post(event(extra: <String, Object?>{'eventTime': time})));
      return sent()['eventTime'];
    }

    test('kept when it is RFC 3339 with a zone, within range', () async {
      expect(
        await forwardedTime('2026-11-28T13:30:00+02:00'),
        '2026-11-28T11:30:00.000Z',
      );
    });

    test(
      'dropped without a zone, with overflowing fields, or out of range',
      () async {
        for (final String time in <String>[
          '2026-11-28T11:59:00',
          '2026-11-28T25:61:00Z',
          '2026-13-01T00:00:00Z',
          '2020-01-01T00:00:00Z',
          '2026-11-28T14:00:00Z',
          'yesterday',
        ]) {
          expect(await forwardedTime(time), isNull, reason: time);
        }
      },
    );
  });

  test(
    'control characters are removed; a long message is cut without splitting a surrogate pair',
    () async {
      await relay()(
        post(
          event(
            extra: <String, Object?>{
              'message':
                  'Error: a\u0000b\u001bc\nline 2\t${'x' * (maxMessageLength - 20)}😀😀',
              'context': <String, Object?>{
                'httpRequest': <String, Object?>{
                  'url': 'https://e.example/\r\nX-Injected: 1',
                },
              },
            },
          ),
        ),
      );
      final Map<String, Object?> body = sent();
      final String message = body['message']! as String;
      expect(message, startsWith('Error: abc\nline 2\t'));
      expect(message.length, lessThanOrEqualTo(maxMessageLength));
      final int last = message.codeUnitAt(message.length - 1);
      expect(last >= 0xd800 && last <= 0xdbff, isFalse);
      final Map<String, Object?> httpRequest =
          (body['context']! as Map<String, Object?>)['httpRequest']!
              as Map<String, Object?>;
      expect(httpRequest['url'], 'https://e.example/X-Injected: 1');
    },
  );

  test(
    'a 401 from Error Reporting gets one retry with a refreshed token',
    () async {
      statuses = <int>[401, 200];
      expect((await relay()(post(event()))).statusCode, 204);
      expect(refreshes, <bool>[false, true]);
      expect(
        forwarded.map((http.Request r) => r.headers['authorization']),
        <String>['Bearer relay-token', 'Bearer fresh-token'],
      );
    },
  );

  test(
    'only an upstream 400 is 400; every other refusal is the relay\'s problem: 503',
    () async {
      for (final int s in <int>[401, 403, 404, 409, 301, 429, 500]) {
        statuses = <int>[s];
        forwarded.clear();
        final Response response = await relay()(post(event()));
        expect(response.statusCode, 503, reason: '$s');
        expect(response.headers['retry-after'], isNotNull, reason: '$s');
      }
      statuses = <int>[400];
      expect((await relay()(post(event()))).statusCode, 400);
    },
  );

  test('no access token is 503', () async {
    final Response response = await relay(
      token: ({bool forceRefresh = false}) async =>
          throw StateError('no credentials'),
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

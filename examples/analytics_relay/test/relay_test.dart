// The relay behind relayGuard, with a fake verifier and a fake Google Analytics (MockClient): nothing leaves the
// process.

import 'dart:async';
import 'dart:convert';

import 'package:analytics_relay/analytics_relay.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relay_guard/relay_guard.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

/// A made-up value for the tests; it only has to be recognisable in a log or an answer.
const String _secret = 'TESTSECRETnotreal0123';
const String _measurementId = 'G-TEST1234';

final class _Verifier implements CallerVerifier {
  @override
  Future<String> appIdOf(String token) async => switch (token) {
    'app-ok' => '1:1:web:a',
    'app-other' => '1:1:web:b',
    _ => throw const CallerRejected('bad App Check token'),
  };

  @override
  Future<String> uidOf(String token) async =>
      token == 'user-ok' ? 'u1' : throw const CallerRejected('bad ID token');
}

/// One relay with a fake upstream that answers [upstream] (or fails with what [fail] throws).
final class _Rig {
  _Rig({
    this.upstream = 204,
    this.fail,
    this.region = CollectionRegion.global,
    this.allowedAppIds,
    this.requireUser = false,
    this.timeout = const Duration(seconds: 10),
  }) {
    handler = const shelf.Pipeline()
        .addMiddleware(
          relayGuard(
            verifier: _Verifier(),
            path: 'collect',
            requireUser: requireUser,
            maxBodyBytes: guardMaxBodyBytes,
            log: logs.add,
          ),
        )
        .addHandler(
          analyticsRelay(
            measurementId: _measurementId,
            apiSecret: _secret,
            region: region,
            allowedAppIds: allowedAppIds,
            timeout: timeout,
            client: MockClient((http.Request request) async {
              sent.add(request);
              final Object? Function(http.Request)? failure = fail;
              if (failure != null) {
                final Object? error = failure(request);
                if (error != null) {
                  Error.throwWithStackTrace(error, StackTrace.current);
                }
                // Never answers.
                await Completer<void>().future;
              }
              return http.Response('', upstream);
            }),
            log: logs.add,
          ),
        );
  }

  final int upstream;

  /// Returns what the upstream throws, or null for an upstream that never answers.
  final Object? Function(http.Request request)? fail;
  final CollectionRegion region;
  final Set<String>? allowedAppIds;
  final bool requireUser;
  final Duration timeout;
  late final shelf.Handler handler;
  final List<http.Request> sent = <http.Request>[];
  final List<String> logs = <String>[];
  final List<String> answers = <String>[];
  final List<bool> closes = <bool>[];

  Future<int> post(
    Object? body, {
    String query = 'measurement_id=$_measurementId',
    Map<String, String> headers = const <String, String>{
      'x-firebase-appcheck': 'app-ok',
    },
  }) async {
    final List<int> bytes = body is String
        ? utf8.encode(body)
        : utf8.encode(jsonEncode(body));
    final shelf.Response response = await handler(
      shelf.Request(
        'POST',
        Uri.parse(
          'https://relay.test/collect${query.isEmpty ? '' : '?$query'}',
        ),
        headers: <String, String>{
          'content-type': 'application/json',
          'x-firebase-gmpid': '1:1:web:a',
          ...headers,
        },
        body: bytes,
      ),
    );
    answers
      ..add(await response.readAsString())
      ..add(response.headers.toString());
    closes.add(response.headers['connection'] == 'close');
    return response.statusCode;
  }
}

Map<String, Object?> _body({int events = 1, Map<String, Object?>? extra}) =>
    <String, Object?>{
      'client_id': '123456789.1764000000',
      'events': <Object?>[
        for (int i = 0; i < events; i++)
          <String, Object?>{
            'name': 'level_up',
            'params': <String, Object?>{'level': i},
          },
      ],
      ...?extra,
    };

void main() {
  group('forwarding', () {
    test(
      'adds the configured secret and measurement id, and no caller header',
      () async {
        final _Rig rig = _Rig();
        expect(
          await rig.post(
            _body(),
            headers: <String, String>{
              'x-firebase-appcheck': 'app-ok',
              'authorization': 'Bearer user-ok',
              'cookie': 'a=b',
              'x-forwarded-for': '203.0.113.9',
            },
          ),
          204,
        );
        expect(rig.sent, hasLength(1));
        final http.Request upstream = rig.sent.single;
        expect(upstream.method, 'POST');
        expect(upstream.url.scheme, 'https');
        expect(upstream.url.host, 'www.google-analytics.com');
        expect(upstream.url.path, '/mp/collect');
        expect(upstream.url.queryParametersAll, <String, List<String>>{
          'measurement_id': <String>[_measurementId],
          'api_secret': <String>[_secret],
        });
        expect(upstream.followRedirects, isFalse);
        expect(
          upstream.headers.keys.map((String k) => k.toLowerCase()).toSet(),
          <String>{'content-type'},
        );
        expect(jsonDecode(upstream.body), _body());
      },
    );

    test('forwards to region1 for the EU', () async {
      final _Rig rig = _Rig(region: CollectionRegion.eu);
      expect(await rig.post(_body()), 204);
      expect(rig.sent.single.url.host, 'region1.google-analytics.com');
    });

    test('accepts a request without the measurement_id query', () async {
      final _Rig rig = _Rig();
      expect(await rig.post(_body(), query: ''), 204);
    });

    test(
      'forwards what it checked when the body repeats a key (the last wins)',
      () async {
        final _Rig rig = _Rig();
        final String events = jsonEncode(_body(events: 30)['events']);
        expect(
          await rig.post(
            '{"client_id":"1.2","events":$events,"events":[{"name":"a"}]}',
          ),
          204,
        );
        expect(
          (jsonDecode(rig.sent.single.body) as Map<String, Object?>)['events'],
          hasLength(1),
        );
      },
    );

    test('takes a body as large as the client sends', () async {
      final _Rig rig = _Rig();
      final Map<String, Object?> body = _body(
        extra: <String, Object?>{'pad': ''},
      );
      final int base = utf8.encode(jsonEncode(body)).length;
      body['pad'] = 'x' * (clientMaxBodyBytes - base);
      expect(utf8.encode(jsonEncode(body)).length, clientMaxBodyBytes);
      expect(await rig.post(body), 204);

      body['pad'] = 'x' * (clientMaxBodyBytes - base + 1);
      expect(await rig.post(body), 413);
      expect(rig.sent, hasLength(1));
    });
  });

  group('refusals', () {
    test('no App Check token: 401 from the guard, nothing forwarded', () async {
      final _Rig rig = _Rig();
      expect(await rig.post(_body(), headers: const <String, String>{}), 401);
      expect(
        await rig.post(
          _body(),
          headers: const <String, String>{'x-firebase-appcheck': 'forged'},
        ),
        401,
      );
      expect(rig.sent, isEmpty);
    });

    test('a body with api_secret or measurement_id: 400', () async {
      final _Rig rig = _Rig();
      expect(
        await rig.post(_body(extra: <String, Object?>{'api_secret': 'x'})),
        400,
      );
      expect(
        await rig.post(
          _body(extra: <String, Object?>{'measurement_id': 'G-OTHER123'}),
        ),
        400,
      );
      expect(rig.sent, isEmpty);
    });

    test(
      'api_secret in the query: 400; another measurement_id or anything else: 403',
      () async {
        final _Rig rig = _Rig();
        for (final String query in <String>[
          'measurement_id=$_measurementId&api_secret=x',
          'api_secret=x',
        ]) {
          expect(await rig.post(_body(), query: query), 400, reason: query);
        }
        for (final String query in <String>[
          'measurement_id=G-OTHER123',
          'measurement_id=$_measurementId&measurement_id=G-OTHER123',
          'measurement_id=$_measurementId&firebase_app_id=x',
        ]) {
          expect(await rig.post(_body(), query: query), 403, reason: query);
        }
        expect(rig.sent, isEmpty);
      },
    );

    test('more than 25 events, or none: 400', () async {
      final _Rig rig = _Rig();
      expect(await rig.post(_body(events: 26)), 400);
      expect(await rig.post(_body(events: 0)), 400);
      expect(await rig.post(_body(events: 25)), 204);
      expect(rig.sent, hasLength(1));
    });

    test('not JSON, or not the shape of a request: 400', () async {
      final _Rig rig = _Rig();
      for (final Object? body in <Object?>[
        'not json',
        '{"client_id":',
        '[1,2]',
        '"text"',
        <String, Object?>{
          'events': <Object?>[
            <String, Object?>{'name': 'a'},
          ],
        },
        <String, Object?>{
          'client_id': 7,
          'events': <Object?>[
            <String, Object?>{'name': 'a'},
          ],
        },
        <String, Object?>{
          'client_id': '',
          'events': <Object?>[
            <String, Object?>{'name': 'a'},
          ],
        },
        <String, Object?>{
          'client_id': 'x' * (maxClientIdLength + 1),
          'events': <Object?>[
            <String, Object?>{'name': 'a'},
          ],
        },
        <String, Object?>{'client_id': '1.2', 'events': 'a'},
        <String, Object?>{
          'client_id': '1.2',
          'events': <Object?>['a'],
        },
        <String, Object?>{
          'client_id': '1.2',
          'events': <Object?>[<String, Object?>{}],
        },
        <String, Object?>{
          'client_id': '1.2',
          'events': <Object?>[
            <String, Object?>{'name': ''},
          ],
        },
      ]) {
        expect(await rig.post(body), 400, reason: '$body');
      }
      // Invalid UTF-8.
      final shelf.Response response = await rig.handler(
        shelf.Request(
          'POST',
          Uri.parse('https://relay.test/collect'),
          headers: const <String, String>{
            'content-type': 'application/json',
            'x-firebase-appcheck': 'app-ok',
          },
          body: <int>[0xff, 0xfe, 0x7b],
        ),
      );
      expect(response.statusCode, 400);
      expect(rig.sent, isEmpty);
    });

    test('an app outside ALLOWED_APP_IDS: 403', () async {
      final _Rig rig = _Rig(allowedAppIds: <String>{'1:1:web:a'});
      expect(
        await rig.post(
          _body(),
          headers: const <String, String>{'x-firebase-appcheck': 'app-other'},
        ),
        403,
      );
      expect(await rig.post(_body()), 204);
      expect(rig.sent, hasLength(1));
    });

    test('with requireUser, no or a bad ID token: 401', () async {
      final _Rig rig = _Rig(requireUser: true);
      expect(await rig.post(_body()), 401);
      expect(
        await rig.post(
          _body(),
          headers: const <String, String>{
            'x-firebase-appcheck': 'app-ok',
            'authorization': 'Bearer forged',
          },
        ),
        401,
      );
      expect(
        await rig.post(
          _body(),
          headers: const <String, String>{
            'x-firebase-appcheck': 'app-ok',
            'authorization': 'Bearer user-ok',
          },
        ),
        204,
      );
      expect(rig.sent, hasLength(1));
    });

    test('a bad ID token is refused even when no user is required', () async {
      final _Rig rig = _Rig();
      expect(
        await rig.post(
          _body(),
          headers: const <String, String>{
            'x-firebase-appcheck': 'app-ok',
            'authorization': 'Bearer forged',
          },
        ),
        401,
      );
      expect(rig.sent, isEmpty);
    });
  });

  group('upstream answers', () {
    test('2xx: 204', () async {
      for (final int status in <int>[200, 204]) {
        expect(await _Rig(upstream: status).post(_body()), 204);
      }
    });

    test('5xx, 429 or a redirect: 503 with Retry-After', () async {
      for (final int status in <int>[500, 502, 503, 429, 302, 307]) {
        final _Rig rig = _Rig(upstream: status);
        expect(await rig.post(_body()), 503, reason: '$status');
        expect(rig.answers.last, contains('retry-after'), reason: '$status');
        expect(rig.sent, hasLength(1), reason: 'no retry inside the relay');
      }
    });

    test('a refused body (400, 413, 422): 400', () async {
      for (final int status in <int>[400, 413, 422]) {
        expect(await _Rig(upstream: status).post(_body()), 400);
      }
    });

    test('a 4xx that points at the relay (401, 403, 404, 405): 503', () async {
      for (final int status in <int>[401, 403, 404, 405]) {
        expect(
          await _Rig(upstream: status).post(_body()),
          503,
          reason: '$status',
        );
      }
    });

    test('a network error or no answer in time: 503', () async {
      final _Rig failing = _Rig(
        fail: (http.Request request) =>
            http.ClientException('connection refused', request.url),
      );
      expect(await failing.post(_body()), 503);
      final _Rig silent = _Rig(
        fail: (_) => null,
        timeout: const Duration(milliseconds: 50),
      );
      expect(await silent.post(_body()), 503);
      expect(silent.sent, hasLength(1));
    });
  });

  group('the secret', () {
    test('is in no answer and no log line', () async {
      final List<_Rig> rigs = <_Rig>[
        for (final int status in <int>[204, 400, 403, 429, 500, 302])
          _Rig(upstream: status),
        // The message of a ClientException quotes the URL, which holds the secret.
        _Rig(
          fail: (http.Request request) =>
              http.ClientException('failed: ${request.url}', request.url),
        ),
        _Rig(
          fail: (http.Request request) => StateError('failed: ${request.url}'),
        ),
        _Rig(fail: (_) => null, timeout: const Duration(milliseconds: 20)),
        _Rig(allowedAppIds: <String>{'1:1:web:z'}),
        _Rig(requireUser: true),
      ];
      for (final _Rig rig in rigs) {
        await rig.post(_body());
        await rig.post(_body(events: 26));
        await rig.post('not json');
        await rig.post(_body(extra: <String, Object?>{'api_secret': _secret}));
        await rig.post(_body(), query: 'api_secret=other');
        await rig.post(_body(), headers: const <String, String>{});
      }
      final List<String> logs = <String>[
        for (final _Rig rig in rigs) ...rig.logs,
      ];
      final List<String> answers = <String>[
        for (final _Rig rig in rigs) ...rig.answers,
      ];
      // The rigs did forward, refuse and fail, and said so.
      expect(logs, isNotEmpty);
      expect(rigs.first.sent.single.url.queryParameters['api_secret'], _secret);
      for (final String line in <String>[...logs, ...answers]) {
        expect(line, isNot(contains(_secret)));
        expect(line, isNot(contains('api_secret=')));
      }
    });

    test('is not quoted when it is refused at construction', () {
      const String bad = 'TESTSECRET with space';
      expect(
        () => analyticsRelay(measurementId: _measurementId, apiSecret: bad),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.toString(),
            'toString',
            isNot(contains('TESTSECRET')),
          ),
        ),
      );
      expect(
        () => analyticsRelay(measurementId: 'UA-1', apiSecret: _secret),
        throwsArgumentError,
      );
    });
  });

  test('a body that cannot be encoded again: 400, nothing upstream', () async {
    final _Rig rig = _Rig();
    final String infinite =
        '{"client_id":"1.2","events":[{"name":"a","params":{"n":1e999}}]}';
    final String deep =
        '{"client_id":"1.2","events":[{"name":"a","params":{"n":${'[' * 6000}${']' * 6000}}}]}';
    for (final String body in <String>[infinite, deep]) {
      expect(await rig.post(body), 400);
    }
    expect(rig.sent, isEmpty);
  });

  test('every answer closes the connection', () async {
    final _Rig rig = _Rig();
    await rig.post(_body());
    await rig.post(_body(), query: 'api_secret=x');
    expect(rig.closes, everyElement(isTrue));
    expect(rig.closes, hasLength(2));
  });
}

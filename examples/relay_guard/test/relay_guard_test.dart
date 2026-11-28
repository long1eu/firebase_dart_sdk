import 'dart:convert';

import 'package:firebase_admin_dart/firebase_admin_dart.dart';
import 'package:relay_guard/relay_guard.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Accepts the tokens `app-ok` (app `1:1:web:a`) and `user-ok` (uid `u1`); `broken` stands for keys that could
/// not be fetched.
final class _Verifier implements CallerVerifier {
  int calls = 0;

  @override
  Future<String> appIdOf(String token) async {
    calls++;
    if (token == 'broken') {
      throw StateError('keys unavailable');
    }
    if (token != 'app-ok') {
      throw const CallerRejected('bad app check');
    }
    return '1:1:web:a';
  }

  @override
  Future<String> uidOf(String token) async {
    calls++;
    if (token != 'user-ok') {
      throw const CallerRejected('bad id token');
    }
    return 'u1';
  }
}

void main() {
  late _Verifier verifier;
  late List<String> logs;
  late DateTime now;
  late List<Caller> seen;

  Handler handler({
    bool requireAppCheck = true,
    bool requireUser = false,
    int maxPerMinute = 60,
  }) => const Pipeline()
      .addMiddleware(
        relayGuard(
          verifier: verifier,
          requireAppCheck: requireAppCheck,
          requireUser: requireUser,
          maxBodyBytes: 1024,
          maxPerMinute: maxPerMinute,
          clock: () => now,
          log: logs.add,
        ),
      )
      .addHandler((Request request) {
        seen.add(callerOf(request));
        return Response.ok(utf8.decode(bodyOf(request)));
      });

  Request post({
    String body = '{"message":"x"}',
    Map<String, String> headers = const <String, String>{
      'x-firebase-appcheck': 'app-ok',
    },
    String method = 'POST',
    String contentType = 'application/json',
  }) => Request(
    method,
    Uri.parse('http://relay.test/errors'),
    body: body,
    headers: <String, String>{'content-type': contentType, ...headers},
  );

  setUp(() {
    verifier = _Verifier();
    logs = <String>[];
    now = DateTime.utc(2026, 11, 28, 12);
    seen = <Caller>[];
  });

  test(
    'a valid request reaches the handler with its caller and body',
    () async {
      final Response response = await handler()(
        post(
          headers: <String, String>{
            'x-firebase-appcheck': 'app-ok',
            'authorization': 'Bearer user-ok',
          },
        ),
      );
      expect(response.statusCode, 200);
      expect(await response.readAsString(), '{"message":"x"}');
      expect(seen.single.appId, '1:1:web:a');
      expect(seen.single.uid, 'u1');
    },
  );

  test('only POST of JSON', () async {
    expect((await handler()(post(method: 'GET', body: ''))).statusCode, 405);
    expect((await handler()(post(contentType: 'text/plain'))).statusCode, 415);
  });

  test('a body over the limit is refused, declared or streamed', () async {
    expect((await handler()(post(body: 'x' * 2000))).statusCode, 413);
    final Request streamed = Request(
      'POST',
      Uri.parse('http://relay.test/errors'),
      body: Stream<List<int>>.fromIterable(<List<int>>[
        List<int>.filled(800, 32),
        List<int>.filled(800, 32),
      ]),
      headers: <String, String>{
        'content-type': 'application/json',
        'x-firebase-appcheck': 'app-ok',
      },
    );
    expect((await handler()(streamed)).statusCode, 413);
    expect(seen, isEmpty);
  });

  test('a missing or invalid App Check token is 401 without detail', () async {
    final Response missing = await handler()(
      post(headers: const <String, String>{}),
    );
    expect(missing.statusCode, 401);
    expect(await missing.readAsString(), isNot(contains('App Check')));
    expect(
      (await handler()(
        post(headers: <String, String>{'x-firebase-appcheck': 'forged'}),
      )).statusCode,
      401,
    );
    expect(logs, <String>[
      'refused: no App Check token',
      'refused: bad app check',
    ]);
  });

  test(
    'App Check can be optional; a token that is present is still checked',
    () async {
      expect(
        (await handler(requireAppCheck: false)(
          post(headers: const <String, String>{}),
        )).statusCode,
        200,
      );
      expect(
        (await handler(requireAppCheck: false)(
          post(headers: <String, String>{'x-firebase-appcheck': 'forged'}),
        )).statusCode,
        401,
      );
    },
  );

  test(
    'an ID token that is present is checked; required only with requireUser',
    () async {
      expect(
        (await handler()(
          post(
            headers: <String, String>{
              'x-firebase-appcheck': 'app-ok',
              'authorization': 'Bearer bad',
            },
          ),
        )).statusCode,
        401,
      );
      expect(
        (await handler()(
          post(
            headers: <String, String>{
              'x-firebase-appcheck': 'app-ok',
              'authorization': 'Basic abc',
            },
          ),
        )).statusCode,
        401,
      );
      expect((await handler(requireUser: true)(post())).statusCode, 401);
      expect((await handler()(post())).statusCode, 200);
    },
  );

  test('a verifier that cannot check is 503 with Retry-After', () async {
    final Response response = await handler()(
      post(headers: <String, String>{'x-firebase-appcheck': 'broken'}),
    );
    expect(response.statusCode, 503);
    expect(response.headers['retry-after'], '30');
  });

  test('the rate limit counts per user, and frees up after a minute', () async {
    final Handler h = handler(maxPerMinute: 3);
    Request asUser() => post(
      headers: <String, String>{
        'x-firebase-appcheck': 'app-ok',
        'authorization': 'Bearer user-ok',
      },
    );
    for (int i = 0; i < 3; i++) {
      expect((await h(asUser())).statusCode, 200);
    }
    final Response limited = await h(asUser());
    expect(limited.statusCode, 429);
    expect(limited.headers['retry-after'], '60');
    // Another caller (no user: app and address) is not affected.
    expect((await h(post())).statusCode, 200);
    now = now.add(const Duration(seconds: 61));
    expect((await h(asUser())).statusCode, 200);
  });

  test(
    'AdminCallerVerifier turns a malformed token into CallerRejected without a request',
    () async {
      final AdminCallerVerifier admin = AdminCallerVerifier(
        FirebaseAdminApp.emulator(
          projectId: 'demo-test',
          authEmulatorHost: '127.0.0.1:1',
        ),
      );
      await expectLater(
        admin.appIdOf('not.a.jwt'),
        throwsA(isA<CallerRejected>()),
      );
      await expectLater(
        admin.uidOf('not-a-jwt'),
        throwsA(isA<CallerRejected>()),
      );
    },
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_admin_dart/firebase_admin_dart.dart';
import 'package:relay_guard/relay_guard.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Accepts App Check tokens starting with `app-ok` (app `1:1:web:a`, or `1:1:web:b` for `app-ok-other-app`) and
/// ID tokens starting with `user-ok` (uid `u1`, or the rest after `user-ok-`); `broken` stands for keys that
/// could not be fetched.
final class _Verifier implements CallerVerifier {
  @override
  Future<String> appIdOf(String token) async {
    if (token == 'broken') {
      throw StateError('keys unavailable');
    }
    if (!token.startsWith('app-ok')) {
      throw const CallerRejected('bad app check');
    }
    return token == 'app-ok-other-app' ? '1:1:web:b' : '1:1:web:a';
  }

  @override
  Future<String> uidOf(String token) async {
    if (!token.startsWith('user-ok')) {
      throw const CallerRejected('bad id token');
    }
    return token == 'user-ok' ? 'u1' : token.substring('user-ok-'.length);
  }
}

void main() {
  late List<String> logs;
  late DateTime now;
  late List<Caller> seen;

  Handler handler({
    bool requireAppCheck = true,
    bool requireUser = false,
    int maxPerCaller = 60,
    int maxPerApp = 3000,
    int maxPerMinute = 10000,
    int trustedProxyHops = 0,
    String? path,
    Duration bodyTimeout = const Duration(seconds: 10),
  }) => const Pipeline()
      .addMiddleware(
        relayGuard(
          verifier: _Verifier(),
          requireAppCheck: requireAppCheck,
          requireUser: requireUser,
          maxBodyBytes: 1024,
          maxPerCallerPerMinute: maxPerCaller,
          maxPerAppPerMinute: maxPerApp,
          maxPerMinute: maxPerMinute,
          trustedProxyHops: trustedProxyHops,
          path: path,
          bodyTimeout: bodyTimeout,
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
    String path = 'errors',
  }) => Request(
    method,
    Uri.parse('http://relay.test/$path'),
    body: body,
    headers: <String, String>{'content-type': contentType, ...headers},
  );

  setUp(() {
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

  test(
    'only POST of JSON, only the given path; refusals close the connection',
    () async {
      expect((await handler()(post(method: 'GET', body: ''))).statusCode, 405);
      expect(
        (await handler()(post(contentType: 'text/plain'))).statusCode,
        415,
      );
      final Response wrong = await handler(path: 'errors')(post(path: 'other'));
      expect(wrong.statusCode, 404);
      expect(wrong.headers['connection'], 'close');
      expect((await handler(path: 'errors')(post())).statusCode, 200);
    },
  );

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

  test(
    'a body that does not arrive in time is 408; one that breaks off is 400',
    () async {
      final StreamController<List<int>> never = StreamController<List<int>>();
      final Response slow =
          await handler(bodyTimeout: const Duration(milliseconds: 300))(
            Request(
              'POST',
              Uri.parse('http://relay.test/errors'),
              body: never.stream,
              headers: <String, String>{
                'content-type': 'application/json',
                'x-firebase-appcheck': 'app-ok',
              },
            ),
          );
      expect(slow.statusCode, 408);
      await never.close();
      final Response broken = await handler()(
        Request(
          'POST',
          Uri.parse('http://relay.test/errors'),
          body: Stream<List<int>>.error(
            const HttpException('connection closed'),
          ),
          headers: <String, String>{
            'content-type': 'application/json',
            'x-firebase-appcheck': 'app-ok',
          },
        ),
      );
      expect(broken.statusCode, 400);
    },
  );

  test('a missing or invalid App Check token is 401 without detail', () async {
    final Response missing = await handler()(
      post(headers: const <String, String>{}),
    );
    expect(missing.statusCode, 401);
    expect(await missing.readAsString(), isEmpty);
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
    'an ID token that is present is checked; requireUser; the bearer form',
    () async {
      expect((await handler(requireUser: true)(post())).statusCode, 401);
      expect((await handler()(post())).statusCode, 200);
      for (final String value in <String>[
        'Bearer bad',
        'bearer user-ok',
        'Bearer  user-ok',
        'Bearer ',
        'Basic abc',
      ]) {
        expect(
          (await handler()(
            post(
              headers: <String, String>{
                'x-firebase-appcheck': 'app-ok',
                'authorization': value,
              },
            ),
          )).statusCode,
          401,
          reason: value,
        );
      }
    },
  );

  test('a verifier that cannot check is 503 with Retry-After', () async {
    final Response response = await handler()(
      post(headers: <String, String>{'x-firebase-appcheck': 'broken'}),
    );
    expect(response.statusCode, 503);
    expect(response.headers['retry-after'], '30');
  });

  group('rate limits', () {
    Request asUser(String user, {String token = 'app-ok'}) => post(
      headers: <String, String>{
        'x-firebase-appcheck': token,
        'authorization': 'Bearer user-ok-$user',
      },
    );

    test('per user, freed after a minute', () async {
      final Handler h = handler(maxPerCaller: 3);
      for (int i = 0; i < 3; i++) {
        expect((await h(asUser('a', token: 'app-ok-$i'))).statusCode, 200);
      }
      final Response limited = await h(asUser('a', token: 'app-ok-9'));
      expect(limited.statusCode, 429);
      expect(limited.headers['retry-after'], '60');
      expect((await h(asUser('b', token: 'app-ok-10'))).statusCode, 200);
      now = now.add(const Duration(seconds: 61));
      expect((await h(asUser('a', token: 'app-ok-11'))).statusCode, 200);
    });

    test(
      'per App Check token: many accounts do not multiply the budget',
      () async {
        final Handler h = handler(maxPerCaller: 3);
        int admitted = 0;
        for (int i = 0; i < 50; i++) {
          if ((await h(asUser('account-$i'))).statusCode == 200) {
            admitted++;
          }
        }
        expect(admitted, 3);
      },
    );

    test('per app, and in all', () async {
      final Handler perApp = handler(maxPerApp: 5);
      int admitted = 0;
      for (int i = 0; i < 10; i++) {
        if ((await perApp(
              post(
                headers: <String, String>{'x-firebase-appcheck': 'app-ok-$i'},
              ),
            )).statusCode ==
            200) {
          admitted++;
        }
      }
      expect(admitted, 5);
      expect(
        (await perApp(
          post(
            headers: <String, String>{
              'x-firebase-appcheck': 'app-ok-other-app',
            },
          ),
        )).statusCode,
        200,
      );
      final Handler all = handler(maxPerMinute: 2);
      expect(
        (await all(
          post(headers: <String, String>{'x-firebase-appcheck': 'app-ok-1'}),
        )).statusCode,
        200,
      );
      expect(
        (await all(
          post(
            headers: <String, String>{
              'x-firebase-appcheck': 'app-ok-other-app',
            },
          ),
        )).statusCode,
        200,
      );
      expect(
        (await all(
          post(headers: <String, String>{'x-firebase-appcheck': 'app-ok-2'}),
        )).statusCode,
        429,
      );
    });

    test(
      'without App Check, per address: X-Forwarded-For counts only with trusted hops, from the right',
      () async {
        Request from(String forwarded) =>
            post(headers: <String, String>{'x-forwarded-for': forwarded});
        final Handler untrusted = handler(
          requireAppCheck: false,
          maxPerCaller: 2,
        );
        // Without trusted hops the header is ignored: here every request comes from "unknown".
        expect((await untrusted(from('1.1.1.1'))).statusCode, 200);
        expect((await untrusted(from('2.2.2.2'))).statusCode, 200);
        expect((await untrusted(from('3.3.3.3'))).statusCode, 429);

        final Handler proxied = handler(
          requireAppCheck: false,
          maxPerCaller: 2,
          trustedProxyHops: 1,
        );
        // A caller cannot choose its address by prepending entries: the last one is what the proxy saw.
        expect((await proxied(from('9.9.9.1, 5.5.5.5'))).statusCode, 200);
        expect((await proxied(from('9.9.9.2, 5.5.5.5'))).statusCode, 200);
        expect((await proxied(from('9.9.9.3, 5.5.5.5'))).statusCode, 429);
        expect((await proxied(from('6.6.6.6'))).statusCode, 200);
        // IPv6 counts per /64.
        expect((await proxied(from('2001:db8:1:2::1'))).statusCode, 200);
        expect((await proxied(from('2001:db8:1:2::2'))).statusCode, 200);
        expect((await proxied(from('2001:db8:1:2:ffff::3'))).statusCode, 429);
      },
    );
  });

  test('serveGuarded destroys a connection that never sends its body', () async {
    final HttpServer server = await serveGuarded(
      handler(),
      InternetAddress.loopbackIPv4,
      0,
      connectionDeadline: const Duration(milliseconds: 500),
    );
    addTearDown(() => server.close(force: true));
    final Socket socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      server.port,
    );
    socket.write(
      'POST /errors HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: 50\r\n\r\n',
    );
    await socket.flush();
    final Stopwatch watch = Stopwatch()..start();
    await socket.drain<void>().timeout(const Duration(seconds: 5));
    expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
    socket.destroy();
  });

  test('serveGuarded answers a complete request normally', () async {
    final HttpServer server = await serveGuarded(
      handler(),
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    final HttpClient client = HttpClient();
    addTearDown(client.close);
    final HttpClientRequest request = await client.post(
      '127.0.0.1',
      server.port,
      '/errors',
    );
    request.headers
      ..contentType = ContentType.json
      ..set('x-firebase-appcheck', 'app-ok');
    request.write('{"message":"x"}');
    final HttpClientResponse response = await request.close();
    expect(response.statusCode, 200);
    await response.drain<void>();
  });

  test(
    'AdminCallerVerifier refuses malformed tokens without a request',
    () async {
      final AdminCallerVerifier admin = AdminCallerVerifier(
        FirebaseAdminApp.emulator(
          projectId: 'demo-test',
          authEmulatorHost: '127.0.0.1:1',
        ),
        allowEmulator: true,
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

  test(
    'AdminCallerVerifier refuses an emulator app unless allowed, and a malformed project number',
    () {
      final FirebaseAdminApp emulator = FirebaseAdminApp.emulator(
        projectId: 'demo-test',
        authEmulatorHost: '127.0.0.1:1',
      );
      expect(() => AdminCallerVerifier(emulator), throwsArgumentError);
      expect(
        () => AdminCallerVerifier(
          emulator,
          allowEmulator: true,
          projectNumber: '',
        ),
        throwsArgumentError,
      );
    },
  );
}

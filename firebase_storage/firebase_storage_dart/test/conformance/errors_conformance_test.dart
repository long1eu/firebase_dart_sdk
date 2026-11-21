import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../fakes.dart';
import 'conformance.dart';

// Conformance with request.test.ts and the error handlers of requests.test.ts of the JS SDK
// (`sharedErrorHandler`, `objectErrorHandler`, the backoff of `implementation/backoff.ts`), and the deliberate
// differences of storage_api_contract.md: X-Firebase-GMPID is sent, every error carries its HTTP status and the
// response body, a 401 is retried once with a refreshed token.
void main() {
  late FirebaseApp app;
  late List<Recorded> requests;
  late FakeTime time;
  late Future<http.Response> Function(Recorded request) respond;
  final List<FirebaseStorage> instances = <FirebaseStorage>[];

  FirebaseStorage storage({
    StorageRetryPolicy retry = const StorageRetryPolicy(),
  }) {
    final FirebaseStorage instance = storageWith(
      app,
      (Recorded r) => respond(r),
      requests: requests,
      time: time,
      retry: retry,
    );
    instances.add(instance);
    return instance;
  }

  setUp(() {
    app = newApp();
    requests = <Recorded>[];
    time = FakeTime();
    respond = (_) => json(serverResource);
  });

  tearDown(() async {
    for (final FirebaseStorage instance in instances) {
      instance.close();
    }
    instances.clear();
    await app.delete();
  });

  Matcher storageError(String code, {int? status, Object? body}) =>
      isA<FirebaseStorageException>()
          .having((FirebaseStorageException e) => e.code, 'code', code)
          .having(
            (FirebaseStorageException e) => e.httpStatus,
            'httpStatus',
            status,
          )
          .having(
            (FirebaseStorageException e) => e.serverResponse,
            'serverResponse',
            body,
          );

  group('request.test.ts', () {
    test(
      'Simple success request works: version header, app id, no token',
      () async {
        await storage().ref('x').metadata();
        expect(headersOf(requests.single), commonHeaders());
      },
    );

    test('Sends auth tokens along properly', () async {
      app.authProvider = FakeAuth(<String?>['totallyLegitAuthToken']);
      await storage().ref('x').metadata();
      expect(
        headersOf(requests.single),
        commonHeaders(<String, String>{
          'authorization': 'Firebase totallyLegitAuthToken',
        }),
      );
    });

    test(
      'Sends APP ID along properly (JS never does: its _appId is always null)',
      () async {
        await storage().ref('x').metadata();
        expect(headersOf(requests.single)['x-firebase-gmpid'], appId);
      },
    );

    test('sends appcheck token along properly', () async {
      app.appCheckProvider = FakeAppCheck(
        AppCheckTokenResult('appcheck-token'),
      );
      await storage().ref('x').metadata();
      expect(
        headersOf(requests.single)['x-firebase-appcheck'],
        'appcheck-token',
      );
    });

    test('an App Check provider that fails: the header is left out', () async {
      // JS: the interop getToken never throws and sends a dummy token instead.
      app.appCheckProvider = FakeAppCheck(
        AppCheckTokenResult('unused'),
        error: StateError('attestation failed'),
      );
      await storage().ref('x').metadata();
      expect(
        headersOf(requests.single).containsKey('x-firebase-appcheck'),
        isFalse,
      );
    });

    test(
      'an empty App Check token is left out (JS sends the empty header)',
      () async {
        app.appCheckProvider = FakeAppCheck(AppCheckTokenResult(''));
        await storage().ref('x').metadata();
        expect(
          headersOf(requests.single).containsKey('x-firebase-appcheck'),
          isFalse,
        );
      },
    );

    test('URL parameters get encoded correctly (encodeURIComponent)', () async {
      respond = (_) => json(<String, Object?>{});
      await storage().ref("par?am #&=+/é!~*'()").list(pageToken: 'v#al?2&=');
      expect(
        requests.single.url.toString(),
        '$prod/v0/b/b/o'
        "?prefix=par%3Fam%20%23%26%3D%2B%2F%C3%A9!~*'()%2F"
        '&delimiter=%2F&pageToken=v%23al%3F2%26%3D',
      );
    });

    test(
      'Propagates errors acceptably: a success body the handler cannot read is unknown',
      () async {
        respond = (_) async => http.Response('[1, 2]', 200);
        await expectLater(
          storage().ref('x').metadata(),
          throwsA(storageError('unknown', status: 200)),
        );
      },
    );
  });

  group('status mapping (objectErrorHandler on object operations)', () {
    final Map<int, String> table = <int, String>{
      400: 'unknown',
      401: 'unauthenticated',
      402: 'quota-exceeded',
      403: 'unauthorized',
      404: 'object-not-found',
      409: 'unknown',
      412: 'unknown',
      416: 'unknown',
    };
    for (final MapEntry<int, String> entry in table.entries) {
      test(
        '${entry.key} is ${entry.value}, with the status and the body',
        () async {
          // JS: object-not-found has status 0 and no operation reads the body; both are fixed here.
          respond = (_) async => http.Response('body ${entry.key}', entry.key);
          await expectLater(
            storage().ref('x').metadata(),
            throwsA(
              storageError(
                entry.value,
                status: entry.key,
                body: 'body ${entry.key}',
              ),
            ),
          );
          expect(requests, hasLength(1));
        },
      );
    }

    test(
      '401 with the App Check message in the body is unauthorized-app',
      () async {
        // JS matches connection.getErrorText() (the status text), so this is unreachable there.
        respond = (_) async => http.Response(
          '{"error":{"code":401,"message":"Firebase App Check token is invalid."}}',
          401,
        );
        await expectLater(
          storage().ref('x').metadata(),
          throwsA(
            isA<FirebaseStorageException>().having(
              (FirebaseStorageException e) => e.code,
              'code',
              'unauthorized-app',
            ),
          ),
        );
      },
    );

    test('the messages are those of the JS SDK', () async {
      final Map<int, String> messages = <int, String>{
        401:
            'User is not authenticated, please authenticate using Firebase Authentication and try again.',
        402:
            "Quota for bucket 'b' exceeded, please view quota on https://firebase.google.com/pricing/.",
        403: "User does not have permission to access 'a/x'.",
        404: "Object 'a/x' does not exist.",
      };
      for (final MapEntry<int, String> entry in messages.entries) {
        respond = (_) async => http.Response('', entry.key);
        await expectLater(
          storage().ref('a/x').metadata(),
          throwsA(
            isA<FirebaseStorageException>().having(
              (FirebaseStorageException e) => e.message,
              'message',
              entry.value,
            ),
          ),
        );
      }
    });

    test('the body in serverResponse is cut at 16 KiB', () async {
      respond = (_) async => http.Response('x' * (64 * 1024), 400);
      await expectLater(
        storage().ref('x').metadata(),
        throwsA(
          isA<FirebaseStorageException>().having(
            (FirebaseStorageException e) => e.serverResponse?.length,
            'serverResponse length',
            16 * 1024,
          ),
        ),
      );
    });
  });

  group('sharedErrorHandler only (list, multipart upload)', () {
    test('list: 404 stays unknown with the status', () async {
      respond = (_) async => http.Response('Not Found', 404);
      await expectLater(
        storage().ref('x').list(),
        throwsA(storageError('unknown', status: 404, body: 'Not Found')),
      );
    });

    test('putString: 404 stays unknown, 403 is unauthorized', () async {
      respond = (_) async => http.Response('', 404);
      await expectLater(
        storage().ref('x').putString('a'),
        throwsA(storageError('unknown', status: 404, body: '')),
      );
      respond = (_) async => http.Response('', 403);
      await expectLater(
        storage().ref('x').putString('a'),
        throwsStorageCode('unauthorized'),
      );
    });
  });

  group('retry and backoff (backoff.ts)', () {
    for (final int status in <int>[500, 503, 509, 599, 408, 429]) {
      test('$status is retried', () async {
        int n = 0;
        respond = (_) async =>
            n++ == 0 ? http.Response('', status) : await json(serverResource);
        await storage().ref('x').metadata();
        expect(requests, hasLength(2));
      });
    }

    test('a network error is retried', () async {
      int n = 0;
      respond = (Recorded r) async {
        if (n++ == 0) {
          throw http.ClientException('connection reset', r.url);
        }
        return json(serverResource);
      };
      await storage().ref('x').metadata();
      expect(requests, hasLength(2));
    });

    test(
      'waits 2, 4, 8, 16, 32, 64, 64 s plus jitter, then retry-limit-exceeded at the deadline',
      () async {
        // Random is 0.5. JS: on the global timeout the pending wait is cut and one last attempt is made.
        respond = (_) async => http.Response('', 503);
        await expectLater(
          storage(
            retry: const StorageRetryPolicy(operation: Duration(minutes: 5)),
          ).ref('x').metadata(),
          throwsA(
            isA<FirebaseStorageException>()
                .having(
                  (FirebaseStorageException e) => e.code,
                  'code',
                  'retry-limit-exceeded',
                )
                .having(
                  (FirebaseStorageException e) => e.httpStatus,
                  'httpStatus',
                  503,
                ),
          ),
        );
        final List<int> waits = <int>[
          for (final Duration d in time.delays) d.inMilliseconds,
        ];
        // 2.5+4.5+8.5+16.5+32.5+64.5+64.5+64.5 = 258 s; the remaining 42 s of the 300 s are the last wait.
        expect(waits, <int>[
          2500,
          4500,
          8500,
          16500,
          32500,
          64500,
          64500,
          64500,
          42000,
        ]);
        expect(requests, hasLength(waits.length + 1));
      },
    );

    test('a zero retry time makes a single attempt', () async {
      respond = (_) async => http.Response('', 500);
      await expectLater(
        storage(
          retry: const StorageRetryPolicy(operation: Duration.zero),
        ).ref('x').metadata(),
        throwsStorageCode('retry-limit-exceeded'),
      );
      expect(requests, hasLength(1));
    });

    test(
      'the tokens are fetched once per logical request, not per attempt',
      () async {
        final FakeAuth auth = FakeAuth(<String?>['t']);
        app.authProvider = auth;
        auth.calls
            .clear(); // The setter of FirebaseApp warms the provider up with forceRefresh: true.
        int n = 0;
        respond = (_) async =>
            n++ < 2 ? http.Response('', 503) : await json(serverResource);
        await storage().ref('x').metadata();
        expect(requests, hasLength(3));
        expect(auth.calls, <bool>[false]);
      },
    );
  });

  group(
    '401 and the token (contract: one forced refresh; JS never refreshes)',
    () {
      test('a 401 is sent again once with a refreshed token', () async {
        final FakeAuth auth = FakeAuth(<String?>['old', 'new']);
        app.authProvider = auth;
        auth.calls
            .clear(); // The setter of FirebaseApp warms the provider up with forceRefresh: true.
        int n = 0;
        respond = (_) async =>
            n++ == 0 ? http.Response('', 401) : await json(serverResource);
        await storage().ref('x').metadata();
        expect(auth.calls, <bool>[false, true]);
        expect(headersOf(requests[0])['authorization'], 'Firebase old');
        expect(headersOf(requests[1])['authorization'], 'Firebase new');
        expect(time.delays, isEmpty, reason: 'right away, no backoff');
      });

      test('a second 401 is unauthenticated', () async {
        app.authProvider = FakeAuth(<String?>['old', 'new']);
        respond = (_) async => http.Response('', 401);
        await expectLater(
          storage().ref('x').metadata(),
          throwsA(storageError('unauthenticated', status: 401, body: '')),
        );
        expect(requests, hasLength(2));
      });

      test('without a signed-in user a 401 is not retried', () async {
        app.authProvider = FakeAuth(<String?>[null]);
        respond = (_) async => http.Response('', 401);
        await expectLater(
          storage().ref('x').metadata(),
          throwsStorageCode('unauthenticated'),
        );
        expect(requests, hasLength(1));
      });
    },
  );
}

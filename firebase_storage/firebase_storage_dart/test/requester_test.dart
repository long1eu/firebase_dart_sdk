import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:firebase_storage_dart/src/errors.dart';
import 'package:firebase_storage_dart/src/request/requester.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'fakes.dart';

// Headers, tokens, retries and timeouts of the request layer (request.test.ts and backoff of the JS SDK, plus
// the deliberate differences of this package).
void main() {
  late FirebaseApp app;
  late List<Recorded> requests;
  late FakeTime time;

  setUp(() {
    app = newApp();
    requests = <Recorded>[];
    time = FakeTime();
  });

  tearDown(() => app.delete());

  FirebaseStorage storageOf(
    Future<http.Response> Function(Recorded request) handler, {
    StorageRetryPolicy retry = const StorageRetryPolicy(),
    String? emulatorHost,
    String? mockUserToken,
    Duration requestTimeout = const Duration(minutes: 1),
  }) {
    final FirebaseStorage storage = storageWith(
      app,
      handler,
      requests: requests,
      time: time,
      retry: retry,
      emulatorHost: emulatorHost,
      mockUserToken: mockUserToken,
      requestTimeout: requestTimeout,
    );
    addTearDown(storage.close);
    return storage;
  }

  /// Answers with the statuses in turn (the last one repeats) and `{}` as the body.
  Future<http.Response> Function(Recorded) statuses(List<int> codes) {
    int index = 0;
    return (_) async {
      final int status = codes[index < codes.length ? index : codes.length - 1];
      index++;
      return http.Response(
        status == 200 ? '{"name":"o"}' : 'error $status',
        status,
      );
    };
  }

  group('headers', () {
    test(
      'version and app id on every request, no token without a provider',
      () async {
        await storageOf(statuses(<int>[200])).ref('o').metadata();
        final Map<String, String> headers = requests.single.headers;
        expect(headers['X-Firebase-Storage-Version'], 'dart/0.1.2');
        expect(headers['X-Firebase-GMPID'], '1:123:dart:abc');
        expect(headers.containsKey('Authorization'), isFalse);
        expect(headers.containsKey('X-Firebase-AppCheck'), isFalse);
      },
    );

    test('the token of the auth provider with the Firebase scheme', () async {
      final FakeAuth auth = FakeAuth(<String>['token-1']);
      app.authProvider = auth;
      auth.calls.clear();
      await storageOf(statuses(<int>[200])).ref('o').metadata();
      expect(requests.single.headers['Authorization'], 'Firebase token-1');
      expect(auth.calls, <bool>[false]);
    });

    test('no Authorization when nobody is signed in', () async {
      app.authProvider = FakeAuth(<String?>[null]);
      await storageOf(statuses(<int>[200])).ref('o').metadata();
      expect(requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test('no Authorization when the provider has no API', () async {
      app.authProvider = FakeAuth(<String>[
        'x',
      ], error: const FirebaseApiNotAvailableException('none'));
      await storageOf(statuses(<int>[200])).ref('o').metadata();
      expect(requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test(
      'a failing auth provider fails the operation with unauthenticated, before any request',
      () async {
        app.authProvider = FakeAuth(<String>[
          'x',
        ], error: StateError('offline'));
        await expectLater(
          storageOf(statuses(<int>[200])).ref('o').metadata(),
          throwsA(
            isA<FirebaseStorageException>()
                .having(
                  (FirebaseStorageException e) => e.code,
                  'code',
                  'unauthenticated',
                )
                .having(
                  (FirebaseStorageException e) => e.message,
                  'message',
                  allOf(contains('StateError'), isNot(contains('offline'))),
                )
                .having(
                  (FirebaseStorageException e) => e.cause,
                  'cause',
                  isA<StateError>(),
                ),
          ),
        );
        expect(requests, isEmpty);
      },
    );

    test('the App Check token, even a placeholder with an error', () async {
      app.appCheckProvider = FakeAppCheck(
        const AppCheckTokenResult('app-check'),
      );
      await storageOf(statuses(<int>[200])).ref('o').metadata();
      app.appCheckProvider = FakeAppCheck(
        AppCheckTokenResult('placeholder', error: StateError('x')),
      );
      await storageOf(statuses(<int>[200])).ref('o').metadata();
      expect(
        requests.map((Recorded r) => r.headers['X-Firebase-AppCheck']),
        <String>['app-check', 'placeholder'],
      );
    });

    test(
      'no App Check header for an empty token or a throwing provider',
      () async {
        final FakeAppCheck empty = FakeAppCheck(const AppCheckTokenResult(''));
        app.appCheckProvider = empty;
        await storageOf(statuses(<int>[200])).ref('o').metadata();
        app.appCheckProvider = FakeAppCheck(
          const AppCheckTokenResult('x'),
          error: StateError('down'),
        );
        await storageOf(statuses(<int>[200])).ref('o').metadata();
        expect(
          requests.every(
            (Recorded r) => !r.headers.containsKey('X-Firebase-AppCheck'),
          ),
          isTrue,
        );
        expect(empty.calls, <bool>[false]);
      },
    );

    test('mockUserToken replaces the auth provider on the emulator', () async {
      final FakeAuth auth = FakeAuth(<String>['real']);
      app.authProvider = auth;
      auth.calls.clear();
      await storageOf(
        statuses(<int>[200]),
        emulatorHost: '127.0.0.1:9199',
        mockUserToken: 'owner',
      ).ref('o').metadata();
      expect(requests.single.headers['Authorization'], 'Firebase owner');
      expect(
        requests.single.url.toString(),
        'http://127.0.0.1:9199/v0/b/b/o/o',
      );
      expect(auth.calls, isEmpty);
    });

    test('the request headers are kept', () async {
      await storageOf(statuses(<int>[200])).ref('o').putBytes(Uint8List(1));
      expect(requests.single.headers['X-Goog-Upload-Protocol'], 'multipart');
      expect(
        requests.single.headers['X-Firebase-Storage-Version'],
        'dart/0.1.2',
      );
    });
  });

  group('401', () {
    test('is retried once with a refreshed token', () async {
      final FakeAuth auth = FakeAuth(<String>['old', 'new']);
      app.authProvider = auth;
      auth.calls.clear();
      await storageOf(statuses(<int>[401, 200])).ref('o').metadata();
      expect(requests.map((Recorded r) => r.headers['Authorization']), <String>[
        'Firebase old',
        'Firebase new',
      ]);
      expect(auth.calls, <bool>[false, true]);
      expect(time.delays, isEmpty);
    });

    test('a second 401 is unauthenticated', () async {
      app.authProvider = FakeAuth(<String>['old', 'new']);
      await expectLater(
        storageOf(statuses(<int>[401])).ref('o').metadata(),
        throwsStorageCode('unauthenticated'),
      );
      expect(requests, hasLength(2));
    });

    test('is not retried without a token or with a mock token', () async {
      await expectLater(
        storageOf(statuses(<int>[401])).ref('o').metadata(),
        throwsStorageCode('unauthenticated'),
      );
      await expectLater(
        storageOf(
          statuses(<int>[401]),
          emulatorHost: 'localhost:9199',
          mockUserToken: 'm',
        ).ref('o').metadata(),
        throwsStorageCode('unauthenticated'),
      );
      expect(requests, hasLength(2));
    });
  });

  group('retries', () {
    test('retryable statuses wait 2, 4, 8, ... seconds plus jitter', () async {
      final FakeAuth auth = FakeAuth(<String>['t']);
      app.authProvider = auth;
      auth.calls.clear();
      await storageOf(
        statuses(<int>[503, 500, 408, 429, 599, 200]),
      ).ref('o').metadata();
      expect(requests, hasLength(6));
      expect(time.delays, const <Duration>[
        Duration(milliseconds: 2500),
        Duration(milliseconds: 4500),
        Duration(milliseconds: 8500),
        Duration(milliseconds: 16500),
        Duration(milliseconds: 32500),
      ]);
      expect(auth.calls, <bool>[
        false,
      ], reason: 'tokens are fetched once per operation');
    });

    test('the wait stops growing at 64 seconds', () async {
      await storageOf(
        statuses(<int>[503, 503, 503, 503, 503, 503, 503, 200]),
        retry: const StorageRetryPolicy(operation: Duration(hours: 1)),
      ).ref('o').metadata();
      expect(time.delays.map((Duration d) => d.inMilliseconds), <int>[
        2500, 4500, 8500, 16500, 32500, 64500, 64500, //
      ]);
    });

    test(
      'after the retry time, one last attempt, then retry-limit-exceeded',
      () async {
        await expectLater(
          storageOf(
            statuses(<int>[503]),
            retry: const StorageRetryPolicy(operation: Duration(seconds: 10)),
          ).ref('o').metadata(),
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
        expect(time.delays.map((Duration d) => d.inMilliseconds), <int>[
          2500,
          4500,
          3000,
        ]);
        expect(requests, hasLength(4));
      },
    );

    test('a zero retry time makes a single attempt', () async {
      await expectLater(
        storageOf(
          statuses(<int>[503, 200]),
          retry: const StorageRetryPolicy(operation: Duration.zero),
        ).ref('o').metadata(),
        throwsStorageCode('retry-limit-exceeded'),
      );
      expect(requests, hasLength(1));
    });

    test('downloads and uploads use their own retry time', () async {
      final FirebaseStorage storage = storageOf(
        statuses(<int>[503]),
        retry: const StorageRetryPolicy(
          operation: Duration.zero,
          upload: Duration(seconds: 3),
          download: Duration(seconds: 7),
        ),
      );
      await expectLater(
        storage.ref('o').getBytes(),
        throwsStorageCode('retry-limit-exceeded'),
      );
      expect(time.delays.map((Duration d) => d.inMilliseconds), <int>[
        2500,
        4500,
      ]);
      time.delays.clear();
      await expectLater(
        storage.ref('o').putBytes(Uint8List(1)),
        throwsStorageCode('retry-limit-exceeded'),
      );
      expect(time.delays.map((Duration d) => d.inMilliseconds), <int>[
        2500,
        500,
      ]);
    });

    test('other errors are not retried', () async {
      for (final int status in <int>[400, 403, 404, 412]) {
        requests.clear();
        await expectLater(
          storageOf(statuses(<int>[status, 200])).ref('o').metadata(),
          throwsA(isA<FirebaseStorageException>()),
          reason: '$status',
        );
        expect(requests, hasLength(1));
      }
      expect(time.delays, isEmpty);
    });

    test('network errors are retried', () async {
      int count = 0;
      final FirebaseStorage storage = storageOf((_) async {
        if (count++ < 2) {
          throw http.ClientException('Connection reset');
        }
        return http.Response('{"name":"o"}', 200);
      });
      expect((await storage.ref('o').metadata()).fullPath, 'o');
      expect(requests, hasLength(3));
      expect(time.delays, hasLength(2));
    });

    test('a network error after the retry time names the cause', () async {
      await expectLater(
        storageOf(
          (_) async => throw http.ClientException('Connection refused'),
          retry: const StorageRetryPolicy(operation: Duration.zero),
        ).ref('o').metadata(),
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
                isNull,
              )
              .having(
                (FirebaseStorageException e) => e.message,
                'message',
                contains('Connection refused'),
              ),
        ),
      );
    });

    test('a request without retryOnStatus maps a retryable status', () async {
      final FirebaseStorage storage = storageOf(statuses(<int>[503, 200]));
      await expectLater(
        storage.requester.send(
          StorageRequest(
            method: 'POST',
            url: Uri.parse('https://upload.example/session'),
            timeout: const Duration(minutes: 10),
            retryOnStatus: false,
            errorMapper: sharedErrorMapper('b', 'o'),
          ),
        ),
        throwsA(
          isA<FirebaseStorageException>()
              .having((FirebaseStorageException e) => e.code, 'code', 'unknown')
              .having(
                (FirebaseStorageException e) => e.httpStatus,
                'httpStatus',
                503,
              ),
        ),
      );
      expect(requests, hasLength(1));
    });

    test(
      'a request without retryOnStatus still retries network errors',
      () async {
        int count = 0;
        final FirebaseStorage storage = storageOf((_) async {
          if (count++ == 0) {
            throw http.ClientException('reset');
          }
          return http.Response(
            '',
            200,
            headers: <String, String>{'x-goog-upload-status': 'final'},
          );
        });
        final StorageResponse response = await storage.requester.send(
          StorageRequest(
            method: 'POST',
            url: Uri.parse('https://upload.example/session'),
            timeout: const Duration(minutes: 10),
            retryOnStatus: false,
            errorMapper: sharedErrorMapper('b', 'o'),
          ),
        );
        expect(response.headers['x-goog-upload-status'], 'final');
        expect(requests, hasLength(2));
      },
    );
  });

  group('timeouts', () {
    test('an attempt without a response in time is retried', () async {
      int count = 0;
      final FirebaseStorage storage = storageOf((_) {
        if (count++ == 0) {
          return Completer<http.Response>().future;
        }
        return Future<http.Response>.value(http.Response('{"name":"o"}', 200));
      }, requestTimeout: const Duration(milliseconds: 20));
      expect((await storage.ref('o').metadata()).fullPath, 'o');
      expect(requests, hasLength(2));
    });

    test('a body that stalls is retried', () async {
      int count = 0;
      final http.Client client = MockClient.streaming((
        http.BaseRequest request,
        _,
      ) async {
        count++;
        final Stream<List<int>> body = count == 1
            ? (StreamController<List<int>>()..add(<int>[123])).stream
            : Stream<List<int>>.value('{"name":"o"}'.codeUnits);
        return http.StreamedResponse(body, 200);
      });
      final FirebaseStorage storage = FirebaseStorage(
        app,
        httpClient: client,
        requestTimeout: const Duration(milliseconds: 20),
        clock: time.clock,
        random: () => 0.5,
        delay: time.delay,
      );
      addTearDown(storage.close);
      expect((await storage.ref('o').metadata()).fullPath, 'o');
      expect(count, 2);
    });

    test(
      'runs out as retry-limit-exceeded with the timeout as the cause',
      () async {
        await expectLater(
          storageOf(
            (_) => Completer<http.Response>().future,
            requestTimeout: const Duration(milliseconds: 10),
            retry: const StorageRetryPolicy(operation: Duration.zero),
          ).ref('o').metadata(),
          throwsA(
            isA<FirebaseStorageException>()
                .having(
                  (FirebaseStorageException e) => e.code,
                  'code',
                  'retry-limit-exceeded',
                )
                .having(
                  (FirebaseStorageException e) => e.message,
                  'message',
                  contains('TimeoutException'),
                ),
          ),
        );
      },
    );
  });

  group('abort', () {
    StorageRequest request() => StorageRequest(
      method: 'GET',
      url: Uri.parse('https://firebasestorage.googleapis.com/v0/b/b/o/o'),
      timeout: const Duration(minutes: 2),
      errorMapper: objectErrorMapper('b', 'o'),
    );

    test('a trigger that already fired cancels before any request', () async {
      final FirebaseStorage storage = storageOf(statuses(<int>[200]));
      final Completer<void> trigger = Completer<void>()..complete();
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        storage.requester.send(request(), abortTrigger: trigger.future),
        throwsStorageCode('canceled'),
      );
      expect(requests, isEmpty);
    });

    test('aborts an attempt in flight', () async {
      final Completer<void> trigger = Completer<void>();
      final FirebaseStorage storage = storageOf((_) {
        trigger.complete();
        return Completer<http.Response>().future;
      });
      await expectLater(
        storage.requester.send(request(), abortTrigger: trigger.future),
        throwsStorageCode('canceled'),
      );
      expect(requests, hasLength(1));
    });

    test('ends a backoff wait', () async {
      final Completer<void> trigger = Completer<void>();
      final FirebaseStorage storage = FirebaseStorage(
        app,
        httpClient: MockClient((_) async => http.Response('', 503)),
        clock: time.clock,
        random: () => 0.5,
        delay: (Duration duration) {
          trigger.complete();
          return Completer<void>().future;
        },
      );
      addTearDown(storage.close);
      await expectLater(
        storage.requester.send(request(), abortTrigger: trigger.future),
        throwsStorageCode('canceled'),
      );
    });
  });

  group('open', () {
    test('hands back the response with its body unread', () async {
      final FirebaseStorage storage = storageOf(statuses(<int>[503, 200]));
      final http.StreamedResponse response = await storage.requester.open(
        StorageRequest(
          method: 'GET',
          url: storage.ref('o').objectUrl(media: true),
          timeout: const Duration(minutes: 10),
          errorMapper: objectErrorMapper('b', 'o'),
        ),
      );
      expect(response.statusCode, 200);
      expect(await response.stream.bytesToString(), '{"name":"o"}');
      expect(requests, hasLength(2));
    });

    test('maps an error status', () async {
      final FirebaseStorage storage = storageOf(statuses(<int>[404]));
      await expectLater(
        storage.requester.open(
          StorageRequest(
            method: 'GET',
            url: storage.ref('o').objectUrl(media: true),
            timeout: const Duration(minutes: 10),
            errorMapper: objectErrorMapper('b', 'o'),
          ),
        ),
        throwsStorageCode('object-not-found'),
      );
    });
  });

  test('the error body is cut at 16 KiB', () async {
    final String body = 'x' * 20000;
    await expectLater(
      storageOf((_) async => http.Response(body, 400)).ref('o').metadata(),
      throwsA(
        isA<FirebaseStorageException>().having(
          (FirebaseStorageException e) => e.serverResponse,
          'serverResponse',
          hasLength(maxErrorBodyBytes),
        ),
      ),
    );
  });

  group('close', () {
    test('later operations throw a StateError', () async {
      final FirebaseStorage storage = storageOf(statuses(<int>[200]));
      storage.close();
      storage.close();
      await expectLater(storage.ref('o').metadata(), throwsStateError);
      expect(requests, isEmpty);
    });

    test('an operation waiting to retry throws a StateError', () async {
      late FirebaseStorage storage;
      storage = FirebaseStorage(
        app,
        httpClient: MockClient((_) async => http.Response('', 503)),
        clock: time.clock,
        random: () => 0.5,
        delay: (Duration duration) async => storage.close(),
      );
      await expectLater(storage.ref('o').metadata(), throwsStateError);
    });

    test('does not close a client it was given', () async {
      bool closed = false;
      final http.Client client = _ClosingClient(() => closed = true);
      FirebaseStorage(app, httpClient: client).close();
      expect(closed, isFalse);
    });
  });
}

class _ClosingClient extends http.BaseClient {
  _ClosingClient(this.onClose);

  final void Function() onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() => onClose();
}

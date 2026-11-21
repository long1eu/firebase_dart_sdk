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

// Deliberate differences from the JS SDK that keep tokens, URLs and memory safe.
void main() {
  late FirebaseApp app;
  late List<Recorded> requests;

  setUp(() {
    app = newApp();
    requests = <Recorded>[];
    app.authProvider = FakeAuth(<String>['user-token']);
    app.appCheckProvider = FakeAppCheck(const AppCheckTokenResult('app-check'));
  });

  tearDown(() => app.delete());

  FirebaseStorage storageOf(
    Future<http.Response> Function(Recorded request) handler, {
    String? emulatorHost,
  }) {
    final FirebaseStorage storage = storageWith(
      app,
      handler,
      requests: requests,
      emulatorHost: emulatorHost,
    );
    addTearDown(storage.close);
    return storage;
  }

  StorageRequest get(String url) => StorageRequest(
    method: 'GET',
    url: Uri.parse(url),
    timeout: Duration.zero,
    errorMapper: sharedErrorMapper('b', 'o'),
  );

  group('tokens travel only over https, to the emulator or to loopback', () {
    test('https and the emulator host get them', () async {
      final FirebaseStorage storage = storageOf(
        (_) async => http.Response('', 200),
        emulatorHost: 'emulator.internal:9199',
      );
      await storage.requester.send(get('https://upload.example/session'));
      await storage.requester.send(
        get('http://emulator.internal:9199/v0/b/b/o/o'),
      );
      await storage.requester.send(
        get('http://EMULATOR.internal:9199/v0/b/b/o/o'),
      );
      for (final Recorded request in requests) {
        expect(
          request.headers['Authorization'],
          'Firebase user-token',
          reason: '${request.url}',
        );
        expect(request.headers['X-Firebase-AppCheck'], 'app-check');
      }
    });

    test('loopback hosts get them', () async {
      final FirebaseStorage storage = storageOf(
        (_) async => http.Response('', 200),
      );
      for (final String url in <String>[
        'http://localhost:9199/x',
        'http://127.0.0.1:9199/x',
        'http://127.4.5.6/x',
        'http://[::1]:9199/x',
      ]) {
        await storage.requester.send(get(url));
      }
      expect(
        requests.map((Recorded r) => r.headers['Authorization']),
        everyElement('Firebase user-token'),
      );
    });

    test('plain http to anybody else gets none', () async {
      final FirebaseStorage storage = storageOf(
        (_) async => http.Response('', 200),
        emulatorHost: '127.0.0.1:9199',
      );
      for (final String url in <String>[
        'http://example.com/x',
        'http://emulator.internal:9199/x',
        'http://127.0.0.1.example.com/x',
      ]) {
        await storage.requester.send(get(url));
      }
      for (final Recorded request in requests) {
        expect(
          request.headers.containsKey('Authorization'),
          isFalse,
          reason: '${request.url}',
        );
        expect(request.headers.containsKey('X-Firebase-AppCheck'), isFalse);
        expect(request.headers['X-Firebase-Storage-Version'], 'dart/0.1.0');
      }
    });

    test('the mock user token follows the same rule', () async {
      final FirebaseStorage storage = storageWith(
        app,
        (_) async => http.Response('', 200),
        requests: requests,
        emulatorHost: 'emulator.internal:9199',
        mockUserToken: 'owner',
      );
      addTearDown(storage.close);
      await storage.requester.send(get('http://emulator.internal:9199/x'));
      await storage.requester.send(get('http://elsewhere.internal:9199/x'));
      expect(
        requests.map((Recorded r) => r.headers['Authorization']),
        <String?>['Firebase owner', null],
      );
    });
  });

  test('redirects are not followed and fail as unknown', () async {
    final List<bool> follow = <bool>[];
    final FirebaseStorage storage = FirebaseStorage(
      app,
      httpClient: MockClient((http.Request request) async {
        follow.add(request.followRedirects);
        return http.Response(
          '',
          302,
          headers: <String, String>{'location': 'http://evil.example/'},
        );
      }),
    );
    addTearDown(storage.close);
    await expectLater(
      storage.ref('o').metadata(),
      throwsA(
        isA<FirebaseStorageException>()
            .having((FirebaseStorageException e) => e.code, 'code', 'unknown')
            .having(
              (FirebaseStorageException e) => e.httpStatus,
              'httpStatus',
              302,
            ),
      ),
    );
    expect(follow, <bool>[false]);
  });

  test('getBytes stops reading once the body passes maxSize', () async {
    bool canceled = false;
    int sent = 0;
    final StreamController<List<int>> body = StreamController<List<int>>(
      onListen: () {},
      onCancel: () => canceled = true,
    );
    final FirebaseStorage storage = FirebaseStorage(
      app,
      httpClient: MockClient.streaming((http.BaseRequest request, _) async {
        // A server that ignores Range and sends a large body.
        Timer.periodic(const Duration(milliseconds: 1), (Timer timer) {
          if (canceled || sent > 1000) {
            timer.cancel();
            return;
          }
          sent++;
          body.add(Uint8List(1024));
        });
        return http.StreamedResponse(body.stream, 200);
      }),
    );
    addTearDown(storage.close);
    await expectLater(
      storage.ref('o').getBytes(maxSize: 2048),
      throwsStorageCode('download-size-exceeded'),
    );
    expect(canceled, isTrue);
    expect(sent, lessThan(10));
  });

  group('dot names', () {
    test(
      "'.' and '..' objects are invalid-argument, before any request",
      () async {
        final FirebaseStorage storage = storageOf(
          (_) async => http.Response('{}', 200),
        );
        for (final Reference ref in <Reference>[
          storage.ref('..'),
          storage.ref('.'),
          storage.refFromUrl('gs://b/..'),
        ]) {
          await expectLater(
            ref.delete(),
            throwsStorageCode('invalid-argument'),
            reason: '$ref',
          );
          await expectLater(
            ref.metadata(),
            throwsStorageCode('invalid-argument'),
          );
          await expectLater(
            ref.putBytes(Uint8List(0)),
            throwsStorageCode('invalid-argument'),
          );
        }
        expect(requests, isEmpty);
      },
    );

    test('names with dots inside stay one escaped segment', () async {
      final FirebaseStorage storage = storageOf(
        (_) async => http.Response('{}', 200),
      );
      await storage.ref('a/..').delete();
      await storage.ref('...').delete();
      expect(requests.map((Recorded r) => r.url.path), <String>[
        '/v0/b/b/o/a%2F..',
        '/v0/b/b/o/...',
      ]);
    });

    test("'.' and '..' buckets are refused", () {
      final FirebaseStorage storage = storageOf(
        (_) async => http.Response('{}', 200),
      );
      for (final String url in <String>[
        'gs://../x',
        'gs://./x',
        'https://firebasestorage.googleapis.com/v0/b/../o/x',
      ]) {
        expect(
          () => storage.refFromUrl(url),
          throwsStorageCode('invalid-url'),
          reason: url,
        );
      }
      for (final String bucket in <String>[
        '..',
        '.',
        'a b',
        'a/b',
        'gs://..',
      ]) {
        expect(
          () => FirebaseStorage(app, bucket: bucket),
          throwsArgumentError,
          reason: bucket,
        );
      }
    });
  });

  test('invalid-url messages leave out the query and the fragment', () {
    final FirebaseStorage storage = storageOf(
      (_) async => http.Response('{}', 200),
    );
    expect(
      () => storage.refFromUrl(
        'https://firebasestorage.googleapis.com/v0/b/b/o/%ZZ?alt=media&token=SECRET#frag',
      ),
      throwsA(
        isA<FirebaseStorageException>()
            .having(
              (FirebaseStorageException e) => e.code,
              'code',
              'invalid-url',
            )
            .having(
              (FirebaseStorageException e) => e.toString(),
              'toString',
              isNot(contains('SECRET')),
            )
            .having(
              (FirebaseStorageException e) => e.message,
              'message',
              contains('/o/%ZZ'),
            ),
      ),
    );
  });

  test('retry-limit messages leave out the query of the URL', () async {
    final FirebaseStorage storage = storageOf(
      (Recorded r) async =>
          throw http.ClientException('Connection reset', r.url),
    );
    await expectLater(
      storage.requester.send(
        get('https://upload.example/session?upload_id=SECRET'),
      ),
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
              contains('Connection reset (GET /session)'),
            )
            .having(
              (FirebaseStorageException e) => e.toString(),
              'toString',
              isNot(contains('SECRET')),
            ),
      ),
    );
  });

  group('upload metadata', () {
    test('md5Hash is sent with an upload, not with updateMetadata', () async {
      final FirebaseStorage storage = storageOf((_) => json(serverResource));
      const SettableMetadata metadata = SettableMetadata(
        md5Hash: 'XUFAKrxLKna5cZ2REBfFkg==',
        contentType: 't/p',
      );
      await storage.ref('o').putBytes(Uint8List(1), metadata: metadata);
      await storage.ref('o').updateMetadata(metadata);
      expect(
        requests.first.body,
        contains(
          '{"name":"o","md5Hash":"XUFAKrxLKna5cZ2REBfFkg==","contentType":"t/p"}',
        ),
      );
      expect(requests.last.body, '{"contentType":"t/p"}');
    });

    test(
      'a content type with control characters is invalid-argument, before any request',
      () async {
        final FirebaseStorage storage = storageOf((_) => json(serverResource));
        for (final String type in <String>[
          'text/plain\r\nX-Injected: 1',
          'a\nb',
          'a\u0000b',
          'a\u007fb',
        ]) {
          await expectLater(
            storage
                .ref('o')
                .putBytes(
                  Uint8List(1),
                  metadata: SettableMetadata(contentType: type),
                ),
            throwsStorageCode('invalid-argument'),
            reason: type,
          );
          await expectLater(
            storage
                .ref('o')
                .putString('x', metadata: SettableMetadata(contentType: type)),
            throwsStorageCode('invalid-argument'),
          );
        }
        expect(requests, isEmpty);
      },
    );

    test('multipart boundaries are random and long', () async {
      final FirebaseStorage storage = storageOf((_) => json(serverResource));
      await storage.ref('a').putBytes(Uint8List(0));
      await storage.ref('b').putBytes(Uint8List(0));
      final List<String> boundaries = <String>[
        for (final Recorded r in requests)
          r.headers['Content-Type']!.split('boundary=').last,
      ];
      expect(boundaries, everyElement(matches(RegExp(r'^[0-9]{32}$'))));
      expect(boundaries.first, isNot(boundaries.last));
    });
  });

  group('wait', () {
    test('a real wait ends when the trigger fires', () async {
      final FirebaseStorage storage = FirebaseStorage(
        app,
        httpClient: MockClient((_) async => http.Response('', 200)),
      );
      addTearDown(storage.close);
      final Completer<void> trigger = Completer<void>();
      final Stopwatch stopwatch = Stopwatch()..start();
      final Future<void> waiting = storage.requester.wait(
        const Duration(hours: 1),
        abortTrigger: trigger.future,
      );
      trigger.complete();
      await waiting;
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('a real wait without a trigger waits', () async {
      final FirebaseStorage storage = FirebaseStorage(
        app,
        httpClient: MockClient((_) async => http.Response('', 200)),
      );
      addTearDown(storage.close);
      final Stopwatch stopwatch = Stopwatch()..start();
      await storage.requester.wait(const Duration(milliseconds: 30));
      expect(
        stopwatch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 25)),
      );
    });

    test('uses the injected clock and delay', () async {
      final FakeTime time = FakeTime();
      final FirebaseStorage storage = storageWith(
        app,
        (_) async => http.Response('', 200),
        time: time,
      );
      addTearDown(storage.close);
      final DateTime start = storage.requester.now();
      await storage.requester.wait(const Duration(seconds: 3));
      expect(
        storage.requester.now().difference(start),
        const Duration(seconds: 3),
      );
      expect(time.delays, <Duration>[const Duration(seconds: 3)]);
    });
  });
}

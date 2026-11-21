import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fakes.dart';
import 'streaming_client.dart';

void main() {
  late FirebaseApp app;
  late FakeTime time;

  setUp(() {
    app = newApp();
    time = FakeTime();
  });
  tearDown(() => app.delete());

  FirebaseStorage storageOn(
    StreamingClient client, {
    Duration requestTimeout = const Duration(minutes: 1),
    StorageRetryPolicy retry = const StorageRetryPolicy(),
  }) {
    return FirebaseStorage(
      app,
      httpClient: client,
      requestTimeout: requestTimeout,
      retry: retry,
      clock: time.clock,
      random: () => 0.5,
      delay: time.delay,
    );
  }

  Future<String> readText(Stream<List<int>> stream) async =>
      utf8.decode(await stream.expand((List<int> c) => c).toList());

  group('openRead', () {
    test('streams the whole object without a Range header', () async {
      final StreamingClient client = StreamingClient.chunks(<String>[
        'hello ',
        'world',
      ]);
      final FirebaseStorage storage = storageOn(client);

      final List<List<int>> chunks = await storage
          .ref('a/b.txt')
          .openRead()
          .toList();

      expect(chunks.map(utf8.decode), <String>['hello ', 'world']);
      final http.BaseRequest request = client.requests.single;
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'https://firebasestorage.googleapis.com/v0/b/b/o/a%2Fb.txt?alt=media',
      );
      expect(request.headers.containsKey('Range'), isFalse);
    });

    test('nothing is requested until the stream is listened to', () async {
      final StreamingClient client = StreamingClient.chunks(<String>['x']);
      final Stream<List<int>> stream = storageOn(client).ref('f').openRead();
      await pumpEventQueue();
      expect(client.requests, isEmpty);
      expect(await readText(stream), 'x');
      expect(client.requests, hasLength(1));
    });

    test('is single-subscription', () {
      final Stream<List<int>> stream = storageOn(
        StreamingClient.chunks(<String>[]),
      ).ref('f').openRead();
      expect(stream.isBroadcast, isFalse);
    });

    test('start and end become an inclusive Range', () async {
      final StreamingClient client = StreamingClient.chunks(<String>[
        'llo',
      ], status: 206);
      final String text = await readText(
        storageOn(client).ref('f').openRead(2, 5),
      );
      expect(text, 'llo');
      expect(client.requests.single.headers['Range'], 'bytes=2-4');
    });

    test('start alone reads to the end of the object', () async {
      final StreamingClient client = StreamingClient.chunks(<String>[
        'world',
      ], status: 206);
      await readText(storageOn(client).ref('f').openRead(6));
      expect(client.requests.single.headers['Range'], 'bytes=6-');
    });

    test('end alone reads from the start', () async {
      final StreamingClient client = StreamingClient.chunks(<String>[
        'hello',
      ], status: 206);
      await readText(storageOn(client).ref('f').openRead(null, 5));
      expect(client.requests.single.headers['Range'], 'bytes=0-4');
    });

    test(
      'a 200 answered to a Range (the emulator) is cut to the range',
      () async {
        final StreamingClient client = StreamingClient.chunks(<String>[
          'hel',
          'lo w',
          'orld',
        ]);
        expect(
          await readText(storageOn(client).ref('f').openRead(6, 9)),
          'wor',
        );
        expect(
          await readText(storageOn(client).ref('f').openRead(4)),
          'o world',
        );
      },
    );

    test('a 200 answered to a Range past the end gives nothing', () async {
      final StreamingClient client = StreamingClient.chunks(<String>['hello']);
      expect(await readText(storageOn(client).ref('f').openRead(99)), isEmpty);
    });

    test('a 206 longer than asked is cut and the request aborted', () async {
      final StreamingClient client = StreamingClient.open(status: 206);
      final Future<String> text = readText(
        storageOn(client).ref('f').openRead(0, 3),
      );
      await client.served.first;
      client.body.add(utf8.encode('abcdef'));
      expect(await text, 'abc');
      await pumpEventQueue();
      expect(client.aborted, isTrue);
    });

    test('416 (range not satisfiable) is an empty stream', () async {
      final StreamingClient client = StreamingClient.chunks(<String>[
        'Requested range not satisfiable',
      ], status: 416);
      expect(await readText(storageOn(client).ref('f').openRead(99)), isEmpty);
    });

    test('an empty range sends no request', () async {
      final StreamingClient client = StreamingClient.chunks(<String>['x']);
      expect(await storageOn(client).ref('f').openRead(3, 3).toList(), isEmpty);
      expect(client.requests, isEmpty);
    });

    test('a negative start or an end before start fails with '
        'invalid-argument', () async {
      final StreamingClient client = StreamingClient.chunks(<String>['x']);
      final Reference ref = storageOn(client).ref('f');
      await expectLater(
        ref.openRead(-1).toList(),
        throwsStorageCode('invalid-argument'),
      );
      await expectLater(
        ref.openRead(5, 4).toList(),
        throwsStorageCode('invalid-argument'),
      );
      expect(client.requests, isEmpty);
    });

    test('the root fails with invalid-root-operation', () {
      final StreamingClient client = StreamingClient.chunks(<String>[]);
      expect(
        storageOn(client).ref().openRead().toList(),
        throwsStorageCode('invalid-root-operation'),
      );
    });

    test('404 fails with object-not-found and its status', () async {
      final StreamingClient client = StreamingClient.chunks(<String>[
        'Not Found',
      ], status: 404);
      await expectLater(
        storageOn(client).ref('f').openRead().toList(),
        throwsA(
          isA<FirebaseStorageException>()
              .having(
                (FirebaseStorageException e) => e.code,
                'code',
                'object-not-found',
              )
              .having(
                (FirebaseStorageException e) => e.httpStatus,
                'status',
                404,
              ),
        ),
      );
    });

    test('a 503 before the body is retried', () async {
      int calls = 0;
      final StreamingClient client = StreamingClient((_) {
        calls++;
        return calls == 1
            ? StreamingClient.response(<String>['busy'], 503)
            : StreamingClient.response(<String>['ok'], 200);
      });
      expect(await readText(storageOn(client).ref('f').openRead()), 'ok');
      expect(client.requests, hasLength(2));
      expect(time.delays, hasLength(1));
    });

    test('a body that breaks before its first byte is opened again', () async {
      int calls = 0;
      final StreamingClient client = StreamingClient((_) {
        calls++;
        if (calls == 1) {
          return StreamingClient.failing(
            <String>[],
            http.ClientException('reset'),
          );
        }
        return StreamingClient.response(<String>['ok'], 200);
      });
      expect(await readText(storageOn(client).ref('f').openRead()), 'ok');
      expect(client.requests, hasLength(2));
      expect(time.delays, <Duration>[const Duration(milliseconds: 2500)]);
    });

    test('a ranged retry asks for the same range', () async {
      int calls = 0;
      final StreamingClient client = StreamingClient((_) {
        calls++;
        if (calls == 1) {
          return StreamingClient.failing(
            <String>[],
            http.ClientException('reset'),
          );
        }
        return StreamingClient.response(<String>['llo'], 206);
      });
      expect(await readText(storageOn(client).ref('f').openRead(2, 5)), 'llo');
      expect(
        client.requests.map((http.BaseRequest r) => r.headers['Range']),
        <String>['bytes=2-4', 'bytes=2-4'],
      );
    });

    test('breaking before the first byte past the retry time fails with '
        'retry-limit-exceeded', () async {
      final StreamingClient client = StreamingClient(
        (_) =>
            StreamingClient.failing(<String>[], http.ClientException('reset')),
      );
      final FirebaseStorage storage = storageOn(
        client,
        retry: const StorageRetryPolicy(download: Duration(seconds: 10)),
      );
      await expectLater(
        storage.ref('f').openRead().toList(),
        throwsStorageCode('retry-limit-exceeded'),
      );
      expect(client.requests.length, greaterThan(1));
      expect(
        time.delays.fold(Duration.zero, (Duration a, Duration b) => a + b),
        const Duration(seconds: 10),
      );
    });

    test('a failure after bytes were delivered ends the stream with an '
        'error and is not retried', () async {
      final StreamingClient client = StreamingClient(
        (_) => StreamingClient.failing(<String>[
          'hel',
        ], http.ClientException('reset')),
      );
      final List<String> data = <String>[];
      Object? error;
      final Completer<void> done = Completer<void>();
      storageOn(client)
          .ref('f')
          .openRead()
          .listen(
            (List<int> chunk) => data.add(utf8.decode(chunk)),
            onError: (Object e) => error = e,
            onDone: done.complete,
          );
      await done.future;
      expect(data, <String>['hel']);
      expect(
        error,
        isA<FirebaseStorageException>()
            .having((FirebaseStorageException e) => e.code, 'code', 'unknown')
            .having(
              (FirebaseStorageException e) => e.message,
              'message',
              contains('after 3 bytes'),
            ),
      );
      expect(client.requests, hasLength(1));
    });

    test('a body that stalls after bytes times out with an error', () async {
      final StreamingClient client = StreamingClient.open();
      final Future<List<List<int>>> result = storageOn(
        client,
        requestTimeout: const Duration(milliseconds: 50),
      ).ref('f').openRead().toList();
      await client.served.first;
      client.body.add(utf8.encode('a'));
      await expectLater(result, throwsStorageCode('unknown'));
      expect(client.requests, hasLength(1));
    });

    test('canceling the subscription aborts the request', () async {
      final StreamingClient client = StreamingClient.open();
      final Completer<void> first = Completer<void>();
      final StreamSubscription<List<int>> subscription = storageOn(
        client,
      ).ref('f').openRead().listen((_) => first.complete());
      await client.served.first;
      client.body.add(utf8.encode('a'));
      await first.future;
      await subscription.cancel();
      await pumpEventQueue();
      expect(client.aborted, isTrue);
      expect(client.bodyCanceled, isTrue);
    });

    test('canceling before the response arrives aborts the request', () async {
      final Completer<http.StreamedResponse> pending =
          Completer<http.StreamedResponse>();
      final StreamingClient client = StreamingClient((_) => pending.future);
      final StreamSubscription<List<int>> subscription = storageOn(
        client,
      ).ref('f').openRead().listen((_) {}, onError: (_) => fail('no error'));
      await pumpEventQueue();
      await subscription.cancel();
      await pumpEventQueue();
      expect(client.aborted, isTrue);
    });

    test('pausing the subscription pauses the body', () async {
      final StreamingClient client = StreamingClient.open();
      final Completer<void> first = Completer<void>();
      final StreamSubscription<List<int>> subscription = storageOn(
        client,
      ).ref('f').openRead().listen((_) => first.complete());
      await client.served.first;
      client.body.add(<int>[1]);
      await first.future;
      subscription.pause();
      await pumpEventQueue();
      expect(client.body.isPaused, isTrue);
      subscription.resume();
      await pumpEventQueue();
      expect(client.body.isPaused, isFalse);
      await subscription.cancel();
    });

    test('after close it fails with a StateError', () async {
      final FirebaseStorage storage = storageOn(
        StreamingClient.chunks(<String>['x']),
      )..close();
      await expectLater(storage.ref('f').openRead().toList(), throwsStateError);
    });
  });
}

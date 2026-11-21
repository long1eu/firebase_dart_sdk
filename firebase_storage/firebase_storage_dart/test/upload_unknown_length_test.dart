import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:firebase_storage_dart/src/upload/upload_source.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fakes.dart';
import 'upload_fakes.dart';

// startStreamUpload without a length (Android putStream): a resumable session that does not announce the
// total, chunks kept until confirmed, one stream event read ahead to know the last chunk, and totalBytes -1
// until the stream ended. Also the internal-error code.
void main() {
  const int kib = 1024;
  const int mib = 1024 * 1024;

  late FirebaseApp app;
  late FakeUploadServer server;
  late FakeTime time;
  late FirebaseStorage storage;

  setUp(() {
    app = newApp();
    server = FakeUploadServer();
    time = FakeTime();
    storage = chunkedStorageWith(app, server.handle, time: time);
  });

  tearDown(() async {
    storage.close();
    await app.delete();
  });

  Reference ref() => storage.ref('f');

  List<int> chunkSizes() => <int>[
    for (final Recorded r in server.chunks) r.bodyBytes.length,
  ];

  List<String?> commands() => <String?>[
    for (final Recorded r in server.requests)
      r.headers['x-goog-upload-command'],
  ];

  List<String?> offsets() => <String?>[
    for (final Recorded r in server.chunks) r.headers['x-goog-upload-offset'],
  ];

  Stream<List<int>> eventsOfSize(Uint8List data, int size) async* {
    for (int i = 0; i < data.length; i += size) {
      yield data.sublist(i, i + size > data.length ? data.length : i + size);
    }
  }

  group('without a length', () {
    test('an empty stream finalizes an empty object', () async {
      final UploadTask task = ref().startStreamUpload(
        const Stream<List<int>>.empty(),
      );
      expect(task.totalBytes, -1);
      final FullMetadata metadata = await task.result;

      expect(commands(), <String?>['start', 'finalize']);
      expect(server.chunks.single.bodyBytes, isEmpty);
      expect(server.chunks.single.headers['x-goog-upload-offset'], '0');
      expect(metadata.size, 0);
      expect(task.totalBytes, 0);
      expect(task.snapshot.totalBytes, 0);
    });

    test('the session start announces no length', () async {
      await ref()
          .startStreamUpload(Stream<List<int>>.value(patternBytes(10)))
          .result;
      final Recorded start = server.requests.first;
      expect(start.headers['x-goog-upload-command'], 'start');
      expect(start.headers['x-goog-upload-protocol'], 'resumable');
      expect(
        start.headers.containsKey('x-goog-upload-header-content-length'),
        isFalse,
      );
      expect(
        start.headers['x-goog-upload-header-content-type'],
        'application/octet-stream',
      );
    });

    test('with a length, the session start still announces it', () async {
      final Uint8List data = patternBytes(300 * kib);
      await ref()
          .startStreamUpload(eventsOfSize(data, 64 * kib), length: data.length)
          .result;
      expect(
        server.requests.first.headers['x-goog-upload-header-content-length'],
        '${data.length}',
      );
    });

    test(
      'less than 256 KiB goes in a session, in one finalizing chunk',
      () async {
        final Uint8List data = patternBytes(1000);
        final FullMetadata metadata = await ref()
            .startStreamUpload(eventsOfSize(data, 7))
            .result;
        expect(commands(), <String?>['start', 'upload, finalize']);
        expect(server.received, data);
        expect(metadata.size, 1000);
      },
    );

    test('exactly one chunk is sent with upload, finalize', () async {
      final Uint8List data = patternBytes(256 * kib);
      await ref().startStreamUpload(eventsOfSize(data, 64 * kib)).result;
      expect(commands(), <String?>['start', 'upload, finalize']);
      expect(chunkSizes(), <int>[256 * kib]);
      expect(server.received, data);
    });

    test(
      'a stream that ends on a chunk boundary finalizes with that chunk',
      () async {
        final Uint8List data = patternBytes(768 * kib);
        Stream<List<int>> withEmptyTail() async* {
          yield* eventsOfSize(data, 128 * kib);
          yield <int>[];
          yield <int>[];
        }

        await ref().startStreamUpload(withEmptyTail()).result;
        expect(commands(), <String?>['start', 'upload', 'upload, finalize']);
        expect(chunkSizes(), <int>[256 * kib, 512 * kib]);
        expect(server.received, data);
      },
    );

    test('chunks double from 256 KiB; only the last is shorter', () async {
      final Uint8List data = patternBytes(2 * mib + 5);
      await ref().startStreamUpload(eventsOfSize(data, 100 * kib + 3)).result;
      expect(chunkSizes(), <int>[256 * kib, 512 * kib, mib, 256 * kib + 5]);
      expect(commands(), <String?>[
        'start',
        'upload',
        'upload',
        'upload',
        'upload, finalize',
      ]);
      expect(offsets(), <String>[
        '0',
        '${256 * kib}',
        '${768 * kib}',
        '${1792 * kib}',
      ]);
      expect(server.received, data);
    });

    test('maxUploadChunkSize caps the chunks', () async {
      storage.close();
      storage = storageWith(
        app,
        server.handle,
        time: time,
        maxUploadChunkSize: 512 * kib,
      );
      final Uint8List data = patternBytes(2 * mib);
      await ref().startStreamUpload(eventsOfSize(data, 64 * kib)).result;
      expect(chunkSizes(), <int>[
        256 * kib,
        512 * kib,
        512 * kib,
        512 * kib,
        256 * kib,
      ]);
      expect(server.received, data);
    });

    test('totalBytes is -1 until the stream ended, then the size', () async {
      final Uint8List data = patternBytes(1 * mib + 10);
      final UploadTask task = ref().startStreamUpload(
        eventsOfSize(data, 64 * kib),
      );
      final List<UploadProgress> events = await task.progress.toList();

      expect(events.first.totalBytes, -1);
      // The confirmations of the chunks before the last one do not know the size yet.
      expect(
        events
            .where((UploadProgress p) => p.bytesTransferred < 768 * kib)
            .map((UploadProgress p) => p.totalBytes),
        everyElement(-1),
      );
      expect(events.last.state, UploadState.success);
      expect(events.last.totalBytes, data.length);
      expect(events.last.bytesTransferred, data.length);
      expect(task.totalBytes, data.length);
      expect(events.first.toString(), 'UploadProgress(running, 0/? bytes)');
    });

    test('reads one chunk and exactly one event ahead', () async {
      final Uint8List data = patternBytes(2 * mib);
      int delivered = 0;
      final List<int> deliveredAtChunk = <int>[];
      server.chunkHook = (int index, Recorded r) {
        deliveredAtChunk.add(delivered);
        return null;
      };
      // fromIterable emits only while the source listens unpaused, and map counts what reached the source.
      final List<Uint8List> events = <Uint8List>[
        for (int i = 0; i < data.length; i += 64 * kib)
          Uint8List.sublistView(data, i, i + 64 * kib),
      ];
      final Stream<List<int>> counted = Stream<Uint8List>.fromIterable(
        events,
      ).map((Uint8List e) => (delivered += e.length, e).$2);

      await ref().startStreamUpload(counted).result;
      // Each chunk ends on an event boundary, so the task read exactly one event past it.
      expect(deliveredAtChunk.sublist(0, 3), <int>[
        256 * kib + 64 * kib,
        768 * kib + 64 * kib,
        1792 * kib + 64 * kib,
      ]);
      expect(server.received, data);
    });

    test(
      'an error of the stream while paused fails the task with that error',
      () async {
        final StreamController<List<int>> input = StreamController<List<int>>();
        final UploadTask task = ref().startStreamUpload(input.stream);
        // A full chunk: the task waits for one more event to know whether it is the last.
        input.add(patternBytes(256 * kib));
        await pumpEventQueue();
        expect(task.pause(), isTrue);
        await task.progress.firstWhere(
          (UploadProgress p) => p.state == UploadState.paused,
        );

        // The abandoned read meets the error while the task is paused.
        input.addError(const FormatException('disk gone'));
        await pumpEventQueue();
        expect(task.resume(), isTrue);
        input.add(patternBytes(10));
        unawaited(input.close());

        await expectLater(
          task.result,
          throwsA(
            isA<FormatException>().having(
              (FormatException e) => e.message,
              'message',
              'disk gone',
            ),
          ),
        );
        expect(task.state, UploadState.error);
        expect(
          commands(),
          isNot(contains(anyOf('upload, finalize', 'finalize'))),
        );
      },
    );

    test(
      'a failure inside a chunk resumes from the partial server offset',
      () async {
        final Uint8List data = patternBytes(1 * mib + 3);
        server.chunkHook = (int index, Recorded r) {
          if (index == 1) {
            // The server kept 10 KiB + 3 bytes of the second chunk, then failed.
            server.store(r.bodyBytes.sublist(0, 10 * kib + 3));
            return http.Response('unavailable', 503);
          }
          return null;
        };
        final UploadTask task = ref().startStreamUpload(
          eventsOfSize(data, 50 * kib),
        );
        await task.result;

        final int resumeAt = 256 * kib + 10 * kib + 3;
        expect(commands(), <String?>[
          'start',
          'upload',
          'upload',
          'query',
          'upload',
          'upload, finalize',
        ]);
        expect(offsets().sublist(2), <String>[
          '$resumeAt',
          '${resumeAt + 256 * kib}',
        ]);
        expect(chunkSizes().sublist(2), <int>[
          256 * kib,
          data.length - resumeAt - 256 * kib,
        ]);
        expect(time.delays, <Duration>[const Duration(seconds: 1)]);
        expect(server.received, data);
        expect(task.totalBytes, data.length);
      },
    );

    test(
      'a failure inside the last chunk resumes and still finalizes',
      () async {
        final Uint8List data = patternBytes(300 * kib);
        server.chunkHook = (int index, Recorded r) {
          if (index == 1) {
            server.store(r.bodyBytes.sublist(0, 1000));
            throw http.ClientException('connection reset');
          }
          return null;
        };
        await ref().startStreamUpload(eventsOfSize(data, 64 * kib)).result;
        expect(commands(), <String?>[
          'start',
          'upload',
          'upload, finalize',
          'query',
          'upload, finalize',
        ]);
        expect(offsets().last, '${256 * kib + 1000}');
        expect(server.received, data);
      },
    );

    test(
      'a last chunk the server does not finalize is followed by finalize',
      () async {
        final Uint8List data = patternBytes(300 * kib);
        server.chunkHook = (int index, Recorded r) {
          if (index == 1) {
            server.store(r.bodyBytes);
            return http.Response(
              'OK',
              200,
              headers: <String, String>{'x-goog-upload-status': 'active'},
            );
          }
          return null;
        };
        final FullMetadata metadata = await ref()
            .startStreamUpload(eventsOfSize(data, 64 * kib))
            .result;
        expect(commands().last, 'finalize');
        expect(server.chunks.last.bodyBytes, isEmpty);
        expect(offsets().last, '${data.length}');
        expect(metadata.size, data.length);
      },
    );

    test(
      'a chunk answered final before the end fails with server-file-wrong-size',
      () async {
        server.chunkHook = (int index, Recorded r) => index == 0
            ? http.Response(
                '{"bucket":"b","name":"f","size":"${256 * kib}"}',
                200,
                headers: <String, String>{'x-goog-upload-status': 'final'},
              )
            : null;
        await expectLater(
          ref()
              .startStreamUpload(eventsOfSize(patternBytes(mib), 64 * kib))
              .result,
          throwsStorageCode('server-file-wrong-size'),
        );
      },
    );

    test('an error of the stream fails the task with that error', () async {
      final StreamController<List<int>> input = StreamController<List<int>>();
      final UploadTask task = ref().startStreamUpload(input.stream);
      input
        ..add(patternBytes(300 * kib))
        ..addError(const FormatException('disk gone'));
      await expectLater(task.result, throwsFormatException);
      expect(task.state, UploadState.error);
      await input.close();
    });

    test('pause during a chunk, then resume', () async {
      final Completer<void> reached = Completer<void>();
      final Completer<void> gate = Completer<void>();
      server.chunkHook = (int index, Recorded r) async {
        if (index == 1) {
          reached.complete();
          await gate.future;
        }
        return null;
      };
      final Uint8List data = patternBytes(1 * mib);
      final UploadTask task = ref().startStreamUpload(
        eventsOfSize(data, 64 * kib),
      );
      await reached.future;

      expect(task.pause(), isTrue);
      final UploadProgress paused = await task.progress.firstWhere(
        (UploadProgress p) => p.state == UploadState.paused,
      );
      expect(paused.bytesTransferred, 256 * kib);
      expect(paused.totalBytes, -1);

      expect(task.resume(), isTrue);
      await task.result;
      gate.complete();

      expect(commands(), <String?>[
        'start',
        'upload',
        'upload',
        'query',
        'upload',
        'upload, finalize',
      ]);
      expect(server.received, data);
    });

    test('pause while the read-ahead waits, then resume', () async {
      final StreamController<List<int>> input = StreamController<List<int>>();
      final Uint8List data = patternBytes(256 * kib + 100);
      final UploadTask task = ref().startStreamUpload(input.stream);
      // Exactly one chunk: the task waits for the next event to know whether it is the last.
      input.add(data.sublist(0, 256 * kib));
      await pumpEventQueue();
      expect(server.chunks, isEmpty);

      expect(task.pause(), isTrue);
      await task.progress.firstWhere(
        (UploadProgress p) => p.state == UploadState.paused,
      );
      expect(task.resume(), isTrue);
      input.add(data.sublist(256 * kib));
      await input.close();
      await task.result;

      expect(chunkSizes(), <int>[256 * kib, 100]);
      expect(server.received, data);
    });

    test('cancel during a chunk cancels the stream and the session', () async {
      final Completer<void> reached = Completer<void>();
      final Completer<void> gate = Completer<void>();
      final StreamController<List<int>> input = StreamController<List<int>>();
      server.chunkHook = (int index, Recorded r) async {
        reached.complete();
        await gate.future;
        return null;
      };
      final UploadTask task = ref().startStreamUpload(input.stream);
      input.add(patternBytes(300 * kib));
      await reached.future;

      expect(task.cancel(), isTrue);
      await expectLater(task.result, throwsStorageCode('canceled'));
      expect(task.state, UploadState.canceled);
      gate.complete();
      await pumpEventQueue();
      expect(input.hasListener, isFalse);
      expect(commands(), <String?>['start', 'upload', 'cancel']);
    });

    test('cancel while the stream stalls', () async {
      final StreamController<List<int>> input = StreamController<List<int>>();
      final UploadTask task = ref().startStreamUpload(input.stream);
      input.add(patternBytes(1000));
      await pumpEventQueue();

      expect(task.cancel(), isTrue);
      await expectLater(task.result, throwsStorageCode('canceled'));
      await pumpEventQueue();
      expect(input.hasListener, isFalse);
      expect(server.chunks, isEmpty);
    });

    test('waits its turn in maxConcurrentUploads', () async {
      storage.close();
      final Completer<void> gate = Completer<void>();
      final List<String> names = <String>[];
      // One fake server per upload; their session URLs are the same, so the order tells them apart: the
      // second starts only after the first ended.
      final FakeUploadServer firstServer = FakeUploadServer();
      final FakeUploadServer secondServer = FakeUploadServer();
      storage = storageWith(
        app,
        (Recorded r) async {
          if (r.headers['x-goog-upload-command'] == 'start') {
            names.add(r.url.queryParameters['name']!);
          }
          if (names.length == 1) {
            await gate.future;
            return firstServer.handle(r);
          }
          return secondServer.handle(r);
        },
        time: time,
        maxUploadChunkSize: chunkedUploads,
        maxConcurrentUploads: 1,
      );
      final UploadTask first = storage
          .ref('first')
          .startStreamUpload(Stream<List<int>>.value(patternBytes(10)));
      final UploadTask second = storage
          .ref('second')
          .startStreamUpload(Stream<List<int>>.value(patternBytes(10)));
      await pumpEventQueue();
      expect(names, <String>['first']);
      expect(second.state, UploadState.running);
      expect(second.bytesTransferred, 0);

      gate.complete();
      await first.result;
      await second.result;
      expect(names, <String>['first', 'second']);
      expect(firstServer.received, patternBytes(10));
      expect(secondServer.received, patternBytes(10));
    });

    test(
      'a producer that reuses one buffer for every event uploads its bytes',
      () async {
        final Uint8List data = patternBytes(1 * mib + 777);
        // Every event is a view of the same buffer, overwritten when the next event is asked for. Events
        // smaller and larger than the first chunk (an event that covers a whole chunk is the one that a
        // source keeping references would send corrupted).
        Stream<List<int>> reusing(int eventSize) async* {
          final Uint8List shared = Uint8List(eventSize);
          for (int i = 0; i < data.length; i += eventSize) {
            final int n = i + eventSize > data.length
                ? data.length - i
                : eventSize;
            shared
              ..fillRange(0, eventSize, 0xEE)
              ..setRange(0, n, data, i);
            yield Uint8List.sublistView(shared, 0, n);
          }
          shared.fillRange(0, eventSize, 0xEE);
        }

        for (final int eventSize in <int>[50 * kib, 300 * kib]) {
          for (final int? length in <int?>[null, data.length]) {
            server = FakeUploadServer()
              // A failure inside a chunk: the resend comes from the bytes the task kept.
              ..chunkHook = (int index, Recorded r) {
                if (index == 1) {
                  server.store(r.bodyBytes.sublist(0, 3 * kib));
                  return http.Response('', 503);
                }
                return null;
              };
            storage.close();
            storage = chunkedStorageWith(app, server.handle, time: time);
            await ref()
                .startStreamUpload(reusing(eventSize), length: length)
                .result;
            expect(
              server.received,
              data,
              reason: 'events of $eventSize, length $length',
            );
          }
        }
      },
    );

    test('a negative length still throws an ArgumentError', () {
      expect(
        () => ref().startStreamUpload(
          const Stream<List<int>>.empty(),
          length: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('existingSessionUri without a length', () {
    final Uri session = Uri.parse(FakeUploadServer.sessionUrl);

    test('skips what the server has in a stream of the whole data', () async {
      final Uint8List data = patternBytes(1 * mib);
      server.store(data.sublist(0, 300 * kib + 7));
      final UploadTask task = ref().startStreamUpload(
        eventsOfSize(data, 100 * kib),
        existingSessionUri: session,
      );
      await task.result;

      expect(commands().first, 'query');
      expect(commands(), isNot(contains('start')));
      expect(offsets().first, '${300 * kib + 7}');
      expect(commands().last, 'upload, finalize');
      expect(server.received, data);
      expect(task.totalBytes, data.length);
    });

    test('skips many tiny events the server already has', () async {
      final Uint8List data = patternBytes(1 * mib);
      const int have = 600 * kib + 3;
      server.store(data.sublist(0, have));
      // 10-byte events, so about 61,000 of them are skipped.
      final UploadTask task = ref().startStreamUpload(
        eventsOfSize(data, 10),
        existingSessionUri: session,
      );
      await task.result;
      expect(offsets().first, '$have');
      expect(server.received, data);
    });

    test('a finished session takes the size of the server', () async {
      final Uint8List data = patternBytes(300 * kib);
      server
        ..store(data)
        ..finalized = true;
      final UploadTask task = ref().startStreamUpload(
        eventsOfSize(data, 100 * kib),
        existingSessionUri: session,
      );
      final FullMetadata metadata = await task.result;
      expect(commands(), <String?>['query', null]);
      expect(metadata.size, data.length);
      expect(task.totalBytes, data.length);
    });

    test(
      'a stream shorter than the session fails with invalid-argument',
      () async {
        server.store(patternBytes(300 * kib));
        await expectLater(
          ref()
              .startStreamUpload(
                Stream<List<int>>.value(patternBytes(100 * kib)),
                existingSessionUri: session,
              )
              .result,
          throwsStorageCode('invalid-argument'),
        );
        expect(server.chunks, isEmpty);
      },
    );
  });

  group('internal-error', () {
    Matcher internal() => throwsA(
      isA<FirebaseStorageException>()
          .having(
            (FirebaseStorageException e) => e.code,
            'code',
            'internal-error',
          )
          .having(
            (FirebaseStorageException e) => e.message,
            'message',
            startsWith('Internal error: '),
          ),
    );

    test(
      'a session reporting more bytes than were sent, within the length',
      () async {
        server
          ..chunkHook = ((int index, _) =>
              index == 1 ? http.Response('', 503) : null)
          ..queryHook = (_) => http.Response(
            'OK',
            200,
            headers: <String, String>{
              'x-goog-upload-status': 'active',
              // 768 KiB were sent (256 KiB confirmed, 512 KiB failed).
              'x-goog-upload-size-received': '${900 * kib}',
            },
          );
        await expectLater(
          ref().startUpload(patternBytes(1 * mib)).result,
          internal(),
        );
      },
    );

    test(
      'a session reporting more bytes than were sent, without a length',
      () async {
        server
          ..chunkHook = ((int index, _) =>
              index == 0 ? http.Response('', 503) : null)
          ..queryHook = (_) => http.Response(
            'OK',
            200,
            headers: <String, String>{
              'x-goog-upload-status': 'active',
              'x-goog-upload-size-received': '$mib',
            },
          );
        await expectLater(
          ref()
              .startStreamUpload(eventsOfSize(patternBytes(2 * mib), 64 * kib))
              .result,
          internal(),
        );
      },
    );

    test('more bytes than the length stay server-file-wrong-size', () async {
      server
        ..chunkHook = ((int index, _) =>
            index == 0 ? http.Response('', 503) : null)
        ..queryHook = (_) => http.Response(
          'OK',
          200,
          headers: <String, String>{
            'x-goog-upload-status': 'active',
            'x-goog-upload-size-received': '${400 * kib}',
          },
        );
      await expectLater(
        ref().startUpload(patternBytes(300 * kib)).result,
        throwsStorageCode('server-file-wrong-size'),
      );
    });

    test('a data source that returns another size than asked', () async {
      final UploadTask task = ref().startUploadFrom(
        _ShortSource(1 * mib),
        operation: 'test',
      );
      await expectLater(task.result, internal());
      expect(server.chunks, isEmpty);
    });
  });
}

/// A source that claims [length] bytes but returns 10 bytes for every read.
final class _ShortSource implements UploadSource {
  _ShortSource(this.length);

  @override
  final int length;

  @override
  Stream<List<int>> Function(int offset)? get openFrom => null;

  @override
  Future<Uint8List> read(int offset, int size) async => Uint8List(10);

  @override
  Future<void> close() async {}
}

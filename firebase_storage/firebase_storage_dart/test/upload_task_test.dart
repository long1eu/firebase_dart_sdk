import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fakes.dart';
import 'upload_fakes.dart';

// The resumable upload task, after task.test.ts of the JS SDK, with the deliberate differences of the
// contract: cancel from paused, the retry wait reset after a success, and the 16 MiB chunk cap.
void main() {
  const int kib = 1024;
  const int mib = 1024 * 1024;

  late FirebaseApp app;
  late FakeUploadServer server;
  late FakeTime time;
  late FirebaseStorage storage;

  FirebaseStorage storageFor(
    FakeTime clock, {
    StorageRetryPolicy retry = const StorageRetryPolicy(),
  }) {
    storage.close();
    time = clock;
    return storage = storageWith(app, server.handle, time: clock, retry: retry);
  }

  setUp(() {
    app = newApp();
    server = FakeUploadServer();
    time = FakeTime();
    storage = storageWith(app, server.handle, time: time);
  });

  tearDown(() async {
    storage.close();
    await app.delete();
  });

  Reference ref() => storage.ref('f');

  /// Every event of [task] until its progress stream closes.
  Future<List<UploadProgress>> eventsOf(UploadTask task) =>
      task.progress.toList();

  List<int> chunkSizes() => <int>[
    for (final Recorded r in server.chunks) r.bodyBytes.length,
  ];

  List<String?> commands() => <String?>[
    for (final Recorded r in server.requests)
      r.headers['x-goog-upload-command'],
  ];

  group('one-shot', () {
    test('up to 256 KiB goes in one multipart request', () async {
      final Uint8List data = patternBytes(256 * kib);
      final UploadTask task = ref().startUpload(
        data,
        metadata: const SettableMetadata(contentType: 'text/x-a'),
      );
      final Future<List<UploadProgress>> events = eventsOf(task);

      final FullMetadata metadata = await task.result;

      expect(server.requests, hasLength(1));
      expect(
        server.requests.single.headers['x-goog-upload-protocol'],
        'multipart',
      );
      expect(server.received, data);
      expect(metadata.size, data.length);
      expect(task.state, UploadState.success);
      expect(task.sessionUri, isNull);
      expect(await events, <UploadProgress>[
        UploadProgress(
          state: UploadState.running,
          bytesTransferred: 0,
          totalBytes: data.length,
        ),
        UploadProgress(
          state: UploadState.running,
          bytesTransferred: data.length,
          totalBytes: data.length,
        ),
        UploadProgress(
          state: UploadState.success,
          bytesTransferred: data.length,
          totalBytes: data.length,
          metadata: metadata,
        ),
      ]);
    });

    test('an empty upload is one multipart request', () async {
      final FullMetadata metadata = await ref()
          .startUpload(Uint8List(0))
          .result;
      expect(metadata.size, 0);
      expect(server.requests, hasLength(1));
    });

    test('cancel while the request is in flight', () async {
      final Completer<void> gate = Completer<void>();
      final Completer<void> sent = Completer<void>();
      storage = storageWith(app, (Recorded r) async {
        sent.complete();
        await gate.future;
        return server.handle(r);
      }, time: time);
      final UploadTask task = ref().startUpload(patternBytes(10));
      await sent.future;

      expect(task.cancel(), isTrue);
      await expectLater(task.result, throwsStorageCode('canceled'));
      expect(task.state, UploadState.canceled);
      gate.complete();
    });

    test('pause and resume send the request again', () async {
      final Completer<void> gate = Completer<void>();
      int calls = 0;
      storage = storageWith(app, (Recorded r) async {
        if (calls++ == 0) {
          await gate.future;
        }
        return server.handle(r);
      }, time: time);
      final UploadTask task = ref().startUpload(patternBytes(10));
      await pumpEventQueue();

      expect(task.pause(), isTrue);
      await task.progress.firstWhere(
        (UploadProgress p) => p.state == UploadState.paused,
      );
      expect(task.resume(), isTrue);
      expect((await task.result).size, 10);
      expect(calls, 2);
      gate.complete();
    });
  });

  group('resumable', () {
    test('256 KiB + 1 byte starts a session and sends two chunks', () async {
      final Uint8List data = patternBytes(256 * kib + 1);
      final UploadTask task = ref().startUpload(
        data,
        metadata: const SettableMetadata(
          contentType: 'image/png',
          customMetadata: <String, String>{'k': 'v'},
        ),
      );
      final FullMetadata metadata = await task.result;

      final Recorded start = server.requests.first;
      expect(start.method, 'POST');
      expect(
        start.url.toString(),
        'https://firebasestorage.googleapis.com/v0/b/b/o?name=f',
      );
      for (final MapEntry<String, String> header in <String, String>{
        'X-Goog-Upload-Protocol': 'resumable',
        'X-Goog-Upload-Command': 'start',
        'X-Goog-Upload-Header-Content-Length': '${data.length}',
        'X-Goog-Upload-Header-Content-Type': 'image/png',
        'Content-Type': 'application/json; charset=utf-8',
      }.entries) {
        expect(start.headers[header.key], header.value, reason: header.key);
      }
      expect(jsonDecode(start.body), <String, Object?>{
        'name': 'f',
        'contentType': 'image/png',
        'metadata': <String, Object?>{'k': 'v'},
      });
      expect(commands(), <String?>['start', 'upload', 'upload, finalize']);
      expect(chunkSizes(), <int>[256 * kib, 1]);
      expect(
        <String?>[
          for (final Recorded r in server.chunks)
            r.headers['x-goog-upload-offset'],
        ],
        <String>['0', '${256 * kib}'],
      );
      expect(server.chunks.first.url.toString(), FakeUploadServer.sessionUrl);
      expect(server.received, data);
      expect(metadata.size, data.length);
      expect(task.sessionUri, Uri.parse(FakeUploadServer.sessionUrl));
      expect(time.delays, isEmpty);
    });

    test('chunks double from 256 KiB and stop at 16 MiB', () async {
      final Uint8List data = Uint8List(50 * mib);
      await ref().startUpload(data).result;

      expect(chunkSizes(), <int>[
        256 * kib,
        512 * kib,
        1 * mib,
        2 * mib,
        4 * mib,
        8 * mib,
        16 * mib,
        16 * mib,
        50 * mib - (31 * mib + 768 * kib) - 16 * mib,
      ]);
      expect(server.received.length, data.length);
    });

    test('emits one event per chunk, then success, then closes', () async {
      final Uint8List data = patternBytes(800 * kib);
      final UploadTask task = ref().startUpload(data);
      final List<UploadProgress> events = await eventsOf(task);

      expect(
        <(UploadState, int)>[
          for (final UploadProgress p in events) (p.state, p.bytesTransferred),
        ],
        <(UploadState, int)>[
          (UploadState.running, 0),
          (UploadState.running, 256 * kib),
          (UploadState.running, 768 * kib),
          (UploadState.running, 800 * kib),
          (UploadState.success, 800 * kib),
        ],
      );
      expect(events.last.metadata, await task.result);
      expect(
        events.every((UploadProgress p) => p.totalBytes == 800 * kib),
        isTrue,
      );
    });

    test('a listener added after the end gets the final snapshot', () async {
      final UploadTask task = ref().startUpload(patternBytes(300 * kib));
      await task.result;
      expect(await eventsOf(task), <UploadProgress>[task.snapshot]);
      expect(task.snapshot.state, UploadState.success);
    });

    test(
      'a failed chunk is followed by a wait, a query, and the rest from the server offset',
      () async {
        final Uint8List data = patternBytes(2 * mib);
        server.chunkHook = (int index, Recorded r) {
          if (index == 1) {
            // The server got 100 KiB of the second chunk, then failed.
            server.store(r.bodyBytes.sublist(0, 100 * kib));
            return http.Response('unavailable', 503);
          }
          return null;
        };
        final UploadTask task = ref().startUpload(data);
        final Future<List<UploadProgress>> events = eventsOf(task);
        await task.result;

        expect(commands(), <String?>[
          'start',
          'upload',
          'upload',
          'query',
          'upload',
          'upload',
          'upload, finalize',
        ]);
        expect(time.delays, <Duration>[const Duration(seconds: 1)]);
        final int resumeAt = 256 * kib + 100 * kib;
        expect(
          server.chunks
              .sublist(2)
              .map((Recorded r) => r.headers['x-goog-upload-offset']),
          <String>[
            '$resumeAt',
            '${resumeAt + 256 * kib}',
            '${resumeAt + 768 * kib}',
          ],
        );
        // The chunk size starts over at 256 KiB after the failure.
        expect(chunkSizes().sublist(2), <int>[
          256 * kib,
          512 * kib,
          2 * mib - resumeAt - 768 * kib,
        ]);
        expect(server.received, data);
        expect(
          (await events).map((UploadProgress p) => p.bytesTransferred),
          <int>[
            0,
            256 * kib,
            resumeAt,
            resumeAt + 256 * kib,
            resumeAt + 768 * kib,
            2 * mib,
            2 * mib,
          ],
        );
      },
    );

    test('a network error on a chunk is retried after a query', () async {
      server.chunkHook = (int index, Recorded r) {
        if (index == 0) {
          throw http.ClientException('connection reset');
        }
        return null;
      };
      final Uint8List data = patternBytes(300 * kib);
      await ref().startUpload(data).result;
      expect(commands(), <String?>[
        'start',
        'upload',
        'query',
        'upload',
        'upload, finalize',
      ]);
      expect(server.received, data);
    });

    test(
      'the wait doubles while chunks keep failing and starts over after a success',
      () async {
        server.chunkHook = (int index, Recorded r) => switch (index) {
          0 || 1 || 2 || 4 => http.Response('', index == 2 ? 429 : 500),
          _ => null,
        };
        await ref().startUpload(patternBytes(600 * kib)).result;
        expect(time.delays, const <Duration>[
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
          Duration(seconds: 1),
        ]);
      },
    );

    test(
      'gives up with retry-limit-exceeded after the upload retry time',
      () async {
        storageFor(
          FakeTime(),
          retry: const StorageRetryPolicy(upload: Duration(minutes: 3)),
        );
        server.chunkHook = (_, _) => http.Response('down', 503);
        final UploadTask task = ref().startUpload(patternBytes(300 * kib));
        final Future<List<UploadProgress>> events = eventsOf(task);

        await expectLater(
          task.result,
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
        // 1+2+4+8+16+32+64 = 127 s, then +64 = 191 s >= 3 min: no wait after that.
        expect(time.delays, const <Duration>[
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
          Duration(seconds: 8),
          Duration(seconds: 16),
          Duration(seconds: 32),
          Duration(seconds: 64),
          Duration(seconds: 64),
        ]);
        expect(task.state, UploadState.error);
        expect((await events).last.state, UploadState.error);
      },
    );

    test('a chunk refused with 403 fails the task at once', () async {
      server.chunkHook = (_, _) => http.Response(
        '{"error":{"code":403,"message":"Permission denied."}}',
        403,
      );
      final UploadTask task = ref().startUpload(patternBytes(300 * kib));
      await expectLater(
        task.result,
        throwsA(
          isA<FirebaseStorageException>()
              .having(
                (FirebaseStorageException e) => e.code,
                'code',
                'unauthorized',
              )
              .having(
                (FirebaseStorageException e) => e.serverResponse,
                'serverResponse',
                contains('Permission denied'),
              ),
        ),
      );
      expect(commands(), <String?>['start', 'upload']);
      expect(time.delays, isEmpty);
    });

    test('a 401 on a chunk is sent again with a refreshed token', () async {
      final FakeAuth auth = FakeAuth(<String?>['set', 'start', 'old', 'new']);
      app.authProvider = auth;
      server.chunkHook = (int index, Recorded r) =>
          index == 0 ? http.Response('', 401) : null;
      final Uint8List data = patternBytes(300 * kib);
      await ref().startUpload(data).result;

      expect(server.chunks.first.headers['authorization'], 'Firebase old');
      expect(server.chunks[1].headers['authorization'], 'Firebase new');
      expect(server.received, data);
    });

    test('a start without an upload URL fails with unknown', () async {
      storage = storageWith(
        app,
        (_) async => http.Response(
          'OK',
          200,
          headers: <String, String>{'x-goog-upload-status': 'active'},
        ),
        time: time,
      );
      await expectLater(
        ref().startUpload(patternBytes(300 * kib)).result,
        throwsStorageCode('unknown'),
      );
    });

    test('a start answered with 403 fails with unauthorized', () async {
      storage = storageWith(
        app,
        (_) async => http.Response('denied', 403),
        time: time,
      );
      await expectLater(
        ref().startUpload(patternBytes(300 * kib)).result,
        throwsStorageCode('unauthorized'),
      );
    });

    test('a query without a received size fails with unknown', () async {
      server.chunkHook = (int index, _) =>
          index == 0 ? http.Response('', 503) : null;
      server.queryHook = (_) => http.Response(
        'OK',
        200,
        headers: <String, String>{'x-goog-upload-status': 'active'},
      );
      await expectLater(
        ref().startUpload(patternBytes(300 * kib)).result,
        throwsStorageCode('unknown'),
      );
    });

    test(
      'a query that reports more bytes than the data fails with server-file-wrong-size',
      () async {
        server.chunkHook = (int index, _) =>
            index == 0 ? http.Response('', 503) : null;
        server.queryHook = (_) => http.Response(
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
      },
    );

    test(
      'a query that finds the upload final but short fails with server-file-wrong-size',
      () async {
        server
          ..chunkHook = ((int index, _) =>
              index == 0 ? http.Response('', 503) : null)
          ..queryHook = (_) => http.Response(
            'OK',
            200,
            headers: <String, String>{
              'x-goog-upload-status': 'final',
              'x-goog-upload-size-received': '10',
            },
          );
        await expectLater(
          ref().startUpload(patternBytes(300 * kib)).result,
          throwsStorageCode('server-file-wrong-size'),
        );
      },
    );

    test(
      'final metadata with another size fails with server-file-wrong-size',
      () async {
        server.chunkHook = (int index, Recorded r) => index == 1
            ? http.Response(
                jsonEncode(<String, Object?>{
                  'bucket': 'b',
                  'name': 'f',
                  'size': '5',
                }),
                200,
                headers: <String, String>{'x-goog-upload-status': 'final'},
              )
            : null;
        await expectLater(
          ref().startUpload(patternBytes(300 * kib)).result,
          throwsStorageCode('server-file-wrong-size'),
        );
      },
    );

    test('a query that finds the upload final reads the metadata', () async {
      final Uint8List data = patternBytes(300 * kib);
      server.chunkHook = (int index, Recorded r) {
        if (index == 1) {
          // The last chunk arrived, but the answer was lost.
          server
            ..store(r.bodyBytes)
            ..finalized = true;
          throw http.ClientException('connection reset');
        }
        return null;
      };
      final FullMetadata metadata = await ref().startUpload(data).result;
      expect(commands(), <String?>[
        'start',
        'upload',
        'upload, finalize',
        'query',
        null,
      ]);
      expect(server.requests.last.method, 'GET');
      expect(server.requests.last.url.path, '/v0/b/b/o/f');
      expect(metadata.size, data.length);
    });

    test(
      'an upload whose last chunk the server does not finalize ends with finalize',
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
        await ref().startUpload(data).result;
        expect(commands().last, 'finalize');
        expect(server.chunks.last.bodyBytes, isEmpty);
      },
    );

    test('throws invalid-root-operation on the root', () {
      expect(
        () => storage.ref().startUpload(Uint8List(1)),
        throwsStorageCode('invalid-root-operation'),
      );
    });
  });

  group('pause, resume and cancel', () {
    /// Holds the chunk with [index] until the returned completer completes.
    (Completer<void> reached, Completer<void> gate) holdChunk(int index) {
      final Completer<void> reached = Completer<void>();
      final Completer<void> gate = Completer<void>();
      server.chunkHook = (int i, Recorded r) async {
        if (i == index) {
          reached.complete();
          await gate.future;
        }
        return null;
      };
      return (reached, gate);
    }

    test(
      'pause aborts the chunk in flight; resume queries and goes on',
      () async {
        final (Completer<void> reached, Completer<void> gate) = holdChunk(1);
        final Uint8List data = patternBytes(1 * mib);
        final UploadTask task = ref().startUpload(data);
        final Future<List<UploadProgress>> events = eventsOf(task);
        await reached.future;

        expect(task.pause(), isTrue);
        expect(task.state, UploadState.running, reason: 'pausing');
        expect(task.pause(), isFalse);
        await task.progress.firstWhere(
          (UploadProgress p) => p.state == UploadState.paused,
        );
        expect(task.state, UploadState.paused);
        expect(task.bytesTransferred, 256 * kib);
        expect(task.pause(), isFalse);

        expect(task.resume(), isTrue);
        expect(task.resume(), isFalse);
        expect(task.state, UploadState.running);
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
        expect(
          (await events)
              .map((UploadProgress p) => (p.state, p.bytesTransferred))
              .toList()
              .sublist(0, 4),
          <(UploadState, int)>[
            (UploadState.running, 0),
            (UploadState.running, 256 * kib),
            (UploadState.paused, 256 * kib),
            (UploadState.running, 256 * kib),
          ],
        );
        expect(time.delays, isEmpty);
      },
    );

    test('resume while pausing does not stop the upload', () async {
      final (Completer<void> reached, Completer<void> gate) = holdChunk(0);
      final Uint8List data = patternBytes(300 * kib);
      final UploadTask task = ref().startUpload(data);
      final Future<List<UploadProgress>> events = eventsOf(task);
      await reached.future;

      expect(task.pause(), isTrue);
      expect(task.resume(), isTrue);
      await task.result;
      gate.complete();

      expect(server.received, data);
      expect(
        (await events).map((UploadProgress p) => p.state),
        isNot(contains(UploadState.paused)),
      );
    });

    test('cancel from paused', () async {
      final (Completer<void> reached, Completer<void> gate) = holdChunk(0);
      final UploadTask task = ref().startUpload(patternBytes(300 * kib));
      await reached.future;
      task.pause();
      await task.progress.firstWhere(
        (UploadProgress p) => p.state == UploadState.paused,
      );

      expect(task.cancel(), isTrue);
      expect(task.state, UploadState.canceled);
      await expectLater(task.result, throwsStorageCode('canceled'));
      expect(task.cancel(), isFalse);
      expect(task.resume(), isFalse);
      expect(task.pause(), isFalse);
      expect(await eventsOf(task), <UploadProgress>[task.snapshot]);
      gate.complete();
    });

    test('cancel during the session start', () async {
      final Completer<void> gate = Completer<void>();
      final Completer<void> reached = Completer<void>();
      storage = storageWith(app, (Recorded r) async {
        reached.complete();
        await gate.future;
        return server.handle(r);
      }, time: time);
      final UploadTask task = ref().startUpload(patternBytes(300 * kib));
      final Future<List<UploadProgress>> events = eventsOf(task);
      await reached.future;

      expect(task.cancel(), isTrue);
      expect(task.cancel(), isFalse);
      await expectLater(task.result, throwsStorageCode('canceled'));
      expect((await events).map((UploadProgress p) => p.state), <UploadState>[
        UploadState.running,
        UploadState.canceled,
      ]);
      gate.complete();
    });

    test('cancel during a chunk', () async {
      final (Completer<void> reached, Completer<void> gate) = holdChunk(1);
      final UploadTask task = ref().startUpload(patternBytes(1 * mib));
      await reached.future;

      expect(task.cancel(), isTrue);
      await expectLater(task.result, throwsStorageCode('canceled'));
      expect(task.bytesTransferred, 256 * kib);
      gate.complete();
      await pumpEventQueue();
      expect(commands(), <String?>['start', 'upload', 'upload', 'cancel']);
      expect(server.requests.last.url.toString(), FakeUploadServer.sessionUrl);
    });

    test('cancel during a query', () async {
      final Completer<void> reached = Completer<void>();
      final Completer<void> gate = Completer<void>();
      server
        ..chunkHook = ((int index, _) =>
            index == 0 ? http.Response('', 503) : null)
        ..queryHook = (_) async {
          reached.complete();
          await gate.future;
          return null;
        };
      final UploadTask task = ref().startUpload(patternBytes(300 * kib));
      await reached.future;

      expect(task.cancel(), isTrue);
      await expectLater(task.result, throwsStorageCode('canceled'));
      gate.complete();
    });

    test('pause and cancel during the wait before a retry', () async {
      final GatedTime gated = GatedTime()..gate = Completer<void>();
      storageFor(gated);
      server.chunkHook = (int index, _) =>
          index == 0 ? http.Response('', 503) : null;
      final UploadTask task = ref().startUpload(patternBytes(300 * kib));
      await gated.waiting.future;

      expect(task.pause(), isTrue);
      await task.progress.firstWhere(
        (UploadProgress p) => p.state == UploadState.paused,
      );
      expect(task.cancel(), isTrue);
      await expectLater(task.result, throwsStorageCode('canceled'));
      gated.gate!.complete();
    });

    test(
      'resume after a pause in the wait goes straight to the query',
      () async {
        final GatedTime gated = GatedTime()..gate = Completer<void>();
        storageFor(gated);
        server.chunkHook = (int index, _) =>
            index == 0 ? http.Response('', 503) : null;
        final Uint8List data = patternBytes(300 * kib);
        final UploadTask task = ref().startUpload(data);
        await gated.waiting.future;

        task.pause();
        await task.progress.firstWhere(
          (UploadProgress p) => p.state == UploadState.paused,
        );
        gated.gate = null;
        task.resume();
        await task.result;
        expect(gated.delays, <Duration>[const Duration(seconds: 1)]);
        expect(server.received, data);
      },
    );

    test('nothing to control after success', () async {
      final UploadTask task = ref().startUpload(patternBytes(300 * kib));
      await task.result;
      expect(task.pause(), isFalse);
      expect(task.resume(), isFalse);
      expect(task.cancel(), isFalse);
    });
  });

  group('session', () {
    final Uri session = Uri.parse(FakeUploadServer.sessionUrl);

    test(
      'existingSessionUri resumes at the server offset without a start',
      () async {
        final Uint8List data = patternBytes(1 * mib);
        server.store(data.sublist(0, 300 * kib));
        final UploadTask task = ref().startUpload(
          data,
          existingSessionUri: session,
        );
        final List<UploadProgress> events = await eventsOf(task);

        expect(commands(), <String?>['query', 'upload', 'upload, finalize']);
        expect(
          server.chunks.first.headers['x-goog-upload-offset'],
          '${300 * kib}',
        );
        expect(server.received, data);
        expect(task.sessionUri, session);
        expect(events[1].bytesTransferred, 300 * kib);
      },
    );

    test('existingSessionUri is used for small data too', () async {
      final Uint8List data = patternBytes(1000);
      server.store(data.sublist(0, 10));
      await ref().startUpload(data, existingSessionUri: session).result;
      expect(commands(), <String?>['query', 'upload, finalize']);
      expect(server.received, data);
    });

    test(
      'existingSessionUri of a finished upload reads the metadata',
      () async {
        final Uint8List data = patternBytes(300 * kib);
        server
          ..store(data)
          ..finalized = true;
        final FullMetadata metadata = await ref()
            .startUpload(data, existingSessionUri: session)
            .result;
        expect(commands(), <String?>['query', null]);
        expect(metadata.size, data.length);
      },
    );

    test(
      'existingSessionUri with a stream skips what the server has',
      () async {
        final Uint8List data = patternBytes(1 * mib);
        server.store(data.sublist(0, 300 * kib + 7));
        Stream<List<int>> pieces() async* {
          for (int i = 0; i < data.length; i += 100 * kib) {
            yield data.sublist(
              i,
              i + 100 * kib > data.length ? data.length : i + 100 * kib,
            );
          }
        }

        await ref()
            .startStreamUpload(
              pieces(),
              length: data.length,
              existingSessionUri: session,
            )
            .result;
        expect(server.received, data);
      },
    );

    test('existingSessionUri on another host throws invalid-argument', () {
      for (final String other in <String>[
        'https://evil.example/v0/b/b/o?upload_id=secret',
        'http://firebasestorage.googleapis.com/v0/b/b/o?upload_id=secret',
        'https://firebasestorage.googleapis.com:8443/v0/b/b/o?upload_id=secret',
        'https://user@firebasestorage.googleapis.com/v0/b/b/o?upload_id=secret',
        'https://firebasestorage.googleapis.com/upload?upload_id=secret',
      ]) {
        expect(
          () => ref().startUpload(
            Uint8List(1),
            existingSessionUri: Uri.parse(other),
          ),
          throwsA(
            isA<FirebaseStorageException>()
                .having(
                  (FirebaseStorageException e) => e.code,
                  'code',
                  'invalid-argument',
                )
                .having(
                  (FirebaseStorageException e) => '$e',
                  'toString',
                  isNot(contains('secret')),
                ),
          ),
          reason: other,
        );
      }
      expect(server.requests, isEmpty);
    });

    test(
      'existingSessionUri must be on the emulator host with an emulatorHost',
      () async {
        storage.close();
        storage = storageWith(
          app,
          server.handle,
          time: time,
          emulatorHost: '127.0.0.1:9199',
        );
        expect(
          () => ref().startUpload(Uint8List(1), existingSessionUri: session),
          throwsStorageCode('invalid-argument'),
        );
        server.store(<int>[1]);
        await ref()
            .startUpload(
              Uint8List.fromList(<int>[1, 2]),
              existingSessionUri: Uri.parse(
                'http://127.0.0.1:9199/v0/b/b/o?name=f&upload_id=u1',
              ),
            )
            .result;
        expect(server.received, <int>[1, 2]);
      },
    );

    test(
      'a session on another host from start fails with unknown and sends nothing there',
      () async {
        for (final String url in <String>[
          'https://evil.example/v0/b/b/o?upload_id=secret',
          'http://firebasestorage.googleapis.com/v0/b/b/o?upload_id=secret',
          '',
        ]) {
          server.requests.clear();
          storage.close();
          storage = storageWith(app, (Recorded r) async {
            server.requests.add(r);
            return http.Response(
              'OK',
              200,
              headers: <String, String>{
                'x-goog-upload-status': 'active',
                'x-goog-upload-url': url,
              },
            );
          }, time: time);
          final UploadTask task = ref().startUpload(patternBytes(300 * kib));
          await expectLater(
            task.result,
            throwsA(
              isA<FirebaseStorageException>()
                  .having(
                    (FirebaseStorageException e) => e.code,
                    'code',
                    'unknown',
                  )
                  .having(
                    (FirebaseStorageException e) => '$e',
                    'toString',
                    isNot(contains('secret')),
                  ),
            ),
            reason: url,
          );
          expect(task.sessionUri, isNull);
          expect(server.requests, hasLength(1), reason: url);
        }
      },
    );

    test(
      'a received size that is not a plain number fails with unknown',
      () async {
        for (final String size in <String>[
          '0x10',
          '-1',
          '+5',
          ' 5',
          '1e3',
          '99999999999999999999',
        ]) {
          server = FakeUploadServer()
            ..chunkHook = ((int index, _) =>
                index == 0 ? http.Response('', 503) : null)
            ..queryHook = (_) => http.Response(
              'OK',
              200,
              headers: <String, String>{
                'x-goog-upload-status': 'active',
                'x-goog-upload-size-received': size,
              },
            );
          storage.close();
          storage = storageWith(app, server.handle, time: time);
          await expectLater(
            ref().startUpload(patternBytes(300 * kib)).result,
            throwsStorageCode('unknown'),
            reason: size,
          );
        }
      },
    );

    test(
      'a received size below the confirmed bytes fails with server-file-wrong-size',
      () async {
        server
          ..chunkHook = ((int index, _) =>
              index == 1 ? http.Response('', 503) : null)
          ..queryHook = (_) => http.Response(
            'OK',
            200,
            headers: <String, String>{
              'x-goog-upload-status': 'active',
              'x-goog-upload-size-received': '${100 * kib}',
            },
          );
        await expectLater(
          ref().startUpload(patternBytes(1 * mib)).result,
          throwsStorageCode('server-file-wrong-size'),
        );
      },
    );

    test(
      'cancel from paused sends the cancel command to the session',
      () async {
        final Completer<void> gate = Completer<void>();
        final Completer<void> reached = Completer<void>();
        server.chunkHook = (int index, _) async {
          if (index == 0) {
            reached.complete();
            await gate.future;
          }
          return null;
        };
        final UploadTask task = ref().startUpload(patternBytes(300 * kib));
        await reached.future;
        task.pause();
        await task.progress.firstWhere(
          (UploadProgress p) => p.state == UploadState.paused,
        );
        task.cancel();
        await expectLater(task.result, throwsStorageCode('canceled'));
        await pumpEventQueue();
        expect(commands().last, 'cancel');
        gate.complete();
      },
    );

    test('a one-shot cancel sends no cancel command', () async {
      final Completer<void> gate = Completer<void>();
      storage = storageWith(app, (Recorded r) async {
        server.requests.add(r);
        await gate.future;
        return http.Response('', 500);
      }, time: time);
      final UploadTask task = ref().startUpload(patternBytes(10));
      await pumpEventQueue();
      task.cancel();
      await expectLater(task.result, throwsStorageCode('canceled'));
      await pumpEventQueue();
      expect(server.requests, hasLength(1));
      gate.complete();
    });

    test('a content type with a line break fails before any request', () async {
      final UploadTask task = ref().startUpload(
        patternBytes(300 * kib),
        metadata: const SettableMetadata(
          contentType: 'text/plain\r\nX-Evil: 1',
        ),
      );
      await expectLater(task.result, throwsStorageCode('invalid-argument'));
      expect(server.requests, isEmpty);
    });
  });

  group('stream', () {
    Stream<List<int>> eventsOfSize(Uint8List data, int size) async* {
      for (int i = 0; i < data.length; i += size) {
        yield data.sublist(i, i + size > data.length ? data.length : i + size);
      }
    }

    test('uploads a stream in chunks', () async {
      final Uint8List data = patternBytes(1 * mib + 5);
      final UploadTask task = ref().startStreamUpload(
        eventsOfSize(data, 100 * kib + 3),
        length: data.length,
      );
      final FullMetadata metadata = await task.result;
      expect(server.received, data);
      expect(metadata.size, data.length);
      expect(chunkSizes(), <int>[256 * kib, 512 * kib, 256 * kib + 5]);
    });

    test('a short stream goes in one multipart request', () async {
      final Uint8List data = patternBytes(1000);
      await ref().startStreamUpload(eventsOfSize(data, 7), length: 1000).result;
      expect(
        server.requests.single.headers['x-goog-upload-protocol'],
        'multipart',
      );
      expect(server.received, data);
    });

    test('reads no more than one chunk ahead', () async {
      final Uint8List data = patternBytes(2 * mib);
      int pulled = 0;
      final List<int> pulledAtChunk = <int>[];
      server.chunkHook = (int index, Recorded r) {
        pulledAtChunk.add(pulled);
        return null;
      };
      Stream<List<int>> counted() async* {
        await for (final List<int> event in eventsOfSize(data, 64 * kib)) {
          pulled += event.length;
          yield event;
        }
      }

      await ref().startStreamUpload(counted(), length: data.length).result;
      // Each chunk was sent once the stream had produced it, and at most one event more.
      expect(pulledAtChunk[0], lessThanOrEqualTo(256 * kib + 64 * kib));
      expect(pulledAtChunk[1], lessThanOrEqualTo(768 * kib + 64 * kib));
      expect(server.received, data);
    });

    test('resumes inside the buffered chunk after a failure', () async {
      final Uint8List data = patternBytes(1 * mib);
      server.chunkHook = (int index, Recorded r) {
        if (index == 1) {
          server.store(r.bodyBytes.sublist(0, 10 * kib));
          return http.Response('', 503);
        }
        return null;
      };
      await ref()
          .startStreamUpload(eventsOfSize(data, 50 * kib), length: data.length)
          .result;
      expect(server.received, data);
    });

    test(
      'a server offset before the buffered chunk fails with server-file-wrong-size',
      () async {
        server
          ..chunkHook = ((int index, _) =>
              index == 1 ? http.Response('', 503) : null)
          ..queryHook = (_) => http.Response(
            'OK',
            200,
            headers: <String, String>{
              'x-goog-upload-status': 'active',
              'x-goog-upload-size-received': '10',
            },
          );
        final Uint8List data = patternBytes(1 * mib);
        await expectLater(
          ref()
              .startStreamUpload(
                eventsOfSize(data, 50 * kib),
                length: data.length,
              )
              .result,
          throwsStorageCode('server-file-wrong-size'),
        );
      },
    );

    test(
      'a stream shorter than its length fails with invalid-argument',
      () async {
        await expectLater(
          ref()
              .startStreamUpload(
                Stream<List<int>>.value(patternBytes(300 * kib)),
                length: 400 * kib,
              )
              .result,
          throwsStorageCode('invalid-argument'),
        );
      },
    );

    test(
      'a stream longer than its length fails with invalid-argument',
      () async {
        await expectLater(
          ref()
              .startStreamUpload(
                Stream<List<int>>.fromIterable(<List<int>>[
                  patternBytes(300 * kib),
                  <int>[],
                  <int>[1],
                ]),
                length: 300 * kib,
              )
              .result,
          throwsStorageCode('invalid-argument'),
        );
        await expectLater(
          ref()
              .startStreamUpload(
                Stream<List<int>>.value(patternBytes(10)),
                length: 5,
              )
              .result,
          throwsStorageCode('invalid-argument'),
        );
      },
    );

    test('an error of the stream fails the task with that error', () async {
      final StreamController<List<int>> input = StreamController<List<int>>();
      final UploadTask task = ref().startStreamUpload(
        input.stream,
        length: 300 * kib,
      );
      input
        ..add(patternBytes(1000))
        ..addError(const FormatException('disk gone'));
      await expectLater(task.result, throwsFormatException);
      expect(task.state, UploadState.error);
      await input.close();
    });

    test('cancel while the stream stalls', () async {
      final StreamController<List<int>> input = StreamController<List<int>>();
      final UploadTask task = ref().startStreamUpload(
        input.stream,
        length: 300 * kib,
      );
      input.add(patternBytes(1000));
      await pumpEventQueue();

      expect(task.cancel(), isTrue);
      await expectLater(task.result, throwsStorageCode('canceled'));
      await pumpEventQueue();
      expect(input.hasListener, isFalse);
      expect(server.chunks, isEmpty);
    });

    test('pause while the stream stalls, then resume', () async {
      final StreamController<List<int>> input = StreamController<List<int>>();
      final Uint8List data = patternBytes(300 * kib);
      final UploadTask task = ref().startStreamUpload(
        input.stream,
        length: data.length,
      );
      input.add(data.sublist(0, 1000));
      await pumpEventQueue();

      expect(task.pause(), isTrue);
      await task.progress.firstWhere(
        (UploadProgress p) => p.state == UploadState.paused,
      );
      expect(task.resume(), isTrue);
      input.add(data.sublist(1000));
      await input.close();
      await task.result;
      expect(server.received, data);
    });

    test('a negative length throws an ArgumentError', () {
      expect(
        () => ref().startStreamUpload(
          const Stream<List<int>>.empty(),
          length: -1,
        ),
        throwsArgumentError,
      );
    });
  });
}

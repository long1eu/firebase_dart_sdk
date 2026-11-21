import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../fakes.dart';
import '../upload_fakes.dart';
import 'conformance.dart';

// Conformance with task.test.ts of the JS SDK (UploadTask), and with the resumable-upload cases of
// requests.test.ts (createResumableUpload, getResumableUploadStatus, continueResumableUpload), through
// Reference.startUpload. JS `task.on('state_changed', next, error, complete)` is UploadTask.progress (which
// also carries the final state) plus UploadTask.result.
//
// The progress assertions hold whether or not the task also reports bytes inside a chunk: they check that
// bytesTransferred never goes down, that every chunk boundary is reported, and the order of the states, not
// the number of events.
//
// JS smallBlob = 1 byte, bigBlob = 1 MiB.
const int kib = 1024;
const int mib = 1024 * kib;

/// The distinct states in the order they were first entered after each change: [running, paused, running,
/// success] for a task paused and resumed once.
List<UploadState> transitions(List<UploadProgress> events) {
  final List<UploadState> states = <UploadState>[];
  for (final UploadProgress event in events) {
    if (states.isEmpty || states.last != event.state) {
      states.add(event.state);
    }
  }
  return states;
}

/// The JS checks of runNormalUploadTest: increasing, same total, last is all (for a success).
void expectWellFormed(List<UploadProgress> events, int total) {
  for (int i = 0; i < events.length - 1; i++) {
    expect(
      events[i].bytesTransferred,
      lessThanOrEqualTo(events[i + 1].bytesTransferred),
      reason: 'bytesTransferred went down at event $i: $events',
    );
  }
  expect(events.map((UploadProgress e) => e.totalBytes).toSet(), <int>{total});
}

void main() {
  late FirebaseApp app;
  late FakeUploadServer server;
  late FakeTime time;
  late FirebaseStorage storage;

  FirebaseStorage storageFor(FakeTime clock) {
    storage.close();
    time = clock;
    return storage = storageWith(app, server.handle, time: clock);
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

  /// Every event of [task] until its progress stream closes, and the outcome of its result.
  Future<(List<UploadProgress>, Object?)> run(UploadTask task) async {
    final Future<List<UploadProgress>> events = task.progress.toList();
    Object? error;
    try {
      await task.result;
    } on Object catch (e) {
      error = e;
    }
    return (await events, error);
  }

  Matcher storageCode(String code) => isA<FirebaseStorageException>().having(
    (FirebaseStorageException e) => e.code,
    'code',
    code,
  );

  group('task.test.ts', () {
    test('Works for a small upload w/ an observer', () async {
      final (List<UploadProgress> events, Object? error) = await run(
        ref().startUpload(Uint8List.fromList(<int>[97])),
      );
      expect(error, isNull);
      expect(events.last.state, UploadState.success);
      expect(events.last.metadata, isNotNull);
    });

    test('Works for a small upload w/ a promise', () async {
      final UploadTask task = ref().startUpload(Uint8List.fromList(<int>[97]));
      final FullMetadata metadata = await task.result;
      expect(task.snapshot.totalBytes, 1);
      expect(task.snapshot.bytesTransferred, 1);
      expect(metadata.size, 1);
    });

    test('Works for a small upload canceled w/ a promise', () async {
      final UploadTask task = ref().startUpload(Uint8List.fromList(<int>[97]));
      expect(task.cancel(), isTrue);
      await expectLater(task.result, throwsA(storageCode('canceled')));
      expect(task.state, UploadState.canceled);
    });

    test('Works properly with multiple observers', () async {
      final UploadTask task = ref().startUpload(Uint8List.fromList(<int>[97]));
      bool badComplete = false;
      final StreamSubscription<UploadProgress> h1 = task.progress.listen(
        null,
        onDone: () => badComplete = true,
      );
      final StreamSubscription<UploadProgress> h2 = task.progress.listen(
        null,
        onDone: () => badComplete = true,
      );
      final Future<List<UploadProgress>> h3 = task.progress.toList();
      await h1.cancel();
      await h2.cancel();
      final List<UploadProgress> events = await task.progress.toList();
      expect(badComplete, isFalse);
      // "resumed" counts entries into running: exactly one.
      expect(
        transitions(
          await h3,
        ).where((UploadState s) => s == UploadState.running),
        hasLength(1),
      );
      expect(events.last.state, UploadState.success);
    });

    test("Works properly with an observer missing the 'next' method", () async {
      final UploadTask task = ref().startUpload(Uint8List.fromList(<int>[97]));
      final Completer<void> done = Completer<void>();
      task.progress.listen(null, onDone: done.complete);
      await done.future;
      await task.result;
    });

    for (final (String name, int size) in <(String, int)>[
      ('small', 1),
      ('big', mib),
    ]) {
      test('Calls callback sequences for $name uploads correctly', () async {
        // runNormalUploadTest: pause at once, resume when paused, complete; then a second task canceled at
        // once fails.
        final UploadTask task = ref().startUpload(patternBytes(size));
        final List<UploadProgress> events = <UploadProgress>[];
        final Completer<void> closed = Completer<void>();
        task.progress.listen((UploadProgress p) {
          events.add(p);
          if (p.state == UploadState.paused) {
            Timer(Duration.zero, task.resume);
          }
        }, onDone: closed.complete);
        expect(task.pause(), isTrue);
        final FullMetadata metadata = await task.result;
        await closed.future;
        expect(transitions(events), <UploadState>[
          UploadState.running,
          UploadState.paused,
          UploadState.running,
          UploadState.success,
        ]);
        expectWellFormed(events, size);
        expect(events.last.bytesTransferred, size);
        expect(metadata.size, size);
        expect(server.received, patternBytes(size));

        final UploadTask task2 = ref().startUpload(patternBytes(size));
        final Future<(List<UploadProgress>, Object?)> outcome = run(task2);
        expect(task2.cancel(), isTrue);
        final (List<UploadProgress> events2, Object? error) = await outcome;
        expect(transitions(events2), <UploadState>[
          UploadState.running,
          UploadState.canceled,
        ]);
        // JS only checks that some failure came; here it is the right one.
        expect(error, storageCode('canceled'));
      });
    }

    test(
      'properly times out if large blobs returns a 503 when finalizing',
      () async {
        // fake503ForFinalizeServerHandler: chunks with finalize get 503, a query reports every byte but active.
        server.chunkHook = (int index, Recorded request) {
          final String command = request.headers['x-goog-upload-command']!;
          if (command.contains('finalize')) {
            return http.Response('', 503);
          }
          return null;
        };
        server.queryHook = (_) => http.Response(
          'OK',
          200,
          headers: <String, String>{
            'x-goog-upload-status': 'active',
            'x-goog-upload-size-received': '$mib',
          },
        );
        final (List<UploadProgress> events, Object? error) = await run(
          ref().startUpload(patternBytes(mib)),
        );
        expect(transitions(events), <UploadState>[
          UploadState.running,
          UploadState.error,
        ]);
        expect(error, storageCode('retry-limit-exceeded'));
        expectWellFormed(events, mib);
        // The chunk boundaries of the JS test: 256 KiB, then a doubled 512 KiB chunk, then the rest from the query.
        final Set<int> reported = events
            .map((UploadProgress e) => e.bytesTransferred)
            .toSet();
        expect(reported, containsAll(<int>[0, 262144, 786432, 1048576]));
        expect(events.first.bytesTransferred, 0);
        expect(events.last.bytesTransferred, mib);
      },
    );

    test(
      'properly times out if large blobs returns a 503 when uploading',
      () async {
        server.chunkHook = (int index, Recorded request) =>
            request.headers['x-goog-upload-command']!.contains('upload')
            ? http.Response('', 503)
            : null;
        final (List<UploadProgress> events, Object? error) = await run(
          ref().startUpload(patternBytes(mib)),
        );
        expect(transitions(events), <UploadState>[
          UploadState.running,
          UploadState.error,
        ]);
        expect(error, storageCode('retry-limit-exceeded'));
        expect(
          events.map((UploadProgress e) => e.bytesTransferred).toSet(),
          <int>{0},
        );
      },
    );

    test(
      'properly errors with a cancel StorageError if a pending timeout remains',
      () async {
        final GatedTime gated = GatedTime()..gate = Completer<void>();
        storageFor(gated);
        server.chunkHook = (int index, Recorded request) =>
            http.Response('', 503);
        final UploadTask task = ref().startUpload(patternBytes(mib));
        final Future<(List<UploadProgress>, Object?)> outcome = run(task);
        await gated.waiting.future;
        expect(task.cancel(), isTrue);
        final (List<UploadProgress> events, Object? error) = await outcome;
        expect(transitions(events), <UploadState>[
          UploadState.running,
          UploadState.canceled,
        ]);
        expect(error, storageCode('canceled'));
        expect(
          events.map((UploadProgress e) => e.bytesTransferred).toSet(),
          <int>{0},
        );
        gated.gate!.complete();
      },
    );

    test(
      'properly errors with a pause StorageError if a pending timeout remains',
      () async {
        final GatedTime gated = GatedTime()..gate = Completer<void>();
        storageFor(gated);
        server.chunkHook = (int index, Recorded request) =>
            http.Response('', 503);
        final UploadTask task = ref().startUpload(patternBytes(mib));
        final Future<(List<UploadProgress>, Object?)> outcome = run(task);
        await gated.waiting.future;
        expect(task.pause(), isTrue);
        await task.progress.firstWhere(
          (UploadProgress p) => p.state == UploadState.paused,
        );
        final Completer<void> held = gated.gate!;
        gated.gate = null;
        held.complete();
        expect(task.resume(), isTrue);
        final (List<UploadProgress> events, Object? error) = await outcome;
        expect(transitions(events), <UploadState>[
          UploadState.running,
          UploadState.paused,
          UploadState.running,
          UploadState.error,
        ]);
        expect(error, storageCode('retry-limit-exceeded'));
        expect(
          events.map((UploadProgress e) => e.bytesTransferred).toSet(),
          <int>{0},
        );
      },
    );

    test('does not error when pausing inflight request', () async {
      // runProgressPauseTest: the first chunk is held, the task is paused while it is in flight, then resumed.
      final Completer<void> inFlight = Completer<void>();
      final Completer<void> release = Completer<void>();
      server.chunkHook = (int index, Recorded request) async {
        if (index != 0) {
          return null;
        }
        inFlight.complete();
        await release.future;
        return http.Response('', 503);
      };
      final UploadTask task = ref().startUpload(patternBytes(mib));
      final Future<(List<UploadProgress>, Object?)> outcome = run(task);
      await inFlight.future;
      expect(task.pause(), isTrue);
      await task.progress.firstWhere(
        (UploadProgress p) => p.state == UploadState.paused,
      );
      expect(task.resume(), isTrue);
      final (List<UploadProgress> events, Object? error) = await outcome;
      release.complete();
      expect(error, isNull);
      expect(transitions(events), <UploadState>[
        UploadState.running,
        UploadState.paused,
        UploadState.running,
        UploadState.success,
      ]);
      expectWellFormed(events, mib);
      expect(events.last.bytesTransferred, mib);
      expect(server.received, patternBytes(mib));
    });

    test(
      'tests if small requests that respond with 500 retry correctly',
      () async {
        // fakeOneShot503ServerHandler: every request is 503. The multipart request is retried until the upload
        // retry time is over.
        final FirebaseStorage failing = storageWith(
          app,
          (Recorded r) async => http.Response('', 503),
          time: time,
        );
        addTearDown(failing.close);
        final (List<UploadProgress> events, Object? error) = await run(
          failing.ref('f').startUpload(Uint8List.fromList(<int>[97])),
        );
        expect(transitions(events), <UploadState>[
          UploadState.running,
          UploadState.error,
        ]);
        expect(error, storageCode('retry-limit-exceeded'));
        expect(
          events.map((UploadProgress e) => e.bytesTransferred).toSet(),
          <int>{0},
        );
        expect(time.delays, isNotEmpty, reason: 'retried with backoff');
      },
    );
  });

  group('requests.test.ts: resumable upload requests', () {
    const SettableMetadata jsMetadata = SettableMetadata(
      contentType: 'application/jason',
      customMetadata: <String, String>{'foo': 'bar'},
    );

    test('createResumableUpload request info', () async {
      for (final (String bucket, String path) in <(String, String)>[
        ('b', 'o'),
        ('b', 'o?'),
      ]) {
        // A server of its own per upload: the fake keeps the bytes it received.
        final FakeUploadServer fresh = FakeUploadServer();
        final FirebaseStorage instance = storageWith(
          app,
          fresh.handle,
          bucket: bucket,
          time: time,
        );
        addTearDown(instance.close);
        final UploadTask task = instance
            .ref(path)
            .startUpload(patternBytes(300 * kib), metadata: jsMetadata);
        await task.result;
        expectRequest(
          fresh.requests.first,
          method: 'POST',
          url:
              '$prod/v0/b/${Uri.encodeComponent(bucket)}/o?name=${Uri.encodeComponent(path)}',
          headers: commonHeaders(<String, String>{
            'x-goog-upload-protocol': 'resumable',
            'x-goog-upload-command': 'start',
            'x-goog-upload-header-content-length': '${300 * kib}',
            'x-goog-upload-header-content-type': 'application/jason',
            'content-type': 'application/json; charset=utf-8',
          }),
          body: jsonEncode(<String, Object?>{
            'name': path,
            'contentType': 'application/jason',
            'metadata': <String, String>{'foo': 'bar'},
          }),
        );
        expect(task.sessionUri, Uri.parse(FakeUploadServer.sessionUrl));
      }
    });

    test(
      'createResumableUpload handler: no status or no upload URL is unknown',
      () async {
        for (final Map<String, String> headers in <Map<String, String>>[
          <String, String>{'x-goog-upload-url': FakeUploadServer.sessionUrl},
          <String, String>{'x-goog-upload-status': 'active'},
          <String, String>{
            'x-goog-upload-status': 'final',
            'x-goog-upload-url': FakeUploadServer.sessionUrl,
          },
        ]) {
          final FirebaseStorage odd = storageWith(
            app,
            (Recorded r) async => http.Response('OK', 200, headers: headers),
            time: time,
          );
          addTearDown(odd.close);
          await expectLater(
            odd.ref('f').startUpload(patternBytes(300 * kib)).result,
            throwsA(storageCode('unknown')),
            reason: '$headers',
          );
        }
      },
    );

    test('getResumableUploadStatus request info', () async {
      // A query is sent after a pause: POST to the session URL, only the command header, no body.
      final Completer<void> inFlight = Completer<void>();
      final Completer<void> release = Completer<void>();
      server.chunkHook = (int index, Recorded request) async {
        if (index != 0) {
          return null;
        }
        inFlight.complete();
        await release.future;
        return http.Response('', 503);
      };
      final UploadTask task = ref().startUpload(patternBytes(300 * kib));
      await inFlight.future;
      task.pause();
      await task.progress.firstWhere(
        (UploadProgress p) => p.state == UploadState.paused,
      );
      task.resume();
      await task.result;
      release.complete();
      final Recorded query = server.requests.firstWhere(
        (Recorded r) => r.headers['x-goog-upload-command'] == 'query',
      );
      expectRequest(
        query,
        method: 'POST',
        url: FakeUploadServer.sessionUrl,
        headers: commonHeaders(<String, String>{
          'x-goog-upload-command': 'query',
        }),
      );
    });

    test(
      'getResumableUploadStatus handler: a size that is not a number is unknown',
      () async {
        server.chunkHook = (int index, _) =>
            index == 0 ? http.Response('', 503) : null;
        server.queryHook = (_) => http.Response(
          'OK',
          200,
          headers: <String, String>{
            'x-goog-upload-status': 'active',
            'x-goog-upload-size-received': 'lots',
          },
        );
        await expectLater(
          ref().startUpload(patternBytes(300 * kib)).result,
          throwsA(storageCode('unknown')),
        );
      },
    );

    test(
      'continueResumableUpload request info: upload, then upload, finalize',
      () async {
        final Uint8List data = patternBytes(300 * kib);
        await ref().startUpload(data).result;
        final List<Recorded> chunks = server.chunks;
        expect(chunks, hasLength(2));
        expect(chunks[0].method, 'POST');
        expect(chunks[0].url.toString(), FakeUploadServer.sessionUrl);
        expect(
          headersOf(chunks[0]),
          commonHeaders(<String, String>{
            'x-goog-upload-command': 'upload',
            'x-goog-upload-offset': '0',
          }),
        );
        expect(chunks[0].bodyBytes, data.sublist(0, 256 * kib));
        expect(chunks[1].headers['x-goog-upload-command'], 'upload, finalize');
        expect(chunks[1].headers['x-goog-upload-offset'], '${256 * kib}');
        expect(chunks[1].bodyBytes, data.sublist(256 * kib));
      },
    );

    test(
      'populates requestInfo with just the finalize command when no more data needs to be uploaded',
      () async {
        // The last chunk reaches the server but its answer is lost: the query reports every byte, still active,
        // and the task sends an empty finalize at the end offset.
        final Uint8List data = patternBytes(300 * kib);
        server.chunkHook = (int index, Recorded request) {
          if (index == 1) {
            server.store(request.bodyBytes);
            return http.Response('', 503);
          }
          return null;
        };
        final FullMetadata metadata = await ref().startUpload(data).result;
        final Recorded finalize = server.chunks.last;
        expect(finalize.headers['x-goog-upload-command'], 'finalize');
        expect(finalize.headers['x-goog-upload-offset'], '${data.length}');
        expect(finalize.bodyBytes, isEmpty);
        expect(metadata.size, data.length);
      },
    );

    test(
      'continueResumableUpload handler: final carries the metadata, active none',
      () async {
        final FullMetadata metadata = await ref()
            .startUpload(patternBytes(300 * kib))
            .result;
        expect(metadata.fullPath, 'f');
        expect(metadata.size, 300 * kib);
      },
    );
  });

  group('deliberate differences (storage_api_contract.md)', () {
    test(
      'cancel works from paused (JS cancel() returns false there)',
      () async {
        final UploadTask task = ref().startUpload(patternBytes(mib));
        expect(task.pause(), isTrue);
        await task.progress.firstWhere(
          (UploadProgress p) => p.state == UploadState.paused,
        );
        expect(task.cancel(), isTrue);
        await expectLater(task.result, throwsA(storageCode('canceled')));
        expect(task.state, UploadState.canceled);
        expect(task.cancel(), isFalse);
        expect(task.resume(), isFalse);
      },
    );

    test(
      'the retry wait resets after a successful chunk (JS sleepTime never resets)',
      () async {
        // Chunks 0 and 2 fail once each: JS would wait 1 s and then 2 s; Dart waits 1 s both times.
        final Set<int> failed = <int>{};
        server.chunkHook = (int index, Recorded request) {
          final int offset = int.parse(
            request.headers['x-goog-upload-offset']!,
          );
          if ((offset == 0 || offset == 768 * kib) && failed.add(offset)) {
            return http.Response('', 503);
          }
          return null;
        };
        await ref().startUpload(patternBytes(mib + kib)).result;
        expect(time.delays, <Duration>[
          const Duration(seconds: 1),
          const Duration(seconds: 1),
        ]);
      },
    );

    test(
      'up to 256 KiB is a single multipart request, one byte more is resumable (_shouldDoResumable)',
      () async {
        await ref().startUpload(patternBytes(256 * kib)).result;
        expect(server.requests, hasLength(1));
        expect(
          server.requests.single.headers['x-goog-upload-protocol'],
          'multipart',
        );
        server = FakeUploadServer();
        storageFor(FakeTime());
        await ref().startUpload(patternBytes(256 * kib + 1)).result;
        expect(
          server.requests.first.headers['x-goog-upload-protocol'],
          'resumable',
        );
        expect(server.chunks, hasLength(2));
      },
    );

    test(
      'chunks double from 256 KiB and stop at 16 MiB (JS comment says 32 MiB, code gives 16)',
      () async {
        const int total =
            256 * kib +
            512 * kib +
            mib +
            2 * mib +
            4 * mib +
            8 * mib +
            16 * mib +
            16 * mib +
            1;
        await ref().startUpload(Uint8List(total)).result;
        expect(server.chunks.map((Recorded r) => r.bodyBytes.length), <int>[
          256 * kib,
          512 * kib,
          mib,
          2 * mib,
          4 * mib,
          8 * mib,
          16 * mib,
          16 * mib,
          1, //
        ]);
        expect(
          server.chunks.last.headers['x-goog-upload-command'],
          'upload, finalize',
        );
      },
    );

    test(
      'a session URL on another host is refused (JS uses X-Goog-Upload-URL verbatim)',
      () async {
        final FirebaseStorage elsewhere = storageWith(
          app,
          (Recorded r) async => http.Response(
            'OK',
            200,
            headers: <String, String>{
              'x-goog-upload-status': 'active',
              'x-goog-upload-url':
                  'https://evil.example.com/v0/b/b/o?upload_id=1',
            },
          ),
          time: time,
        );
        addTearDown(elsewhere.close);
        await expectLater(
          elsewhere.ref('f').startUpload(patternBytes(300 * kib)).result,
          throwsA(storageCode('unknown')),
        );
        expect(
          () => ref().startUpload(
            patternBytes(300 * kib),
            existingSessionUri: Uri.parse(
              'https://evil.example.com/v0/b/b/o?upload_id=1',
            ),
          ),
          throwsA(storageCode('invalid-argument')),
        );
      },
    );

    test(
      'startUpload on the root throws invalid-root-operation (JS uploadBytesResumable throws)',
      () {
        expect(
          () => storage.ref().startUpload(Uint8List(0)),
          throwsA(storageCode('invalid-root-operation')),
        );
        expect(server.requests, isEmpty);
      },
    );
  });

  group('getStream (streamed downloads, Reference.openRead)', () {
    late List<Recorded> requests;
    late Future<http.Response> Function(Recorded request) respond;
    late FirebaseStorage downloads;
    final Uint8List content = Uint8List.fromList(utf8.encode('hello world'));

    setUp(() {
      requests = <Recorded>[];
      respond = (_) async => http.Response.bytes(content, 200);
      downloads = storageWith(
        app,
        (Recorded r) => respond(r),
        requests: requests,
        time: time,
      );
    });

    tearDown(() => downloads.close());

    Future<List<int>> read(Stream<List<int>> stream) =>
        stream.expand((List<int> c) => c).toList();

    test('getStream request: GET ?alt=media, no Range', () async {
      expect(await read(downloads.ref('o').openRead()), content);
      expectRequest(
        requests.single,
        method: 'GET',
        url: '$prod/v0/b/b/o/o?alt=media',
        headers: commonHeaders(),
      );
    });

    test(
      'a range is sent as an inclusive Range header and 206 is accepted (Dart extra)',
      () async {
        respond = (_) async => http.Response.bytes(content.sublist(2, 5), 206);
        expect(
          await read(downloads.ref('o').openRead(2, 5)),
          content.sublist(2, 5),
        );
        expect(headersOf(requests.single)['range'], 'bytes=2-4');
        requests.clear();
        respond = (_) async => http.Response.bytes(content.sublist(3), 206);
        expect(await read(downloads.ref('o').openRead(3)), content.sublist(3));
        expect(headersOf(requests.single)['range'], 'bytes=3-');
      },
    );

    test(
      'a 200 to a ranged request is the whole object: the start is skipped',
      () async {
        expect(
          await read(downloads.ref('o').openRead(6, 9)),
          utf8.encode('wor'),
        );
      },
    );

    test('a 416 is an empty read; an empty range sends nothing', () async {
      respond = (_) async => http.Response('', 416);
      expect(await read(downloads.ref('o').openRead(99)), isEmpty);
      requests.clear();
      expect(await read(downloads.ref('o').openRead(4, 4)), isEmpty);
      expect(requests, isEmpty);
    });

    test(
      '404 is object-not-found on the stream (objectErrorHandler)',
      () async {
        respond = (_) async => http.Response('Not Found', 404);
        await expectLater(
          read(downloads.ref('o').openRead()),
          throwsA(storageCode('object-not-found')),
        );
      },
    );

    test('root and bad ranges fail on the stream before any request', () async {
      await expectLater(
        read(downloads.ref().openRead()),
        throwsA(storageCode('invalid-root-operation')),
      );
      await expectLater(
        read(downloads.ref('o').openRead(-1)),
        throwsA(storageCode('invalid-argument')),
      );
      await expectLater(
        read(downloads.ref('o').openRead(5, 2)),
        throwsA(storageCode('invalid-argument')),
      );
      expect(requests, isEmpty);
    });

    test('a 503 before the first byte is retried with backoff', () async {
      int n = 0;
      respond = (_) async =>
          n++ == 0 ? http.Response('', 503) : http.Response.bytes(content, 200);
      expect(await read(downloads.ref('o').openRead()), content);
      expect(requests, hasLength(2));
    });
  });
}

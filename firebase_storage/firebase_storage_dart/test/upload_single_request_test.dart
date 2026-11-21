@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:firebase_storage_dart/io.dart';
import 'package:firebase_storage_dart/src/upload/upload_source.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fakes.dart';
import 'upload_fakes.dart';

// 0.1.1: on the VM an upload of bytes or of a file goes in one streamed request of the resumable session;
// maxUploadChunkSize brings chunks back; requestTimeout is an idle timeout; maxConcurrentUploads queues
// the uploads of an instance.
void main() {
  const int kib = 1024;
  const int mib = 1024 * 1024;

  late FirebaseApp app;
  late FakeUploadServer server;
  late FakeTime time;
  FirebaseStorage? storage;

  setUp(() {
    app = newApp();
    server = FakeUploadServer();
    time = FakeTime();
  });

  tearDown(() async {
    storage?.close();
    storage = null;
    await app.delete();
  });

  List<String?> commands() => <String?>[
    for (final Recorded r in server.requests)
      r.headers['x-goog-upload-command'],
  ];

  /// A storage whose client reads bodies piece by piece, with one request for the rest of an upload.
  FirebaseStorage single({
    Future<void> Function(Recorded request, int consumed)? onConsumed,
    Duration requestTimeout = const Duration(minutes: 1),
  }) {
    return storage = slowStorage(
      app,
      server,
      time,
      maxUploadChunkSize: null,
      onConsumed: onConsumed,
      requestTimeout: requestTimeout,
    );
  }

  bool firstRequest(Recorded request) =>
      request.headers['x-goog-upload-offset'] == '0';

  group('one request', () {
    test('bytes go in one request of the session, with progress', () async {
      final Uint8List data = patternBytes(1 * mib);
      final UploadTask task = single().ref('f').startUpload(data);
      final List<UploadProgress> events = await task.progress.toList();

      expect(commands(), <String?>['start', 'upload, finalize']);
      expect(server.chunks.single.headers['x-goog-upload-offset'], '0');
      expect(server.chunks.single.bodyBytes, data);
      expect(server.received, data);
      final List<int> between = <int>[
        for (final UploadProgress p in events)
          if (p.bytesTransferred > 0 && p.bytesTransferred < data.length)
            p.bytesTransferred,
      ];
      expect(between, isNotEmpty);
      expect(events.last.state, UploadState.success);
    });

    test('up to 256 KiB is still one multipart request', () async {
      final Uint8List data = patternBytes(256 * kib);
      await single().ref('f').startUpload(data).result;
      expect(
        server.requests.single.headers['x-goog-upload-protocol'],
        'multipart',
      );
    });

    test('a stream is still chunked', () async {
      final Uint8List data = patternBytes(1 * mib);
      await single()
          .ref('f')
          .startStreamUpload(Stream<List<int>>.value(data), length: data.length)
          .result;
      expect(commands(), <String?>[
        'start',
        'upload',
        'upload',
        'upload, finalize',
      ]);
      expect(server.received, data);
    });

    test(
      'a failure in the middle resumes from the server offset (bytes)',
      () async {
        final Uint8List data = patternBytes(1 * mib);
        bool failed = false;
        single(
          onConsumed: (Recorded request, int consumed) async {
            if (!failed && firstRequest(request) && consumed >= 300 * kib) {
              failed = true;
              // The server kept the first 300 KiB, then the connection broke.
              server.store(data.sublist(0, 300 * kib));
              throw http.ClientException('Connection reset by peer');
            }
          },
        );
        final UploadTask task = storage!.ref('f').startUpload(data);
        final List<UploadProgress> events = await task.progress.toList();

        expect(commands(), <String?>[
          // The broken attempt never reached the server.
          'start',
          'query',
          'upload, finalize',
        ]);
        final Recorded second = server.chunks.last;
        expect(second.headers['x-goog-upload-offset'], '${300 * kib}');
        expect(second.bodyBytes, data.sublist(300 * kib));
        expect(server.received, data);
        expect(time.delays, <Duration>[const Duration(seconds: 1)]);
        expect(
          events.map((UploadProgress p) => p.bytesTransferred),
          contains(300 * kib),
        );
        expect(events.last.state, UploadState.success);
      },
    );

    test('pause in the middle, then resume from the server offset', () async {
      final Uint8List data = patternBytes(1 * mib);
      final Completer<void> reached = Completer<void>();
      final Completer<void> gate = Completer<void>();
      single(
        onConsumed: (Recorded request, int consumed) async {
          if (firstRequest(request) && consumed >= 256 * kib) {
            if (!reached.isCompleted) {
              server.store(data.sublist(0, 256 * kib));
              reached.complete();
            }
            await gate.future;
            throw http.ClientException('aborted');
          }
        },
      );
      final UploadTask task = storage!.ref('f').startUpload(data);
      await reached.future;

      expect(task.pause(), isTrue);
      final UploadProgress paused = await task.progress.firstWhere(
        (UploadProgress p) => p.state == UploadState.paused,
      );
      // Nothing was confirmed before the pause.
      expect(paused.bytesTransferred, 0);
      expect(task.resume(), isTrue);
      await task.result;
      gate.complete();

      expect(commands(), <String?>['start', 'query', 'upload, finalize']);
      expect(
        server.chunks.single.headers['x-goog-upload-offset'],
        '${256 * kib}',
      );
      expect(server.received, data);
    });

    test(
      'a file goes in one request and resumes from the server offset',
      () async {
        final Directory dir = await Directory.systemTemp.createTemp(
          'upload_single',
        );
        addTearDown(() => dir.delete(recursive: true));
        final Uint8List data = patternBytes(1 * mib + 3);
        final File file = File('${dir.path}/data.bin')..writeAsBytesSync(data);
        bool failed = false;
        single(
          onConsumed: (Recorded request, int consumed) async {
            if (!failed && firstRequest(request) && consumed >= 512 * kib) {
              failed = true;
              server.store(data.sublist(0, 400 * kib));
              throw http.ClientException('Connection reset by peer');
            }
          },
        );

        final FullMetadata metadata = await storage!
            .ref('f')
            .putFile(file)
            .result;

        expect(commands(), <String?>[
          // The broken attempt never reached the server.
          'start',
          'query',
          'upload, finalize',
        ]);
        expect(
          server.chunks.last.headers['x-goog-upload-offset'],
          '${400 * kib}',
        );
        expect(server.received, data);
        expect(metadata.size, data.length);
      },
    );

    test(
      'a file that shrinks fails with invalid-argument, without a retry',
      () async {
        final Uint8List data = patternBytes(1 * mib);
        single();
        final UploadTask task = storage!
            .ref('f')
            .startUploadFrom(
              UploadSource.seekable(
                data.length,
                (int offset) => Stream<List<int>>.value(
                  data.sublist(offset, data.length - 10),
                ),
              ),
              operation: 'putFile',
            );
        await expectLater(task.result, throwsStorageCode('invalid-argument'));
        expect(commands(), isNot(contains('query')));
      },
    );

    test('a file that grows fails with invalid-argument', () async {
      final Uint8List data = patternBytes(1 * mib);
      single();
      final UploadTask task = storage!
          .ref('f')
          .startUploadFrom(
            UploadSource.seekable(
              data.length,
              (int offset) => Stream<List<int>>.fromIterable(<List<int>>[
                data.sublist(offset),
                <int>[1, 2, 3],
              ]),
            ),
            operation: 'putFile',
          );
      await expectLater(task.result, throwsStorageCode('invalid-argument'));
      expect(commands(), isNot(contains('query')));
    });

    test('a read error of the file fails the task with that error', () async {
      single();
      final UploadTask task = storage!
          .ref('f')
          .startUploadFrom(
            UploadSource.seekable(
              1 * mib,
              (int offset) => Stream<List<int>>.error(
                const FileSystemException('Input/output error'),
              ),
            ),
            operation: 'putFile',
          );
      await expectLater(task.result, throwsA(isA<FileSystemException>()));
      expect(commands(), isNot(contains('query')));
    });
  });

  group('maxUploadChunkSize', () {
    test('is rounded down to 256 KiB, at least 256 KiB', () {
      FirebaseStorage make(int? size) =>
          storageWith(app, server.handle, maxUploadChunkSize: size)..close();
      expect(make(null).maxUploadChunkSize, isNull);
      expect(make(1).maxUploadChunkSize, 256 * kib);
      expect(make(300 * kib).maxUploadChunkSize, 256 * kib);
      expect(make(1 * mib + 5).maxUploadChunkSize, 1 * mib);
      expect(make(64 * mib).maxUploadChunkSize, 64 * mib);
      expect(() => make(0), throwsArgumentError);
      expect(() => make(-1), throwsArgumentError);
    });

    test('caps the chunks of bytes', () async {
      storage = storageWith(
        app,
        server.handle,
        time: time,
        maxUploadChunkSize: 600 * kib,
      );
      final Uint8List data = patternBytes(2 * mib);
      await storage!.ref('f').startUpload(data).result;
      expect(
        <int>[for (final Recorded r in server.chunks) r.bodyBytes.length],
        <int>[256 * kib, 512 * kib, 512 * kib, 512 * kib, 256 * kib],
      );
      expect(server.received, data);
    });

    test('caps the chunks of a stream above 16 MiB too', () async {
      storage = storageWith(
        app,
        server.handle,
        time: time,
        maxUploadChunkSize: 32 * mib,
      );
      final Uint8List data = Uint8List(40 * mib);
      await storage!
          .ref('f')
          .startStreamUpload(Stream<List<int>>.value(data), length: data.length)
          .result;
      expect(
        <int>[for (final Recorded r in server.chunks) r.bodyBytes.length],
        <int>[
          256 * kib,
          512 * kib,
          1 * mib,
          2 * mib,
          4 * mib,
          8 * mib,
          16 * mib,
          40 * mib - (31 * mib + 768 * kib),
        ],
      );
    });
  });

  group('idle timeout', () {
    test('a slow body that keeps moving never times out', () async {
      final Uint8List data = patternBytes(1 * mib);
      single(
        requestTimeout: const Duration(milliseconds: 200),
        onConsumed: (Recorded request, int consumed) =>
            Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      // 16 pieces of 80 ms: 1.3 s for the body, far over the 200 ms timeout.
      await storage!.ref('f').startUpload(data).result;
      expect(commands(), <String?>['start', 'upload, finalize']);
      expect(server.received, data);
    });

    test('a body that stalls times out and resumes after a query', () async {
      final Uint8List data = patternBytes(1 * mib);
      bool stalled = false;
      single(
        requestTimeout: const Duration(milliseconds: 200),
        onConsumed: (Recorded request, int consumed) async {
          if (!stalled && firstRequest(request) && consumed >= 128 * kib) {
            stalled = true;
            await Future<void>.delayed(const Duration(milliseconds: 600));
            // This attempt was given up; end it here so it never reaches the server.
            throw http.ClientException('gone');
          }
        },
      );
      await storage!.ref('f').startUpload(data).result;
      expect(commands(), <String?>[
        // The broken attempt never reached the server.
        'start',
        'query',
        'upload, finalize',
      ]);
      expect(server.received, data);
    });

    test('no response long after the body ended times out', () async {
      final Uint8List data = patternBytes(1 * mib);
      bool waited = false;
      single(
        requestTimeout: const Duration(milliseconds: 200),
        onConsumed: (Recorded request, int consumed) async {
          if (!waited && firstRequest(request) && consumed == data.length) {
            waited = true;
            await Future<void>.delayed(const Duration(milliseconds: 600));
            throw http.ClientException('gone');
          }
        },
      );
      await storage!.ref('f').startUpload(data).result;
      expect(commands(), <String?>[
        // The broken attempt never reached the server.
        'start',
        'query',
        'upload, finalize',
      ]);
      expect(server.received, data);
    });
  });

  group('maxConcurrentUploads', () {
    late List<String> started;
    late Map<String, Completer<void>> gates;

    /// Uploads of 10 bytes (one multipart request each) that are held until [finish] is called.
    FirebaseStorage limited(int limit) {
      started = <String>[];
      gates = <String, Completer<void>>{};
      return storage = storageWith(
        app,
        (Recorded r) async {
          final String name = r.url.queryParameters['name']!;
          started.add(name);
          await (gates[name] = Completer<void>()).future;
          return json(<String, Object?>{
            'bucket': 'b',
            'name': name,
            'size': '10',
          });
        },
        time: time,
        maxConcurrentUploads: limit,
      );
    }

    Future<void> finish(String name) async {
      gates[name]!.complete();
      await pumpEventQueue();
    }

    UploadTask upload(String name) =>
        storage!.ref(name).startUpload(Uint8List(10));

    test('must be at least 1', () {
      expect(
        () => storageWith(app, server.handle, maxConcurrentUploads: 0),
        throwsArgumentError,
      );
    });

    test('runs uploads in order, at most the limit at once', () async {
      limited(2);
      final List<UploadTask> tasks = <UploadTask>[
        for (final String name in <String>['a', 'b', 'c', 'd']) upload(name),
      ];
      await pumpEventQueue();
      expect(started, <String>['a', 'b']);
      expect(tasks[2].state, UploadState.running);
      expect(tasks[2].bytesTransferred, 0);
      expect(storage!.uploadSlots.waiting, 2);

      await finish('a');
      expect(started, <String>['a', 'b', 'c']);
      await finish('b');
      expect(started, <String>['a', 'b', 'c', 'd']);
      await finish('c');
      await finish('d');
      for (final UploadTask task in tasks) {
        expect((await task.result).name, isNotEmpty);
      }
      expect(storage!.uploadSlots.active, 0);
    });

    test(
      'a task paused while waiting leaves the queue and queues again on resume',
      () async {
        limited(2);
        final UploadTask a = upload('a');
        upload('b');
        final UploadTask c = upload('c');
        final UploadTask d = upload('d');
        await pumpEventQueue();

        expect(c.pause(), isTrue);
        await c.progress.firstWhere(
          (UploadProgress p) => p.state == UploadState.paused,
        );
        expect(c.bytesTransferred, 0);
        await finish('a');
        expect(started, <String>['a', 'b', 'd']);

        expect(c.resume(), isTrue);
        await pumpEventQueue();
        expect(started, <String>['a', 'b', 'd']);
        await finish('b');
        expect(started, <String>['a', 'b', 'd', 'c']);
        await finish('d');
        await finish('c');
        await a.result;
        await c.result;
        await d.result;
      },
    );

    test('a task canceled while waiting leaves the queue', () async {
      limited(1);
      final UploadTask a = upload('a');
      final UploadTask b = upload('b');
      final UploadTask c = upload('c');
      await pumpEventQueue();

      expect(b.cancel(), isTrue);
      await expectLater(b.result, throwsStorageCode('canceled'));
      expect(storage!.uploadSlots.waiting, 1);
      await finish('a');
      expect(started, <String>['a', 'c']);
      await finish('c');
      await a.result;
      await c.result;
    });

    test('pausing a running task gives its turn to the next one', () async {
      limited(1);
      final UploadTask a = upload('a');
      final UploadTask b = upload('b');
      await pumpEventQueue();
      expect(started, <String>['a']);

      expect(a.pause(), isTrue);
      await a.progress.firstWhere(
        (UploadProgress p) => p.state == UploadState.paused,
      );
      await pumpEventQueue();
      expect(started, <String>['a', 'b']);
      expect(a.cancel(), isTrue);
      await expectLater(a.result, throwsStorageCode('canceled'));
      await finish('b');
      await b.result;
      gates['a']!.complete();
    });

    test('putBytes and putString wait their turn too', () async {
      limited(1);
      final UploadTask a = upload('a');
      await pumpEventQueue();
      final Future<FullMetadata> put = storage!
          .ref('p')
          .putBytes(Uint8List(10));
      final Future<FullMetadata> string = storage!
          .ref('s')
          .putString('0123456789');
      await pumpEventQueue();
      expect(started, <String>['a']);

      await finish('a');
      expect(started, <String>['a', 'p']);
      await finish('p');
      expect(started, <String>['a', 'p', 's']);
      await finish('s');
      await a.result;
      await put;
      await string;
    });
  });
}

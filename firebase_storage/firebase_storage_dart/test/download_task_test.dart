// The resumable file download of io.dart (DownloadTask): progress, pause and resume with a Range request,
// resume after a broken body, the generation guard, servers that ignore Range, and the partial file.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:firebase_storage_dart/io.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fakes.dart';
import 'streaming_client.dart';

const int _kib = 1024;

/// One object behind the metadata and media endpoints, with knobs for the failures the task must survive.
final class FakeObjectServer {
  FakeObjectServer(this.bytes, {this.chunkSize = 64 * _kib});

  /// The content; a test replaces it to model an object that is overwritten.
  List<int> bytes;

  /// The size of each chunk of a media body.
  final int chunkSize;

  /// The generation of the object, in the metadata and in `x-goog-generation`.
  String generation = '7';

  /// Whether media responses carry `x-goog-generation`.
  bool sendGeneration = true;

  /// Whether a ranged request gets the whole object with 200, as the emulator does for some ranges.
  bool ignoreRange = false;

  /// For each of the next media responses, the number of chunks after which the body breaks.
  final List<int> breakAfter = <int>[];

  /// The media response that holds its body after [holdAfter] chunks until [release] completes.
  int? holdAfter;
  Completer<void> release = Completer<void>();

  /// A status to answer the media requests with.
  int? mediaStatus;

  /// Called before each media response is built, with its index.
  void Function(int index)? onMedia;

  /// Advances [time] by this much before each chunk.
  Duration perChunk = Duration.zero;
  FakeTime? time;

  final List<http.BaseRequest> metadataRequests = <http.BaseRequest>[];
  final List<http.BaseRequest> mediaRequests = <http.BaseRequest>[];

  /// Whether the object is missing: every request gets 404.
  bool missing = false;

  /// Whether the object is stored gzip-compressed (`contentEncoding: gzip`). Like Cloud Storage, a request
  /// with `Accept-Encoding: identity` gets the unzipped bytes with 200 whatever its `Range`; any other request
  /// gets the stored bytes with `Content-Encoding: gzip`.
  bool gzipped = false;

  /// The size in the metadata instead of the length of [bytes].
  int? metadataSize;

  /// Added to the first byte that the `Content-Range` of a 206 names, to model a misplaced part.
  int contentRangeShift = 0;

  List<int> get _stored => gzipped ? gzip.encode(bytes) : bytes;

  /// Called once the body of a metadata response was handed over.
  void Function()? onMetadataServed;

  Stream<List<int>> _metadataBody(List<int> json) async* {
    yield json;
    onMetadataServed?.call();
  }

  Future<http.StreamedResponse> handle(http.BaseRequest request) async {
    if (missing) {
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('{"error":{"code":404}}')),
        404,
      );
    }
    if (request.url.queryParameters['alt'] != 'media') {
      metadataRequests.add(request);
      return http.StreamedResponse(
        _metadataBody(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'bucket': 'b',
              'name': 'a/b.bin',
              'generation': generation,
              'metageneration': '1',
              'size': '${metadataSize ?? _stored.length}',
              if (gzipped) 'contentEncoding': 'gzip',
            }),
          ),
        ),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    }
    final int index = mediaRequests.length;
    mediaRequests.add(request);
    onMedia?.call(index);
    final int? status = mediaStatus;
    if (status != null) {
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('Failure')),
        status,
      );
    }
    final bool identity = request.headers['Accept-Encoding'] == 'identity';
    final bool transcoded = gzipped && identity;
    final List<int> content = transcoded ? bytes : _stored;
    final Match? range = RegExp(
      r'^bytes=(\d+)-$',
    ).firstMatch(request.headers['Range'] ?? '');
    final bool ranged = range != null && !ignoreRange && !transcoded;
    final int start = ranged ? int.parse(range[1]!) : 0;
    final Map<String, String> headers = <String, String>{
      if (sendGeneration) 'x-goog-generation': generation,
      if (gzipped && !identity) 'content-encoding': 'gzip',
      if (ranged)
        'content-range':
            'bytes ${start + contentRangeShift}-${content.length - 1}/'
            '${content.length}',
    };
    if (start >= content.length && start > 0) {
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        416,
        headers: headers,
      );
    }
    final int? breakAt = breakAfter.isEmpty ? null : breakAfter.removeAt(0);
    final int? holdAt = holdAfter;
    holdAfter = null;
    return http.StreamedResponse(
      _body(content, start, breakAt, holdAt),
      ranged ? 206 : 200,
      headers: headers,
    );
  }

  /// [content] from [start] in chunks; it breaks after [breakAt] chunks (also after the last one) and holds
  /// after [holdAt] chunks until [release] completes.
  Stream<List<int>> _body(
    List<int> content,
    int start,
    int? breakAt,
    int? holdAt,
  ) async* {
    int sent = 0;
    for (int i = start; i < content.length; i += chunkSize) {
      if (holdAt != null && sent == holdAt) {
        await release.future;
      }
      if (breakAt != null && sent == breakAt) {
        throw http.ClientException('connection reset');
      }
      final FakeTime? clock = time;
      if (clock != null) {
        clock.now = clock.now.add(perChunk);
      }
      yield content.sublist(i, math.min(i + chunkSize, content.length));
      sent++;
    }
    if (breakAt != null && sent == breakAt) {
      throw http.ClientException('connection reset after the last byte');
    }
  }
}

void main() {
  late FirebaseApp app;
  late Directory dir;
  late FakeTime time;
  late FakeObjectServer server;
  late StreamingClient client;
  FirebaseStorage? current;
  late File target;

  final List<int> data = List<int>.generate(300 * _kib, (int i) => i % 251);

  FirebaseStorage storageOn(
    FakeObjectServer objects, {
    StorageRetryPolicy retry = const StorageRetryPolicy(),
  }) {
    current?.close();
    server = objects;
    client = StreamingClient(objects.handle);
    return current = FirebaseStorage(
      app,
      httpClient: client,
      retry: retry,
      clock: time.clock,
      random: () => 0.5,
      delay: time.delay,
    );
  }

  setUp(() async {
    app = newApp();
    dir = await Directory.systemTemp.createTemp('storage_download_task');
    target = File('${dir.path}/out.bin');
    time = FakeTime();
    storageOn(FakeObjectServer(data));
  });

  tearDown(() async {
    current?.close();
    current = null;
    await app.delete();
    await dir.delete(recursive: true);
  });

  FirebaseStorage storage() => current!;

  Reference ref() => storage().ref('a/b.bin');

  List<String> namesInDir() =>
      dir
          .listSync()
          .map((FileSystemEntity e) => e.uri.pathSegments.last)
          .toList()
        ..sort();

  /// Waits (real time, the file writes are real I/O) until [condition] holds.
  Future<void> until(bool Function() condition) async {
    for (int i = 0; i < 5000 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(condition(), isTrue, reason: 'condition not reached');
  }

  String? rangeOf(http.BaseRequest request) => request.headers['Range'];

  group('download', () {
    test('writes the object, renames the partial file and returns the '
        'metadata', () async {
      final DownloadTask task = ref().startDownloadToFile(target);
      final FullMetadata metadata = await task.result;
      expect(metadata.fullPath, 'a/b.bin');
      expect(metadata.generation, '7');
      expect(metadata.size, data.length);
      expect(await target.readAsBytes(), data);
      expect(namesInDir(), <String>['out.bin']);
      expect(task.state, DownloadState.success);
      expect(task.bytesTransferred, data.length);
      expect(task.totalBytes, data.length);
      expect(server.metadataRequests, hasLength(1));
      expect(server.mediaRequests, hasLength(1));
      expect(rangeOf(server.mediaRequests.single), isNull);
    });

    test(
      'the partial file has an unpredictable name next to the target',
      () async {
        server.holdAfter = 1;
        final DownloadTask task = ref().startDownloadToFile(target);
        await until(() => task.bytesTransferred == 64 * _kib);
        expect(namesInDir(), <Matcher>[
          matches(RegExp(r'^out\.bin\.[0-9a-f]{16}\.part$')),
        ]);
        server.release.complete();
        await task.result;
        expect(namesInDir(), <String>['out.bin']);
      },
    );

    test('replaces a file already there', () async {
      target.writeAsStringSync('a much longer old content than before');
      storageOn(FakeObjectServer(utf8.encode('new')));
      await ref().startDownloadToFile(target).result;
      expect(target.readAsStringSync(), 'new');
    });

    test('an empty object gives an empty file', () async {
      storageOn(FakeObjectServer(<int>[]));
      final DownloadTask task = ref().startDownloadToFile(target);
      await task.result;
      expect(target.lengthSync(), 0);
      expect(task.totalBytes, 0);
    });

    test('the root of the bucket throws at once', () {
      expect(
        () => storage().ref().startDownloadToFile(target),
        throwsStorageCode('invalid-root-operation'),
      );
    });
  });

  group('progress', () {
    test('reports the size, then bytes at most every 64 KiB and 100 ms, then '
        'success', () async {
      final FakeObjectServer objects =
          FakeObjectServer(data, chunkSize: 32 * _kib)
            ..time = time
            ..perChunk = const Duration(milliseconds: 60);
      storageOn(objects);
      final DownloadTask task = ref().startDownloadToFile(target);
      final List<DownloadProgress> events = await task.progress.toList();

      expect(
        events.first,
        const DownloadProgress(
          state: DownloadState.running,
          bytesTransferred: 0,
          totalBytes: 0,
        ),
      );
      expect(
        events[1],
        DownloadProgress(
          state: DownloadState.running,
          bytesTransferred: 0,
          totalBytes: data.length,
        ),
      );
      expect(
        events.last,
        DownloadProgress(
          state: DownloadState.success,
          bytesTransferred: data.length,
          totalBytes: data.length,
        ),
      );
      final List<int> running = <int>[
        for (final DownloadProgress p in events.skip(1))
          if (p.state == DownloadState.running) p.bytesTransferred,
      ];
      expect(running.length, greaterThan(2), reason: 'events while reading');
      for (int i = 1; i < running.length; i++) {
        expect(running[i] - running[i - 1], greaterThanOrEqualTo(64 * _kib));
      }
    });

    test('a late listener gets the current snapshot and no replay', () async {
      final DownloadTask task = ref().startDownloadToFile(target);
      await task.result;
      expect(await task.progress.toList(), <DownloadProgress>[
        DownloadProgress(
          state: DownloadState.success,
          bytesTransferred: data.length,
          totalBytes: data.length,
        ),
      ]);
    });
  });

  group('pause and resume', () {
    test('pause closes the connection and resume asks for the rest with '
        'Range', () async {
      server.holdAfter = 2;
      final DownloadTask task = ref().startDownloadToFile(target);
      await until(() => task.bytesTransferred == 128 * _kib);

      expect(task.pause(), isTrue);
      expect(task.pause(), isFalse);
      final DownloadProgress paused = await task.progress.firstWhere(
        (DownloadProgress p) => p.state == DownloadState.paused,
      );
      expect(paused.bytesTransferred, 128 * _kib);
      expect(client.aborted, isTrue, reason: 'the request was aborted');
      expect(task.state, DownloadState.paused);
      server.release.complete();
      await pumpEventQueue();
      expect(
        server.mediaRequests,
        hasLength(1),
        reason: 'nothing while paused',
      );

      expect(task.resume(), isTrue);
      expect(task.resume(), isFalse);
      await task.result;
      expect(server.mediaRequests, hasLength(2));
      expect(rangeOf(server.mediaRequests[1]), 'bytes=${128 * _kib}-');
      expect(await target.readAsBytes(), data);
      expect(
        server.metadataRequests,
        hasLength(1),
        reason: 'the generation header confirmed each response',
      );
    });

    test('pause and resume while the metadata is read', () async {
      final DownloadTask task = ref().startDownloadToFile(target);
      final Future<DownloadProgress> paused = task.progress.firstWhere(
        (DownloadProgress p) => p.state == DownloadState.paused,
      );
      expect(task.pause(), isTrue);
      await paused;
      expect(server.mediaRequests, isEmpty, reason: 'paused before the body');
      expect(task.resume(), isTrue);
      await task.result;
      expect(await target.readAsBytes(), data);
    });

    test('resume before the pause took effect keeps going', () async {
      server.holdAfter = 1;
      final DownloadTask task = ref().startDownloadToFile(target);
      await until(() => task.bytesTransferred == 64 * _kib);
      expect(task.pause(), isTrue);
      expect(task.resume(), isTrue);
      server.release.complete();
      await task.result;
      expect(await target.readAsBytes(), data);
    });
  });

  group('resume after a failure', () {
    test('a body broken in the middle is asked for again from the written '
        'offset', () async {
      server.breakAfter.add(2);
      final DownloadTask task = ref().startDownloadToFile(target);
      await task.result;
      expect(await target.readAsBytes(), data);
      expect(server.mediaRequests, hasLength(2));
      expect(rangeOf(server.mediaRequests[1]), 'bytes=${128 * _kib}-');
      expect(time.delays, contains(const Duration(seconds: 1)));
    });

    test('the wait doubles while the body breaks with no bytes', () async {
      server.breakAfter.addAll(<int>[1, 0, 0, 0]);
      await ref().startDownloadToFile(target).result;
      expect(await target.readAsBytes(), data);
      expect(time.delays, const <Duration>[
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
      ]);
    });

    test('gives up with retry-limit-exceeded when the failures last the '
        'download time', () async {
      storageOn(
        FakeObjectServer(data)..breakAfter.addAll(List<int>.filled(20, 0)),
        retry: const StorageRetryPolicy(download: Duration(seconds: 5)),
      );
      target.writeAsStringSync('old');
      await expectLater(
        ref().startDownloadToFile(target).result,
        throwsStorageCode('retry-limit-exceeded'),
      );
      expect(target.readAsStringSync(), 'old');
      expect(namesInDir(), <String>['out.bin']);
    });

    test('time spent paused does not count against the retry time', () async {
      final FakeObjectServer objects = FakeObjectServer(data)
        // 1: breaks with no bytes; 2: held, then paused; 3: breaks again; 4: complete.
        ..breakAfter.addAll(<int>[0, 0, 0]);
      objects.onMedia = (int index) {
        if (index == 1) {
          objects.holdAfter = 0;
        }
      };
      storageOn(
        objects,
        retry: const StorageRetryPolicy(download: Duration(seconds: 5)),
      );
      final DownloadTask task = ref().startDownloadToFile(target);
      await until(() => objects.mediaRequests.length == 2);
      final Future<DownloadProgress> paused = task.progress.firstWhere(
        (DownloadProgress p) => p.state == DownloadState.paused,
      );
      expect(task.pause(), isTrue);
      await paused;
      time.now = time.now.add(const Duration(hours: 1));
      expect(task.resume(), isTrue);
      await task.result;
      expect(await target.readAsBytes(), data);
      expect(objects.mediaRequests, hasLength(4));
      expect(
        time.delays.last,
        const Duration(seconds: 1),
        reason: 'the wait started over',
      );
      objects.release.complete();
    });

    test('bytes reset the retry time', () async {
      // Five breaks of 1 s each with bytes in between: longer than the 3 s download time, but each one made
      // progress.
      final FakeObjectServer objects = FakeObjectServer(data)
        ..breakAfter.addAll(<int>[1, 1, 1, 1]);
      storageOn(
        objects,
        retry: const StorageRetryPolicy(download: Duration(seconds: 3)),
      );
      await ref().startDownloadToFile(target).result;
      expect(await target.readAsBytes(), data);
      expect(objects.mediaRequests, hasLength(5));
      expect(time.delays, List<Duration>.filled(4, const Duration(seconds: 1)));
    });

    test('a server that answers a range with 200 is read past the written '
        'bytes', () async {
      server
        ..ignoreRange = true
        ..breakAfter.add(2);
      await ref().startDownloadToFile(target).result;
      expect(await target.readAsBytes(), data);
      expect(rangeOf(server.mediaRequests[1]), 'bytes=${128 * _kib}-');
    });
  });

  group('generation guard', () {
    test('a new generation in the resumed response fails with '
        'object-changed, and the target never holds mixed bytes', () async {
      target.writeAsStringSync('old');
      final List<int> second = List<int>.generate(
        data.length,
        (int i) => 255 - i % 251,
      );
      server
        ..breakAfter.add(2)
        ..onMedia = (int index) {
          if (index == 1) {
            server
              ..generation = '8'
              ..bytes = second;
          }
        };
      await expectLater(
        ref().startDownloadToFile(target).result,
        throwsStorageCode('object-changed'),
      );
      expect(
        server.mediaRequests,
        hasLength(2),
        reason: 'the new bytes were offered',
      );
      expect(target.readAsStringSync(), 'old');
      expect(namesInDir(), <String>['out.bin']);
    });

    test('a new generation in the first response fails too', () async {
      server.onMedia = (int index) => server.generation = '8';
      await expectLater(
        ref().startDownloadToFile(target).result,
        throwsStorageCode('object-changed'),
      );
      expect(namesInDir(), isEmpty);
    });

    test('without the header, the metadata is read again before the resumed '
        'request', () async {
      server
        ..sendGeneration = false
        ..breakAfter.add(2)
        ..onMedia = (int index) {
          if (index == 0) {
            server.generation = '8';
          }
        };
      await expectLater(
        ref().startDownloadToFile(target).result,
        throwsStorageCode('object-changed'),
      );
      expect(server.metadataRequests, hasLength(2));
      expect(server.mediaRequests, hasLength(1), reason: 'failed before it');
      expect(namesInDir(), isEmpty);
    });

    test('without the header, an unchanged object is confirmed before the '
        'resume and before the rename', () async {
      server
        ..sendGeneration = false
        ..breakAfter.add(2);
      await ref().startDownloadToFile(target).result;
      expect(await target.readAsBytes(), data);
      expect(server.metadataRequests, hasLength(3));
    });

    test('without the header, an object overwritten during a single response '
        'fails before the rename', () async {
      target.writeAsStringSync('old');
      server
        ..sendGeneration = false
        ..onMedia = (int index) => server.generation = '8';
      await expectLater(
        ref().startDownloadToFile(target).result,
        throwsStorageCode('object-changed'),
      );
      expect(target.readAsStringSync(), 'old');
      expect(namesInDir(), <String>['out.bin']);
    });
  });

  group('end of the content', () {
    test('a body that breaks after its last byte gets a 416 on resume and '
        'completes', () async {
      // 300 KiB in chunks of 64 KiB: 5 chunks, then the break.
      server.breakAfter.add(5);
      final DownloadTask task = ref().startDownloadToFile(target);
      await task.result;
      expect(await target.readAsBytes(), data);
      expect(rangeOf(server.mediaRequests[1]), 'bytes=${data.length}-');
    });

    test('a 416 before the size of the metadata is object-changed', () async {
      target.writeAsStringSync('old');
      server
        ..breakAfter.add(2)
        ..onMedia = (int index) {
          if (index == 1) {
            // Shorter than the 128 KiB already written, same generation: only the 416 shows it.
            server.bytes = data.sublist(0, 64 * _kib);
          }
        };
      await expectLater(
        ref().startDownloadToFile(target).result,
        throwsStorageCode('object-changed'),
      );
      expect(target.readAsStringSync(), 'old');
      expect(namesInDir(), <String>['out.bin']);
    });

    test('a body shorter than the size of the metadata fails before the '
        'rename', () async {
      target.writeAsStringSync('old');
      server.metadataSize = data.length + 10;
      await expectLater(
        ref().startDownloadToFile(target).result,
        throwsStorageCode('unknown'),
      );
      expect(target.readAsStringSync(), 'old');
      expect(namesInDir(), <String>['out.bin']);
    });

    test('a 206 that does not start at the offset asked for is not '
        'appended', () async {
      target.writeAsStringSync('old');
      server
        ..breakAfter.add(2)
        ..contentRangeShift = 1;
      await expectLater(
        ref().startDownloadToFile(target).result,
        throwsStorageCode('unknown'),
      );
      expect(target.readAsStringSync(), 'old');
      expect(namesInDir(), <String>['out.bin']);
    });
  });

  group('encoding', () {
    test('every media request asks for identity encoding', () async {
      server.breakAfter.add(2);
      await ref().startDownloadToFile(target).result;
      expect(server.mediaRequests, hasLength(2));
      for (final http.BaseRequest request in server.mediaRequests) {
        expect(request.headers['Accept-Encoding'], 'identity');
      }
    });

    test('a gzip-stored object is written unzipped, and a resume asks for it '
        'whole and skips what it has', () async {
      // Compressible: the stored size is far below the unzipped one.
      final List<int> text = utf8.encode('hello storage ' * 30000);
      final FakeObjectServer objects = FakeObjectServer(text)
        ..gzipped = true
        ..breakAfter.add(2);
      storageOn(objects);
      final DownloadTask task = ref().startDownloadToFile(target);
      await task.result;
      expect(await target.readAsBytes(), text);
      expect(task.bytesTransferred, text.length);
      expect(objects.mediaRequests, hasLength(2));
      expect(rangeOf(objects.mediaRequests[1]), isNull);
      expect(objects.mediaRequests[1].headers['Accept-Encoding'], 'identity');
    });
  });

  group('cancel and errors', () {
    test('a cancel while the file is being finished keeps the target', () async {
      target.writeAsStringSync('old');
      late final DownloadTask task;
      bool? canceled;
      server
        ..sendGeneration = false
        ..onMetadataServed = () {
          // The second metadata read is the check before the rename; the cancel lands right after it.
          if (server.metadataRequests.length == 2) {
            Timer.run(() => canceled = task.cancel());
          }
        };
      task = ref().startDownloadToFile(target);
      await expectLater(task.result, throwsStorageCode('canceled'));
      expect(canceled, isTrue);
      expect(task.state, DownloadState.canceled);
      expect(target.readAsStringSync(), 'old');
      expect(namesInDir(), <String>['out.bin']);
    });

    test('cancel while running deletes the partial file', () async {
      target.writeAsStringSync('old');
      server.holdAfter = 1;
      final DownloadTask task = ref().startDownloadToFile(target);
      await until(() => task.bytesTransferred == 64 * _kib);
      expect(task.cancel(), isTrue);
      expect(task.cancel(), isFalse);
      await expectLater(task.result, throwsStorageCode('canceled'));
      expect(task.state, DownloadState.canceled);
      expect(target.readAsStringSync(), 'old');
      expect(namesInDir(), <String>['out.bin']);
      server.release.complete();
    });

    test('cancel while paused deletes the partial file', () async {
      server.holdAfter = 1;
      final DownloadTask task = ref().startDownloadToFile(target);
      await until(() => task.bytesTransferred == 64 * _kib);
      expect(task.pause(), isTrue);
      await task.progress.firstWhere(
        (DownloadProgress p) => p.state == DownloadState.paused,
      );
      expect(task.cancel(), isTrue);
      final List<DownloadProgress> events = await task.progress.toList();
      expect(events.single.state, DownloadState.canceled);
      await expectLater(task.result, throwsStorageCode('canceled'));
      expect(namesInDir(), isEmpty);
      server.release.complete();
    });

    test('a missing object fails with object-not-found and creates no '
        'file', () async {
      server.missing = true;
      await expectLater(
        ref().startDownloadToFile(target).result,
        throwsStorageCode('object-not-found'),
      );
      expect(namesInDir(), isEmpty);
      expect(server.mediaRequests, isEmpty);
    });

    test('a refused media request keeps the target and leaves no partial '
        'file', () async {
      target.writeAsStringSync('old');
      server.mediaStatus = 403;
      await expectLater(
        ref().startDownloadToFile(target).result,
        throwsStorageCode('unauthorized'),
      );
      expect(target.readAsStringSync(), 'old');
      expect(namesInDir(), <String>['out.bin']);
    });

    test('a missing directory fails with a FileSystemException', () async {
      await expectLater(
        ref().startDownloadToFile(File('${dir.path}/missing/out.bin')).result,
        throwsA(isA<FileSystemException>()),
      );
      expect(namesInDir(), isEmpty);
    });
  });

  group('writeToFile', () {
    test('returns the size of the object', () async {
      expect(await ref().writeToFile(target), data.length);
      expect(await target.readAsBytes(), data);
    });

    test('resumes after a broken body', () async {
      server.breakAfter.add(1);
      expect(await ref().writeToFile(target), data.length);
      expect(await target.readAsBytes(), data);
      expect(rangeOf(server.mediaRequests[1]), 'bytes=${64 * _kib}-');
    });

    test('the root of the bucket fails the future', () async {
      await expectLater(
        storage().ref().writeToFile(target),
        throwsStorageCode('invalid-root-operation'),
      );
    });
  });
}

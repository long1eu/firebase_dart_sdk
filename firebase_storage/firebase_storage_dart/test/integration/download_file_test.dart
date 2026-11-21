/// Downloads and the file helpers against the Storage emulator. Run with FIREBASE_STORAGE_EMULATOR_HOST set,
/// after `tool/start_storage_emulator.sh <port>`.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:firebase_storage_dart/io.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

final String? _host = FirebaseStorage.emulatorHostFromEnvironment;

void main() {
  late FirebaseApp app;
  late FirebaseStorage storage;
  late Reference folder;

  setUp(() {
    app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'key',
        appId: '1:123:dart:abc',
        projectId: 'demo-test',
        storageBucket: 'demo-test.appspot.com',
      ),
      name: 'download-it-${DateTime.now().microsecondsSinceEpoch}',
    );
    storage = FirebaseStorage(app, emulatorHost: _host);
    folder = storage.ref(
      'download-it/${DateTime.now().microsecondsSinceEpoch}',
    );
  });
  tearDown(() async {
    storage.close();
    await app.delete();
  });

  Future<String> readText(Stream<List<int>> stream) async =>
      utf8.decode(await stream.expand((List<int> c) => c).toList());

  group(
    'openRead',
    skip: _host == null ? 'FIREBASE_STORAGE_EMULATOR_HOST is not set' : false,
    () {
      late Reference ref;
      setUp(() async {
        ref = folder.child('hello.txt');
        await ref.putString('hello world');
      });

      test('reads the whole object', () async {
        expect(await readText(ref.openRead()), 'hello world');
      });

      test('reads ranges', () async {
        expect(await readText(ref.openRead(0, 5)), 'hello');
        expect(await readText(ref.openRead(6)), 'world');
        expect(await readText(ref.openRead(null, 3)), 'hel');
        expect(await readText(ref.openRead(4, 7)), 'o w');
      });

      test(
        'a range past the end is empty (the emulator answers 200)',
        () async {
          expect(await readText(ref.openRead(99, 100)), isEmpty);
          expect(await readText(ref.openRead(11)), isEmpty);
        },
      );

      test('a missing object fails with object-not-found', () async {
        await expectLater(
          folder.child('missing').openRead().toList(),
          throwsA(
            isA<FirebaseStorageException>().having(
              (FirebaseStorageException e) => e.code,
              'code',
              'object-not-found',
            ),
          ),
        );
      });

      // How many bytes arrive before the cancel depends on the runner: a fast one can deliver the whole
      // object as the first chunk. So the test checks what does not depend on timing: leaving the loop
      // after the first chunk returns promptly, that chunk is a prefix of the object, and the next read
      // works. That the cancel closes the HTTP response is pinned by the unit tests (download_test.dart).
      test('canceling after the first chunk stops the download', () async {
        final Uint8List data = Uint8List.fromList(
          List<int>.generate(2 * 1024 * 1024, (int i) => i % 251),
        );
        final Reference big = folder.child('big.bin');
        await big.putBytes(data);
        final List<int> first = <int>[];
        await () async {
          await for (final List<int> chunk in big.openRead()) {
            first.addAll(chunk);
            break;
          }
        }().timeout(const Duration(seconds: 10));
        expect(first, isNotEmpty);
        expect(first.length, lessThanOrEqualTo(data.length));
        expect(first, data.sublist(0, first.length));
        expect(await big.getBytes(), data);
      });
    },
  );

  group(
    'files',
    skip: _host == null ? 'FIREBASE_STORAGE_EMULATOR_HOST is not set' : false,
    () {
      late Directory dir;
      setUp(() async {
        dir = await Directory.systemTemp.createTemp('storage_download_it');
      });
      tearDown(() => dir.delete(recursive: true));

      test('5 MB round trip through putFile and writeToFile', () async {
        final math.Random random = math.Random(42);
        final Uint8List data = Uint8List.fromList(
          List<int>.generate(5 * 1024 * 1024 + 123, (_) => random.nextInt(256)),
        );
        final File source = File('${dir.path}/source.bin')
          ..writeAsBytesSync(data);
        final Reference ref = folder.child('round-trip.bin');

        final FullMetadata uploaded = await ref
            .putFile(
              source,
              metadata: const SettableMetadata(
                contentType: 'application/x-test',
              ),
            )
            .result;
        expect(uploaded.size, data.length);
        expect(uploaded.contentType, 'application/x-test');

        final File target = File('${dir.path}/target.bin');
        expect(await ref.writeToFile(target), data.length);
        expect(target.readAsBytesSync(), data);
        expect(
          dir
              .listSync()
              .map((FileSystemEntity e) => e.uri.pathSegments.last)
              .toSet(),
          <String>{'source.bin', 'target.bin'},
        );
      });

      test('an 8 MiB download task paused and resumed', () async {
        final math.Random random = math.Random(7);
        final Uint8List data = Uint8List.fromList(
          List<int>.generate(8 * 1024 * 1024, (_) => random.nextInt(256)),
        );
        final _SlowClient client = _SlowClient();
        final FirebaseStorage slow = FirebaseStorage(
          app,
          emulatorHost: _host,
          httpClient: client,
        );
        addTearDown(slow.close);
        final Reference ref = slow.ref(folder.child('paused.bin').fullPath);
        await ref.putBytes(data);

        final File target = File('${dir.path}/paused.bin');
        final DownloadTask task = ref.startDownloadToFile(target);
        final DownloadProgress running = await task.progress.firstWhere(
          (DownloadProgress p) =>
              p.state == DownloadState.running && p.bytesTransferred > 0,
        );
        expect(
          task.pause(),
          isTrue,
          reason: 'paused at ${running.bytesTransferred}',
        );
        final DownloadProgress paused = await task.progress.firstWhere(
          (DownloadProgress p) => p.state == DownloadState.paused,
        );
        expect(paused.bytesTransferred, greaterThan(0));
        expect(paused.bytesTransferred, lessThan(data.length));
        expect(paused.totalBytes, data.length);

        expect(task.resume(), isTrue);
        final FullMetadata metadata = await task.result;
        expect(metadata.size, data.length);
        expect(target.readAsBytesSync(), data);
        expect(client.ranges.first, isNull);
        expect(client.ranges.last, 'bytes=${paused.bytesTransferred}-');
        expect(
          dir.listSync().map((FileSystemEntity e) => e.uri.pathSegments.last),
          <String>['paused.bin'],
        );
      });

      test('an object overwritten while the task is paused fails it with '
          'object-changed', () async {
        final Uint8List data = Uint8List(4 * 1024 * 1024);
        final FirebaseStorage slow = FirebaseStorage(
          app,
          emulatorHost: _host,
          httpClient: _SlowClient(),
        );
        addTearDown(slow.close);
        final Reference ref = slow.ref(folder.child('changed.bin').fullPath);
        await ref.putBytes(data);

        final File target = File('${dir.path}/changed.bin')
          ..writeAsStringSync('old');
        final DownloadTask task = ref.startDownloadToFile(target);
        await task.progress.firstWhere(
          (DownloadProgress p) =>
              p.state == DownloadState.running && p.bytesTransferred > 0,
        );
        expect(task.pause(), isTrue);
        await task.progress.firstWhere(
          (DownloadProgress p) => p.state == DownloadState.paused,
        );
        await ref.putBytes(Uint8List(4 * 1024 * 1024)..fillRange(0, 10, 1));

        expect(task.resume(), isTrue);
        await expectLater(
          task.result,
          throwsA(
            isA<FirebaseStorageException>().having(
              (FirebaseStorageException e) => e.code,
              'code',
              'object-changed',
            ),
          ),
        );
        expect(target.readAsStringSync(), 'old');
        expect(
          dir.listSync().map((FileSystemEntity e) => e.uri.pathSegments.last),
          <String>['changed.bin'],
        );
      });

      test('writeToFile of a missing object leaves no file behind', () async {
        final File target = File('${dir.path}/target.bin');
        await expectLater(
          folder.child('missing').writeToFile(target),
          throwsA(isA<FirebaseStorageException>()),
        );
        expect(dir.listSync(), isEmpty);
      });
    },
  );
}

/// A client that slows the media bodies down (a few milliseconds per chunk), so that a download of a few MiB
/// from a local emulator lasts long enough to be paused, and records the `Range` header of each media
/// request (null when there is none).
final class _SlowClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  final List<String?> ranges = <String?>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bool media = request.url.queryParameters['alt'] == 'media';
    if (media) {
      ranges.add(request.headers['Range']);
    }
    final http.StreamedResponse response = await _inner.send(request);
    if (!media) {
      return response;
    }
    return http.StreamedResponse(
      _slices(response.stream),
      response.statusCode,
      contentLength: response.contentLength,
      headers: response.headers,
      request: response.request,
    );
  }

  // The emulator can send a large object in a few big chunks, too fast for a progress event or a pause: cut
  // the body into 64 KiB slices, 5 ms apart.
  static Stream<List<int>> _slices(Stream<List<int>> body) async* {
    await for (final List<int> chunk in body) {
      for (int i = 0; i < chunk.length; i += 65536) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        yield chunk.sublist(i, math.min(i + 65536, chunk.length));
      }
    }
  }

  @override
  void close() => _inner.close();
}

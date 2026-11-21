@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:firebase_storage_dart/io.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fakes.dart';
import 'streaming_client.dart';

void main() {
  late FirebaseApp app;
  late Directory dir;

  setUp(() async {
    app = newApp();
    dir = await Directory.systemTemp.createTemp('storage_io_test');
  });
  tearDown(() async {
    await app.delete();
    await dir.delete(recursive: true);
  });

  Reference refOn(StreamingClient client) {
    final FakeTime time = FakeTime();
    return FirebaseStorage(
      app,
      httpClient: client,
      clock: time.clock,
      random: () => 0.5,
      delay: time.delay,
    ).ref('a/b.bin');
  }

  /// Answers the metadata request of an object of [size] bytes (writeToFile reads it first) and the media
  /// requests with [media].
  StreamingClient objectClient(
    int size,
    Future<http.StreamedResponse> Function(http.BaseRequest request) media,
  ) => StreamingClient((http.BaseRequest request) {
    if (request.url.queryParameters['alt'] == 'media') {
      return media(request);
    }
    return StreamingClient.response(<String>[
      jsonEncode(<String, Object?>{
        'bucket': 'b',
        'name': 'a/b.bin',
        'generation': '1',
        'size': '$size',
      }),
    ], 200);
  });

  /// [objectClient] whose media requests get a 200 made of [chunks].
  StreamingClient chunksClient(List<String> chunks) => objectClient(
    utf8.encode(chunks.join()).length,
    (_) => StreamingClient.response(chunks, 200),
  );

  List<String> namesIn(Directory directory) => directory
      .listSync()
      .map((FileSystemEntity e) => e.uri.pathSegments.last)
      .toList();

  group('writeToFile', () {
    test('writes the object and returns its size', () async {
      final File file = File('${dir.path}/out.txt');
      final int size = await refOn(
        chunksClient(<String>['hello ', 'world']),
      ).writeToFile(file);
      expect(size, 11);
      expect(await file.readAsString(), 'hello world');
      expect(namesIn(dir), <String>['out.txt']);
    });

    test('writes to an unpredictable .part sibling, then renames it', () async {
      final File file = File('${dir.path}/out.txt');
      final StreamController<List<int>> body = StreamController<List<int>>();
      final Completer<void> served = Completer<void>();
      final StreamingClient client = objectClient(3, (_) async {
        served.complete();
        return http.StreamedResponse(body.stream, 200);
      });
      final Future<int> done = refOn(client).writeToFile(file);
      await served.future;
      body.add(<int>[1, 2, 3]);
      await pumpEventQueue();
      expect(namesIn(dir), <Matcher>[
        matches(RegExp(r'^out\.txt\.[0-9a-f]{16}\.part$')),
      ]);
      await body.close();
      expect(await done, 3);
      expect(namesIn(dir), <String>['out.txt']);
    });

    test('replaces a file already there', () async {
      final File file = File('${dir.path}/out.txt')
        ..writeAsStringSync('a much longer old content');
      await refOn(chunksClient(<String>['new'])).writeToFile(file);
      expect(await file.readAsString(), 'new');
      expect(namesIn(dir), <String>['out.txt']);
    });

    test('an empty object gives an empty file', () async {
      final File file = File('${dir.path}/out.txt');
      expect(await refOn(chunksClient(<String>[])).writeToFile(file), 0);
      expect(file.lengthSync(), 0);
    });

    test('a failure mid-download deletes the partial file and keeps the '
        'old one', () async {
      final File file = File('${dir.path}/out.txt')..writeAsStringSync('old');
      // Every attempt breaks after the same bytes, so the retries make no progress and run out of time.
      final StreamingClient client = objectClient(
        100,
        (_) => StreamingClient.failing(<String>[
          'partial',
        ], http.ClientException('reset')),
      );
      await expectLater(
        refOn(client).writeToFile(file),
        throwsA(isA<FirebaseStorageException>()),
      );
      expect(await file.readAsString(), 'old');
      expect(namesIn(dir), <String>['out.txt']);
    });

    test('a missing object leaves no file', () async {
      final File file = File('${dir.path}/out.txt');
      await expectLater(
        refOn(
          StreamingClient.chunks(<String>['Not Found'], status: 404),
        ).writeToFile(file),
        throwsStorageCode('object-not-found'),
      );
      expect(namesIn(dir), isEmpty);
    });

    test('a missing directory fails with a FileSystemException', () async {
      final File file = File('${dir.path}/missing/out.txt');
      await expectLater(
        refOn(chunksClient(<String>['x'])).writeToFile(file),
        throwsA(isA<FileSystemException>()),
      );
      expect(namesIn(dir), isEmpty);
    });
  });

  group('putFile', () {
    test('a missing file throws a FileSystemException at once', () {
      expect(
        () => refOn(
          StreamingClient.chunks(<String>[]),
        ).putFile(File('${dir.path}/missing.bin')),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}

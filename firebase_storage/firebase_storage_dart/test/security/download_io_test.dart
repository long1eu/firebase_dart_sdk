// Threat model: storage_threat_model.md, "Downloads to files and streams" (T15, T16).
//
// Written against the contract (Reference.openRead, ReferenceIo.writeToFile) before the download code landed;
// writeToFile reads the metadata first since it became a resumable DownloadTask.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:firebase_storage_dart/io.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'security_support.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('storage_security_');
  });

  tearDown(() => dir.delete(recursive: true));

  List<String> entries() =>
      dir
          .listSync()
          .map(
            (FileSystemEntity e) =>
                e.uri.pathSegments.where((String s) => s.isNotEmpty).last,
          )
          .toList()
        ..sort();

  /// Answers the media requests with [media] and the metadata request (writeToFile reads it first) with the
  /// resource of object `x`.
  FirebaseStorage storageAnswering(SecurityHandler media) {
    final FirebaseStorage storage = securityStorage(
      securityApp(),
      RecordingClient(
        (SentRequest r) => r.url.queryParameters['alt'] == 'media'
            ? media(r)
            : respondJson(objectResource('x')),
      ),
      retry: const StorageRetryPolicy(download: Duration.zero),
    );
    addTearDown(storage.close);
    return storage;
  }

  group('writeToFile', () {
    test('an error response leaves no file behind', () async {
      final FirebaseStorage storage = storageAnswering(
        (SentRequest r) => respond(404, body: 'Not Found'),
      );
      await expectLater(
        storage.ref('x').writeToFile(File('${dir.path}/out.bin')),
        throwsStorageCode('object-not-found'),
      );
      expect(entries(), isEmpty);
    });

    test(
      'a body cut half way keeps the old file and leaves no temp file',
      () async {
        final File target = File('${dir.path}/out.bin')
          ..writeAsStringSync('old');
        final FirebaseStorage storage = storageAnswering((SentRequest r) {
          final StreamController<List<int>> body =
              StreamController<List<int>>();
          body
            ..add(List<int>.filled(1000, 7))
            ..addError(http.ClientException('reset', r.url))
            ..close();
          return http.StreamedResponse(body.stream, 200, contentLength: 5000);
        });
        await expectLater(
          storage.ref('x').writeToFile(target),
          throwsA(isA<FirebaseStorageException>()),
        );
        expect(target.readAsStringSync(), 'old');
        expect(entries(), <String>['out.bin']);
      },
    );

    test('a symlink at the target is replaced, not written through', () async {
      final File victim = File('${dir.path}/victim.txt')
        ..writeAsStringSync('keep me');
      final Link link = Link('${dir.path}/out.bin')..createSync(victim.path);
      final FirebaseStorage storage = storageAnswering(
        (SentRequest r) => respond(200, body: 'downloaded'),
      );
      await storage.ref('x').writeToFile(File(link.path));
      expect(victim.readAsStringSync(), 'keep me');
      expect(FileSystemEntity.isLinkSync(link.path), isFalse);
      expect(File(link.path).readAsStringSync(), 'downloaded');
    });

    test(
      'a pre-placed symlink in the directory is never written through',
      () async {
        // An attacker who can write to the directory plants links under every name it can guess.
        final File victim = File('${dir.path}/victim.txt')
          ..writeAsStringSync('keep me');
        for (final String guess in <String>[
          'out.bin.tmp',
          'out.bin.part',
          '.out.bin.tmp',
          'out.bin.download',
          'out.bin~',
        ]) {
          Link('${dir.path}/$guess').createSync(victim.path);
        }
        final FirebaseStorage storage = storageAnswering(
          (SentRequest r) => respond(200, body: 'downloaded'),
        );
        await storage.ref('x').writeToFile(File('${dir.path}/out.bin'));
        expect(victim.readAsStringSync(), 'keep me');
        expect(File('${dir.path}/out.bin').readAsStringSync(), 'downloaded');
      },
    );

    test(
      'the file is not readable by others while it is written (POSIX)',
      () async {
        final FirebaseStorage storage = storageAnswering(
          (SentRequest r) => respond(200, body: 'secret-key'),
        );
        final File target = File('${dir.path}/out.bin');
        await storage.ref('x').writeToFile(target);
        final int mode = target.statSync().mode;
        expect(
          mode & 0x2,
          0,
          reason: 'world-writable: ${mode.toRadixString(8)}',
        );
      },
      testOn: 'posix',
    );
  });

  group('openRead', () {
    test('rejects negative and inverted ranges before any request', () async {
      final RecordingClient client = RecordingClient(
        (SentRequest r) => respond(200, body: 'x'),
      );
      final FirebaseStorage storage = securityStorage(securityApp(), client);
      addTearDown(storage.close);
      for (final (int?, int?) range in <(int?, int?)>[
        (-1, null),
        (5, 2),
        (0, -1),
      ]) {
        await expectLater(
          storage.ref('x').openRead(range.$1, range.$2).drain<void>(),
          throwsA(
            anyOf(
              isA<FirebaseStorageException>(),
              isA<ArgumentError>(),
              isA<RangeError>(),
            ),
          ),
          reason: '$range',
        );
      }
      expect(client.sent, isEmpty);
    });

    test('pulls the body only as fast as the listener reads it', () async {
      final LazyBody body = LazyBody(chunkSize: 64 * 1024, chunkCount: 1024);
      final FirebaseStorage storage = storageAnswering(
        (SentRequest r) => http.StreamedResponse(body.stream(), 200),
      );
      final Completer<void> first = Completer<void>();
      late StreamSubscription<List<int>> subscription;
      subscription = storage.ref('x').openRead().listen((List<int> chunk) {
        subscription.pause();
        if (!first.isCompleted) {
          first.complete();
        }
      });
      await first.future;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        body.pulled,
        lessThan(8),
        reason: 'buffered ${body.pulled} chunks of 64 KiB while paused',
      );
      await subscription.cancel();
    });
  });
}

// The tasks through the official firebase_storage API, against a fake
// backend: uploads (putData, putString, putFile) and writeToFile, as futures
// and as streams of snapshots, with pause, resume and cancel.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// The metadata JSON of the last upload.
Map<String, Object?> startMetadata() => backend.uploadMetadata!;

void main() {
  registerForTests();

  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('storage_shim_test');
  });
  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  Future<Reference> refAt(String path) async =>
      FirebaseStorage.instanceFor(app: await newApp()).ref(path);

  group('uploads', () {
    test(
      'putData completes with a success snapshot and its metadata',
      () async {
        final Reference ref = await refAt('up/a.png');
        final UploadTask task = ref.putData(Uint8List.fromList(<int>[1, 2, 3]));
        final List<TaskState> states = <TaskState>[];
        task.snapshotEvents.listen((TaskSnapshot s) => states.add(s.state));

        final TaskSnapshot done = await task;
        expect(done.state, TaskState.success);
        expect(done.bytesTransferred, 3);
        expect(done.totalBytes, 3);
        expect(done.metadata!.fullPath, 'up/a.png');
        expect(done.metadata!.size, 3);
        expect(done.ref.fullPath, 'up/a.png');
        expect(task.snapshot.state, TaskState.success);
        expect(states.last, TaskState.success);
        expect(backend.objects['$bucket/up/a.png']!.bytes, <int>[1, 2, 3]);
        // firebase_storage infers the content type of putData from the name.
        expect(startMetadata()['contentType'], 'image/png');
      },
    );

    test('a resumable putData reports the progress of each chunk', () async {
      final Reference ref = await refAt('up/large');
      final UploadTask task = ref.putData(Uint8List(600 * 1024));
      final List<TaskSnapshot> snapshots = <TaskSnapshot>[];
      task.snapshotEvents.listen(snapshots.add);
      await task;
      final List<int> transferred = snapshots
          .map((TaskSnapshot s) => s.bytesTransferred)
          .toList();
      expect(transferred.first, 0);
      expect(transferred.last, 600 * 1024);
      expect(transferred.toSet().length, greaterThan(2), reason: 'chunks');
      expect(transferred, orderedEquals(List<int>.of(transferred)..sort()));
      expect(
        snapshots.every((TaskSnapshot s) => s.totalBytes == 600 * 1024),
        isTrue,
      );
      expect(snapshots.last.state, TaskState.success);
      expect(backend.objects['$bucket/up/large']!.bytes.length, 600 * 1024);
    });

    test('putString raw uploads the UTF-8 bytes', () async {
      final Reference ref = await refAt('up/s.txt');
      await ref.putString(
        'héllo',
        metadata: SettableMetadata(customMetadata: <String, String>{'k': 'v'}),
      );
      expect(utf8.decode(backend.objects['$bucket/up/s.txt']!.bytes), 'héllo');
      expect(startMetadata()['metadata'], <String, Object?>{'k': 'v'});
    });

    test('putString with a data URL takes its content type', () async {
      final Reference ref = await refAt('up/d');
      await ref.putString(
        'data:image/gif;base64,R0lG',
        format: PutStringFormat.dataUrl,
      );
      expect(backend.objects['$bucket/up/d']!.bytes, <int>[71, 73, 70]);
      expect(startMetadata()['contentType'], 'image/gif');
    });

    test(
      'putString with a bad base64 string fails with invalid-format',
      () async {
        final Reference ref = await refAt('up/bad');
        final UploadTask task = ref.putString(
          '***',
          format: PutStringFormat.base64,
        );
        final Future<void> streamError = expectLater(
          task.snapshotEvents,
          emitsError(isStorageCode('invalid-format')),
        );
        await expectLater(task, throwsStorageCode('invalid-format'));
        await streamError;
        expect(task.snapshot.state, TaskState.error);
        expect(backend.requests, isEmpty);
      },
    );

    test('putFile streams the file and infers the content type', () async {
      final File file = File('${temp.path}/photo.jpeg')
        ..writeAsBytesSync(<int>[9, 8, 7]);
      final Reference ref = await refAt('up/photo');
      final TaskSnapshot done = await ref.putFile(file);
      expect(done.state, TaskState.success);
      expect(backend.objects['$bucket/up/photo']!.bytes, <int>[9, 8, 7]);
      expect(startMetadata()['contentType'], 'image/jpeg');
    });

    test('putFile keeps a content type of the metadata', () async {
      final File file = File('${temp.path}/photo.jpeg')
        ..writeAsBytesSync(<int>[1]);
      final Reference ref = await refAt('up/photo');
      await ref.putFile(file, SettableMetadata(contentType: 'x/y'));
      expect(startMetadata()['contentType'], 'x/y');
    });

    test('a failed upload fails the future and the stream', () async {
      final Reference ref = await refAt('up/denied');
      backend.failWith = 403;
      final UploadTask task = ref.putData(Uint8List(1));
      final Future<void> streamError = expectLater(
        task.snapshotEvents,
        emitsThrough(emitsError(isStorageCode('unauthorized'))),
      );
      await expectLater(task, throwsStorageCode('unauthorized'));
      await streamError;
      expect(task.snapshot.state, TaskState.error);
    });

    test('pause, resume and cancel', () async {
      final Reference ref = await refAt('up/big');
      final Completer<void> gate = backend.chunkGate = Completer<void>();
      final UploadTask task = ref.putData(Uint8List(300 * 1024));
      final List<TaskState> states = <TaskState>[];
      task.snapshotEvents.listen(
        (TaskSnapshot s) => states.add(s.state),
        onError: (Object _) {},
      );
      await pumpEventQueue();

      expect(await task.pause(), isTrue);
      expect(task.snapshot.state, TaskState.paused);
      expect(await task.pause(), isFalse);
      expect(await task.resume(), isTrue);
      expect(task.snapshot.state, TaskState.running);
      expect(await task.cancel(), isTrue);
      gate.complete();

      await expectLater(task, throwsStorageCode('canceled'));
      expect(task.snapshot.state, TaskState.canceled);
      expect(states, containsAllInOrder(<TaskState>[TaskState.paused]));
      expect(await task.cancel(), isFalse);
      expect(backend.objects, isEmpty);
    });

    test('a paused upload can be canceled', () async {
      final Reference ref = await refAt('up/big');
      final Completer<void> gate = backend.chunkGate = Completer<void>();
      final UploadTask task = ref.putData(Uint8List(300 * 1024));
      await pumpEventQueue();
      expect(await task.pause(), isTrue);
      expect(await task.cancel(), isTrue);
      gate.complete();
      await expectLater(task, throwsStorageCode('canceled'));
      expect(task.snapshot.state, TaskState.canceled);
    });

    test('a failure nobody awaits is not an unhandled error', () async {
      final Reference ref = await refAt('up/denied');
      backend.failWith = 403;
      final UploadTask task = ref.putData(Uint8List(1));
      await pumpEventQueue(times: 50);
      expect(task.snapshot.state, TaskState.error);
    });
  });

  group('writeToFile', () {
    test('writes the object and reports its progress', () async {
      final Reference ref = await refAt('down/a.bin');
      final List<int> bytes = List<int>.generate(1000, (int i) => i % 256);
      backend.put(bucket, 'down/a.bin', bytes);
      final File target = File('${temp.path}/a.bin');

      final DownloadTask task = ref.writeToFile(target);
      final List<TaskSnapshot> snapshots = <TaskSnapshot>[];
      task.snapshotEvents.listen(snapshots.add);
      final TaskSnapshot done = await task;

      expect(done.state, TaskState.success);
      expect(done.bytesTransferred, 1000);
      expect(done.totalBytes, 1000);
      expect(done.metadata!.size, 1000);
      expect(target.readAsBytesSync(), bytes);
      expect(snapshots.last.state, TaskState.success);
      expect(snapshots.first.totalBytes, 1000);
      expect(temp.listSync(), hasLength(1), reason: 'no temporary file left');
    });

    test('replaces an existing file', () async {
      final Reference ref = await refAt('down/a');
      backend.put(bucket, 'down/a', <int>[1]);
      final File target = File('${temp.path}/a')..writeAsBytesSync(<int>[5, 5]);
      await ref.writeToFile(target);
      expect(target.readAsBytesSync(), <int>[1]);
    });

    test('a missing object fails with object-not-found and leaves the target '
        'alone', () async {
      final Reference ref = await refAt('down/missing');
      final File target = File('${temp.path}/keep')..writeAsStringSync('old');
      final DownloadTask task = ref.writeToFile(target);
      final Future<void> streamError = expectLater(
        task.snapshotEvents,
        emitsError(isStorageCode('object-not-found')),
      );
      await expectLater(task, throwsStorageCode('object-not-found'));
      await streamError;
      expect(task.snapshot.state, TaskState.error);
      expect(target.readAsStringSync(), 'old');
      expect(temp.listSync(), hasLength(1));
    });

    test('a failure while reading removes the temporary file', () async {
      final Reference ref = await refAt('down/a');
      backend.put(bucket, 'down/a', <int>[1, 2, 3]);
      backend.failMediaWith = 403;
      final File target = File('${temp.path}/a');
      await expectLater(
        ref.writeToFile(target),
        throwsStorageCode('unauthorized'),
      );
      expect(temp.listSync(), isEmpty);
    });

    test('pause, resume and cancel', () async {
      final Reference ref = await refAt('down/a');
      backend.put(bucket, 'down/a', <int>[1, 2, 3]);
      final File target = File('${temp.path}/a');

      final DownloadTask task = ref.writeToFile(target);
      expect(await task.resume(), isFalse);
      expect(await task.pause(), isTrue);
      expect(task.snapshot.state, TaskState.paused);
      await pumpEventQueue(times: 50);
      expect(target.existsSync(), isFalse, reason: 'held while paused');
      expect(await task.resume(), isTrue);
      expect((await task).state, TaskState.success);
      expect(target.readAsBytesSync(), <int>[1, 2, 3]);

      final DownloadTask canceled = ref.writeToFile(File('${temp.path}/b'));
      expect(await canceled.pause(), isTrue);
      expect(await canceled.cancel(), isTrue);
      await expectLater(canceled, throwsStorageCode('canceled'));
      expect(canceled.snapshot.state, TaskState.canceled);
      expect(await canceled.cancel(), isFalse);
      await pumpEventQueue(times: 50);
      expect(
        temp.listSync().map((FileSystemEntity e) => e.uri.pathSegments.last),
        <String>['a'],
        reason: 'the canceled download left no file',
      );
    });
  });
}

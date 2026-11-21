@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:test/test.dart';

import '../fakes.dart';
import '../upload_fakes.dart';

// Resumable uploads against the Storage emulator: tool/start_storage_emulator.sh <port>, then
// FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:<port> dart test test/integration.
void main() {
  final String? host = FirebaseStorage.emulatorHostFromEnvironment;
  if (host == null) {
    test(
      'resumable uploads against the emulator',
      () {},
      skip: 'FIREBASE_STORAGE_EMULATOR_HOST is not set',
    );
    return;
  }

  late FirebaseApp app;
  late FirebaseStorage storage;
  late String prefix;

  setUp(() {
    app = newApp(storageBucket: 'demo-test.appspot.com');
    storage = FirebaseStorage(app, emulatorHost: host);
    prefix = 'upload-task/${DateTime.now().microsecondsSinceEpoch}';
  });

  tearDown(() async {
    storage.close();
    await app.delete();
  });

  test('a multi-chunk upload stores every byte and its metadata', () async {
    final Uint8List data = patternBytes(3 * 1024 * 1024 + 17);
    final Reference ref = storage.ref('$prefix/big.bin');
    final UploadTask task = ref.startUpload(
      data,
      metadata: const SettableMetadata(
        contentType: 'application/x-test',
        customMetadata: <String, String>{'k': 'v'},
      ),
    );
    final Future<List<UploadProgress>> events = task.progress.toList();

    final FullMetadata metadata = await task.result;

    expect(metadata.size, data.length);
    expect(metadata.contentType, 'application/x-test');
    expect(metadata.customMetadata, <String, String>{'k': 'v'});
    expect(task.sessionUri?.queryParameters['upload_id'], isNotEmpty);
    // On the VM progress is also reported while a chunk is sent (at most every 64 KiB and 100 ms),
    // so a slow runner sees events between the chunk boundaries. What is fixed: the count never goes
    // down, every confirmed chunk boundary is reported, and the last event is the whole object.
    final List<int> transferred = (await events)
        .map((UploadProgress p) => p.bytesTransferred)
        .toList();
    for (int i = 1; i < transferred.length; i++) {
      expect(transferred[i], greaterThanOrEqualTo(transferred[i - 1]));
    }
    expect(
      transferred,
      containsAllInOrder(<int>[
        0,
        256 * 1024,
        768 * 1024,
        1792 * 1024,
        data.length,
      ]),
    );
    expect(transferred.last, data.length);
    expect(await ref.getBytes(), data);
  });

  test('a stream upload stores every byte', () async {
    final Uint8List data = patternBytes(700 * 1024);
    final Reference ref = storage.ref('$prefix/stream.bin');
    Stream<List<int>> pieces() async* {
      for (int i = 0; i < data.length; i += 10000) {
        yield data.sublist(
          i,
          i + 10000 > data.length ? data.length : i + 10000,
        );
      }
    }

    await ref.startStreamUpload(pieces(), length: data.length).result;
    expect(await ref.getBytes(), data);
  });

  test('pause and resume', () async {
    final Uint8List data = patternBytes(2 * 1024 * 1024);
    final Reference ref = storage.ref('$prefix/paused.bin');
    final UploadTask task = ref.startUpload(data);

    await task.progress.firstWhere(
      (UploadProgress p) => p.bytesTransferred > 0,
    );
    expect(task.pause(), isTrue);
    final UploadProgress paused = await task.progress.firstWhere(
      (UploadProgress p) => p.state == UploadState.paused,
    );
    expect(paused.bytesTransferred, lessThan(data.length));
    expect(task.resume(), isTrue);

    expect((await task.result).size, data.length);
    expect(await ref.getBytes(), data);
  });

  test('a new task resumes the session of a paused one', () async {
    final Uint8List data = patternBytes(2 * 1024 * 1024);
    final Reference ref = storage.ref('$prefix/resumed.bin');
    final UploadTask first = ref.startUpload(data);
    await first.progress.firstWhere(
      (UploadProgress p) => p.bytesTransferred > 0,
    );
    first.pause();
    await first.progress.firstWhere(
      (UploadProgress p) => p.state == UploadState.paused,
    );
    final Uri session = first.sessionUri!;

    final UploadTask second = ref.startUpload(
      data,
      existingSessionUri: session,
    );
    expect((await second.result).size, data.length);
    expect(await ref.getBytes(), data);
  });

  test('cancel leaves no object', () async {
    final Reference ref = storage.ref('$prefix/canceled.bin');
    final UploadTask task = ref.startUpload(patternBytes(2 * 1024 * 1024));
    await task.progress.firstWhere(
      (UploadProgress p) => p.bytesTransferred > 0,
    );

    expect(task.cancel(), isTrue);
    await expectLater(task.result, throwsStorageCode('canceled'));
    expect(task.state, UploadState.canceled);
    await expectLater(ref.metadata(), throwsStorageCode('object-not-found'));
  });
}

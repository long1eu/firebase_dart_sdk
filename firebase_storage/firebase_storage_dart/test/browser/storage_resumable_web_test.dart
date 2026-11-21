@TestOn('browser')
@Tags(<String>['browser'])
library;

import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:test/test.dart';

import '../fakes.dart';
import '../upload_fakes.dart';
import 'emulator_port.dart';

/// Resumable uploads in the browser: the session and chunks go over fetch, and the task aborts
/// a chunk in flight with an AbortController. The browser gives no upload progress, so the
/// events come once per confirmed chunk.
void main() {
  late FirebaseApp app;
  late FirebaseStorage storage;
  late String prefix;

  setUpAll(loadEmulatorPort);

  setUp(() {
    app = newApp(storageBucket: 'demo-test.appspot.com');
    storage = FirebaseStorage(
      app,
      emulatorHost: emulatorHost,
      mockUserToken: 'owner',
    );
    prefix = 'browser-test/upload/${DateTime.now().microsecondsSinceEpoch}';
  });

  tearDown(() async {
    storage.close();
    await app.delete();
  });

  const int kib = 1024;

  test('a multi-chunk upload reports progress per chunk only', () async {
    final Uint8List data = patternBytes(3 * 1024 * kib + 17);
    final Reference ref = storage.ref('$prefix/big.bin');
    final UploadTask task = ref.startUpload(
      data,
      metadata: const SettableMetadata(contentType: 'application/x-test'),
    );
    final Future<List<UploadProgress>> events = task.progress.toList();

    final FullMetadata metadata = await task.result;

    expect(metadata.size, data.length);
    expect(metadata.contentType, 'application/x-test');
    expect(task.sessionUri, isNotNull);
    final List<UploadProgress> seen = await events;
    // 256 KiB, then the chunks double: nothing in between, as fetch reports no upload progress.
    expect(seen.map((UploadProgress p) => p.bytesTransferred).toSet(), <int>{
      0,
      256 * kib,
      768 * kib,
      1792 * kib,
      data.length,
    });
    expect(seen.last.state, UploadState.success);
    expect(await ref.getBytes(), data);
  });

  test('pause then resume completes the upload', () async {
    final Uint8List data = patternBytes(8 * 1024 * kib);
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

  test('cancel fails the result and leaves no object', () async {
    final Reference ref = storage.ref('$prefix/canceled.bin');
    final UploadTask task = ref.startUpload(patternBytes(8 * 1024 * kib));
    await task.progress.firstWhere(
      (UploadProgress p) => p.bytesTransferred > 0,
    );

    expect(task.cancel(), isTrue);
    await expectLater(task.result, throwsStorageCode('canceled'));
    expect(task.state, UploadState.canceled);
    await expectLater(ref.metadata(), throwsStorageCode('object-not-found'));
  });

  test('a second task resumes the session of a paused one', () async {
    final Uint8List data = patternBytes(8 * 1024 * kib);
    final Reference ref = storage.ref('$prefix/resumed.bin');
    final UploadTask first = ref.startUpload(data);
    await first.progress.firstWhere(
      (UploadProgress p) => p.bytesTransferred > 0,
    );
    expect(first.pause(), isTrue);
    final UploadProgress paused = await first.progress.firstWhere(
      (UploadProgress p) => p.state == UploadState.paused,
    );
    final Uri session = first.sessionUri!;

    final UploadTask second = ref.startUpload(
      data,
      existingSessionUri: session,
    );
    expect((await second.result).size, data.length);
    expect(second.sessionUri, session);
    expect(paused.bytesTransferred, greaterThan(0));
    expect(await ref.getBytes(), data);
  });

  group('rules', () {
    test('signed out, an upload to the auth bucket is unauthorized', () async {
      final FirebaseApp authApp = newApp(
        storageBucket: 'demo-test-auth.appspot.com',
      );
      addTearDown(authApp.delete);
      authApp.authProvider = FakeAuth(<String?>[null]);
      final FirebaseStorage signedOut = FirebaseStorage(
        authApp,
        emulatorHost: emulatorHost,
      );
      addTearDown(signedOut.close);

      await expectLater(
        signedOut
            .ref('shared/x-$prefix'.replaceAll('/', '-'))
            .putBytes(Uint8List.fromList(<int>[1, 2, 3])),
        throwsA(
          isA<FirebaseStorageException>()
              .having(
                (FirebaseStorageException e) => e.code,
                'code',
                'unauthorized',
              )
              .having(
                (FirebaseStorageException e) => e.httpStatus,
                'httpStatus',
                403,
              ),
        ),
      );
    });
  });
}

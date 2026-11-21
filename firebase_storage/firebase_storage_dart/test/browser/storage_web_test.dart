@TestOn('browser')
@Tags(<String>['browser'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:test/test.dart';

import 'emulator_port.dart';

/// The client over fetch (package:http picks BrowserClient) against the private emulator.
void main() {
  late FirebaseApp app;
  late FirebaseStorage storage;
  late Reference dir;
  int counter = 0;

  setUpAll(loadEmulatorPort);

  setUp(() {
    app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'key',
        appId: '1:123:dart:browser',
        projectId: 'demo-test',
        storageBucket: 'demo-test.appspot.com',
      ),
      name: 'storage-web-${counter++}',
    );
    storage = FirebaseStorage(
      app,
      emulatorHost: emulatorHost,
      mockUserToken: 'owner',
    );
    dir = storage.ref(
      'browser-test/${DateTime.now().microsecondsSinceEpoch}-$counter',
    );
  });

  tearDown(() {
    storage.close();
    app.delete();
  });

  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  test('putBytes then getBytes round-trips the content', () async {
    final Reference ref = dir.child('hello.bin');
    final Uint8List data = Uint8List.fromList(
      List<int>.generate(1000, (int i) => i % 256),
    );
    final FullMetadata metadata = await ref.putBytes(
      data,
      metadata: const SettableMetadata(contentType: 'application/x-test'),
    );
    expect(metadata.size, 1000);
    expect(metadata.contentType, 'application/x-test');
    expect(await ref.getBytes(), data);
  });

  test('metadata reads and updates custom metadata', () async {
    final Reference ref = dir.child('meta.txt');
    await ref.putBytes(
      bytes('x'),
      metadata: const SettableMetadata(
        contentType: 'text/plain',
        customMetadata: <String, String>{'a': '1'},
      ),
    );
    final FullMetadata read = await ref.metadata();
    expect(read.fullPath, ref.fullPath);
    expect(read.customMetadata, <String, String>{'a': '1'});

    final FullMetadata updated = await ref.updateMetadata(
      const SettableMetadata(cacheControl: 'no-cache'),
    );
    expect(updated.cacheControl, 'no-cache');
    expect(updated.customMetadata, <String, String>{'a': '1'});
  });

  test('list returns items and prefixes', () async {
    await dir.child('a.txt').putBytes(bytes('a'));
    await dir.child('b.txt').putBytes(bytes('b'));
    await dir.child('sub/c.txt').putBytes(bytes('c'));
    final ListResult result = await dir.list();
    expect(result.items.map((Reference r) => r.name), <String>[
      'a.txt',
      'b.txt',
    ]);
    expect(result.prefixes.map((Reference r) => r.name), <String>['sub']);
    expect((await dir.listAll()).items, hasLength(2));
  });

  test(
    'delete removes the object; getting it again is object-not-found',
    () async {
      final Reference ref = dir.child('gone.txt');
      await ref.putBytes(bytes('x'));
      await ref.delete();
      await expectLater(
        ref.getBytes(),
        throwsA(
          isA<FirebaseStorageException>().having(
            (FirebaseStorageException e) => e.code,
            'code',
            'object-not-found',
          ),
        ),
      );
    },
  );

  test('a download URL of the emulator can be fetched', () async {
    final Reference ref = dir.child('url.txt');
    await ref.putBytes(bytes('via url'));
    final String url = await ref.downloadUrl();
    expect(url, startsWith('http://$emulatorHost/'));
  });
}

/// Reads of an object stored gzip-compressed (`contentEncoding: gzip`) against the Storage emulator. Run with
/// FIREBASE_STORAGE_EMULATOR_HOST set, after `tool/start_storage_emulator.sh <port>`.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:test/test.dart';

final String? _host = FirebaseStorage.emulatorHostFromEnvironment;

void main() {
  late FirebaseApp app;
  late FirebaseStorage storage;
  late Reference ref;
  final Uint8List plain = Uint8List.fromList(
    utf8.encode(List<String>.generate(20000, (int i) => 'line $i\n').join()),
  );

  setUp(() async {
    app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'key',
        appId: '1:123:dart:abc',
        projectId: 'demo-test',
        storageBucket: 'demo-test.appspot.com',
      ),
      name: 'gzip-it-${DateTime.now().microsecondsSinceEpoch}',
    );
    storage = FirebaseStorage(app, emulatorHost: _host);
    ref = storage.ref('gzip-it/${DateTime.now().microsecondsSinceEpoch}.txt');
    await ref.putBytes(
      Uint8List.fromList(gzip.encode(plain)),
      metadata: const SettableMetadata(
        contentType: 'text/plain',
        contentEncoding: 'gzip',
      ),
    );
  });
  tearDown(() async {
    storage.close();
    await app.delete();
  });

  Future<List<int>> read(Stream<List<int>> s) =>
      s.expand((List<int> c) => c).toList();

  group(
    'an object stored gzip-compressed',
    skip: _host == null ? 'FIREBASE_STORAGE_EMULATOR_HOST is not set' : false,
    () {
      test('getBytes returns the unzipped bytes', () async {
        expect(await ref.getBytes(), plain);
      });

      test(
        'openRead from an offset reads the unzipped bytes from there',
        () async {
          expect(await read(ref.openRead(1000)), plain.sublist(1000));
          expect(
            await read(ref.openRead(1000, 2000)),
            plain.sublist(1000, 2000),
          );
        },
      );

      test('getBytes with maxSize counts unzipped bytes', () async {
        expect(await ref.getBytes(maxSize: plain.length), plain);
        await expectLater(
          ref.getBytes(maxSize: plain.length - 1),
          throwsA(
            isA<FirebaseStorageException>().having(
              (FirebaseStorageException e) => e.code,
              'code',
              'download-size-exceeded',
            ),
          ),
        );
      });
    },
  );
}

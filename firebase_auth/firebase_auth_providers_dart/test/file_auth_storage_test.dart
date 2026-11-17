// FileAuthStorage: an owner-only JSON file, written atomically; and WebAuthStorage is refused on the VM.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('file_auth_storage_'));
  tearDown(() => root.deleteSync(recursive: true));

  final bool posix = Platform.isLinux || Platform.isMacOS;
  int permissions(String path) => FileStat.statSync(path).mode & 0x1ff;

  test('stores, reads and removes values', () async {
    final FileAuthStorage storage = FileAuthStorage(
      '${root.path}/session.json',
    );
    expect(await storage.read('a'), isNull);
    await storage.write('a', 'one');
    await storage.write('b', 'two');
    expect(await storage.read('a'), 'one');
    expect(await FileAuthStorage(storage.path).read('b'), 'two');
    expect(jsonDecode(File(storage.path).readAsStringSync()), <String, Object?>{
      'a': 'one',
      'b': 'two',
    });
    await storage.write('a', null);
    expect(await storage.read('a'), isNull);
    expect(await storage.read('b'), 'two');
    // The last value gone: the file too.
    await storage.write('b', null);
    expect(File(storage.path).existsSync(), isFalse);
    await storage.write('b', null);
  });

  test(
    'the file is readable by its owner only, and a new directory too',
    () async {
      final String path = '${root.path}/new/dir/session.json';
      final FileAuthStorage storage = FileAuthStorage(path);
      await storage.write('k', 'secret');
      expect(permissions(path), 0x180); // 0600
      expect(permissions('${root.path}/new/dir'), 0x1c0); // 0700
    },
    skip: posix ? null : 'POSIX modes (Linux and macOS)',
  );

  test(
    'a world-readable file is replaced by an owner-only one',
    () async {
      final String path = '${root.path}/session.json';
      File(path).writeAsStringSync('{}');
      Process.runSync('chmod', <String>['644', path]);
      expect(permissions(path), 0x1a4);
      await FileAuthStorage(path).write('k', 'secret');
      expect(permissions(path), 0x180);
    },
    skip: posix ? null : 'POSIX modes (Linux and macOS)',
  );

  test('no temporary file is left, and writes keep their order', () async {
    final FileAuthStorage storage = FileAuthStorage('${root.path}/s.json');
    await Future.wait(<Future<void>>[
      for (int i = 0; i < 20; i++) storage.write('k', '$i'),
      storage.write('other', 'x'),
    ]);
    expect(await storage.read('k'), '19');
    expect(await storage.read('other'), 'x');
    expect(
      root.listSync().map((FileSystemEntity e) => e.uri.pathSegments.last),
      <String>['s.json'],
    );
  });

  test('a file that is not JSON counts as empty and is replaced', () async {
    final String path = '${root.path}/s.json';
    File(path).writeAsStringSync('not json');
    final FileAuthStorage storage = FileAuthStorage(path);
    expect(await storage.read('k'), isNull);
    await storage.write('k', 'v');
    expect(await storage.read('k'), 'v');
  });

  test(
    'a FirebaseUserAuth restores the session a previous one stored',
    () async {
      final FakeBackend backend = FakeBackend();
      final String path = '${root.path}/session.json';
      final FirebaseUserAuth first = backend.create(
        storage: FileAuthStorage(path),
      );
      final UserCredential user = await first.signInAnonymously();
      await first.dispose();
      expect(File(path).readAsStringSync(), contains('refresh:anon-user'));

      final FirebaseUserAuth second = backend.create(
        storage: FileAuthStorage(path),
      );
      await second.restore();
      expect(second.uid, user.uid);
      await second.signOut();
      expect(File(path).existsSync(), isFalse);
      await second.dispose();
    },
  );

  test('WebAuthStorage needs a browser', () {
    expect(WebAuthStorage.session, throwsUnsupportedError);
    expect(WebAuthStorage.local, throwsUnsupportedError);
  });
}

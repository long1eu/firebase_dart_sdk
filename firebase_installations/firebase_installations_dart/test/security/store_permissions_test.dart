// Spec v4 5.2.1 "Directory and permissions" for the file store: chmod 700 at first use, the mode check,
// and failures thrown as storage-error by FirebaseInstallations (a configuration failure, 5.3).
@TestOn('posix')
library;

import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/io.dart';
import 'package:test/test.dart';

import '../support/fis_sec_io.dart';
import '../support/fis_sec_support.dart';

int _mode(String path) => FileStat.statSync(path).mode & 0x1ff;

void _chmod(String mode, String path) {
  final ProcessResult result = Process.runSync('chmod', <String>[mode, path]);
  if (result.exitCode != 0) {
    throw StateError('chmod $mode failed: ${result.stderr}');
  }
}

/// A runner that records its calls and answers [exitCode] without touching the file system.
final class _FakeRunner {
  _FakeRunner(this.exitCode);

  final int exitCode;
  final List<List<String>> calls = <List<String>>[];

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    calls.add(<String>[executable, ...arguments]);
    return ProcessResult(
      0,
      exitCode,
      '',
      exitCode == 0 ? '' : 'chmod: Operation not permitted',
    );
  }
}

void main() {
  FileKeyValueStore storeIn(String path, {_FakeRunner? runner}) {
    final FileKeyValueStore store = FileKeyValueStore(
      path,
      runCommand: runner?.call,
    );
    addTearDown(store.close);
    return store;
  }

  group('5.2.1 chmod 700 at first use', () {
    test(
      '5.2.1: a missing directory is created and ends with mode 0700',
      () async {
        final String path = '${fisSecTempDir().path}/a/b/store';
        final FileKeyValueStore store = storeIn(path);
        await store.write('k', 'v');
        expect(_mode(path), 0x1c0);
      },
    );

    for (final String mode in <String>['755', '777', '750', '701', '711']) {
      test(
        '5.2.1: an existing directory with mode 0$mode ends with mode 0700',
        () async {
          final Directory dir = fisSecTempDir();
          _chmod(mode, dir.path);
          final FileKeyValueStore store = storeIn(dir.path);
          expect(await store.read('k'), isNull);
          expect(_mode(dir.path), 0x1c0);
        },
      );
    }

    test(
      '5.2.1: chmod runs once, on the canonical path of a symbolic link',
      () async {
        final Directory target = fisSecTempDir();
        _chmod('755', target.path);
        final Link link = Link('${fisSecTempDir().path}/link')
          ..createSync(target.path);
        final List<List<String>> calls = <List<String>>[];
        final FileKeyValueStore store = FileKeyValueStore(
          link.path,
          runCommand: (String executable, List<String> arguments) {
            calls.add(<String>[executable, ...arguments]);
            return Process.run(executable, arguments);
          },
        );
        addTearDown(store.close);
        await store.write('a', '1');
        await store.write('b', '2');
        expect(await store.read('a'), '1');
        expect(calls, <List<String>>[
          <String>['chmod', '700', target.resolveSymbolicLinksSync()],
        ]);
        expect(_mode(target.path), 0x1c0);
      },
    );

    test(
      '5.2.1: writes leave the directory at 0700 and no temporary file behind',
      () async {
        final Directory dir = fisSecTempDir();
        final FileKeyValueStore store = storeIn(dir.path);
        final FirebaseApp app = fisSecApp();
        final FirebaseInstallations installations = fisSecInstallations(
          app,
          store: store,
          client: FisSecClient(fisSecHappyHandler()),
        );
        await installations.getToken();
        await installations.getToken(forceRefresh: true);
        expect(_mode(dir.path), 0x1c0);
        expect(fisSecStoreFile(dir, fisSecRecordKey(app)).existsSync(), isTrue);
        final List<String> names = dir
            .listSync()
            .map((FileSystemEntity e) => e.uri.pathSegments.last)
            .toList();
        expect(names.where((String n) => n.endsWith('.tmp')), isEmpty);
      },
    );
  });

  group('5.2.1 the mode check', () {
    for (final String mode in <String>[
      '755',
      '750',
      '705',
      '701',
      '710',
      '770',
      '707',
    ]) {
      test(
        '5.2.1: a 0$mode directory that chmod did not change is a storage-error',
        () async {
          final Directory dir = fisSecTempDir();
          _chmod(mode, dir.path);
          final _FakeRunner runner = _FakeRunner(0);
          final FileKeyValueStore store = storeIn(dir.path, runner: runner);
          await expectLater(
            store.read('k'),
            throwsA(
              isFisCode('storage-error').having(
                (FirebaseInstallationsException e) => e.message,
                'message',
                contains('private to the user'),
              ),
            ),
          );
          expect(runner.calls, hasLength(1));
        },
      );
    }

    test(
      '5.2.1: a 0700 directory passes the check even when chmod did nothing',
      () async {
        final Directory dir = fisSecTempDir();
        _chmod('700', dir.path);
        final FileKeyValueStore store = storeIn(
          dir.path,
          runner: _FakeRunner(0),
        );
        await store.write('k', 'v');
        expect(await store.read('k'), 'v');
      },
    );

    test(
      '5.2.1: a non-zero exit of chmod is a storage-error even on a 0700 directory',
      () async {
        final Directory dir = fisSecTempDir();
        _chmod('700', dir.path);
        final FileKeyValueStore store = storeIn(
          dir.path,
          runner: _FakeRunner(1),
        );
        await expectLater(
          store.write('k', 'v'),
          throwsFisCode('storage-error'),
        );
      },
    );

    test('5.2.1: a refused directory gets no record file', () async {
      final Directory dir = fisSecTempDir();
      _chmod('755', dir.path);
      final FileKeyValueStore store = storeIn(dir.path, runner: _FakeRunner(0));
      await expectLater(
        store.write('k', 'secret'),
        throwsFisCode('storage-error'),
      );
      expect(fisSecStoreFile(dir, 'k').existsSync(), isFalse);
    });
  });

  group('5.3 permission failures through FirebaseInstallations', () {
    test(
      '5.3: getId on a store whose directory is not private throws storage-error and sends nothing',
      () async {
        final Directory dir = fisSecTempDir();
        _chmod('777', dir.path);
        final FisSecClient client = FisSecClient(fisSecHappyHandler());
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: storeIn(dir.path, runner: _FakeRunner(0)),
          client: client,
        );
        await expectLater(
          installations.getId(),
          throwsFisCode('storage-error'),
        );
        await expectLater(
          installations.getToken(),
          throwsFisCode('storage-error'),
        );
        expect(client.requests, isEmpty);
      },
    );

    test(
      '5.3: a failing chmod is thrown from getToken, not kept in memory',
      () async {
        final Directory dir = fisSecTempDir();
        final FisSecClient client = FisSecClient(fisSecHappyHandler());
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: storeIn(dir.path, runner: _FakeRunner(1)),
          client: client,
        );
        await expectLater(
          installations.getToken(),
          throwsFisCode('storage-error'),
        );
        await expectLater(
          installations.getId(),
          throwsFisCode('storage-error'),
        );
        expect(client.requests, isEmpty);
      },
    );
  });
}

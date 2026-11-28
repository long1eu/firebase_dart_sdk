@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/io.dart';
import 'package:test/test.dart';

const int _mib16 = 16 * 1024 * 1024;

/// The file name 5.2.1 gives the value of [key]: lowercase hex SHA-256 of the UTF-8 key plus `.json`.
String _fileName(String key) => '${sha256.convert(utf8.encode(key))}.json';

Matcher _storageError([String? messagePart]) =>
    isA<FirebaseInstallationsException>()
        .having(
          (FirebaseInstallationsException e) => e.code,
          'code',
          'storage-error',
        )
        .having(
          (FirebaseInstallationsException e) => e.message,
          'message',
          messagePart == null ? anything : contains(messagePart),
        );

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fis_file_store_');
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
  });

  /// A store over [path] (default: the test directory), closed after the test.
  FileKeyValueStore open({
    String? path,
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    runCommand,
  }) {
    final FileKeyValueStore store = FileKeyValueStore(
      path ?? dir.path,
      runCommand: runCommand,
    );
    addTearDown(store.close);
    return store;
  }

  group('5.2.1 serialization', () {
    test(
      '5.2.1 updates issued together run in order, each seeing the one before',
      () async {
        final FileKeyValueStore store = open();
        final List<Future<String?>> updates = <Future<String?>>[
          for (int i = 0; i < 50; i++)
            store.update(
              'k',
              (String? current) => current == null ? '$i' : '$current,$i',
            ),
        ];
        final List<String?> results = await Future.wait(updates);
        for (int i = 0; i < 50; i++) {
          expect(results[i], List<int>.generate(i + 1, (int n) => n).join(','));
        }
        expect(await store.read('k'), results.last);
      },
    );

    test('5.2.1 reads and writes issued together run in call order', () async {
      final FileKeyValueStore store = open();
      final Future<void> first = store.write('k', 'a');
      final Future<String?> readA = store.read('k');
      final Future<void> second = store.write('k', 'b');
      final Future<String?> readB = store.read('k');
      final Future<void> removed = store.write('k', null);
      final Future<String?> readNone = store.read('k');
      await Future.wait(<Future<void>>[first, second, removed]);
      expect(await readA, 'a');
      expect(await readB, 'b');
      expect(await readNone, isNull);
    });

    test(
      '5.2 a throwing transform writes nothing and the error is rethrown',
      () async {
        final FileKeyValueStore store = open();
        await store.write('k', 'kept');
        await expectLater(
          store.update(
            'k',
            (String? current) => throw const FormatException('no'),
          ),
          throwsA(isA<FormatException>()),
        );
        expect(await store.read('k'), 'kept');
      },
    );

    test('5.2 calls after close fail', () async {
      final FileKeyValueStore store = open();
      await store.write('k', 'v');
      await store.close();
      await expectLater(store.read('k'), throwsStateError);
    });
  });

  group('5.2.1 files', () {
    test(
      '5.2.1 one file per key named by the SHA-256 of the key; no temporary left',
      () async {
        final FileKeyValueStore store = open();
        await store.write('installations/app', '{"v":1}');
        final File file = File(
          '${dir.path}${Platform.pathSeparator}${_fileName('installations/app')}',
        );
        expect(file.readAsStringSync(), '{"v":1}');
        final List<String> names = dir
            .listSync()
            .map((FileSystemEntity e) => e.uri.pathSegments.last)
            .where((String name) => name.endsWith('.tmp'))
            .toList();
        expect(names, isEmpty);

        await store.write('installations/app', null);
        expect(file.existsSync(), isFalse);
      },
    );

    test('5.2.1 a file of 16 MiB + 1 byte counts as absent', () async {
      File(
        '${dir.path}${Platform.pathSeparator}${_fileName('big')}',
      ).writeAsBytesSync(List<int>.filled(_mib16 + 1, 0x61));
      final FileKeyValueStore store = open();
      expect(await store.read('big'), isNull);
    });

    test('5.2.1 a file of exactly 16 MiB is read', () async {
      File(
        '${dir.path}${Platform.pathSeparator}${_fileName('edge')}',
      ).writeAsBytesSync(List<int>.filled(_mib16, 0x61));
      final FileKeyValueStore store = open();
      final String? value = await store.read('edge');
      expect(value?.length, _mib16);
    });

    test(
      '5.2.1 temporary files older than 1 h are deleted at first use',
      () async {
        final String sep = Platform.pathSeparator;
        final DateTime now = DateTime.now();
        File old(String name, Duration age) {
          final File file = File('${dir.path}$sep$name')
            ..writeAsStringSync('x');
          file.setLastModifiedSync(now.subtract(age));
          return file;
        }

        final File stale = old(
          '.${_fileName('a')}.${'0' * 32}.tmp',
          const Duration(hours: 2),
        );
        final File recent = old(
          '.${_fileName('b')}.${'1' * 32}.tmp',
          const Duration(minutes: 30),
        );
        final File notOurs = old('old.tmp', const Duration(hours: 2));

        final FileKeyValueStore store = open();
        await store.read('anything');

        expect(stale.existsSync(), isFalse);
        expect(recent.existsSync(), isTrue);
        expect(notOurs.existsSync(), isTrue);
      },
    );
  });

  group('5.2.1 owner', () {
    final String child = File('test/support/store_child.dart').absolute.path;

    Future<List<String>> runChild() async {
      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        <String>[child, dir.path],
      );
      expect(result.exitCode, 0, reason: 'child stderr: ${result.stderr}');
      return const LineSplitter().convert((result.stdout as String).trim());
    }

    test(
      '5.2.1 a second process gets storage-error while the first owns the directory',
      () async {
        final FileKeyValueStore store = open();
        await store.write('k', 'v');

        final List<String> held = await runChild();
        expect(held.first, 'storage-error');
        expect(held.last, contains('in use by another process'));

        await store.close();
        final List<String> released = await runChild();
        expect(released, <String>['ok']);
      },
      timeout: const Timeout.factor(3),
    );

    test(
      '5.2.1 a second store for the same directory in one isolate gets StateError',
      () async {
        final FileKeyValueStore first = open();
        await first.read('k');
        final FileKeyValueStore second = open();
        await expectLater(second.read('k'), throwsStateError);

        await first.close();
        await second.write('k', 'v');
        expect(await second.read('k'), 'v');
      },
    );

    test(
      '5.2.1 a second store through a symbolic link to the same directory gets StateError',
      () async {
        final FileKeyValueStore first = open();
        await first.read('k');
        final Directory parent = Directory.systemTemp.createTempSync(
          'fis_file_store_link_',
        );
        addTearDown(() => parent.deleteSync(recursive: true));
        final Link link = Link('${parent.path}${Platform.pathSeparator}store')
          ..createSync(dir.path);
        final FileKeyValueStore second = open(path: link.path);
        await expectLater(second.read('k'), throwsStateError);
      },
      testOn: '!windows',
    );
  });

  group('5.2.1 directory and permissions', () {
    test('5.2.1 a missing directory is created', () async {
      final String path =
          '${dir.path}${Platform.pathSeparator}a${Platform.pathSeparator}b';
      final FileKeyValueStore store = open(path: path);
      await store.write('k', 'v');
      expect(Directory(path).existsSync(), isTrue);
    });

    test('5.2.1 chmod 700 leaves the directory private', () async {
      await Process.run('chmod', <String>['755', dir.path]);
      final FileKeyValueStore store = open();
      await store.write('k', 'v');
      expect(dir.statSync().mode & 0x3f, 0);
    }, testOn: 'mac-os || linux');

    test(
      '5.2.1 a directory other users can access is refused',
      () async {
        await Process.run('chmod', <String>['755', dir.path]);
        final List<List<String>> calls = <List<String>>[];
        final FileKeyValueStore store = open(
          runCommand: (String executable, List<String> arguments) async {
            calls.add(<String>[executable, ...arguments]);
            return ProcessResult(0, 0, '', '');
          },
        );
        await expectLater(
          store.read('k'),
          throwsA(_storageError('must be private to the user')),
        );
        expect(calls.first.sublist(0, 2), <String>['chmod', '700']);
        await expectLater(store.write('k', 'v'), throwsA(_storageError()));
      },
      testOn: 'mac-os || linux',
    );

    test('5.2.1 a non-zero chmod exit is storage-error', () async {
      final FileKeyValueStore store = open(
        runCommand: (String executable, List<String> arguments) async =>
            ProcessResult(0, 1, '', 'Operation not permitted'),
      );
      await expectLater(
        store.read('k'),
        throwsA(_storageError('must be private to the user')),
      );
    }, testOn: 'mac-os || linux');

    test('5.2.1 a missing chmod is storage-error', () async {
      final FileKeyValueStore store = open(
        runCommand: (String executable, List<String> arguments) =>
            throw const ProcessException(
              'chmod',
              <String>[],
              'No such file or directory',
              2,
            ),
      );
      await expectLater(
        store.read('k'),
        throwsA(_storageError('must be private to the user')),
      );
    }, testOn: 'mac-os || linux');
  });

  test(
    '5.2.1 on Windows a read concurrent with the rename of a write sees a whole value',
    () async {
      final FileKeyValueStore store = open();
      const String key = 'installations/windows';
      final File file = File(
        '${dir.path}${Platform.pathSeparator}${_fileName(key)}',
      );
      String valueOf(int i) => 'value-$i-${'x' * 4096}';
      final Set<String> written = <String>{
        for (int i = 0; i < 200; i++) valueOf(i),
      };
      await store.write(key, valueOf(0));

      bool writing = true;
      int readerErrors = 0;
      final List<String> torn = <String>[];
      Future<void> rawReader() async {
        while (writing) {
          try {
            final String text = await file.readAsString();
            if (!written.contains(text)) {
              torn.add(text.length > 40 ? text.substring(0, 40) : text);
            }
          } on FileSystemException {
            readerErrors++;
          }
        }
      }

      final List<Future<void>> readers = <Future<void>>[
        rawReader(),
        rawReader(),
      ];
      final List<String?> storeReads = <String?>[];
      for (int i = 1; i < 200; i++) {
        await store.write(key, valueOf(i));
        storeReads.add(await store.read(key));
      }
      writing = false;
      await Future.wait(readers);

      expect(torn, isEmpty, reason: 'a raw read saw a partial value');
      for (int i = 0; i < storeReads.length; i++) {
        expect(storeReads[i], valueOf(i + 1));
      }
      expect(
        await store.read(key),
        valueOf(199),
        reason: 'raw reader errors: $readerErrors',
      );
    },
    testOn: 'windows',
    timeout: const Timeout.factor(4),
  );
}

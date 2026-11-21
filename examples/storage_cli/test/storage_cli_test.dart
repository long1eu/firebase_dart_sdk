// Runs storage_cli as a program against the Storage emulator
// (tool/start_storage_emulator.sh in the repository root):
//
//     FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9384 dart test
//
// Without FIREBASE_STORAGE_EMULATOR_HOST the tests are skipped. The rules test also
// needs FIREBASE_AUTH_EMULATOR_HOST (an Auth emulator).

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final String? emulator =
      Platform.environment['FIREBASE_STORAGE_EMULATOR_HOST'];
  final Object skip = emulator == null || emulator.isEmpty
      ? 'Set FIREBASE_STORAGE_EMULATOR_HOST to run these tests against the Storage '
            'emulator.'
      : false;
  final String? authEmulator =
      Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'];
  final Object skipAuth = skip != false
      ? skip
      : authEmulator == null || authEmulator.isEmpty
      ? 'Set FIREBASE_AUTH_EMULATOR_HOST to test the rules that need a user.'
      : false;

  late Directory temp;
  final String prefix = 'cli-test-${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() => temp = Directory.systemTemp.createTempSync('storage_cli_'));
  tearDownAll(() => temp.deleteSync(recursive: true));

  Future<ProcessResult> cli(
    List<String> arguments, {
    String bucket = 'demo-test.appspot.com',
  }) => Process.run(Platform.resolvedExecutable, <String>[
    'run',
    'bin/storage_cli.dart',
    '--project=demo-test',
    '--bucket=$bucket',
    ...arguments,
  ], stdoutEncoding: null);

  String text(ProcessResult r) => utf8.decode(r.stdout as List<int>).trim();
  String errorText(ProcessResult r) => utf8.decode(r.stderr as List<int>);

  test(
    'put, ls, stat, cat, get, url and rm',
    () async {
      final File source = File('${temp.path}/hello.txt')
        ..writeAsStringSync('hello storage\n');

      final ProcessResult put = await cli(<String>[
        'put',
        '--content-type=text/plain',
        '--meta=kind=smoke',
        source.path,
        '$prefix/hello.txt',
      ]);
      expect(put.exitCode, 0, reason: errorText(put));
      expect(text(put), '$prefix/hello.txt');
      expect(errorText(put), contains('uploaded 14 of 14 bytes (100%)'));

      final ProcessResult ls = await cli(<String>['ls', prefix]);
      expect(ls.exitCode, 0, reason: errorText(ls));
      expect(text(ls), '$prefix/hello.txt');
      final ProcessResult root = await cli(<String>['ls']);
      expect(text(root).split('\n'), contains('$prefix/'));

      final ProcessResult stat = await cli(<String>[
        'stat',
        '$prefix/hello.txt',
      ]);
      final Map<String, Object?> metadata =
          jsonDecode(text(stat)) as Map<String, Object?>;
      expect(metadata['size'], 14);
      expect(metadata['contentType'], 'text/plain');
      expect(metadata['customMetadata'], <String, Object?>{'kind': 'smoke'});

      final ProcessResult cat = await cli(<String>['cat', '$prefix/hello.txt']);
      expect(utf8.decode(cat.stdout as List<int>), 'hello storage\n');

      final File target = File('${temp.path}/copy.txt');
      final ProcessResult get = await cli(<String>[
        'get',
        '$prefix/hello.txt',
        target.path,
      ]);
      expect(get.exitCode, 0, reason: errorText(get));
      expect(target.readAsStringSync(), 'hello storage\n');

      final ProcessResult url = await cli(<String>['url', '$prefix/hello.txt']);
      expect(text(url), startsWith('http'));
      expect(text(url), contains('token='));

      final ProcessResult rm = await cli(<String>['rm', '$prefix/hello.txt']);
      expect(rm.exitCode, 0, reason: errorText(rm));
      final ProcessResult gone = await cli(<String>[
        'stat',
        '$prefix/hello.txt',
      ]);
      expect(gone.exitCode, 66);
      expect(errorText(gone), contains('object-not-found'));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'rules that need a user: refused without sign-in, allowed with it',
    () async {
      const String bucket = 'demo-test-auth.appspot.com';
      final File source = File('${temp.path}/note.txt')
        ..writeAsStringSync('note');
      final String email = '$prefix@example.com';

      final ProcessResult anonymous = await cli(<String>[
        'put',
        source.path,
        'shared/$prefix.txt',
      ], bucket: bucket);
      expect(anonymous.exitCode, isNot(0));
      expect(errorText(anonymous), contains('unauthenticated'));

      final List<String> signedIn = <String>[
        '--email=$email',
        '--password=correct-horse',
        '--create-account',
      ];
      final ProcessResult put = await cli(<String>[
        ...signedIn,
        'put',
        source.path,
        'shared/$prefix.txt',
      ], bucket: bucket);
      expect(put.exitCode, 0, reason: errorText(put));
      final ProcessResult rm = await cli(<String>[
        ...signedIn,
        'rm',
        'shared/$prefix.txt',
      ], bucket: bucket);
      expect(rm.exitCode, 0, reason: errorText(rm));
    },
    skip: skipAuth,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('a missing source file exits 66 before any request', () async {
    final ProcessResult r = await cli(<String>[
      'put',
      '${temp.path}/missing.txt',
      'x.txt',
    ]);
    expect(r.exitCode, 66);
  }, skip: skip);

  test('no arguments is a usage error', () async {
    final ProcessResult r = await cli(<String>['stat']);
    expect(r.exitCode, 64);
  }, skip: skip);
}

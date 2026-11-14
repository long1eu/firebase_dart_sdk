// Runs firestore_cli as a program against the Firestore emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test
//
// The tests that need the emulator are skipped without FIRESTORE_EMULATOR_HOST.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final String? emulator = Platform.environment['FIRESTORE_EMULATOR_HOST'];
  final Object skip = emulator == null || emulator.isEmpty
      ? 'Set FIRESTORE_EMULATOR_HOST to run these tests against the emulator.'
      : false;

  late Directory temp;
  late String cli;

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('firestore_cli_test_');
    cli = '${temp.path}/firestore_cli';
    final ProcessResult compiled = await Process.run(
      Platform.resolvedExecutable,
      <String>['compile', 'exe', 'bin/firestore_cli.dart', '-o', cli],
    );
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}${compiled.stderr}',
    );
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  Future<ProcessResult> run(
    List<String> arguments, {
    String? input,
    Map<String, String>? environment,
  }) async {
    final Process process = await Process.start(
      cli,
      arguments,
      environment: environment ?? Platform.environment,
      includeParentEnvironment: false,
    );
    if (input != null) {
      process.stdin.write(input);
    }
    await process.stdin.close();
    final Future<String> out = process.stdout.transform(utf8.decoder).join();
    final Future<String> err = process.stderr.transform(utf8.decoder).join();
    final int code = await process.exitCode.timeout(const Duration(minutes: 1));
    return ProcessResult(process.pid, code, await out, await err);
  }

  String collection(String name) =>
      'cli-test-${DateTime.now().microsecondsSinceEpoch}-$name';

  test('imports in batches and exports a filtered, ordered query', () async {
    final String people = collection('people');
    final String input = jsonEncode(<Map<String, Object?>>[
      for (int i = 0; i < 5; i++)
        <String, Object?>{
          'id': 'p$i',
          'age': 20 + i,
          'city': i.isEven ? 'Paris' : 'Rome',
        },
    ]);
    final ProcessResult imported = await run(<String>[
      'import',
      '-',
      '-c',
      people,
      '--batch-size',
      '2',
    ], input: input);
    expect(imported.exitCode, 0, reason: '${imported.stderr}');
    expect(LineSplitter.split(imported.stdout as String), <String>[
      'committed 2/5',
      'committed 4/5',
      'committed 5/5',
      'imported 5 documents into $people',
    ]);

    final ProcessResult exported = await run(<String>[
      'export',
      '-c',
      people,
      '-w',
      'city==Paris',
      '-w',
      'age>20',
      '--order-by',
      'age:desc',
      '--limit',
      '1',
    ]);
    expect(exported.exitCode, 0, reason: '${exported.stderr}');
    expect(jsonDecode(exported.stdout as String), <Object?>[
      <String, Object?>{'id': 'p4', 'age': 24, 'city': 'Paris'},
    ]);
  }, skip: skip);

  test('export and import round-trip timestamps, bytes, geo points, vectors '
      'and references', () async {
    final String source = collection('source');
    final Map<String, Object?> document = <String, Object?>{
      'id': 'all',
      'when': <String, Object?>{
        'type': 'firestore/timestamp/1.0',
        'seconds': 1700000000,
        // Whole microseconds: the emulator truncates the rest.
        'nanoseconds': 123456000,
      },
      'bytes': <String, Object?>{
        'type': 'firestore/bytes/1.0',
        'bytes': 'AQID',
      },
      'where': <String, Object?>{
        'type': 'firestore/geoPoint/1.0',
        'latitude': 48.85,
        'longitude': 2.35,
      },
      'embedding': <String, Object?>{
        'type': 'firestore/vectorValue/1.0',
        'vectorValues': <double>[0.5, 1.5],
      },
      'owner': <String, Object?>{
        'type': 'firestore/documentReference/1.0',
        'referencePath': 'users/ada',
      },
      'nested': <String, Object?>{
        'list': <Object?>[1, 'two', null, true],
      },
    };
    final ProcessResult imported = await run(<String>[
      'import',
      '-',
      '-c',
      source,
    ], input: jsonEncode(<Object?>[document]));
    expect(imported.exitCode, 0, reason: '${imported.stderr}');

    final String file = '${temp.path}/export.json';
    final ProcessResult exported = await run(<String>[
      'export',
      '-c',
      source,
      '-o',
      file,
    ]);
    expect(exported.exitCode, 0, reason: '${exported.stderr}');
    expect(exported.stdout, contains('exported 1 documents to $file'));
    expect(jsonDecode(File(file).readAsStringSync()), <Object?>[document]);

    // The exported file imports into another collection unchanged.
    final String copy = collection('copy');
    expect((await run(<String>['import', file, '-c', copy])).exitCode, 0);
    final ProcessResult again = await run(<String>['export', '-c', copy]);
    expect(jsonDecode(again.stdout as String), <Object?>[document]);
  }, skip: skip);

  test('watch prints the documents, then each change', () async {
    final String watched = collection('watched');
    await run(<String>[
      'import',
      '-',
      '-c',
      watched,
    ], input: '[{"id": "a", "n": 1}, {"id": "b", "n": 2}]');

    final Process watch = await Process.start(cli, <String>[
      'watch',
      '-c',
      watched,
      '--order-by',
      'n',
      '--exit-after',
      '4',
    ]);
    final Stream<String> lines = watch.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    final List<String> printed = <String>[];
    lines.listen(printed.add);
    // The first snapshot holds the two documents that are there already.
    await lines.take(2).toList().timeout(const Duration(seconds: 30));

    await run(<String>[
      'import',
      '-',
      '-c',
      watched,
    ], input: '[{"id": "a", "n": 3}, {"id": "c", "n": 0}]');
    expect(await watch.exitCode.timeout(const Duration(seconds: 30)), 0);
    expect(printed, <String>[
      'added a {"n":1}',
      'added b {"n":2}',
      // The batch arrives as one snapshot: c is new, a changed.
      ...<String>['added c {"n":0}', 'modified a {"n":3}'],
    ]);
  }, skip: skip);

  test(
    'reports usage and configuration errors with their exit codes',
    () async {
      final ProcessResult noCollection = await run(<String>['export']);
      expect(noCollection.exitCode, 64);
      expect(noCollection.stderr, contains('--collection (-c) is required.'));

      // The filter is read before anything is sent: no emulator is needed.
      final ProcessResult badFilter = await run(
        <String>['export', '-c', 'x', '-w', 'nonsense'],
        environment: <String, String>{
          ...Platform.environment,
          'FIRESTORE_EMULATOR_HOST': '127.0.0.1:9',
        },
      );
      expect(badFilter.exitCode, 64);

      final ProcessResult noBackend = await run(
        <String>['export', '-c', 'x'],
        environment: Map<String, String>.of(Platform.environment)
          ..remove('FIRESTORE_EMULATOR_HOST')
          ..remove('FIREBASE_PROJECT_ID'),
      );
      expect(noBackend.exitCode, 78);
      expect(noBackend.stderr, contains('Set FIRESTORE_EMULATOR_HOST'));
    },
  );
}

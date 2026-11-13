// Runs example/main.dart as its own process and checks what it prints.

@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'example/main.dart creates and looks up the apps',
    () async {
      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', 'example/main.dart'],
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, isEmpty);
      expect(
        (result.stdout as String).split('\n'),
        containsAllInOrder(<String>[
          'default app: [DEFAULT], project my-project',
          'named app: secondary',
          'lookup: true',
        ]),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

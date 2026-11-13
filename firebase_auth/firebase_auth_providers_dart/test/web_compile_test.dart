// The main library is web-compatible: it compiles with dart2js and with dart2wasm (neither accepts dart:io).

@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory out;

  setUp(() => out = Directory.systemTemp.createTempSync('auth_providers_web_'));
  tearDown(() => out.deleteSync(recursive: true));

  for (final String target in <String>['js', 'wasm']) {
    test('compiles to $target', () {
      final ProcessResult result = Process.runSync(
          Platform.resolvedExecutable, <String>[
        'compile',
        target,
        '-o',
        '${out.path}/out.$target',
        'test/web/web_main.dart'
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(File('${out.path}/out.$target').existsSync(), isTrue);
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}

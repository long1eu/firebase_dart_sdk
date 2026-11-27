// Runs the "Shutting down" snippet of docs/guides/database.md (support/shutdown_snippet/main.dart)
// in a subprocess, sends it SIGTERM once it is connected, and checks that it exits 0 with no
// unhandled error: the onConnected listener has no onError, so it must survive close().
@TestOn('vm && !windows')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'the shutdown snippet exits 0 on SIGTERM with no unhandled error',
    () async {
      final Process process = await Process.start(
        Platform.resolvedExecutable,
        <String>['run', 'test/api/support/shutdown_snippet/main.dart'],
      );
      final StringBuffer stderrText = StringBuffer();
      final Future<void> stderrDone = process.stderr
          .transform(utf8.decoder)
          .forEach(stderrText.write);
      final List<String> lines = <String>[];
      final Completer<void> connected = Completer<void>();
      final Future<void> stdoutDone = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((String line) {
            lines.add(line);
            if (line == 'connected: true' && !connected.isCompleted) {
              connected.complete();
            }
          });

      await connected.future.timeout(const Duration(seconds: 60));
      process.kill(ProcessSignal.sigterm);
      final int code = await process.exitCode.timeout(
        const Duration(seconds: 30),
      );
      await Future.wait(<Future<void>>[stdoutDone, stderrDone]);

      expect(stderrText.toString(), isNot(contains('Unhandled exception')));
      expect(code, 0, reason: 'stderr: $stderrText');
      expect(lines, <String>['connected: false', 'connected: true']);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

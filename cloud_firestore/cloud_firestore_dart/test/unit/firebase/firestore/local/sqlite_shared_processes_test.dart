// Two clients on one SQLite file in two processes. sqlite_shared_clients_test.dart covers clients in one isolate and
// in several isolates of one process; within one process SQLite shares its file locks between connections, while two
// processes take them from the operating system (POSIX advisory locks on Linux and macOS, LockFileEx on Windows).

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../util/sqlite3_database.dart';
import 'sqlite_shared_clients_test.dart' as shared;

/// The prefix of the lines of the writer protocol; the other lines on its output are logs of the client.
const String protocolPrefix = 'writer: ';

const String writerScript =
    'test/unit/firebase/firestore/local/sqlite_shared_process_writer.dart';

/// A writer process (sqlite_shared_process_writer.dart) and its output lines.
class WriterProcess {
  WriterProcess._(this.process, this._lines);

  final Process process;
  final StreamIterator<String> _lines;
  final StringBuffer stderrText = StringBuffer();
  final StringBuffer logLines = StringBuffer();

  static Future<WriterProcess> start(String name, int writer) async {
    final Process process = await Process.start(
      Platform.resolvedExecutable,
      <String>['run', writerScript, name, '$writer'],
    );
    final WriterProcess result = WriterProcess._(
      process,
      StreamIterator<String>(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ),
    );
    process.stderr.transform(utf8.decoder).listen(result.stderrText.write);
    return result;
  }

  /// The next line of the protocol, without its prefix; fails with the output of the process when it ended.
  Future<String> next() async {
    while (await _lines.moveNext().timeout(const Duration(minutes: 2))) {
      final String line = _lines.current;
      if (line.startsWith(protocolPrefix)) {
        return line.substring(protocolPrefix.length);
      }
      logLines.writeln(line);
    }
    fail('writer exited (${await process.exitCode}): $stderrText\n$logLines');
  }

  void send(String line) => process.stdin.writeln(line);
}

void main() {
  test(
    'clients in two processes write in turns without sharing an id',
    () async {
      final String name = shared.newName('processes');
      addTearDown(() => DatabaseMock.deleteDatabaseFiles(name));

      // Create the file first, so that the processes race on targets and batches, not on the setup.
      final shared.Client first = await shared.Client.open(name);
      await first.persistence.shutdown();

      const int writers = 2;
      const int rounds = 20;
      final List<WriterProcess> processes = <WriterProcess>[
        for (int writer = 0; writer < writers; writer++)
          await WriterProcess.start(name, writer),
      ];
      addTearDown(() {
        for (final WriterProcess p in processes) {
          p.process.kill(ProcessSignal.sigkill);
        }
      });
      for (final WriterProcess p in processes) {
        expect(await p.next(), 'ready');
      }

      // Every round goes to both processes at once, and the next one only when both have answered: in each round a
      // process allocates with ids it read before the other process committed its previous round.
      final Set<int> targetIds = <int>{};
      final Set<int> batchIds = <int>{};
      final Set<int> sequenceNumbers = <int>{};
      for (int round = 0; round < rounds; round++) {
        for (final WriterProcess p in processes) {
          p.send('round $round');
        }
        for (final WriterProcess p in processes) {
          final List<String> done = (await p.next()).split(' ');
          expect(done.take(2), <String>['done', '$round']);
          targetIds.add(int.parse(done[2]));
          batchIds.add(int.parse(done[3]));
          sequenceNumbers.add(int.parse(done[4]));
        }
      }
      for (final WriterProcess p in processes) {
        p.send('close');
        expect(await p.next(), 'closed');
        expect(await p.process.exitCode, 0);
      }

      expect(targetIds, hasLength(writers * rounds));
      expect(batchIds, hasLength(writers * rounds));
      expect(sequenceNumbers, hasLength(writers * rounds));

      final shared.Client check = await shared.Client.open(name);
      addTearDown(check.persistence.shutdown);
      const int targets = writers * rounds + rounds;
      expect((await check.targetGlobals())['target_count'], targets);
      expect(
        (await check.persistence.query(
          'SELECT COUNT(*) AS c FROM mutations',
        )).single['c'],
        writers * rounds,
      );
      expect(
        (await check.persistence.query(
          'PRAGMA integrity_check',
        )).single.values.single,
        'ok',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

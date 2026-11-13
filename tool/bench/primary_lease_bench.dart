// Cost of the primary lease (stage 1 of the multi-client plan) on a file backed SQLite cache: an empty transaction
// against an empty primary-only transaction (which reads the lease before the operation and writes it after), and
// one refresh of the client metadata (every 4 s per client).
//
//   dart run primary_lease_bench.dart [<transactions per round>] [<directory for the database file>] [--fsync]
//       [--profile]
//
// Rounds alternate between the kinds; the median of the rounds is printed, in microseconds per transaction. --profile
// also prints the time per SQL statement of 1000 transactions of each kind.

import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';

import 'local_store_bench.dart' show BenchDatabase;

const int rounds = 7;

/// A write that makes the transaction commit to the file (in a table of the benchmark).
const String write = 'UPDATE bench SET v = v + 1';

Future<void> main(List<String> args) async {
  final List<String> positional = <String>[
    for (final String arg in args)
      if (!arg.startsWith('--')) arg,
  ];
  BenchDatabase.fsync = args.contains('--fsync');
  final int count = positional.isNotEmpty ? int.parse(positional[0]) : 20000;
  final Directory dir = positional.length > 1
      ? Directory(positional[1])
      : Directory.systemTemp.createTempSync('primary_lease_bench');
  final String file = '${dir.path}/primary_lease_bench.db';
  for (final String suffix in <String>['', '-wal', '-shm', '-journal']) {
    final File f = File('$file$suffix');
    if (f.existsSync()) {
      f.deleteSync();
    }
  }

  final DatabaseId databaseId = DatabaseId.forProject('bench');
  final SQLitePersistence persistence = await SQLitePersistence.create(
    'bench',
    databaseId,
    LocalSerializer(RemoteSerializer(databaseId)),
    BenchDatabase.opener(file),
    const LruGarbageCollectorParams(),
  );
  await persistence.start();
  await persistence.execute('CREATE TABLE bench (v INTEGER)');
  await persistence.execute('INSERT INTO bench (v) VALUES (0)');

  final Map<String, Future<void> Function()> kinds =
      <String, Future<void> Function()>{
    'transaction': () =>
        persistence.runTransactionAndReturn<void>('bench', () async {}),
    'primary transaction': () =>
        persistence.runPrimaryTransaction<void>('bench', () async {}),
    // Every primary-only transaction of the SDK writes (a remote event, an acknowledgement, a GC run): the lease
    // write then shares the commit.
    'write transaction': () => persistence.runTransactionAndReturn<void>(
          'bench',
          () => persistence.execute(write),
        ),
    'primary write'
        ' transaction': () => persistence.runPrimaryTransaction<void>(
          'bench',
          () => persistence.execute(write),
        ),
    'metadata refresh': persistence.refreshClientMetadata,
  };

  // Warm up.
  for (final Future<void> Function() run in kinds.values) {
    for (int i = 0; i < 1000; i++) {
      await run();
    }
  }

  final Map<String, List<double>> results = <String, List<double>>{
    for (final String kind in kinds.keys) kind: <double>[],
  };
  for (int round = 0; round < rounds; round++) {
    for (final MapEntry<String, Future<void> Function()> kind
        in kinds.entries) {
      final Stopwatch watch = Stopwatch()..start();
      for (int i = 0; i < count; i++) {
        await kind.value();
      }
      results[kind.key]!.add(watch.elapsedMicroseconds / count);
    }
  }
  if (args.contains('--profile')) {
    BenchDatabase.profiling = true;
    for (final MapEntry<String, Future<void> Function()> kind
        in kinds.entries) {
      BenchDatabase.resetProfile();
      for (int i = 0; i < 1000; i++) {
        await kind.value();
      }
      BenchDatabase.printProfile('${kind.key}, 1000 times');
    }
  }
  await persistence.shutdown();

  double median(List<double> values) =>
      (values.toList()..sort())[values.length ~/ 2];
  print(
    'SQLite ${BenchDatabase.fsync ? 'with' : 'without'} fsync, $count transactions per round, median of $rounds '
    'rounds:',
  );
  for (final MapEntry<String, List<double>> entry in results.entries) {
    final double value = median(entry.value);
    print(
      '  ${entry.key.padRight(26)} ${value.toStringAsFixed(2).padLeft(8)} us'
      '${entry.key.startsWith('primary') ? '  (+${(value - median(results[entry.key == 'primary transaction' ? 'transaction' : 'write transaction']!)).toStringAsFixed(2)} us)' : ''}',
    );
  }
}

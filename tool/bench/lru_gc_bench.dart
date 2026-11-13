// LRU garbage collection benchmark on a SQLite cache: time and memory peak of each step on a cache of N documents.
//
//   dart run lru_gc_bench.dart <documents> [<directory for the database file>]
//
// Every step runs in a fresh child process (an AOT executable compiled first), so that the peak resident set size of a step (`ProcessInfo.maxRss` at
// its end minus the resident set size right after the database was opened) is not hidden by an earlier step:
//
//   build      N documents in 10 collections, one target per collection, remote events of 1000 documents (each
//              event has its own sequence number), then all targets are released.
//   targets    removes the 10 released targets (`removeTargets`): every document is now orphaned.
//   gc default one collection with the default parameters (10 %, at most 1000 sequence numbers): counts and
//              enumerates the sequence numbers of all N orphaned documents and removes the oldest ones.
//   gc all     collects everything that is left (100 %, no cap): removes the remaining orphaned documents.
//
// Results: notes/perf/local_store_bench.md.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/target_change.dart';
import 'local_store_bench.dart'
    show
        collectionQuery,
        collections,
        docOf,
        eventSize,
        keys,
        openPersistence,
        version;

String fileFor(String dir, int n) => '$dir/lru_gc_bench_$n.db';

double mb(int bytes) => bytes / (1024 * 1024);

Future<void> main(List<String> args) async {
  final List<String> positional =
      args.where((String arg) => !arg.startsWith('--')).toList();
  final String? step = args
      .where((String arg) => arg.startsWith('--step='))
      .map((String arg) => arg.substring('--step='.length))
      .firstOrNull;
  final int n = int.parse(positional.isEmpty ? '10000' : positional[0]);
  final String dir =
      positional.length > 1 ? positional[1] : Directory.systemTemp.path;

  if (step != null) {
    await runStep(step, n, fileFor(dir, n));
    return;
  }

  final String file = fileFor(dir, n);
  for (final String suffix in <String>['', '-journal', '-wal', '-shm']) {
    final File f = File('$file$suffix');
    if (f.existsSync()) {
      f.deleteSync();
    }
  }
  print('LRU GC benchmark, $n documents in $collections collections');
  // The steps run as an AOT executable: in JIT mode the peak of the compiler would hide the peak of a step.
  final bool aot = !Platform.script.path.endsWith('.dart');
  final String exe = aot ? Platform.resolvedExecutable : '$dir/lru_gc_bench_exe';
  final ProcessResult compiled = aot
      ? ProcessResult(0, 0, '', '')
      : await Process.run(Platform.resolvedExecutable,
          <String>['compile', 'exe', Platform.script.toFilePath(), '-o', exe]);
  if (compiled.exitCode != 0) {
    stderr
      ..writeln(compiled.stdout)
      ..writeln(compiled.stderr);
    exit(compiled.exitCode);
  }
  final List<String> lines = <String>[];
  for (final String s in <String>['build', 'targets', 'default', 'all']) {
    final ProcessResult result =
        await Process.run(exe, <String>['$n', dir, '--step=$s']);
    if (result.exitCode != 0) {
      stderr
        ..writeln(result.stdout)
        ..writeln(result.stderr);
      exit(result.exitCode);
    }
    final String out = (result.stdout as String).trim();
    print(out);
    lines.add(out);
  }
  File(file).deleteSync();
  if (!aot) {
    File(exe).deleteSync();
  }
  print('\n=== LRU GC, $n documents ===');
  lines.forEach(print);
}

Future<void> runStep(String step, int n, String file) async {
  final SQLitePersistence persistence = await openPersistence(file);
  final LocalStore store = LocalStore(persistence, User.unauthenticated);
  await store.start();
  final int rssAtStart = ProcessInfo.currentRss;
  final Stopwatch sw = Stopwatch()..start();
  String what;

  switch (step) {
    case 'build':
      final int perCollection = n ~/ collections;
      int clock = 1000;
      for (int c = 0; c < collections; c++) {
        final QueryData target =
            await store.allocateTarget(collectionQuery(c).toTarget());
        for (int start = 0; start < perCollection; start += eventSize) {
          final Map<DocumentKey, MaybeDocument> updates =
              <DocumentKey, MaybeDocument>{};
          for (int i = start; i < min(start + eventSize, perCollection); i++) {
            final Document doc = docOf(c, i, clock);
            updates[doc.key] = doc;
          }
          clock++;
          await store.applyRemoteEvent(RemoteEvent(
            documentUpdates: updates,
            resolvedLimboDocuments: const <DocumentKey>{},
            snapshotVersion: version(clock),
            targetChanges: <int, TargetChange>{
              target.targetId: TargetChange(
                resumeToken: Uint8List.fromList(<int>[1, 2, 3]),
                current: true,
                addedDocuments: keys(updates.keys),
                modifiedDocuments: DocumentKey.emptyKeySet,
                removedDocuments: DocumentKey.emptyKeySet,
              ),
            },
          ));
        }
        await store.releaseTarget(target.targetId);
      }
      what = 'build: ${(sw.elapsedMicroseconds / n).toStringAsFixed(1)} us/doc, '
          'database ${mb(File(file).lengthSync()).toStringAsFixed(1)} MB';
    case 'targets':
      final int removed = await persistence.runTransactionAndReturn(
          'remove targets',
          () => persistence.referenceDelegate
              .removeTargets(1 << 62, const <int>{}));
      what = 'removeTargets: $removed targets';
    case 'default':
    case 'all':
      final LruGarbageCollector collector = LruGarbageCollector(
        persistence.referenceDelegate,
        step == 'default'
            ? const LruGarbageCollectorParams(minBytesThreshold: 1)
            : const LruGarbageCollectorParams(
                minBytesThreshold: 1,
                percentileToCollect: 100,
                maximumSequenceNumbersToCollect: 1 << 30),
      );
      final LruGarbageCollectorResults gc = await store.collectGarbage(collector);
      what = 'gc $step: ${gc.sequenceNumbersCollected} sequence numbers, '
          '${gc.targetsRemoved} targets, ${gc.documentsRemoved} documents removed';
    default:
      throw ArgumentError('unknown step $step');
  }
  final int micros = sw.elapsedMicroseconds;
  await persistence.shutdown();
  final int peak = ProcessInfo.maxRss - rssAtStart;
  print('${step.padRight(8)} ${(micros / 1000).toStringAsFixed(1).padLeft(10)} ms '
      'peak +${mb(max(0, peak)).toStringAsFixed(1).padLeft(7)} MB  ($what)');
}

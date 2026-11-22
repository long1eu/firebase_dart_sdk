// Measures the SQLite engine on the calling isolate (the engine is synchronous, so this is the
// time an application's main isolate would be blocked): writing and loading a server cache of
// 1, 10 and 50 MB, loading one small child cold, and the cost of one pending write.
//
// Usage: dart run tool/bench_load.dart [repeats]   (default 5; prints medians as a Markdown table)
import 'dart:io';

import 'package:firebase_database_dart/storage_engine.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_persistence.dart';

const int _rowBytes = 100;
const int _pendingWrites = 200;

Future<void> main(List<String> arguments) async {
  final int repeats = arguments.isEmpty ? 5 : int.parse(arguments.first);
  stdout.writeln(
    '| Cache | Rows | Write | Reopen | Load all | Load one child | '
    'One pending write | Load $_pendingWrites pending |',
  );
  stdout.writeln('|---|---|---|---|---|---|---|---|');
  for (final int megabytes in <int>[1, 10, 50]) {
    final List<_Run> runs = <_Run>[
      for (int i = 0; i < repeats; i++) await _measure(megabytes),
    ];
    String median(int Function(_Run run) pick) {
      final List<int> values = runs.map(pick).toList()..sort();
      return '${(values[values.length ~/ 2] / 1000).toStringAsFixed(1)} ms';
    }

    stdout.writeln(
      '| $megabytes MB | ${runs.first.rows} | ${median((_Run r) => r.write)} | '
      '${median((_Run r) => r.reopen)} | ${median((_Run r) => r.loadAll)} | '
      '${median((_Run r) => r.loadOne)} | ${median((_Run r) => r.pendingWrite)} | '
      '${median((_Run r) => r.loadPending)} |',
    );
  }
}

/// The microseconds of one run.
final class _Run {
  _Run({
    required this.rows,
    required this.write,
    required this.reopen,
    required this.loadAll,
    required this.loadOne,
    required this.pendingWrite,
    required this.loadPending,
  });

  final int rows;
  final int write;
  final int reopen;
  final int loadAll;
  final int loadOne;
  final int pendingWrite;
  final int loadPending;
}

Future<_Run> _measure(int megabytes) async {
  final Directory root = Directory.systemTemp.createTempSync('rtdb_bench_');
  final PersistenceKey key = PersistenceKey(
    appName: 'bench',
    databaseUrl: Uri.parse('https://bench-default-rtdb.firebaseio.com'),
  );
  try {
    final int rows = megabytes * 1000 * 1000 ~/ _rowBytes;
    final String text = 'x' * 40;
    final Node data = nodeFromJson(<String, Object?>{
      for (int i = 0; i < rows; i++)
        'row${i.toString().padLeft(7, '0')}': <String, Object?>{
          'name': text,
          'count': i,
          'done': i.isEven,
        },
    });
    final Path items = Path('items');

    PersistenceStorageEngine engine = await SqlitePersistence(
      root.path,
    ).open(key);
    final Stopwatch watch = Stopwatch()..start();
    _inTransaction(engine, () => engine.overwriteServerCache(items, data));
    final int write = watch.elapsedMicroseconds;

    final List<int> pending = <int>[];
    final Node small = nodeFromJson(<String, Object?>{'name': text, 'n': 1});
    for (int id = 1; id <= _pendingWrites; id++) {
      watch.reset();
      _inTransaction(
        engine,
        () => engine.saveUserOverwrite(Path('items/new$id'), small, id),
      );
      pending.add(watch.elapsedMicroseconds);
    }
    pending.sort();
    engine.close();

    watch.reset();
    engine = await SqlitePersistence(root.path).open(key);
    final int reopen = watch.elapsedMicroseconds;

    watch.reset();
    final Node one = engine.serverCache(Path('items/row0000042'));
    final int loadOne = watch.elapsedMicroseconds;
    if (one.isEmpty) {
      throw StateError('The child was not stored.');
    }

    watch.reset();
    final int loadedWrites = engine.loadUserWrites().length;
    final int loadPending = watch.elapsedMicroseconds;
    if (loadedWrites != _pendingWrites) {
      throw StateError('Loaded $loadedWrites pending writes.');
    }

    watch.reset();
    final Node all = engine.serverCache(items);
    final int loadAll = watch.elapsedMicroseconds;
    if (all.numChildren != rows) {
      throw StateError('Loaded ${all.numChildren} of $rows rows.');
    }
    engine.close();
    return _Run(
      rows: rows,
      write: write,
      reopen: reopen,
      loadAll: loadAll,
      loadOne: loadOne,
      pendingWrite: pending[pending.length ~/ 2],
      loadPending: loadPending,
    );
  } finally {
    root.deleteSync(recursive: true);
  }
}

void _inTransaction(PersistenceStorageEngine engine, void Function() body) {
  engine.beginTransaction();
  body();
  engine.setTransactionSuccessful();
  engine.endTransaction();
}

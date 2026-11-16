// Cache size and LRU garbage collection on a SQLite cache: a small threshold,
// a cache that grows past it, and what the first collection run removes.
//
// A run removes the least recently used 10 % of the queries (and of the
// cached documents that no query holds), at most 1000, and the documents that
// only those queries held. Here that is 5 of the 50 released queries.
//
// There is no API that starts a collection. The SDK checks the size one
// minute after the instance was created and then every five minutes, so this
// example waits a little over a minute. It reads the debug log of the garbage
// collector to show what the run did (the log is written with `print`, which a
// Zone can intercept); the texts of these lines are not part of the API.
//
// Takes about 70 seconds.
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/performance/cache_size_and_gc.dart

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';
import '../sqlite_database.dart';

const int documentCount = 600;

Future<void> main() async {
  await runZoned(
    run,
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        if (line.contains('LruGarbageCollector')) {
          final int separator = line.indexOf('||');
          parent.print(zone, '  sdk: ${line.substring(separator + 2)}');
        } else if (!line.contains('||')) {
          parent.print(zone, line); // this program's own output
        }
      },
    ),
  );
}

/// The size of the cache files (the database and its write-ahead log).
String filesSize(Directory directory) {
  int bytes = 0;
  for (final FileSystemEntity entity in directory.listSync()) {
    if (entity is File) {
      bytes += entity.lengthSync();
    }
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

Future<void> run() async {
  final Directory directory = Directory.systemTemp.createTempSync(
    'firestore_example_',
  );
  final Stopwatch sinceStart = Stopwatch()..start();
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: exampleApp(),
    openDatabase: sqliteOpener(directory),
    settings: emulatorSettings(
      // The smallest threshold allowed: 1 MB. The default is 100 MB;
      // FirestoreSettings.cacheSizeUnlimited turns the collection off.
      cacheSettings: PersistentCacheSettings(sizeBytes: 1024 * 1024),
    ),
  );

  // About 3 MB of documents.
  final CollectionReference<Map<String, Object?>> notes = firestore.collection(
    scratch('notes'),
  );
  final String text = 'x' * 5000;
  for (int start = 0; start < documentCount; start += 200) {
    final WriteBatch batch = firestore.batch();
    for (int i = start; i < start + 200; i++) {
      batch.set(notes.doc('n$i'), <String, Object?>{'i': i, 'text': text});
    }
    await batch.commit();
  }

  // 50 queries that are listened to once and then released (a get() listens
  // until it has the result): their targets, and the documents that no other
  // target holds, may be collected. One more query stays active: its documents
  // are never collected while the listener is there.
  for (int start = 0; start < 500; start += 10) {
    await notes
        .where('i', isGreaterThanOrEqualTo: start)
        .where('i', isLessThan: start + 10)
        .get();
  }
  final StreamSubscription<QuerySnapshot<Map<String, Object?>>> active = notes
      .where('i', isGreaterThanOrEqualTo: 500)
      .snapshots
      .listen((_) {});

  Future<int> cached() async => (await notes.get(Source.cache)).length;
  print(
    'before: ${await cached()} documents in the cache, files ${filesSize(directory)}',
  );

  FirebaseFirestore.setLogLevel(LogLevel.debug);
  final Duration wait =
      const Duration(seconds: 65) -
      Duration(milliseconds: sinceStart.elapsedMilliseconds);
  print('waiting ${wait.inSeconds} seconds for the first collection run...');
  await Future<void>.delayed(wait);
  FirebaseFirestore.setLogLevel(LogLevel.warn);

  // The files do not get smaller: SQLite keeps the freed pages and reuses
  // them for new data. The size the collector compares with the threshold is
  // that of the file, free pages included, so once a cache has passed the
  // threshold every run (every five minutes) removes another 10 %.
  print(
    'after: ${await cached()} documents in the cache, files ${filesSize(directory)}',
  );

  await active.cancel();
  await firestore.terminate();
  directory.deleteSync(recursive: true);
}

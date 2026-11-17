// Persistent cache indexes, watched from the outside: which plan the SDK
// chose for a cache query, when it created an index, how far the background
// fill got, and how long the query took each time.
//
// There is no API that lists the indexes. The SDK says what it does in its
// debug log, and this example reads that log: it raises the log level and
// keeps the lines of the query engine and of the index backfill (the log is
// written with `print`, which a Zone can intercept). The texts of these lines
// are not part of the API; use them to look, not in code that depends on them.
//
// Takes about 20 seconds: the first index fill runs 15 seconds after the
// instance was created.
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/performance/cache_index_inspection.dart

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';

import '../common.dart';

const int documentCount = 2000;

/// The log lines kept so far, and the number already shown.
final List<String> sdkLog = <String>[];
int shown = 0;

/// Prints the log lines of the query engine and of the backfill that arrived
/// since the last call.
void showLog() {
  for (final String line in sdkLog.skip(shown)) {
    final int separator = line.indexOf('||');
    final String text = (separator < 0 ? line : line.substring(separator + 2))
        // Shorten `Query(target=Query(<path> where ...);limitType=...)`.
        .replaceAllMapped(
          RegExp(r'Query\(target=Query\((.*?)\);limitType=\w+\)'),
          (Match match) => '[${match[1]}]',
        )
        .replaceAll(RegExp(r'examples/\d+/'), '');
    print('  sdk: $text');
  }
  shown = sdkLog.length;
}

Future<void> main() async {
  await runZoned(
    run,
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        if (line.contains('DefaultQueryEngine') ||
            line.contains('IndexBackfiller') && line.contains('offset')) {
          sdkLog.add(line);
        } else if (!line.contains('||')) {
          parent.print(zone, line); // this program's own output
        }
      },
    ),
  );
}

Future<void> run() async {
  final Directory directory = Directory.systemTemp.createTempSync(
    'firestore_example_',
  );
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: exampleApp(),
    openDatabase: sqliteOpener(directory: directory.path),
    settings: emulatorSettings(cacheSettings: PersistentCacheSettings()),
  );
  final PersistentCacheIndexManager indexes =
      firestore.persistentCacheIndexManager!;
  await indexes.enableIndexAutoCreation();

  final String path = scratch('orders');
  final CollectionReference<Map<String, Object?>> orders = firestore.collection(
    path,
  );
  for (int start = 0; start < documentCount; start += 500) {
    final WriteBatch batch = firestore.batch();
    for (int i = start; i < start + 500; i++) {
      batch.set(
        orders.doc('o${i.toString().padLeft(5, '0')}'),
        <String, Object?>{
          'status': i % 50 == 0 ? 'open' : 'closed',
          'total': i,
        },
      );
    }
    await batch.commit();
  }
  // Read the collection once so that the cache holds the documents as the
  // backend has them (an index is filled from those, not from pending writes).
  await orders.get(GetOptions(source: Source.server));

  FirebaseFirestore.setLogLevel(LogLevel.debug);

  Future<void> timed(String label, Query<Map<String, Object?>> query) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final QuerySnapshot<Map<String, Object?>> snapshot = await query.get(
      GetOptions(source: Source.cache),
    );
    stopwatch.stop();
    print(
      '$label: ${snapshot.length} documents in '
      '${stopwatch.elapsedMicroseconds / 1000} ms',
    );
    showLog();
  }

  final Query<Map<String, Object?>> open = orders.where(
    'status',
    isEqualTo: 'open',
  );

  // 1. A scan of the 2000 cached documents for 40 results: the SDK creates
  //    an index on `status`, which is still empty.
  await timed('open orders, first run', open);

  // 2. The index exists but holds nothing yet: the documents it does not
  //    cover are read as well, so the result is complete. No log line: the
  //    query took the index path.
  await timed('open orders, index not filled', open);

  // 3. The background fill: 50 documents per run, the first run 15 seconds
  //    after the instance was created, then one run per minute.
  print('waiting 16 seconds for the first index fill...');
  await Future<void>.delayed(const Duration(seconds: 16));
  showLog();
  await timed('open orders, 50 documents indexed', open);

  // 4. A limit query without filters: the scan returns every document (the
  //    limit is applied afterwards), so the rule "read more than twice the
  //    results" never holds and no index is created for it.
  await timed(
    'top 5 by total (orderBy + limit)',
    orders.orderBy('total', descending: true).limit(5),
  );

  // Such a query can get an index by configuration instead (deprecated API,
  // as in the other SDKs). It is filled by the same background runs.
  // ignore: deprecated_member_use
  await firestore.setIndexConfigurationFromJSON('''
{
  "indexes": [
    {
      "collectionGroup": "orders",
      "queryScope": "COLLECTION",
      "fields": [{"fieldPath": "total", "order": "DESCENDING"}]
    }
  ],
  "fieldOverrides": []
}''');
  await timed(
    'top 5 by total, configured index (not filled yet)',
    orders.orderBy('total', descending: true).limit(5),
  );

  FirebaseFirestore.setLogLevel(LogLevel.warn);
  // Back to plain scans for every query of this instance.
  await indexes.deleteAllIndexes();

  await firestore.terminate();
  directory.deleteSync(recursive: true);
}

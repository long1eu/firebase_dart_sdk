// Property: limit queries and several listeners, against a fake backend with
// watch reconnects (the harness and the fake are in
// view_property_harness.dart; held_back_view_property_test.dart has the same
// interleavings for one listener of one query).
//
// One client (memory and SQLite persistence) has up to three listeners at a
// time on overlapping queries of one collection of six documents:
//  * `c` and `c where m == true`;
//  * `c order by v limit 2`, `c where m == true order by v limit 2`,
//    `c order by v desc limit 3` and `c where m == true order by v
//    limitToLast 2`.
// Listeners are added and removed during the run, with and without metadata
// changes, often on a query that already has a listener (they share the
// target and the view). The seeded random interleavings are those of the
// held-back property: user sets, patches and deletes, acknowledgements and
// rejections, writes of another client (documents move in and out of the
// filter and in the order by a field change, by either client), the changes
// of a target, existence filters, CURRENT, global snapshots at older and
// newer versions, target resets, watch reconnects with resume tokens, limbo
// resolutions. A second test has one listener on one limit query, where
// every change of the window is the query's own (refills from the cache,
// limbo resolutions of the documents that moved out on the backend).
//
// Invariants, per listener:
//  * the snapshots form a sequence: each one starts from the documents of
//    the previous one, and its changes (added, modified, removed), applied
//    in order, give its documents; a document is not added twice or removed
//    or modified while absent; no metadata change without asking for them;
//  * a limit query never shows more documents than its limit;
//  * listeners of the same query show the same documents after every step;
//  * a query without a limit never loses a document that has no pending
//    write and that the backend had at every version since the last global
//    snapshot, while its target is CURRENT;
//  * a held-back document only enters limbo when a target is CURRENT on the
//    current watch stream (see the held-back property);
//  * after the drain every listener shows the result of its query on the
//    backend, in the order of the query: for a limit query the first (or
//    last) N documents; with metadata changes also not from cache and
//    without pending writes; nothing is left in limbo.
//
// A failure shows the seed, the shortest failing prefix and its trace.
// PROPERTY_SCALE=<n> runs n times as many interleavings, PROPERTY_SEED=<seed>
// reruns a failing one and PROPERTY_TRACE=1 prints every step.

@TestOn('vm')
library;

import 'package:firebase_app_dart/internal.dart' show InternalLogLevel, Log;
import 'package:test/test.dart';

import '../../../../util/property.dart';
import 'view_property_harness.dart';

const int _steps = 60;

final QuerySpec _all = QuerySpec('c');
final QuerySpec _m = QuerySpec('c where m == true', onlyM: true);
final QuerySpec _first2 = QuerySpec('c order by v limit 2', limit: 2);
final QuerySpec _mFirst2 = QuerySpec(
  'c where m == true order by v limit 2',
  onlyM: true,
  limit: 2,
);
final QuerySpec _top3 = QuerySpec(
  'c order by v desc limit 3',
  descending: true,
  limit: 3,
);
final QuerySpec _mLast2 = QuerySpec(
  'c where m == true order by v limitToLast 2',
  onlyM: true,
  limit: 2,
  limitToLast: true,
);

void main() {
  // The rejected writes of the property are logged as warnings.
  late InternalLogLevel logLevel;
  setUp(() {
    logLevel = Log.level;
    Log.level = InternalLogLevel.e;
  });
  tearDown(() => Log.level = logLevel);

  final Map<String, RunConfig> configs = <String, RunConfig>{
    'one listener on a limit query': RunConfig(
      queries: <QuerySpec>[_mFirst2],
      documents: 6,
    ),
    'one listener on a limitToLast query': RunConfig(
      queries: <QuerySpec>[_mLast2],
      documents: 6,
    ),
    'several listeners on overlapping queries': RunConfig(
      queries: <QuerySpec>[_mFirst2, _all, _m, _first2, _top3, _mLast2],
      documents: 6,
      maxListeners: 3,
    ),
  };

  for (final MapEntry<String, RunConfig> config in configs.entries) {
    for (final bool sqlite in <bool>[false, true]) {
      final String persistence = sqlite ? 'SQLite' : 'memory';
      test(
        '${config.key}, $persistence persistence',
        () async {
          final Stats stats = Stats();
          final String? failure = await runProperty(
            config.key,
            config.value,
            count: cases(config.value.churn ? 30 : 15),
            steps: _steps,
            sqlite: sqlite,
            stats: stats,
          );
          if (failure != null) {
            fail(failure);
          }
          print('${config.key} ($persistence): $stats');
          // The interleavings must reach the cases the property is about.
          expect(stats.reconnects, greaterThan(0), reason: '$stats');
          expect(stats.removals, greaterThan(0), reason: '$stats');
          if (config.value.churn) {
            expect(stats.sharedQueries, greaterThan(0), reason: '$stats');
            expect(stats.listenersRemoved, greaterThan(0), reason: '$stats');
          }
        },
        timeout: Timeout(Duration(minutes: 2 + 2 * cases(1))),
      );
    }
  }
}

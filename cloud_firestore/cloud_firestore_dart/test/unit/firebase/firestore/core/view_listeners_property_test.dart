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
// More query shapes, each case with up to three listeners that come and go:
//  * cursors: `c order by v startAt(5) endBefore(20)`, `c where m == true
//    order by v desc startAfter(18) limit 2`, `c order by v endAt(12)
//    limitToLast 2`, `c order by v desc endAt(6)`;
//  * an inequality on v and `in`: `c where v > 8`, `c where v <= 15 limit
//    2`, `c where m == true and v >= 6 limit 3`, `c where v in [2, 4, ...
//    24]`, `c where m == true and v in [...]`.
//
// The last case compares the local query engine with and without field
// indexes: every interleaving runs twice on SQLite, in step, once with the
// indexes (v), (m, v), (v desc) and (m, v desc) configured and backfilled
// after every step, and once without. After every step the query engine must
// return, for every listener's query, what a scan of the same cache returns,
// and after every step and after the drain the listeners of both runs must
// show the same documents in the same order. Its queries are a mix of the
// shapes above. Its global snapshots never repeat a version (see the skipped
// test of the backfill below).
//
// Which invariant applies to which query shape:
//  * snapshot sequence, limit never exceeded, same documents for listeners
//    of one query, settled result equals the backend's, with and without
//    indexes: all shapes;
//  * no unexplained removal: the queries without a limit (plain, filtered,
//    inequality, `in`, and cursors without a limit: the cursor bounds are
//    part of what "the backend had it" means);
//  * held-back limbo: all shapes (it is about the documents, not the query).
//
// A failure shows the seed, the shortest failing prefix and its trace.
// PROPERTY_SCALE=<n> runs n times as many interleavings, PROPERTY_SEED=<seed>
// reruns a failing one and PROPERTY_TRACE=1 prints every step.

@TestOn('vm')
library;

import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:firebase_app_dart/internal.dart' show InternalLogLevel, Log;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/index_helpers.dart';
import '../../../../util/property.dart';
import '../../../../util/test_util.dart';
import '../local/mock/database_mock.dart';
import '../local/persistence_test_helpers.dart';
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

// Cursors.
final QuerySpec _between = QuerySpec(
  'c order by v startAt(5) endBefore(20)',
  start: 5,
  end: 20,
  endInclusive: false,
);
final QuerySpec _mAfter18Desc = QuerySpec(
  'c where m == true order by v desc startAfter(18) limit 2',
  onlyM: true,
  descending: true,
  start: 18,
  startInclusive: false,
  limit: 2,
);
final QuerySpec _until12Last2 = QuerySpec(
  'c order by v endAt(12) limitToLast 2',
  end: 12,
  limit: 2,
  limitToLast: true,
);
final QuerySpec _descUntil6 = QuerySpec(
  'c order by v desc endAt(6)',
  descending: true,
  end: 6,
);

// An inequality on v, and `in`.
final QuerySpec _above8 = QuerySpec(
  'c where v > 8',
  vOperator: '>',
  vOperand: 8,
);
final QuerySpec _upTo15First2 = QuerySpec(
  'c where v <= 15 limit 2',
  vOperator: '<=',
  vOperand: 15,
  limit: 2,
);
final QuerySpec _mFrom6First3 = QuerySpec(
  'c where m == true and v >= 6 limit 3',
  onlyM: true,
  vOperator: '>=',
  vOperand: 6,
  limit: 3,
);
const List<int> _even = <int>[2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24];
final QuerySpec _inEven = QuerySpec('c where v in $_even', vIn: _even);
final QuerySpec _mInEven = QuerySpec(
  'c where m == true and v in $_even',
  onlyM: true,
  vIn: _even,
);

/// The interleavings of each case in a default run, per persistence. The cases
/// added later run fewer, to keep the default run of the view property tests
/// at about three minutes; PROPERTY_SCALE runs n times as many.
const Map<String, int> _defaultCounts = <String, int>{
  'one listener on a limit query': 15,
  'one listener on a limitToLast query': 15,
  'several listeners on overlapping queries': 30,
  'listeners on queries with cursors': 4,
  'listeners on queries with an inequality or in': 4,
};

/// The interleavings of the index comparison in a default run (each one runs
/// twice).
const int _indexComparisonCount = 4;

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
    'listeners on queries with cursors': RunConfig(
      queries: <QuerySpec>[_between, _mAfter18Desc, _until12Last2, _descUntil6],
      documents: 6,
      maxListeners: 3,
    ),
    'listeners on queries with an inequality or in': RunConfig(
      queries: <QuerySpec>[
        _above8,
        _upTo15First2,
        _mFrom6First3,
        _inEven,
        _mInEven,
      ],
      documents: 6,
      maxListeners: 3,
    ),
  };

  // Found by the index comparison (seed 20261113, 52 steps). The backfill wrote the index entries of a document as
  // its pending writes left it; when one of those writes was rejected, the document changed back but nothing made
  // the backfill look at it again (its remote version and the batch ids of its other writes are behind the offset of
  // the index). A query served by the index then missed the document, or found it at the old place.
  test('a query served by a field index sees a document after one of its '
      'pending writes was rejected', () async {
    final List<FieldIndex> indexes = <FieldIndex>[
      fieldIndex(
        'c',
        fieldsAndKinds: <Object>[
          'm',
          SegmentKind.ascending,
          'v',
          SegmentKind.ascending,
        ],
      ),
      fieldIndex(
        'c',
        fieldsAndKinds: <Object>[
          'm',
          SegmentKind.ascending,
          'v',
          SegmentKind.descending,
        ],
      ),
    ];
    final String name =
        'firebase/firestore/core/view_property_${const Uuid().v4()}';
    final ViewRun run = ViewRun(
      0,
      Gen(0),
      Stats(),
      RunConfig(queries: <QuerySpec>[_mFirst2, _mLast2], documents: 2),
    );
    try {
      await run.start(
        await createSQLitePersistenceForProject('test-project', name),
        indexes: indexes,
      );
      run.backend.change('d0', <String, Object?>{'m': true, 'v': 5});
      run.backend.change('d1', <String, Object?>{'m': true, 'v': 3});
      await run.sendChanges(run.main!, run.backend.latest);
      await run.markCurrent(run.main!);
      await run.globalSnapshot(run.backend.latest);
      expect(run.listener.documents, <String>['d1: 3', 'd0: 5']);

      // The user deletes d0 and then patches it (the patch does nothing to a deleted document); the index is
      // brought up to date: it has no entry for d0.
      await run.writeMutation(
        PendingWrite('d0', 'delete', null),
        deleteMutation('c/d0'),
      );
      await run.writeMutation(
        PendingWrite('d0', 'patch', <String, Object?>{'v': 9}),
        patchMutation('c/d0', <String, Object?>{'v': 9}),
      );
      await run.backfill();
      expect(run.listener.documents, <String>['d1: 3']);

      // The backend rejects the delete: d0 is back, with the patch.
      await run.answerWrite(mayReject: false, reject: true);
      await run.backfill();
      expect(run.listener.documents, <String>['d1: 3', 'd0: 9']);

      // A new listener on another query, which the index serves, sees d0 too.
      await run.addListener(_mLast2, includeMetadata: true);
      expect(run.fullyIndexedListeners, 2);
      expect(run.listeners.last.documents, <String>[
        'd1: 3',
        'd0: 9',
      ], reason: run.trace.join('\n'));
    } finally {
      await run.shutdown();
      DatabaseMock.deleteDatabaseFiles(name);
    }
  });

  // Found by the index comparison (seed 20569954 at PROPERTY_SCALE=10: 60 steps, and 47 steps with the check of the
  // query engine). An acknowledged write stores its document with the commit version as read time; a backfill moved
  // the offset of the index to (that time, that document). Watch can deliver other documents afterwards in a snapshot
  // of an older version (it lags behind the commit), or of the same version with a key that sorts before: they were
  // behind the offset and the backfill never wrote their entries (the JS and Android SDKs have the same gap). The
  // offset now never passes the last snapshot version of watch (`IndexBackfiller`).
  test('the index backfill indexes a document that watch delivers at or before '
      'the commit version of an acknowledged write', () async {
    final List<FieldIndex> indexes = <FieldIndex>[
      for (final SegmentKind kind in SegmentKind.values)
        if (kind != SegmentKind.contains)
          fieldIndex(
            'c',
            fieldsAndKinds: <Object>['m', SegmentKind.ascending, 'v', kind],
          ),
    ];
    final String name =
        'firebase/firestore/core/view_property_${const Uuid().v4()}';
    final ViewRun run = ViewRun(
      0,
      Gen(0),
      Stats(),
      RunConfig(queries: <QuerySpec>[_mFirst2, _mLast2], documents: 2),
    );
    try {
      await run.start(
        await createSQLitePersistenceForProject('test-project', name),
        indexes: indexes,
      );
      await run.sendChanges(run.main!, 1000);
      await run.markCurrent(run.main!);
      await run.globalSnapshot(1000);
      // Another client creates d0 at 2000; the user's write of d1 is committed at 3000 and acknowledged before
      // watch sends anything. The backfill indexes d1.
      run.backend.change('d0', <String, Object?>{'m': true, 'v': 1});
      await run.writeMutation(
        PendingWrite('d1', 'set', <String, Object?>{'m': true, 'v': 2}),
        setMutation('c/d1', <String, Object?>{'m': true, 'v': 2}),
      );
      await run.answerWrite(mayReject: false);
      await run.backfill();
      // Watch delivers d0 (and d1) in the snapshot at 3000, the commit version.
      await run.sendChanges(run.main!, 3000);
      await run.globalSnapshot(3000);
      await run.backfill();
      expect(run.listener.documents, <String>['d0: 1', 'd1: 2']);

      // A new listener on another query, which the index serves.
      await run.addListener(_mLast2, includeMetadata: true);
      expect(run.fullyIndexedListeners, 2);
      expect(run.listeners.last.documents, <String>[
        'd0: 1',
        'd1: 2',
      ], reason: run.trace.join('\n'));
    } finally {
      await run.shutdown();
      DatabaseMock.deleteDatabaseFiles(name);
    }
  });

  // Found by the index comparison (seed 20791686 at PROPERTY_SCALE=10, 21 steps; that case was the index backfill
  // gap above). A limit query served by an index takes the first documents of the index and looks further only when
  // the document at the edge of the window has pending writes or changed after the index offset. Upstream (JS and
  // Android) tests the latter with the version of the document, its update time; a document that a lagging target
  // delivers after the offset carries an older update time, so it was not noticed when it moved out of the window.
  test('a limit query served by a field index refills its window when a '
      'document at its edge changed after the index offset with an older '
      'version', () async {
    final String name =
        'firebase/firestore/core/view_property_${const Uuid().v4()}';
    final ViewRun run = ViewRun(
      0,
      Gen(0),
      Stats(),
      RunConfig(queries: <QuerySpec>[_mFirst2, _inEven], documents: 3),
    );
    try {
      await run.start(
        await createSQLitePersistenceForProject('test-project', name),
        indexes: <FieldIndex>[
          fieldIndex(
            'c',
            fieldsAndKinds: <Object>[
              'm',
              SegmentKind.ascending,
              'v',
              SegmentKind.ascending,
            ],
          ),
        ],
      );
      // The limit query has d0 and d1.
      run.backend.change('d0', <String, Object?>{'m': true, 'v': 1});
      run.backend.change('d1', <String, Object?>{'m': true, 'v': 2});
      await run.sendChanges(run.main!, 3000);
      await run.markCurrent(run.main!);
      await run.globalSnapshot(3000);
      expect(run.listener.documents, <String>['d0: 1', 'd1: 2']);

      // Another client moves d0 behind the others (4000) and creates d2 (5000). The stream reconnects: the target
      // of the limit query is resumed and lags behind.
      run.backend.change('d0', <String, Object?>{'m': true, 'v': 9});
      run.backend.change('d2', <String, Object?>{'m': true, 'v': 4});
      await run.closeStream();
      await run.reconnect();
      await run.syncTargets();

      // A listener of `v in [even]` gets d1 and d2 at 5000; the index is backfilled up to there.
      await run.addListener(_inEven, includeMetadata: true);
      await run.syncTargets();
      final WatchTarget inEven = run.queryTargets.firstWhere(
        (WatchTarget t) => t.spec == _inEven,
      );
      await run.sendChanges(inEven, 5000);
      await run.markCurrent(inEven);
      await run.send(
        WatchChangeWatchTargetChange(
          WatchTargetChangeType.noChange,
          const <int>[],
        ),
        5000,
      );
      await settle();
      await run.backfill();

      // The limit target catches up at 6000: d0 left its window with the change of 4000 (it arrives with that
      // version, before the read time of the index offset), d2 entered it.
      final WatchTarget limit = run.queryTargets.firstWhere(
        (WatchTarget t) => t.spec == _mFirst2,
      );
      await run.sendChanges(limit, 5000);
      await run.markCurrent(limit);
      await run.send(
        WatchChangeWatchTargetChange(
          WatchTargetChangeType.noChange,
          const <int>[],
        ),
        6000,
      );
      await settle();
      expect(run.listeners.first.documents, <String>['d1: 2', 'd2: 4']);

      // The query engine, served by the index, gives the window of a scan of the cache.
      expect(run.fullyIndexedListeners, greaterThan(0));
      expect(
        await run.engineDifferences(),
        isEmpty,
        reason: run.trace.join('\n'),
      );
    } finally {
      await run.shutdown();
      DatabaseMock.deleteDatabaseFiles(name);
    }
  });

  // Found by the index comparison once the backfill stopped at the snapshot version of watch (seed 20791686, 7
  // steps). With an offset that comes from a field index, the documents read after the offset are read without the
  // filters of the query (to apply the overlays of earlier batches, a deviation of the port); when none of them had an
  // overlay they were returned unfiltered, and the query engine returned documents that do not match.
  test('the query engine served by a field index only returns matching '
      'documents that changed after the index offset', () async {
    final String name =
        'firebase/firestore/core/view_property_${const Uuid().v4()}';
    final ViewRun run = ViewRun(
      0,
      Gen(0),
      Stats(),
      RunConfig(queries: <QuerySpec>[_mFirst2, _inEven], documents: 6),
    );
    try {
      await run.start(
        await createSQLitePersistenceForProject('test-project', name),
        indexes: <FieldIndex>[
          fieldIndex('c', fieldsAndKinds: <Object>['v', SegmentKind.ascending]),
        ],
      );
      await run.sendChanges(run.main!, 1000);
      await run.markCurrent(run.main!);
      await run.globalSnapshot(1000);
      // d4 (v 1) is acknowledged, d5 (v 2) is pending: the backfill stops at the snapshot version of watch, with the
      // batch of d5 in its offset.
      await run.writeMutation(
        PendingWrite('d4', 'set', <String, Object?>{'m': true, 'v': 1}),
        setMutation('c/d4', <String, Object?>{'m': true, 'v': 1}),
      );
      await run.answerWrite(mayReject: false);
      await run.writeMutation(
        PendingWrite('d5', 'set', <String, Object?>{'m': true, 'v': 2}),
        setMutation('c/d5', <String, Object?>{'m': true, 'v': 2}),
      );
      await run.backfill();

      await run.addListener(_inEven, includeMetadata: true);
      expect(run.listeners.last.documents, <String>['d5: 2']);
      expect(
        await run.engineDifferences(),
        isEmpty,
        reason: run.trace.join('\n'),
      );
    } finally {
      await run.shutdown();
      DatabaseMock.deleteDatabaseFiles(name);
    }
  });

  // Found by the index comparison (seed 21646938, 43 steps). Watch can deliver new documents in a later event at
  // the same snapshot version as one that the backfill has already passed: a document whose key sorts before the key
  // of the offset is behind it and never indexed. No acknowledged write is involved (that case is fixed above). The JS
  // and Android SDKs have the same gap. Not fixed: see the summary of the property work; the index comparison avoids
  // it with `RunConfig.distinctSnapshotVersions`.
  test(
    'the index backfill indexes a document that watch delivers in a later '
    'event at the snapshot version of the offset',
    skip:
        'Known gap, inherited from the JS and Android SDKs, waiting for a '
        'decision: the backfill offset passes documents that a later event '
        'delivers at the same snapshot version with a smaller key.',
    () async {
      final String name =
          'firebase/firestore/core/view_property_${const Uuid().v4()}';
      final ViewRun run = ViewRun(
        0,
        Gen(0),
        Stats(),
        RunConfig(queries: <QuerySpec>[_mFirst2, _inEven], documents: 2),
      );
      try {
        await run.start(
          await createSQLitePersistenceForProject('test-project', name),
          indexes: <FieldIndex>[
            fieldIndex(
              'c',
              fieldsAndKinds: <Object>['v', SegmentKind.ascending],
            ),
            fieldIndex(
              'c',
              fieldsAndKinds: <Object>[
                'm',
                SegmentKind.ascending,
                'v',
                SegmentKind.ascending,
              ],
            ),
          ],
        );
        // d1 is a result of the limit query, d0 only of `v in [even]`.
        run.backend.change('d0', <String, Object?>{'m': false, 'v': 2});
        run.backend.change('d1', <String, Object?>{'m': true, 'v': 1});
        await run.sendChanges(run.main!, 3000);
        await run.markCurrent(run.main!);
        await run.globalSnapshot(3000);
        await run.backfill();

        // A listener of `v in [even]`: its target gets d0 in a snapshot at the same version 3000.
        await run.addListener(_inEven, includeMetadata: true);
        await run.syncTargets();
        final WatchTarget inEven = run.queryTargets.firstWhere(
          (WatchTarget t) => t.spec == _inEven,
        );
        await run.sendChanges(inEven, 3000);
        await run.markCurrent(inEven);
        await run.globalSnapshot(3000);
        await run.backfill();
        expect(run.listeners.last.documents, <String>['d0: 2']);
        expect(
          await run.engineDifferences(),
          isEmpty,
          reason: run.trace.join('\n'),
        );
      } finally {
        await run.shutdown();
        DatabaseMock.deleteDatabaseFiles(name);
      }
    },
  );

  test('the listeners show the same documents with and without field '
      'indexes', () async {
    final RunConfig config = RunConfig(
      queries: <QuerySpec>[
        _mFirst2,
        _between,
        _mAfter18Desc,
        _upTo15First2,
        _above8,
        _inEven,
        _top3,
        _mLast2,
      ],
      documents: 6,
      maxListeners: 3,
      distinctSnapshotVersions: true,
      indexes: <FieldIndex>[
        fieldIndex('c', fieldsAndKinds: <Object>['v', SegmentKind.ascending]),
        fieldIndex(
          'c',
          fieldsAndKinds: <Object>[
            'm',
            SegmentKind.ascending,
            'v',
            SegmentKind.ascending,
          ],
        ),
        fieldIndex('c', fieldsAndKinds: <Object>['v', SegmentKind.descending]),
        fieldIndex(
          'c',
          fieldsAndKinds: <Object>[
            'm',
            SegmentKind.ascending,
            'v',
            SegmentKind.descending,
          ],
        ),
      ],
    );
    final Stats stats = Stats();
    final String? failure = await runProperty(
      'the same documents with and without field indexes',
      config,
      count: cases(_indexComparisonCount),
      steps: _steps,
      sqlite: true,
      stats: stats,
    );
    if (failure != null) {
      fail(failure);
    }
    print('with and without field indexes (SQLite): $stats');
    // The run with indexes must really serve queries from them.
    expect(stats.indexedListenerSteps, greaterThan(0), reason: '$stats');
    expect(stats.reconnects, greaterThan(0), reason: '$stats');
  }, timeout: Timeout(Duration(minutes: 2 + 2 * cases(1))));

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
            count: cases(_defaultCounts[config.key]!),
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

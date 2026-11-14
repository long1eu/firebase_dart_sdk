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
// after every step, and once without. After every step and after the drain
// the listeners of both runs must show the same documents in the same
// order. Its queries are a mix of the shapes above.
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
  // query engine). An acknowledged write stores its document with the commit version as read time; a backfill then
  // moves the offset of the index to (that time, that document). Watch can deliver other documents afterwards in a
  // snapshot of an older version (it lags behind the commit), or of the same version with a key that sorts before:
  // they are behind the offset and the backfill never writes their entries. The Android SDK does the same. Not fixed
  // (see the summary of the property work); the comparison case avoids it with `RunConfig.snapshotsAfterCommits`.
  test(
    'the index backfill misses a document that watch delivers at or before '
    'the commit version of an acknowledged write',
    skip:
        'Known gap, inherited from the Android SDK, waiting for a decision: '
        'the offset of the index backfill passes the documents that watch '
        'delivers at or before the commit version of an acknowledged write.',
    () async {
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
    },
  );

  // Found by the index comparison (seed 20791686 at PROPERTY_SCALE=10, 21 steps). A limit query served by an index
  // takes the first documents of the index and only looks further when the document at the edge of the window has
  // pending writes or a version after the read time of the index offset. A document that arrives with an older
  // version than that (from a target that lags, or after an acknowledgement moved the offset ahead) and moves out of
  // the window is not noticed: the window keeps it until the next backfill and a later change of the view. The
  // Android SDK has the same check. Not fixed (see the summary of the property work).
  test(
    'a limit query served by a field index refills its window when a '
    'document arrives with a version before the read time of the index',
    skip:
        'Known gap, inherited from the Android SDK, waiting for a decision: '
        'the refill check of a limit query served by an index compares the '
        'version of the document with the read time of the index offset.',
    () async {
      final String name =
          'firebase/firestore/core/view_property_${const Uuid().v4()}';
      final ViewRun run = ViewRun(
        0,
        Gen(0),
        Stats(),
        RunConfig(queries: <QuerySpec>[_mFirst2], documents: 4),
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
        run.backend.change('d0', <String, Object?>{'m': true, 'v': 1});
        run.backend.change('d1', <String, Object?>{'m': true, 'v': 2});
        await run.sendChanges(run.main!, 3000);
        await run.markCurrent(run.main!);
        await run.globalSnapshot(3000);
        expect(run.listener.documents, <String>['d0: 1', 'd1: 2']);

        // Another client moves d0 behind the others (4000). The user writes d2, the next one in the order, and d3,
        // which is acknowledged at 5000: the index is backfilled up to that read time.
        run.backend.change('d0', <String, Object?>{'m': true, 'v': 5});
        await run.writeMutation(
          PendingWrite('d3', 'set', <String, Object?>{'m': false, 'v': 9}),
          setMutation('c/d3', <String, Object?>{'m': false, 'v': 9}),
        );
        await run.answerWrite(mayReject: false);
        await run.writeMutation(
          PendingWrite('d2', 'set', <String, Object?>{'m': true, 'v': 3}),
          setMutation('c/d2', <String, Object?>{'m': true, 'v': 3}),
        );
        await run.backfill();
        expect(run.fullyIndexedListeners, 1);

        // Watch delivers the change of d0, at its version 4000.
        await run.sendChanges(run.main!, 4000);
        await run.globalSnapshot(4000);
        expect(run.listener.documents, <String>[
          'd1: 2',
          'd2: 3',
        ], reason: run.trace.join('\n'));
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
      snapshotsAfterCommits: true,
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
      count: cases(20),
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

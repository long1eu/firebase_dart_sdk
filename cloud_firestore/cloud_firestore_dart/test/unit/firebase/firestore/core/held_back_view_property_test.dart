// Property: the held-back rule of the view under watch reconnects.
//
// The view holds an acknowledged write back until watch sends the document
// (`View._awaitingSync`), and puts the document in limbo once a snapshot of
// watch at or after the commit lacks it while the target is CURRENT on the
// current watch stream (see spec/held_back_reconnect_spec_test.dart).
//
// One client (memory and SQLite persistence) listens to `c where m == true`
// against a fake backend that keeps every version of its documents and
// speaks the watch and write protocols through the mock datastore. Seeded
// random interleavings of:
//  * user sets, patches and deletes of documents that match the query or not;
//  * write acknowledgements and rejections;
//  * sets and deletes of the backend by "another client";
//  * watch: the changes of a target up to some version, an existence filter,
//    CURRENT with a resume token, a global snapshot at some version (not
//    always the latest), a target reset;
//  * the watch stream closing and reconnecting: targets are resumed from
//    their token, and the backend may leave out the removals since then and
//    send an existence filter instead (a mismatch, as the real backend);
//  * limbo resolutions: the fake answers the document targets of the client
//    like any other target.
// Then everything is drained: writes acknowledged, every target caught up
// to the latest version and CURRENT, global snapshots.
//
// Invariants:
//  * no held-back document (the view shows its local version although its
//    writes are answered) enters limbo unless the target of the query is
//    CURRENT on the current watch stream, or is being filled again after the
//    client reset it for an existence filter mismatch (the reset takes every
//    document out of the target). Other documents of the view that the
//    target lacks go to limbo as in the other SDKs, where the view stays
//    current across a reconnect;
//  * the listener never sees a document removed that has no pending write
//    and that the backend had, matching, at every version since the last
//    global snapshot (so no removed/added flicker of a held-back document);
//  * after the drain the listener is in sync (not from cache, no pending
//    writes), nothing is left in limbo, and its documents are those of the
//    backend: every held-back document was released.
//
// The harness and the fake backend are in view_property_harness.dart, shared
// with view_listeners_property_test.dart (limit queries, several listeners).
//
// A failure shows the seed, the shortest failing prefix and its trace.
// PROPERTY_SCALE=<n> runs n times as many interleavings, PROPERTY_SEED=<seed>
// reruns a failing one and PROPERTY_TRACE=1 prints every step.

@TestOn('vm')
library;

import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/existence_filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:firebase_app_dart/internal.dart' show InternalLogLevel, Log;
import 'package:test/test.dart';

import '../../../../util/property.dart';
import '../../../../util/test_util.dart';
import '../local/persistence_test_helpers.dart';
import 'view_property_harness.dart';

const int _steps = 60;

/// One listener, with metadata changes, on `c where m == true`.
final RunConfig _config = RunConfig(
  queries: <QuerySpec>[QuerySpec('c where m == true', onlyM: true)],
  documents: 4,
);

void main() {
  // The rejected writes of the property are logged as warnings.
  late InternalLogLevel logLevel;
  setUp(() {
    logLevel = Log.level;
    Log.level = InternalLogLevel.e;
  });
  tearDown(() => Log.level = logLevel);

  // Found by the property (seed 21045094 at PROPERTY_SCALE=10 led to it). After an existence filter mismatch the
  // client resets the target and watches it again; its view is still current from before. A limbo resolution that
  // confirmed a document before the target was filled again made the view drop the document for good
  // (`View.backendMismatches`), although the backend has it.
  test('a document confirmed by its limbo resolution is kept while the target '
      'is filled again after an existence filter mismatch', () async {
    final ViewRun run = ViewRun(0, Gen(0), Stats(), _config);
    final Persistence persistence = await createLRUMemoryPersistence();
    try {
      await run.start(persistence);
      run.backend.change('d0', <String, Object?>{'m': true, 'v': 1});
      run.backend.change('d1', <String, Object?>{'m': true, 'v': 2});
      await run.sendChanges(run.main!, 3000);
      await run.markCurrent(run.main!);
      await run.globalSnapshot(3000);
      // d1 is deleted while the stream is down; the resumed target gets an existence filter.
      await run.closeStream();
      run.backend.change('d1', null); // 4000
      await run.reconnect();
      await run.syncTargets();
      await run.acknowledgeTarget(run.main!);
      run.main!.sentVersion = 4000;
      await run.send(
        WatchChangeExistenceFilterWatchChange(
          run.main!.id,
          const ExistenceFilter(1),
        ),
      );
      await run.markCurrent(run.main!);
      await run.globalSnapshot(4000);
      // The client reset the target and watches it again; nothing is refilled yet.
      await run.writeMutation(
        PendingWrite('d0', 'set', <String, Object?>{'m': true, 'v': 3}),
        setMutation('c/d0', <String, Object?>{'m': true, 'v': 3}),
      );
      await run.answerWrite(mayReject: false); // 5000
      await settle();
      await run.syncTargets();
      // The limbo resolutions answer before the target is filled again.
      for (final WatchTarget t in run.targets.values.toList()) {
        if (t.docId != null) {
          await run.sendChanges(t, 5000);
          await run.markCurrent(t);
        }
      }
      await run.send(
        WatchChangeWatchTargetChange(
          WatchTargetChangeType.noChange,
          const <int>[],
        ),
        5000,
      );
      await settle();
      await run.syncTargets();
      // d0 is still in the view: the target is not CURRENT yet, so the confirmation says nothing about it.
      expect(
        run.listener.describe(),
        '{d0: 3} from cache',
        reason: run.trace.join('\n'),
      );
      await run.drain();
      expect(run.differences(), isEmpty, reason: run.trace.join('\n'));
      expect(run.listener.describe(), '{d0: 3}');
      expect(
        run.violations.where((String v) => v.contains('removed')),
        isEmpty,
        reason: run.trace.join('\n'),
      );
    } finally {
      await run.shutdown();
    }
  });

  for (final bool sqlite in <bool>[false, true]) {
    test('held-back documents under watch reconnects, '
        '${sqlite ? 'SQLite' : 'memory'} persistence', () async {
      final Stats stats = Stats();
      final String? failure = await runProperty(
        'held-back documents under watch reconnects',
        _config,
        count: cases(30),
        steps: _steps,
        sqlite: sqlite,
        stats: stats,
      );
      if (failure != null) {
        fail(failure);
      }
      print('held-back property (${sqlite ? 'SQLite' : 'memory'}): $stats');
      // The interleavings must reach the cases the property is about.
      expect(stats.reconnects, greaterThan(0), reason: '$stats');
      expect(stats.limboResolutions, greaterThan(0), reason: '$stats');
      expect(stats.filterMismatches, greaterThan(0), reason: '$stats');
    }, timeout: Timeout(Duration(minutes: 2 + 2 * cases(1))));
  }
}

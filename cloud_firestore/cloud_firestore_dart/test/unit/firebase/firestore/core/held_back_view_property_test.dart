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
// A failure shows the seed, the shortest failing prefix and its trace.
// PROPERTY_SCALE=<n> runs n times as many interleavings, PROPERTY_SEED=<seed>
// reruns a failing one and PROPERTY_TRACE=1 prints every step.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query_stream.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/serial_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/existence_filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:firebase_app_dart/internal.dart' show InternalLogLevel, Log;
import 'package:grpc/grpc.dart';
import 'package:rxdart/subjects.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/property.dart';
import '../../../../util/test_util.dart';
import '../local/mock/database_mock.dart';
import '../local/persistence_test_helpers.dart';
import '../remote/mock_datastore.dart';

const int _documents = 4;
const int _steps = 60;

/// Forwards the callbacks of a remote store to the sync engine, which is
/// created after it.
class _Callback implements RemoteStoreCallback {
  late SyncEngine syncEngine;

  @override
  Future<void> handleRemoteEvent(RemoteEvent remoteEvent) =>
      syncEngine.handleRemoteEvent(remoteEvent);

  @override
  Future<void> handleRejectedListen(int targetId, GrpcError error) =>
      syncEngine.handleRejectedListen(targetId, error);

  @override
  Future<void> handleSuccessfulWrite(MutationBatchResult result) =>
      syncEngine.handleSuccessfulWrite(result);

  @override
  Future<void> handleRejectedWrite(int batchId, GrpcError error) =>
      syncEngine.handleRejectedWrite(batchId, error);

  @override
  Future<void> handleOnlineStateChange(OnlineState onlineState) =>
      syncEngine.handleOnlineStateChange(onlineState);

  @override
  ImmutableSortedSet<DocumentKey> Function(int) get getRemoteKeysForTarget =>
      syncEngine.getRemoteKeysForTarget;
}

Future<void> _settle() async {
  // The mock streams deliver their events on timers.
  for (int i = 0; i < 3; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// A document of the fake backend.
class _Doc {
  _Doc(this.data, this.version);

  final Map<String, Object?> data;

  /// The version of its last change.
  final int version;

  bool get matches => data['m'] == true;
}

/// The fake backend: every version of its documents.
class _Backend {
  final List<(int, Map<String, _Doc>)> _history = <(int, Map<String, _Doc>)>[
    (1000, <String, _Doc>{}),
  ];

  int get latest => _history.last.$1;

  List<int> get versions => <int>[for (final (int v, _) in _history) v];

  /// The documents at [version].
  Map<String, _Doc> at(int version) =>
      _history.lastWhere(((int, Map<String, _Doc>) s) => s.$1 <= version).$2;

  /// Sets ([data]) or deletes (null) [id] at a new version, which is
  /// returned.
  int change(String id, Map<String, Object?>? data) {
    final int version = latest + 1000;
    final Map<String, _Doc> docs = Map<String, _Doc>.of(_history.last.$2);
    if (data == null) {
      docs.remove(id);
    } else {
      docs[id] = _Doc(data, version);
    }
    _history.add((version, docs));
    return version;
  }

  /// Whether [id] existed and matched the query at every version from
  /// [since] on.
  bool matchedSince(String id, int since) {
    for (final (int version, Map<String, _Doc> docs) in _history) {
      if (version >= since && docs[id]?.matches != true) {
        return false;
      }
    }
    // The state at [since] itself (the last change at or before it).
    return at(since)[id]?.matches ?? false;
  }
}

/// A target of the client on the current watch stream, as the backend sees
/// it.
class _Target {
  _Target(this.id, this.docId, this.sentVersion, {required this.resumed});

  final int id;

  /// The document of a document target (a limbo resolution), or null for the
  /// target of the query.
  final String? docId;

  /// The version up to which the changes of the target were sent (from the
  /// resume token at first), or null when nothing was sent yet.
  int? sentVersion;

  /// The target was resumed with a resume token.
  final bool resumed;
  bool acknowledged = false;
  bool current = false;

  /// The client watched this target id before on the same stream (a target
  /// that it reset after an existence filter mismatch): the backend answers
  /// the removal first.
  bool replaces = false;

  /// Removals were left out of what was sent since the resume token: an
  /// existence filter must tell the client.
  bool omittedRemovals = false;
}

/// A write of the user that the backend has not answered.
class _Write {
  _Write(this.id, this.kind, this.data);

  final String id;
  final String kind;
  final Map<String, Object?>? data;

  @override
  String toString() => '$kind($id${data == null ? '' : ', $data'})';
}

/// What the interleavings did, over all seeds of a test.
class _Stats {
  int runs = 0;
  int acknowledged = 0;
  int rejected = 0;
  int reconnects = 0;
  int resets = 0;
  int filterMismatches = 0;
  int limboResolutions = 0;
  int removals = 0;

  @override
  String toString() =>
      '$runs interleavings, $acknowledged writes acknowledged, $rejected '
      'rejected, $reconnects watch reconnects, $resets target resets, '
      '$filterMismatches existence filter mismatches, $limboResolutions '
      'limbo resolutions, $removals documents removed from the view';
}

class _Run {
  _Run(this.seed, this.gen, this.stats);

  final _Stats stats;

  final int seed;
  final Gen gen;

  late final Persistence persistence;
  late final SerialQueue queue;
  late final MockDatastore datastore;
  late final RemoteStore remoteStore;
  late final SyncEngine syncEngine;
  late final EventManager eventManager;
  final Query query = testQuery;

  static final Query testQuery = queryOf();

  static Query queryOf() =>
      // `c where m == true`
      Query(path('c')).filter(filter('m', '==', true));

  final _Backend backend = _Backend();
  final Map<int, _Target> targets = <int, _Target>{};
  final List<_Write> pending = <_Write>[];
  final Set<String> limbo = <String>{};

  /// The client reset the target of the query for an existence filter
  /// mismatch and the target was not CURRENT since (also across reconnects
  /// of the stream).
  bool refillPending = false;
  int lastGlobal = 1000;
  int _counter = 0;

  /// The latest snapshot of the listener.
  ViewSnapshot? view;
  final List<String> trace = <String>[];
  final List<String> violations = <String>[];

  void log(String step) {
    trace.add(step);
    if (traceProperties) {
      print('TRACE seed $seed $step');
    }
  }

  String id(int i) => 'd$i';

  bool get streamOpen => datastore.isWatchStreamOpen;

  _Target? get main {
    for (final _Target t in targets.values) {
      if (t.docId == null) {
        return t;
      }
    }
    return null;
  }

  Future<T> onQueue<T>(Future<T> Function() task) => queue.run<T>(task);

  // ------------------------------------------------------------ the client

  Future<void> start(Persistence persistence) async {
    this.persistence = persistence;
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    final TaskScheduler scheduler = TaskScheduler('held-back-$seed');
    datastore = MockDatastore(scheduler)..onWatchQuery = _onWatchQuery;
    final _Callback callback = _Callback();
    // As `FirestoreClient`: one queue for the remote store and for every
    // call into the sync engine.
    queue = SerialQueue();
    remoteStore = RemoteStore(
      callback,
      localStore,
      datastore,
      BehaviorSubject<bool>.seeded(true),
      scheduler,
      queue: queue,
    );
    syncEngine = SyncEngine(localStore, remoteStore, User.unauthenticated);
    callback.syncEngine = syncEngine;
    eventManager = EventManager(syncEngine);
    await onQueue<void>(() async {
      await localStore.start();
      await remoteStore.start();
    });
    final QueryStream listener = QueryStream(
      query,
      const ListenOptions(
        includeDocumentMetadataChanges: true,
        includeQueryMetadataChanges: true,
      ),
    )..listen(_onSnapshot);
    await onQueue<int>(() => eventManager.addQueryListener(listener));
    await _settle();
    log('the client listens to c where m == true');
  }

  void _onSnapshot(ViewSnapshot snapshot) {
    view = snapshot;
    final List<String> changes = <String>[];
    for (final DocumentViewChange change in snapshot.changes) {
      final String docId = change.document.key.path.last;
      changes.add('${change.type} $docId');
      if (change.type != DocumentViewChangeType.removed) {
        continue;
      }
      stats.removals++;
      // A removal needs a reason: a write of the user that is not answered
      // yet (or was just rejected: then the backend does not have the
      // document either), or a version of the backend, since the last
      // global snapshot, without the document.
      if (pending.every((_Write w) => w.id != docId) &&
          backend.matchedSince(docId, lastGlobal)) {
        violations.add(
          '$docId was removed from the view although it has no pending write '
          'and the backend had it at every version since $lastGlobal',
        );
      }
    }
    log(
      '    snapshot: ${describeView()}'
      '${changes.isEmpty ? '' : ' (${changes.join(', ')})'}',
    );
  }

  String describeView() {
    final ViewSnapshot? snapshot = view;
    if (snapshot == null) {
      return 'none';
    }
    return '{${<String>[for (final Document doc in snapshot.documents) '${doc.key.path.last}: ${doc.getFieldValue(field('v'))}${doc.hasLocalMutations ? ' local' : ''}${doc.hasCommittedMutations ? ' committed' : ''}'].join(', ')}}'
        '${snapshot.isFromCache ? ' from cache' : ''}'
        '${snapshot.mutatedKeys.isEmpty ? '' : ' pending writes'}';
  }

  void _onWatchQuery(QueryData queryData) {
    final String token = utf8.decode(queryData.resumeToken);
    final int? resumeVersion = token.isEmpty
        ? null
        : int.parse(token.substring(1));
    final String? docId = queryData.target.isDocumentQuery
        ? queryData.target.path.last
        : null;
    final bool replaces = targets.containsKey(queryData.targetId);
    targets[queryData.targetId] = _Target(
      queryData.targetId,
      docId,
      resumeVersion,
      resumed: resumeVersion != null,
    )..replaces = replaces;
    if (queryData.purpose == QueryPurpose.existenceFilterMismatch ||
        queryData.purpose == QueryPurpose.existenceFilterMismatchBloom) {
      refillPending = true;
    }
    log(
      '    the client watches target ${queryData.targetId} '
      '(${docId ?? 'the query'}, ${queryData.purpose.name}'
      '${resumeVersion == null ? '' : ', resumed from $resumeVersion'})',
    );
    if (queryData.purpose == QueryPurpose.existenceFilterMismatch && replaces) {
      stats.filterMismatches++;
    }
    if (docId != null &&
        queryData.purpose == QueryPurpose.limboResolution &&
        limbo.add(docId)) {
      stats.limboResolutions++;
      // Not for a limbo resolution that is only sent again after a reconnect.
      // Except while the target is filled again after an existence filter
      // mismatch: the reset took every document out of the target, and the
      // next change of the view puts those without pending writes in limbo
      // (as in the other SDKs; the resolutions are answered like any other).
      final _Target? target = main;
      // Only for a held-back document: the view shows its local version
      // although its writes are answered. Any other document of the view
      // that the target lacks is in limbo as in the other SDKs, where the
      // view stays current across a reconnect.
      final Document? shown = view?.documents.getDocument(key('c/$docId'));
      final bool heldBack =
          shown != null &&
          shown.hasLocalMutations &&
          pending.every((_Write w) => w.id != docId);
      if (heldBack && (target == null || !(target.current || refillPending))) {
        violations.add(
          'the held-back $docId entered limbo while the target of the query '
          'was not CURRENT on the current watch stream',
        );
      }
    }
  }

  /// Forgets the targets the client stopped watching.
  void syncTargets() {
    if (!streamOpen) {
      return;
    }
    final Map<int, QueryData> active = datastore.activeTargets;
    targets.removeWhere((int id, _) => !active.containsKey(id));
    limbo.removeWhere(
      (String docId) => targets.values.every((_Target t) => t.docId != docId),
    );
  }

  // --------------------------------------------------------------- writes

  Future<void> userWrite() async {
    final String docId = id(gen.below(_documents));
    final _Write write;
    final Mutation mutation;
    switch (gen.below(10)) {
      case 0 || 1 || 2 || 3 || 4:
        final Map<String, Object?> data = <String, Object?>{
          'm': gen.chance(75),
          'v': ++_counter,
        };
        write = _Write(docId, 'set', data);
        mutation = setMutation('c/$docId', data);
      case 5 || 6 || 7:
        final Map<String, Object?> data = gen.chance(70)
            ? <String, Object?>{'v': ++_counter}
            : <String, Object?>{'m': gen.chance(50)};
        write = _Write(docId, 'patch', data);
        mutation = patchMutation('c/$docId', data);
      default:
        write = _Write(docId, 'delete', null);
        mutation = deleteMutation('c/$docId');
    }
    pending.add(write);
    log('the user writes $write');
    final Completer<void> userTask = Completer<void>();
    // A rejected write completes its task with an error.
    unawaited(userTask.future.catchError((Object _) {}));
    await onQueue<void>(
      () => syncEngine.writeMutations(<Mutation>[mutation], userTask),
    );
    await _settle();
  }

  /// The backend answers the oldest write the client sent: it applies and
  /// acknowledges it, or rejects it (always for a patch of a missing
  /// document; any write with [mayReject]).
  Future<void> answerWrite({required bool mayReject}) async {
    if (datastore.writesSent == 0) {
      return;
    }
    datastore.waitForWriteSend();
    final _Write write = pending.removeAt(0);
    final _Doc? existing = backend.at(backend.latest)[write.id];
    final bool missing = write.kind == 'patch' && existing == null;
    if (missing || (mayReject && gen.chance(15))) {
      log('the backend rejects $write');
      stats.rejected++;
      await datastore.failWrite(
        missing
            ? GrpcError.notFound('no document to update')
            : GrpcError.permissionDenied('denied'),
      );
      await _settle();
      return;
    }
    final int version_ = backend.change(write.id, switch (write.kind) {
      'set' => write.data,
      'patch' => <String, Object?>{...existing!.data, ...write.data!},
      _ => null,
    });
    log('the backend applies $write at $version_');
    stats.acknowledged++;
    await datastore.ackWrite(version(version_), <MutationResult>[
      MutationResult(version(version_), const <FieldValue>[]),
    ]);
    await _settle();
  }

  void otherClientWrite() {
    final String docId = id(gen.below(_documents));
    if (gen.chance(40)) {
      final int version = backend.change(docId, null);
      log('another client deletes $docId at $version');
    } else {
      final Map<String, Object?> data = <String, Object?>{
        'm': gen.chance(75),
        'v': ++_counter,
      };
      final int version = backend.change(docId, data);
      log('another client sets $docId to $data at $version');
    }
  }

  // ---------------------------------------------------------------- watch

  Future<void> _send(WatchChange change, [int? snapshotVersion]) =>
      datastore.writeWatchChange(
        change,
        snapshotVersion == null
            ? SnapshotVersion.none
            : version(snapshotVersion),
      );

  /// The documents of [target] at [version].
  Map<String, _Doc> _result(_Target target, int version) {
    final Map<String, _Doc> docs = backend.at(version);
    final String? docId = target.docId;
    if (docId != null) {
      final _Doc? doc = docs[docId];
      return <String, _Doc>{docId: ?doc};
    }
    return <String, _Doc>{
      for (final MapEntry<String, _Doc> entry in docs.entries)
        if (entry.value.matches) entry.key: entry.value,
    };
  }

  Uint8List _token(int version) => Uint8List.fromList(utf8.encode('v$version'));

  /// A version at or after everything that was sent on the stream.
  int _pickVersion(int atLeast) {
    final List<int> candidates = <int>[
      for (final int v in backend.versions)
        if (v >= atLeast && v >= lastGlobal) v,
    ];
    return candidates.isEmpty || gen.chance(60)
        ? backend.latest
        : gen.pick(candidates);
  }

  Future<void> _acknowledgeTarget(_Target target) async {
    if (!target.acknowledged) {
      target.acknowledged = true;
      if (target.replaces) {
        await _send(
          WatchChangeWatchTargetChange(WatchTargetChangeType.removed, <int>[
            target.id,
          ]),
        );
      }
      await _send(
        WatchChangeWatchTargetChange(WatchTargetChangeType.added, <int>[
          target.id,
        ]),
      );
    }
  }

  /// Sends the changes of [target] up to [to].
  Future<void> sendChanges(_Target target, int to) async {
    await _acknowledgeTarget(target);
    final int? from = target.sentVersion;
    final Map<String, _Doc> before = from == null
        ? <String, _Doc>{}
        : _result(target, from);
    final Map<String, _Doc> after = _result(target, to);
    // A backend that resumes a target does not always send what left it.
    final bool omit = target.resumed && target.docId == null && gen.chance(50);
    final List<String> sent = <String>[];
    for (final MapEntry<String, _Doc> entry in after.entries) {
      if (before[entry.key]?.version != entry.value.version) {
        sent.add('${entry.key}@${entry.value.version}');
        await _send(
          WatchChangeDocumentChange(
            <int>[target.id],
            const <int>[],
            key('c/${entry.key}'),
            doc('c/${entry.key}', entry.value.version, entry.value.data),
          ),
        );
      }
    }
    for (final String docId in before.keys) {
      if (after.containsKey(docId)) {
        continue;
      }
      if (omit) {
        target.omittedRemovals = true;
        sent.add('(not: -$docId)');
        continue;
      }
      sent.add('-$docId');
      final _Doc? now = backend.at(to)[docId];
      await _send(
        WatchChangeDocumentChange(
          const <int>[],
          <int>[target.id],
          key('c/$docId'),
          now == null
              ? deletedDoc('c/$docId', to)
              : doc('c/$docId', now.version, now.data),
        ),
      );
    }
    target.sentVersion = to;
    log(
      'watch sends target ${target.id} up to $to: '
      '${sent.isEmpty ? 'nothing' : sent.join(', ')}',
    );
  }

  Future<void> sendFilter(_Target target) async {
    final int count = _result(target, target.sentVersion!).length;
    target.omittedRemovals = false;
    log('watch sends an existence filter for target ${target.id}: $count');
    await _send(
      WatchChangeExistenceFilterWatchChange(target.id, ExistenceFilter(count)),
    );
  }

  Future<void> makeCurrent(_Target target) async {
    if (target.sentVersion == null) {
      await sendChanges(target, _pickVersion(lastGlobal));
    }
    if (target.omittedRemovals || gen.chance(10)) {
      await sendFilter(target);
    }
    target.current = true;
    if (target.docId == null) {
      refillPending = false;
    }
    log('watch marks target ${target.id} CURRENT at ${target.sentVersion}');
    await _send(
      WatchChangeWatchTargetChange(WatchTargetChangeType.current, <int>[
        target.id,
      ], _token(target.sentVersion!)),
    );
  }

  /// A global snapshot at [at], or at a version that is at or after
  /// everything sent on the stream. The targets that are CURRENT get their
  /// changes up to it first.
  Future<void> globalSnapshot([int? at]) async {
    int atLeast = lastGlobal;
    for (final _Target target in targets.values) {
      final int? sent = target.sentVersion;
      if (sent != null && sent > atLeast && target.acknowledged) {
        atLeast = sent;
      }
    }
    final int snapshot = at ?? _pickVersion(atLeast);
    for (final _Target target in targets.values.toList()) {
      if (target.current) {
        await sendChanges(target, snapshot);
        if (target.omittedRemovals) {
          await sendFilter(target);
        }
      }
      // The resume token of the snapshot stands for what the client has of
      // each target. A target with removals left out keeps its older token:
      // resumed from that one, the removals are still due.
      final int? sent = target.sentVersion;
      if (target.acknowledged && sent != null && !target.omittedRemovals) {
        await _send(
          WatchChangeWatchTargetChange(WatchTargetChangeType.noChange, <int>[
            target.id,
          ], _token(sent)),
        );
      }
    }
    lastGlobal = snapshot;
    log('watch sends a global snapshot at $snapshot');
    await _send(
      WatchChangeWatchTargetChange(
        WatchTargetChangeType.noChange,
        const <int>[],
      ),
      snapshot,
    );
    await _settle();
    syncTargets();
  }

  /// Watch resets [target] and sends its documents again. Both are part of
  /// one snapshot of the backend: no global snapshot comes in between.
  Future<void> resetTarget(_Target target) async {
    await _acknowledgeTarget(target);
    final int to = _pickVersion(target.sentVersion ?? lastGlobal);
    target
      ..sentVersion = null
      ..current = false
      ..omittedRemovals = false;
    log('watch resets target ${target.id}');
    stats.resets++;
    await _send(
      WatchChangeWatchTargetChange(WatchTargetChangeType.reset, <int>[
        target.id,
      ]),
    );
    await sendChanges(target, to);
  }

  Future<void> closeStream() async {
    log('the watch stream closes');
    targets.clear();
    datastore.failWatchStream(GrpcError.unavailable('closed'));
    await _settle();
  }

  Future<void> reconnect() async {
    if (datastore.isWatchStreamInBackoff) {
      log('the watch stream reconnects');
      stats.reconnects++;
      datastore.runWatchStreamBackoff();
      await _settle();
    }
  }

  // ---------------------------------------------------------------- steps

  Future<void> step() async {
    final int choice = gen.below(100);
    if (choice < 22) {
      await userWrite();
    } else if (choice < 40) {
      await answerWrite(mayReject: true);
      await _settle();
    } else if (choice < 48) {
      otherClientWrite();
    } else if (!streamOpen) {
      await reconnect();
    } else if (choice < 54) {
      await closeStream();
      if (gen.chance(70)) {
        await reconnect();
      }
    } else if (targets.isEmpty) {
      return;
    } else {
      final _Target target = gen.pick(targets.values.toList());
      if (choice < 68) {
        await sendChanges(
          target,
          _pickVersion(target.sentVersion ?? lastGlobal),
        );
      } else if (choice < 80) {
        await makeCurrent(target);
      } else if (choice < 84) {
        await resetTarget(target);
      } else {
        await globalSnapshot();
      }
    }
    await _settle();
    syncTargets();
  }

  /// Whether the listener is in sync and shows the documents of the backend.
  List<String> differences() {
    final ViewSnapshot? snapshot = view;
    if (snapshot == null) {
      return <String>['the listener never got a snapshot'];
    }
    final List<String> result = <String>[
      if (snapshot.isFromCache) 'the listener is still from cache',
      if (snapshot.mutatedKeys.isNotEmpty)
        'the listener still has pending writes',
      if (limbo.isNotEmpty) 'still in limbo: $limbo',
    ];
    final Map<String, Object?> actual = <String, Object?>{
      for (final Document doc in snapshot.documents)
        doc.key.path.last: doc.getFieldValue(field('v')),
    };
    final Map<String, Object?> expected = <String, Object?>{
      for (final MapEntry<String, _Doc> entry
          in backend.at(backend.latest).entries)
        if (entry.value.matches) entry.key: entry.value.data['v'],
    };
    String sorted(Map<String, Object?> docs) =>
        (docs.entries.toList()..sort(
              (MapEntry<String, Object?> a, MapEntry<String, Object?> b) =>
                  a.key.compareTo(b.key),
            ))
            .map((MapEntry<String, Object?> e) => '${e.key}: ${e.value}')
            .join(', ');
    if (sorted(actual) != sorted(expected)) {
      result.add(
        'the listener has $actual (v by document), the backend $expected',
      );
    }
    return result;
  }

  /// Everything is answered and caught up: the writes, then every target up
  /// to the latest version and CURRENT, and a global snapshot; again while
  /// the client reacts with new targets (resets, limbo resolutions).
  Future<void> drain() async {
    log('drain');
    for (int round = 0; round < 12; round++) {
      while (datastore.writesSent > 0) {
        await answerWrite(mayReject: false);
        await _settle();
      }
      await reconnect();
      syncTargets();
      for (final _Target target in targets.values.toList()) {
        await sendChanges(target, backend.latest);
        await makeCurrent(target);
      }
      await globalSnapshot(backend.latest);
      await _settle();
      syncTargets();
      if (round > 0 && pending.isEmpty && differences().isEmpty) {
        break;
      }
    }
  }
}

/// Runs the interleaving of [seed] with [steps] steps on a new persistence;
/// returns the failures and the trace.
Future<(List<String>, List<String>)> _runSeed(
  int seed,
  int steps, {
  required bool sqlite,
  _Stats? stats,
}) async {
  final String name =
      'firebase/firestore/core/held_back_property_${const Uuid().v4()}';
  final Persistence persistence = sqlite
      ? await createSQLitePersistenceForProject('test-project', name)
      : await createLRUMemoryPersistence();
  final _Run run = _Run(seed, Gen(seed), stats ?? _Stats());
  try {
    await run.start(persistence);
    for (int i = 0; i < steps && run.violations.isEmpty; i++) {
      await run.step();
    }
    await run.drain();
    stats?.runs++;
    return (<String>[...run.violations, ...run.differences()], run.trace);
  } finally {
    await run.remoteStore.shutdown();
    await persistence.shutdown();
    if (sqlite) {
      DatabaseMock.deleteDatabaseFiles(name);
    }
  }
}

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
    final _Run run = _Run(0, Gen(0), _Stats());
    final Persistence persistence = await createLRUMemoryPersistence();
    try {
      await run.start(persistence);
      Future<void> current(_Target t) => run._send(
        WatchChangeWatchTargetChange(WatchTargetChangeType.current, <int>[
          t.id,
        ], run._token(t.sentVersion!)),
      );
      run.backend.change('d0', <String, Object?>{'m': true, 'v': 1});
      run.backend.change('d1', <String, Object?>{'m': true, 'v': 2});
      await run.sendChanges(run.main!, 3000);
      await current(run.main!);
      run.main!.current = true;
      await run.globalSnapshot(3000);
      // d1 is deleted while the stream is down; the resumed target gets an existence filter.
      await run.closeStream();
      run.backend.change('d1', null); // 4000
      await run.reconnect();
      run.syncTargets();
      await run._acknowledgeTarget(run.main!);
      run.main!.sentVersion = 4000;
      await run._send(
        WatchChangeExistenceFilterWatchChange(
          run.main!.id,
          const ExistenceFilter(1),
        ),
      );
      await current(run.main!);
      run.main!.current = true;
      await run.globalSnapshot(4000);
      // The client reset the target and watches it again; nothing is refilled yet.
      run.log('--- user write');
      run.pending.add(
        _Write('d0', 'set', <String, Object?>{'m': true, 'v': 3}),
      );
      final Completer<void> task = Completer<void>();
      await run.onQueue<void>(
        () => run.syncEngine.writeMutations(<Mutation>[
          setMutation('c/d0', <String, Object?>{'m': true, 'v': 3}),
        ], task),
      );
      await _settle();
      await run.answerWrite(mayReject: false); // 5000
      await _settle();
      run.syncTargets();
      run.log('--- limbo target answers before the refill');
      for (final _Target t in run.targets.values.toList()) {
        if (t.docId != null) {
          await run.sendChanges(t, 5000);
          await current(t);
        }
      }
      await run._send(
        WatchChangeWatchTargetChange(
          WatchTargetChangeType.noChange,
          const <int>[],
        ),
        5000,
      );
      await _settle();
      run.syncTargets();
      // d0 is still in the view: the target is not CURRENT yet, so the confirmation says nothing about it.
      expect(
        run.describeView(),
        '{d0: 3} from cache',
        reason: run.trace.join('\n'),
      );
      await run.drain();
      expect(run.differences(), isEmpty, reason: run.trace.join('\n'));
      expect(run.describeView(), '{d0: 3}');
      expect(
        run.violations.where((String v) => v.contains('removed')),
        isEmpty,
        reason: run.trace.join('\n'),
      );
    } finally {
      await run.remoteStore.shutdown();
      await persistence.shutdown();
    }
  });

  for (final bool sqlite in <bool>[false, true]) {
    test('held-back documents under watch reconnects, '
        '${sqlite ? 'SQLite' : 'memory'} persistence', () async {
      final _Stats stats = _Stats();
      for (int i = 0; i < cases(30); i++) {
        final int seed = caseSeed(i);
        final (List<String> failures, List<String> trace) = await _runSeed(
          seed,
          _steps,
          sqlite: sqlite,
          stats: stats,
        );
        if (failures.isEmpty) {
          continue;
        }
        // The shortest prefix of the same interleaving that still fails.
        int shortest = _steps;
        List<String> shortestFailures = failures;
        List<String> shortestTrace = trace;
        for (int n = 0; n < _steps; n++) {
          final (List<String> f, List<String> t) = await _runSeed(
            seed,
            n,
            sqlite: sqlite,
          );
          if (f.isNotEmpty) {
            shortest = n;
            shortestFailures = f;
            shortestTrace = t;
            break;
          }
        }
        fail(
          'Property "held-back documents under watch reconnects" failed.\n'
          '  seed: $seed (rerun with PROPERTY_SEED=$seed), '
          '${sqlite ? 'SQLite' : 'memory'} persistence, shortest failing '
          'prefix: $shortest of $_steps steps, then the drain\n'
          '  failures:\n${shortestFailures.map((String f) => '    $f\n').join()}'
          '  trace:\n${shortestTrace.map((String t) => '    $t\n').join()}',
        );
      }
      print('held-back property (${sqlite ? 'SQLite' : 'memory'}): $stats');
      // The interleavings must reach the cases the property is about.
      expect(stats.reconnects, greaterThan(0), reason: '$stats');
      expect(stats.limboResolutions, greaterThan(0), reason: '$stats');
      expect(stats.filterMismatches, greaterThan(0), reason: '$stats');
    }, timeout: Timeout(Duration(minutes: 2 + 2 * cases(1))));
  }
}

// The harness of the view property tests (held_back_view_property_test.dart
// and view_listeners_property_test.dart): one client, built like
// `FirestoreClient` builds it, against a fake backend that keeps every version
// of its documents and speaks the watch and write protocols through the mock
// datastore.
//
// The documents are `c/d0` ... with the fields `m` (a bool, the filter of
// some queries) and `v` (a number that is unique per write, the order of
// some queries).

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
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
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
import 'package:grpc/grpc.dart';
import 'package:rxdart/subjects.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/property.dart';
import '../../../../util/test_util.dart';
import '../local/mock/database_mock.dart';
import '../local/persistence_test_helpers.dart';
import '../remote/mock_datastore.dart';

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

Future<void> settle() async {
  // The mock streams deliver their events on timers.
  for (int i = 0; i < 3; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// A document of the fake backend.
class BackendDoc {
  BackendDoc(this.data, this.version);

  final Map<String, Object?> data;

  /// The version of its last change.
  final int version;

  bool get m => data['m'] == true;

  int get v => data['v']! as int;
}

/// A query of the properties: `c`, optionally `where m == true`, optionally
/// ordered by `v` with a limit (to first or to last).
class QuerySpec {
  QuerySpec(
    this.name, {
    this.onlyM = false,
    this.descending = false,
    this.limit,
    this.limitToLast = false,
  }) {
    Query query = Query(path('c'));
    if (onlyM) {
      query = query.filter(filter('m', '==', true));
    }
    if (limit != null) {
      query = query.orderBy(orderBy('v', descending ? 'desc' : 'asc'));
      query = limitToLast
          ? query.limitToLast(limit!)
          : query.limitToFirst(limit!);
    }
    this.query = query;
  }

  final String name;
  final bool onlyM;
  final bool descending;
  final int? limit;
  final bool limitToLast;
  late final Query query;

  bool matches(BackendDoc? doc) => doc != null && (!onlyM || doc.m);

  /// The ids of the result for [docs], in the order of the query.
  List<String> result(Map<String, BackendDoc> docs) {
    final List<String> ids = <String>[
      for (final MapEntry<String, BackendDoc> entry in docs.entries)
        if (matches(entry.value)) entry.key,
    ];
    final int? limit = this.limit;
    if (limit == null) {
      return ids..sort();
    }
    // By `v`, then by key, both in the direction of the order.
    ids.sort((String a, String b) {
      final int byV = docs[a]!.v.compareTo(docs[b]!.v);
      final int order = byV != 0 ? byV : a.compareTo(b);
      return descending ? -order : order;
    });
    if (ids.length <= limit) {
      return ids;
    }
    return limitToLast
        ? ids.sublist(ids.length - limit)
        : ids.sublist(0, limit);
  }

  @override
  String toString() => name;
}

/// The fake backend: every version of its documents.
class Backend {
  final List<(int, Map<String, BackendDoc>)> _history =
      <(int, Map<String, BackendDoc>)>[(1000, <String, BackendDoc>{})];

  int get latest => _history.last.$1;

  List<int> get versions => <int>[for (final (int v, _) in _history) v];

  /// The documents at [version].
  Map<String, BackendDoc> at(int version) => _history
      .lastWhere(((int, Map<String, BackendDoc>) s) => s.$1 <= version)
      .$2;

  /// Sets ([data]) or deletes (null) [id] at a new version, which is
  /// returned.
  int change(String id, Map<String, Object?>? data) {
    final int version = latest + 1000;
    final Map<String, BackendDoc> docs = Map<String, BackendDoc>.of(
      _history.last.$2,
    );
    if (data == null) {
      docs.remove(id);
    } else {
      docs[id] = BackendDoc(data, version);
    }
    _history.add((version, docs));
    return version;
  }

  /// Whether [id] existed and matched the filter of [spec] at every version
  /// from [since] on.
  bool matchedSince(QuerySpec spec, String id, int since) {
    for (final (int version, Map<String, BackendDoc> docs) in _history) {
      if (version >= since && !spec.matches(docs[id])) {
        return false;
      }
    }
    // The state at [since] itself (the last change at or before it).
    return spec.matches(at(since)[id]);
  }
}

/// A target of the client on the current watch stream, as the backend sees
/// it.
class WatchTarget {
  WatchTarget(
    this.id,
    this.spec,
    this.docId,
    this.sentVersion, {
    required this.resumed,
  });

  final int id;

  /// The query of the target, or null for a document target (a limbo
  /// resolution).
  final QuerySpec? spec;

  /// The document of a document target.
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
class PendingWrite {
  PendingWrite(this.id, this.kind, this.data);

  final String id;
  final String kind;
  final Map<String, Object?>? data;

  @override
  String toString() => '$kind($id${data == null ? '' : ', $data'})';
}

/// A listener of the client.
class Listener {
  Listener(this.number, this.spec, {required this.includeMetadata});

  final int number;
  final QuerySpec spec;
  final bool includeMetadata;
  late final QueryStream stream;
  late final StreamSubscription<ViewSnapshot> subscription;

  /// Its latest snapshot.
  ViewSnapshot? view;

  String get name =>
      'listener $number (${spec.name}${includeMetadata ? ', metadata changes' : ''})';

  /// The ids and `v` of its documents, in order.
  List<String> get documents => <String>[
    for (final Document doc in view?.documents ?? const <Document>[])
      '${doc.key.path.last}: ${doc.getFieldValue(field('v'))}',
  ];

  String describe() {
    final ViewSnapshot? snapshot = view;
    if (snapshot == null) {
      return 'none';
    }
    return '{${<String>[for (final Document doc in snapshot.documents) '${doc.key.path.last}: ${doc.getFieldValue(field('v'))}${doc.hasLocalMutations ? ' local' : ''}${doc.hasCommittedMutations ? ' committed' : ''}'].join(', ')}}'
        '${snapshot.isFromCache ? ' from cache' : ''}'
        '${snapshot.mutatedKeys.isEmpty ? '' : ' pending writes'}';
  }
}

/// What the interleavings did, over all seeds of a test.
class Stats {
  int runs = 0;
  int acknowledged = 0;
  int rejected = 0;
  int reconnects = 0;
  int resets = 0;
  int filterMismatches = 0;
  int limboResolutions = 0;
  int removals = 0;
  int snapshots = 0;
  int listenersAdded = 0;
  int listenersRemoved = 0;
  int sharedQueries = 0;

  @override
  String toString() =>
      '$runs interleavings, $acknowledged writes acknowledged, $rejected '
      'rejected, $reconnects watch reconnects, $resets target resets, '
      '$filterMismatches existence filter mismatches, $limboResolutions '
      'limbo resolutions, $snapshots snapshots, $removals documents removed '
      'from a view'
      '${listenersAdded == 0 ? '' : ', $listenersAdded listeners added '
                '($sharedQueries on a query that had one) and '
                '$listenersRemoved removed'}';
}

/// What a run does.
class RunConfig {
  const RunConfig({
    required this.queries,
    required this.documents,
    this.maxListeners = 1,
  });

  /// The queries of the listeners; the first listener uses the first one.
  final List<QuerySpec> queries;

  /// The number of documents.
  final int documents;

  /// With more than one, listeners are added and removed during the run,
  /// with and without metadata changes.
  final int maxListeners;

  bool get churn => maxListeners > 1;
}

/// One client and the fake backend, for one interleaving.
class ViewRun {
  ViewRun(this.seed, this.gen, this.stats, this.config);

  final Stats stats;
  final RunConfig config;
  final int seed;
  final Gen gen;

  late final Persistence persistence;
  late final SerialQueue queue;
  late final MockDatastore datastore;
  late final RemoteStore remoteStore;
  late final SyncEngine syncEngine;
  late final EventManager eventManager;

  final Backend backend = Backend();
  final Map<int, WatchTarget> targets = <int, WatchTarget>{};
  final List<PendingWrite> pending = <PendingWrite>[];
  final List<Listener> listeners = <Listener>[];
  final Set<String> limbo = <String>{};

  /// The client reset the target of a query for an existence filter mismatch
  /// and the target was not CURRENT since (also across reconnects of the
  /// stream).
  final Set<QuerySpec> refillPending = <QuerySpec>{};

  /// The documents that watch took out of the target of a query (a removal,
  /// a reset, or the reset of the client after an existence filter mismatch)
  /// and did not put back since.
  final Set<String> removedByWatch = <String>{};

  /// The documents that watch sent to the target of a query on the current
  /// stream: with several queries, one target can release a held-back
  /// document that another query shows too.
  final Set<String> sentOnStream = <String>{};
  int lastGlobal = 1000;

  /// The global snapshot before the one being delivered: a target that is
  /// not CURRENT can be behind the snapshot that raises its changes, but not
  /// behind the one before.
  int _removalFloor = 1000;

  /// The document of the write that the backend just rejected: the view
  /// goes back to what the cache has, which is nothing when watch has not
  /// delivered a document that another client created.
  String? _justRejected;
  int _counter = 0;
  int _listenerCount = 0;

  final List<String> trace = <String>[];
  final List<String> violations = <String>[];

  /// The only listener of a run without churn.
  Listener get listener => listeners.single;

  void log(String step) {
    trace.add(step);
    if (traceProperties) {
      print('TRACE seed $seed $step');
    }
  }

  String id(int i) => 'd$i';

  bool get streamOpen => datastore.isWatchStreamOpen;

  /// The targets of queries (not of limbo resolutions).
  Iterable<WatchTarget> get queryTargets =>
      targets.values.where((WatchTarget t) => t.spec != null);

  /// The target of the only query of a run with one query.
  WatchTarget? get main => queryTargets.isEmpty ? null : queryTargets.first;

  Future<T> onQueue<T>(Future<T> Function() task) => queue.run<T>(task);

  // ------------------------------------------------------------ the client

  Future<void> start(Persistence persistence) async {
    this.persistence = persistence;
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    final TaskScheduler scheduler = TaskScheduler('view-property-$seed');
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
    await addListener(config.queries.first, includeMetadata: true);
  }

  Future<void> shutdown() async {
    for (final Listener listener in listeners) {
      await listener.subscription.cancel();
    }
    await remoteStore.shutdown();
    await persistence.shutdown();
  }

  Future<void> addListener(
    QuerySpec spec, {
    required bool includeMetadata,
  }) async {
    final Listener listener = Listener(
      ++_listenerCount,
      spec,
      includeMetadata: includeMetadata,
    );
    if (listeners.any((Listener l) => l.spec == spec)) {
      stats.sharedQueries++;
    }
    listeners.add(listener);
    log('${listener.name} starts');
    listener.stream = QueryStream(
      spec.query,
      ListenOptions(
        includeDocumentMetadataChanges: includeMetadata,
        includeQueryMetadataChanges: includeMetadata,
      ),
    );
    listener.subscription = listener.stream.listen(
      (ViewSnapshot snapshot) => _onSnapshot(listener, snapshot),
    );
    await onQueue<int>(() => eventManager.addQueryListener(listener.stream));
    await settle();
  }

  Future<void> removeListener(Listener listener) async {
    log('${listener.name} stops');
    listeners.remove(listener);
    await onQueue<bool>(
      () => eventManager.removeQueryListener(listener.stream),
    );
    await listener.subscription.cancel();
    await settle();
  }

  bool _sameDocuments(
    Iterable<Document> a,
    Iterable<Document> b, {
    required bool metadata,
  }) {
    final List<Document> left = a.toList();
    final List<Document> right = b.toList();
    if (left.length != right.length) {
      return false;
    }
    for (int i = 0; i < left.length; i++) {
      final bool same = metadata
          ? left[i] == right[i]
          : left[i].key == right[i].key && left[i].data == right[i].data;
      if (!same) {
        return false;
      }
    }
    return true;
  }

  String _ids(Iterable<Document> docs) =>
      '[${docs.map((Document d) => '${d.key.path.last}: ${d.getFieldValue(field('v'))}').join(', ')}]';

  void _onSnapshot(Listener listener, ViewSnapshot snapshot) {
    stats.snapshots++;
    final ViewSnapshot? previous = listener.view;
    listener.view = snapshot;
    final List<String> changes = <String>[];

    // The snapshots form a sequence: this one starts from the documents of
    // the previous one, and its changes, applied in order, give its
    // documents. A listener without metadata changes is not told when only
    // the metadata of a document changes, so it is compared by key and data.
    final bool metadata = listener.includeMetadata;
    if (!_sameDocuments(
      previous?.documents ?? const <Document>[],
      snapshot.oldDocuments,
      metadata: metadata,
    )) {
      violations.add(
        '${listener.name}: a snapshot starts from '
        '${_ids(snapshot.oldDocuments)}, the previous one had '
        '${_ids(previous?.documents ?? const <Document>[])}',
      );
    }
    DocumentSet applied = snapshot.oldDocuments;
    for (final DocumentViewChange change in snapshot.changes) {
      final Document document = change.document;
      final String docId = document.key.path.last;
      changes.add('${change.type} $docId');
      final bool had = applied.getDocument(document.key) != null;
      if (change.type == DocumentViewChangeType.added) {
        if (had) {
          violations.add('${listener.name}: $docId was added twice');
        }
        applied = applied.add(document);
      } else if (change.type == DocumentViewChangeType.removed) {
        if (!had) {
          violations.add(
            '${listener.name}: $docId was removed but was not in the result',
          );
        }
        applied = applied.remove(document.key);
      } else {
        if (!had) {
          violations.add(
            '${listener.name}: $docId was modified but was not in the result',
          );
        }
        if (change.type == DocumentViewChangeType.metadata && !metadata) {
          violations.add(
            '${listener.name}: got a metadata change of $docId without '
            'asking for metadata changes',
          );
        }
        applied = applied.remove(document.key).add(document);
      }

      if (change.type != DocumentViewChangeType.removed) {
        continue;
      }
      stats.removals++;
      _checkRemoval(listener, docId);
    }
    if (!_sameDocuments(applied, snapshot.documents, metadata: metadata)) {
      violations.add(
        '${listener.name}: the changes (${changes.join(', ')}) applied to '
        '${_ids(snapshot.oldDocuments)} give ${_ids(applied)}, the snapshot '
        'has ${_ids(snapshot.documents)}',
      );
    }
    final int? limit = listener.spec.limit;
    if (limit != null && snapshot.documents.length > limit) {
      violations.add(
        '${listener.name}: the snapshot has ${snapshot.documents.length} '
        'documents, the limit is ${listener.spec.limit}',
      );
    }
    log(
      '    ${listener.name}: ${listener.describe()}'
      '${changes.isEmpty ? '' : ' (${changes.join(', ')})'}',
    );
  }

  /// A removal needs a reason: a write of the user to the document that is
  /// not answered yet or was just rejected, or a version of the backend,
  /// since the global snapshot before the last one, without the document.
  ///
  /// Not checked for a limit query: its window is computed from the cache,
  /// which mixes what watch sent with the acknowledged writes of the user,
  /// so a document can leave the window and come back. And with several
  /// queries only while the target of the query is CURRENT: a target that
  /// lags can deliver an older version of a document that another query
  /// shows.
  void _checkRemoval(Listener listener, String docId) {
    final QuerySpec spec = listener.spec;
    if (spec.limit != null) {
      return;
    }
    if (config.queries.length > 1 &&
        !queryTargets.any((WatchTarget t) => t.spec == spec && t.current)) {
      return;
    }
    if (docId != _justRejected &&
        pending.every((PendingWrite w) => w.id != docId) &&
        backend.matchedSince(spec, docId, _removalFloor)) {
      violations.add(
        '${listener.name}: $docId was removed although it has no pending '
        'write and the backend had it at every version since $_removalFloor',
      );
    }
  }

  void _onWatchQuery(QueryData queryData) {
    final String token = utf8.decode(queryData.resumeToken);
    final int? resumeVersion = token.isEmpty
        ? null
        : int.parse(token.substring(1));
    final String? docId = queryData.target.isDocumentQuery
        ? queryData.target.path.last
        : null;
    QuerySpec? spec;
    if (docId == null) {
      spec = config.queries.firstWhere(
        (QuerySpec s) =>
            s.query.toTarget().canonicalId == queryData.target.canonicalId,
      );
    }
    final bool replaces = targets.containsKey(queryData.targetId);
    targets[queryData.targetId] = WatchTarget(
      queryData.targetId,
      spec,
      docId,
      resumeVersion,
      resumed: resumeVersion != null,
    )..replaces = replaces;
    final bool mismatch =
        queryData.purpose == QueryPurpose.existenceFilterMismatch ||
        queryData.purpose == QueryPurpose.existenceFilterMismatchBloom;
    if (mismatch && spec != null) {
      refillPending.add(spec);
      // The reset of the client takes out what the target had; of those,
      // the documents that a view shows matter.
      for (final Listener listener in listeners) {
        if (listener.spec == spec) {
          removedByWatch.addAll(<String>[
            for (final Document doc
                in listener.view?.documents ?? const <Document>[])
              doc.key.path.last,
          ]);
        }
      }
    }
    log(
      '    the client watches target ${queryData.targetId} '
      '(${docId ?? spec}, ${queryData.purpose.name}'
      '${resumeVersion == null ? '' : ', resumed from $resumeVersion'})',
    );
    if (mismatch && replaces) {
      stats.filterMismatches++;
    }
    if (docId != null &&
        queryData.purpose == QueryPurpose.limboResolution &&
        limbo.add(docId)) {
      stats.limboResolutions++;
      _checkLimbo(docId);
    }
  }

  /// A held-back document (a view shows its local version although its
  /// writes are answered) only enters limbo when the target of a query is
  /// CURRENT on the current watch stream, or is being filled again after an
  /// existence filter mismatch (the reset took every document out of the
  /// target). Not for a limbo resolution that is only sent again after a
  /// reconnect. Any other document of a view that the target lacks is in
  /// limbo as in the other SDKs, where the view stays current across a
  /// reconnect.
  ///
  /// Also not for a document that watch took out of a target before: the
  /// view remembers that (`View._removedByWatch`, pinned by view_test.dart
  /// "a document that watch dropped before its write was acknowledged is in
  /// limbo after the acknowledgement"), also when the user wrote the
  /// document again afterwards, and puts it in limbo when that write is
  /// acknowledged. The resolution finds the document.
  void _checkLimbo(String docId) {
    final bool heldBack =
        pending.every((PendingWrite w) => w.id != docId) &&
        listeners.any(
          (Listener l) =>
              l.includeMetadata &&
              (l.view?.documents
                      .getDocument(key('c/$docId'))
                      ?.hasLocalMutations ??
                  false),
        );
    if (heldBack &&
        !removedByWatch.contains(docId) &&
        !sentOnStream.contains(docId) &&
        refillPending.isEmpty &&
        !queryTargets.any((WatchTarget t) => t.current)) {
      violations.add(
        'the held-back $docId entered limbo while no target of a query was '
        'CURRENT on the current watch stream',
      );
    }
  }

  /// Forgets the targets the client stopped watching; the backend confirms
  /// their removal.
  Future<void> syncTargets() async {
    if (!streamOpen) {
      return;
    }
    final Map<int, QueryData> active = datastore.activeTargets;
    for (final WatchTarget target in targets.values.toList()) {
      if (!active.containsKey(target.id)) {
        targets.remove(target.id);
        if (target.acknowledged && config.churn) {
          await send(
            WatchChangeWatchTargetChange(WatchTargetChangeType.removed, <int>[
              target.id,
            ]),
          );
        }
      }
    }
    limbo.removeWhere(
      (String docId) =>
          targets.values.every((WatchTarget t) => t.docId != docId),
    );
  }

  // --------------------------------------------------------------- writes

  Future<void> userWrite() async {
    final String docId = id(gen.below(config.documents));
    final PendingWrite write;
    final Mutation mutation;
    switch (gen.below(10)) {
      case 0 || 1 || 2 || 3 || 4:
        final Map<String, Object?> data = <String, Object?>{
          'm': gen.chance(75),
          'v': ++_counter,
        };
        write = PendingWrite(docId, 'set', data);
        mutation = setMutation('c/$docId', data);
      case 5 || 6 || 7:
        final Map<String, Object?> data = gen.chance(70)
            ? <String, Object?>{'v': ++_counter}
            : <String, Object?>{'m': gen.chance(50)};
        write = PendingWrite(docId, 'patch', data);
        mutation = patchMutation('c/$docId', data);
      default:
        write = PendingWrite(docId, 'delete', null);
        mutation = deleteMutation('c/$docId');
    }
    await writeMutation(write, mutation);
  }

  Future<void> writeMutation(PendingWrite write, Mutation mutation) async {
    pending.add(write);
    log('the user writes $write');
    final Completer<void> userTask = Completer<void>();
    // A rejected write completes its task with an error.
    unawaited(userTask.future.catchError((Object _) {}));
    await onQueue<void>(
      () => syncEngine.writeMutations(<Mutation>[mutation], userTask),
    );
    await settle();
  }

  /// The backend answers the oldest write the client sent: it applies and
  /// acknowledges it, or rejects it (always for a patch of a missing
  /// document; any write with [mayReject]).
  Future<void> answerWrite({required bool mayReject}) async {
    if (datastore.writesSent == 0) {
      return;
    }
    datastore.waitForWriteSend();
    final PendingWrite write = pending.removeAt(0);
    final BackendDoc? existing = backend.at(backend.latest)[write.id];
    final bool missing = write.kind == 'patch' && existing == null;
    if (missing || (mayReject && gen.chance(15))) {
      log('the backend rejects $write');
      stats.rejected++;
      _justRejected = write.id;
      await datastore.failWrite(
        missing
            ? GrpcError.notFound('no document to update')
            : GrpcError.permissionDenied('denied'),
      );
      await settle();
      _justRejected = null;
      return;
    }
    final int commit = backend.change(write.id, switch (write.kind) {
      'set' => write.data,
      'patch' => <String, Object?>{...existing!.data, ...write.data!},
      _ => null,
    });
    log('the backend applies $write at $commit');
    stats.acknowledged++;
    await datastore.ackWrite(version(commit), <MutationResult>[
      MutationResult(version(commit), const <FieldValue>[]),
    ]);
    await settle();
  }

  void otherClientWrite() {
    final String docId = id(gen.below(config.documents));
    final BackendDoc? existing = backend.at(backend.latest)[docId];
    final int choice = gen.below(10);
    if (choice < 3) {
      final int version = backend.change(docId, null);
      log('another client deletes $docId at $version');
      return;
    }
    final Map<String, Object?> data;
    if (existing != null && choice < 6) {
      // The document moves: in or out of a filter, or in the order.
      data = gen.chance(50)
          ? <String, Object?>{...existing.data, 'm': !existing.m}
          : <String, Object?>{...existing.data, 'v': ++_counter};
    } else {
      data = <String, Object?>{'m': gen.chance(75), 'v': ++_counter};
    }
    final int version = backend.change(docId, data);
    log('another client sets $docId to $data at $version');
  }

  // ---------------------------------------------------------------- watch

  Future<void> send(WatchChange change, [int? snapshotVersion]) =>
      datastore.writeWatchChange(
        change,
        snapshotVersion == null
            ? SnapshotVersion.none
            : version(snapshotVersion),
      );

  /// The documents of [target] at [version].
  Map<String, BackendDoc> _result(WatchTarget target, int version) {
    final Map<String, BackendDoc> docs = backend.at(version);
    final String? docId = target.docId;
    if (docId != null) {
      final BackendDoc? doc = docs[docId];
      return <String, BackendDoc>{docId: ?doc};
    }
    return <String, BackendDoc>{
      for (final String id in target.spec!.result(docs)) id: docs[id]!,
    };
  }

  Uint8List token(int version) => Uint8List.fromList(utf8.encode('v$version'));

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

  Future<void> acknowledgeTarget(WatchTarget target) async {
    if (!target.acknowledged) {
      target.acknowledged = true;
      if (target.replaces) {
        await send(
          WatchChangeWatchTargetChange(WatchTargetChangeType.removed, <int>[
            target.id,
          ]),
        );
      }
      await send(
        WatchChangeWatchTargetChange(WatchTargetChangeType.added, <int>[
          target.id,
        ]),
      );
    }
  }

  /// Sends the changes of [target] up to [to].
  Future<void> sendChanges(WatchTarget target, int to) async {
    await acknowledgeTarget(target);
    final int? from = target.sentVersion;
    final Map<String, BackendDoc> before = from == null
        ? <String, BackendDoc>{}
        : _result(target, from);
    final Map<String, BackendDoc> after = _result(target, to);
    // A backend that resumes a target does not always send what left it.
    final bool omit = target.resumed && target.docId == null && gen.chance(50);
    final List<String> sent = <String>[];
    for (final MapEntry<String, BackendDoc> entry in after.entries) {
      if (before[entry.key]?.version != entry.value.version) {
        sent.add('${entry.key}@${entry.value.version}');
        if (target.spec != null) {
          removedByWatch.remove(entry.key);
          sentOnStream.add(entry.key);
        }
        await send(
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
      if (target.spec != null) {
        removedByWatch.add(docId);
      }
      final BackendDoc? now = backend.at(to)[docId];
      await send(
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

  Future<void> sendFilter(WatchTarget target) async {
    final int count = _result(target, target.sentVersion!).length;
    target.omittedRemovals = false;
    log('watch sends an existence filter for target ${target.id}: $count');
    await send(
      WatchChangeExistenceFilterWatchChange(target.id, ExistenceFilter(count)),
    );
  }

  Future<void> makeCurrent(WatchTarget target) async {
    if (target.sentVersion == null) {
      await sendChanges(target, _pickVersion(lastGlobal));
    }
    if (target.omittedRemovals || gen.chance(10)) {
      await sendFilter(target);
    }
    await markCurrent(target);
  }

  /// CURRENT for [target], with the resume token of what was sent.
  Future<void> markCurrent(WatchTarget target) async {
    target.current = true;
    refillPending.remove(target.spec);
    log('watch marks target ${target.id} CURRENT at ${target.sentVersion}');
    await send(
      WatchChangeWatchTargetChange(WatchTargetChangeType.current, <int>[
        target.id,
      ], token(target.sentVersion!)),
    );
  }

  /// A global snapshot at [at], or at a version that is at or after
  /// everything sent on the stream. The targets that are CURRENT get their
  /// changes up to it first.
  Future<void> globalSnapshot([int? at]) async {
    int atLeast = lastGlobal;
    for (final WatchTarget target in targets.values) {
      final int? sent = target.sentVersion;
      if (sent != null && sent > atLeast && target.acknowledged) {
        atLeast = sent;
      }
    }
    final int snapshot = at ?? _pickVersion(atLeast);
    for (final WatchTarget target in targets.values.toList()) {
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
        await send(
          WatchChangeWatchTargetChange(WatchTargetChangeType.noChange, <int>[
            target.id,
          ], token(sent)),
        );
      }
    }
    lastGlobal = snapshot;
    log('watch sends a global snapshot at $snapshot');
    await send(
      WatchChangeWatchTargetChange(
        WatchTargetChangeType.noChange,
        const <int>[],
      ),
      snapshot,
    );
    await settle();
    _removalFloor = snapshot;
    await syncTargets();
  }

  /// Watch resets [target] and sends its documents again. Both are part of
  /// one snapshot of the backend: no global snapshot comes in between.
  Future<void> resetTarget(WatchTarget target) async {
    await acknowledgeTarget(target);
    final int to = _pickVersion(target.sentVersion ?? lastGlobal);
    final int? sent = target.sentVersion;
    if (target.spec != null && sent != null) {
      // The reset takes out what the target had.
      removedByWatch.addAll(_result(target, sent).keys);
    }
    target
      ..sentVersion = null
      ..current = false
      ..omittedRemovals = false;
    log('watch resets target ${target.id}');
    stats.resets++;
    await send(
      WatchChangeWatchTargetChange(WatchTargetChangeType.reset, <int>[
        target.id,
      ]),
    );
    await sendChanges(target, to);
  }

  Future<void> closeStream() async {
    log('the watch stream closes');
    targets.clear();
    sentOnStream.clear();
    datastore.failWatchStream(GrpcError.unavailable('closed'));
    await settle();
  }

  Future<void> reconnect() async {
    if (datastore.isWatchStreamInBackoff) {
      log('the watch stream reconnects');
      stats.reconnects++;
      datastore.runWatchStreamBackoff();
      await settle();
    }
  }

  // ---------------------------------------------------------------- steps

  Future<void> _changeListeners() async {
    if (listeners.length > 1 &&
        (listeners.length == config.maxListeners || gen.chance(45))) {
      stats.listenersRemoved++;
      await removeListener(gen.pick(listeners));
      return;
    }
    stats.listenersAdded++;
    // Often a query that already has a listener: they share target and view.
    final QuerySpec spec = gen.chance(35)
        ? gen.pick(listeners).spec
        : gen.pick(config.queries);
    await addListener(spec, includeMetadata: gen.chance(50));
  }

  Future<void> step() async {
    if (config.churn && gen.chance(10)) {
      await _changeListeners();
      await syncTargets();
      _checkSharedQueries();
      return;
    }
    final int choice = gen.below(100);
    if (choice < 22) {
      await userWrite();
    } else if (choice < 40) {
      await answerWrite(mayReject: true);
      await settle();
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
      final WatchTarget target = gen.pick(targets.values.toList());
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
    await settle();
    await syncTargets();
    _checkSharedQueries();
  }

  /// Listeners of one query share its view: they show the same documents. A
  /// listener that has no snapshot yet (an empty result from the cache is
  /// not raised) counts as empty.
  void _checkSharedQueries() {
    for (int i = 0; i < listeners.length; i++) {
      for (int j = i + 1; j < listeners.length; j++) {
        final Listener a = listeners[i];
        final Listener b = listeners[j];
        if (a.spec == b.spec &&
            a.documents.toString() != b.documents.toString()) {
          violations.add(
            '${a.name} has ${a.documents}, ${b.name} on the same query has '
            '${b.documents}',
          );
        }
      }
    }
  }

  /// What keeps the listeners from being in sync with the backend: every
  /// listener shows the result of its query on the backend, in order (for a
  /// limit query the first, or last, documents), not from cache and without
  /// pending writes.
  List<String> differences() {
    final List<String> result = <String>[
      if (limbo.isNotEmpty) 'still in limbo: $limbo',
    ];
    final Map<String, BackendDoc> docs = backend.at(backend.latest);
    for (final Listener listener in listeners) {
      final ViewSnapshot? snapshot = listener.view;
      if (snapshot == null) {
        result.add('${listener.name} never got a snapshot');
        continue;
      }
      // A listener without metadata changes is not told when the result
      // stops being from cache or having pending writes.
      if (listener.includeMetadata) {
        if (snapshot.isFromCache) {
          result.add('${listener.name} is still from cache');
        }
        if (snapshot.mutatedKeys.isNotEmpty) {
          result.add('${listener.name} still has pending writes');
        }
      }
      final List<String> expected = <String>[
        for (final String id in listener.spec.result(docs))
          '$id: ${docs[id]!.v}',
      ];
      if (listener.documents.toString() != expected.toString()) {
        result.add(
          '${listener.name} has ${listener.documents} (v by document), the '
          'backend $expected',
        );
      }
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
        await settle();
      }
      await reconnect();
      await syncTargets();
      for (final WatchTarget target in targets.values.toList()) {
        await sendChanges(target, backend.latest);
        await makeCurrent(target);
      }
      await globalSnapshot(backend.latest);
      await settle();
      await syncTargets();
      if (round > 0 && pending.isEmpty && differences().isEmpty) {
        break;
      }
    }
    _checkSharedQueries();
  }
}

/// Runs the interleaving of [seed] with [steps] steps on a new persistence;
/// returns the failures and the trace.
Future<(List<String>, List<String>)> runSeed(
  int seed,
  int steps,
  RunConfig config, {
  required bool sqlite,
  Stats? stats,
}) async {
  final String name =
      'firebase/firestore/core/view_property_${const Uuid().v4()}';
  final Persistence persistence = sqlite
      ? await createSQLitePersistenceForProject('test-project', name)
      : await createLRUMemoryPersistence();
  final ViewRun run = ViewRun(seed, Gen(seed), stats ?? Stats(), config);
  try {
    await run.start(persistence);
    for (int i = 0; i < steps && run.violations.isEmpty; i++) {
      await run.step();
    }
    await run.drain();
    stats?.runs++;
    return (<String>[...run.violations, ...run.differences()], run.trace);
  } finally {
    await run.shutdown();
    if (sqlite) {
      DatabaseMock.deleteDatabaseFiles(name);
    }
  }
}

/// Runs [count] interleavings of [steps] steps; on a failure, the message
/// has the seed, the shortest failing prefix and its trace.
Future<String?> runProperty(
  String property,
  RunConfig config, {
  required int count,
  required int steps,
  required bool sqlite,
  required Stats stats,
}) async {
  for (int i = 0; i < count; i++) {
    final int seed = caseSeed(i);
    final (List<String> failures, List<String> trace) = await runSeed(
      seed,
      steps,
      config,
      sqlite: sqlite,
      stats: stats,
    );
    if (failures.isEmpty) {
      continue;
    }
    // The shortest prefix of the same interleaving that still fails.
    int shortest = steps;
    List<String> shortestFailures = failures;
    List<String> shortestTrace = trace;
    for (int n = 0; n < steps; n++) {
      final (List<String> f, List<String> t) = await runSeed(
        seed,
        n,
        config,
        sqlite: sqlite,
      );
      if (f.isNotEmpty) {
        shortest = n;
        shortestFailures = f;
        shortestTrace = t;
        break;
      }
    }
    return 'Property "$property" failed.\n'
        '  seed: $seed (rerun with PROPERTY_SEED=$seed), '
        '${sqlite ? 'SQLite' : 'memory'} persistence, shortest failing '
        'prefix: $shortest of $steps steps, then the drain\n'
        '  failures:\n${shortestFailures.map((String f) => '    $f\n').join()}'
        '  trace:\n${shortestTrace.map((String t) => '    $t\n').join()}';
  }
  return null;
}

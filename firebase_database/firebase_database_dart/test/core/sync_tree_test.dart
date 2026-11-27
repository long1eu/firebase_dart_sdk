// Own tests of SyncTree (Android `core/SyncTree.java`, JS `core/SyncTree.ts`) for what
// syncPointSpec.json cannot show: persistence calls and transaction boundaries, keepSynced, tag
// bookkeeping, idempotent server data, pending writes as complete data, and exact ordering of
// integers above 2^53. Expectations follow the upstream code paths named in each test.
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/listen_provider.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/value_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/sync_tree.dart';
import 'package:firebase_database_dart/src/core/tag.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/util/server_values.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';
import 'package:test/test.dart';

Node n(Object? json) => nodeFromJson(json);
Path p(String path) => Path(path);

/// Records every persistence call, transaction boundaries included, into [log].
final class RecordingPersistenceManager implements PersistenceManager {
  RecordingPersistenceManager(this.log);

  final List<String> log;

  /// What [serverCache] returns.
  CacheNode cache = CacheNode(
    ChildrenNode.empty,
    fullyInitialized: false,
    filtered: false,
  );

  /// The nodes given to [applyUserWriteToServerCache].
  final List<Node> appliedWrites = <Node>[];

  bool _inside = false;

  void _record(String entry) {
    expect(_inside, isTrue, reason: '$entry outside a transaction');
    log.add(entry);
  }

  @override
  void saveUserOverwrite(Path path, Node node, WriteId writeId) =>
      _record('saveUserOverwrite $path $writeId');

  @override
  void saveUserMerge(Path path, CompoundWrite children, WriteId writeId) =>
      _record('saveUserMerge $path $writeId');

  @override
  void removeUserWrite(WriteId writeId) => _record('removeUserWrite $writeId');

  @override
  void removeAllUserWrites() => _record('removeAllUserWrites');

  @override
  void applyUserWriteToServerCache(Path path, Node node) {
    appliedWrites.add(node);
    _record('applyUserWriteToServerCache $path');
  }

  @override
  void applyUserMergeToServerCache(Path path, CompoundWrite merge) =>
      _record('applyUserMergeToServerCache $path');

  @override
  List<UserWriteRecord> loadUserWrites() => const <UserWriteRecord>[];

  @override
  CacheNode serverCache(QuerySpec query) {
    log.add('serverCache $query');
    return cache;
  }

  @override
  void updateServerCache(QuerySpec query, Node node) =>
      _record('updateServerCache $query');

  @override
  void updateServerCacheWithMerge(Path path, CompoundWrite children) =>
      _record('updateServerCacheWithMerge $path');

  @override
  void setQueryActive(QuerySpec query) => _record('setQueryActive $query');

  @override
  void setQueryInactive(QuerySpec query) => _record('setQueryInactive $query');

  @override
  void setQueryComplete(QuerySpec query) => _record('setQueryComplete $query');

  @override
  void setTrackedQueryKeys(QuerySpec query, Set<ChildKey> keys) => _record(
    'setTrackedQueryKeys $query ${keys.map((ChildKey k) => k.name).toList()}',
  );

  @override
  void updateTrackedQueryKeys(
    QuerySpec query,
    Set<ChildKey> added,
    Set<ChildKey> removed,
  ) => _record(
    'updateTrackedQueryKeys $query '
    '+${added.map((ChildKey k) => k.name).toList()} '
    '-${removed.map((ChildKey k) => k.name).toList()}',
  );

  @override
  bool get isDurable => true;

  @override
  T runInTransaction<T>(T Function() body) {
    expect(_inside, isFalse, reason: 'nested transaction');
    log.add('begin');
    _inside = true;
    try {
      return body();
    } finally {
      _inside = false;
      log.add('end');
    }
  }
}

/// Records starts and stops into the shared [log], keeping the arguments.
final class LoggingListenProvider implements ListenProvider {
  LoggingListenProvider(this.log);

  final List<String> log;

  final List<
    ({
      QuerySpec query,
      Tag? tag,
      ListenHashProvider hash,
      ListenCompletion onComplete,
    })
  >
  started =
      <
        ({
          QuerySpec query,
          Tag? tag,
          ListenHashProvider hash,
          ListenCompletion onComplete,
        })
      >[];

  final List<({QuerySpec query, Tag? tag})> stopped =
      <({QuerySpec query, Tag? tag})>[];

  @override
  List<Event> startListening(
    QuerySpec query,
    Tag? tag,
    ListenHashProvider hash,
    ListenCompletion onComplete,
  ) {
    log.add('start $query ${tag?.number}');
    started.add((query: query, tag: tag, hash: hash, onComplete: onComplete));
    return const <Event>[];
  }

  @override
  void stopListening(QuerySpec query, Tag? tag) {
    log.add('stop $query ${tag?.number}');
    stopped.add((query: query, tag: tag));
  }
}

/// A registration for every event type; registrations sharing a [token] are the same listener.
final class Reg extends EventRegistration {
  Reg(this.querySpec, [Object? token]) : token = token ?? Object();

  @override
  final QuerySpec querySpec;

  final Object token;

  @override
  bool respondsTo(EventType type) => true;

  @override
  DataEvent createEvent(Change change, QuerySpec query) => DataEvent(
    change.eventType,
    this,
    change.childKey == null || change.eventType == EventType.value
        ? query.path
        : query.path.child(change.childKey!),
    change.node,
    previousName: change.prevName,
  );

  @override
  void fireEvent(DataEvent event) {}

  @override
  void fireCancelEvent(DatabaseError error) {}

  @override
  EventRegistration clone(QuerySpec newQuery) => Reg(newQuery, token);

  @override
  bool isSameListener(EventRegistration other) =>
      other is Reg && identical(other.token, token);
}

List<Object?> valuesOf(List<Event> events) => <Object?>[
  for (final Event e in events)
    if (e is DataEvent && e.eventType == EventType.value) e.snapshot.toJson(),
];

void main() {
  late List<String> log;
  late RecordingPersistenceManager persistence;
  late LoggingListenProvider provider;
  late SyncTree tree;

  final QuerySpec defaultA = QuerySpec.defaultAt(p('a'));
  final QuerySpec firstA = QuerySpec(
    p('a'),
    QueryParams.defaultParams.limitToFirst(1),
  );
  final QuerySpec lastA = QuerySpec(
    p('a'),
    QueryParams.defaultParams.limitToLast(1),
  );

  setUp(() {
    log = <String>[];
    persistence = RecordingPersistenceManager(log);
    provider = LoggingListenProvider(log);
    tree = SyncTree(listenProvider: provider, persistenceManager: persistence);
  });

  group('persistence calls (Android SyncTree)', () {
    test('applyUserOverwrite saves the unresolved data when persisted', () {
      tree.applyUserOverwrite(
        p('a'),
        n(<String, Object?>{'.sv': 'timestamp'}),
        n(1),
        1,
        visible: true,
        persist: true,
      );
      tree.applyUserOverwrite(
        p('b'),
        n(2),
        n(2),
        2,
        visible: true,
        persist: false,
      );
      expect(log, <String>[
        'begin',
        'saveUserOverwrite /a 1',
        'end',
        'begin',
        'end',
      ]);
    });

    test('applyUserMerge saves the merge when persisted', () {
      final CompoundWrite merge = CompoundWrite.fromValue(<String, Object?>{
        'x': 1,
      });
      tree.applyUserMerge(p('a'), merge, merge, 1, persist: true);
      expect(log, <String>['begin', 'saveUserMerge /a 1', 'end']);
    });

    test('an ack removes the write and promotes it to the server cache in one '
        'transaction, with server values resolved', () {
      tree.applyUserOverwrite(
        p('a'),
        n(<String, Object?>{'.sv': 'timestamp'}),
        n(<String, Object?>{'.sv': 'timestamp'}),
        1,
        visible: true,
        persist: true,
      );
      log.clear();
      tree.ackUserWrite(
        1,
        revert: false,
        persist: true,
        serverValues: generateServerValues(timestamp: 42),
      );
      expect(log, <String>[
        'begin',
        'removeUserWrite 1',
        'applyUserWriteToServerCache /a',
        'end',
      ]);
      expect(persistence.appliedWrites.single.toJson(), 42);
    });

    test('an acked merge goes to applyUserMergeToServerCache', () {
      final CompoundWrite merge = CompoundWrite.fromValue(<String, Object?>{
        'x': 1,
      });
      tree.applyUserMerge(p('a'), merge, merge, 1, persist: true);
      log.clear();
      tree.ackUserWrite(
        1,
        revert: false,
        persist: true,
        serverValues: generateServerValues(timestamp: 0),
      );
      expect(log, <String>[
        'begin',
        'removeUserWrite 1',
        'applyUserMergeToServerCache /a',
        'end',
      ]);
    });

    test('a reverted write only leaves the log', () {
      tree.applyUserOverwrite(
        p('a'),
        n(1),
        n(1),
        1,
        visible: true,
        persist: true,
      );
      log.clear();
      tree.ackUserWrite(
        1,
        revert: true,
        persist: true,
        serverValues: generateServerValues(timestamp: 0),
      );
      expect(log, <String>['begin', 'removeUserWrite 1', 'end']);
    });

    test('removeAllWrites clears the persisted writes', () {
      tree.applyUserOverwrite(
        p('a'),
        n(1),
        n(1),
        1,
        visible: true,
        persist: true,
      );
      log.clear();
      tree.removeAllWrites();
      expect(log, <String>['begin', 'removeAllUserWrites', 'end']);
    });

    test('server data updates the server cache', () {
      tree.applyServerOverwrite(p('a'), n(1));
      tree.applyServerMerge(p('b'), <Path, Node>{p('c'): n(2)});
      tree.applyListenComplete(p('a'));
      // Nothing listens at /a or /b, so nothing is stored (decisions section 25 row 23): the empty
      // merge only counts the update for the prune check.
      expect(log, <String>[
        'begin',
        'updateServerCacheWithMerge /a',
        'end',
        'begin',
        'updateServerCacheWithMerge /b',
        'end',
        'begin',
        'setQueryComplete $defaultA',
        'end',
      ]);
    });

    test('a default listen: active, cache lookup, then the listen after the '
        'transaction', () {
      tree.addEventRegistration(Reg(defaultA));
      expect(log, <String>[
        'begin',
        'setQueryActive $defaultA',
        'serverCache $defaultA',
        'end',
        'start $defaultA null',
      ]);
    });

    test('a filtered listen tracks its keys; tagged data updates them', () {
      tree.addEventRegistration(Reg(firstA));
      expect(log, <String>[
        'begin',
        'setQueryActive $firstA',
        'serverCache $firstA',
        'setTrackedQueryKeys $firstA []',
        'end',
        'start $firstA 1',
      ]);
      log.clear();
      tree.applyTaggedQueryOverwrite(
        p('a'),
        n(<String, Object?>{'x': 1}),
        const Tag(1),
      );
      expect(log, <String>[
        'begin',
        'updateServerCache $firstA',
        'updateTrackedQueryKeys $firstA +[x] -[]',
        'end',
      ]);
      log.clear();
      tree.applyTaggedListenComplete(const Tag(1));
      expect(log, <String>['begin', 'setQueryComplete $firstA', 'end']);
    });

    test('a tagged overwrite below the query path caches the default query '
        'there; a tagged merge merges at the absolute path', () {
      tree.addEventRegistration(Reg(firstA));
      tree.applyTaggedQueryOverwrite(
        p('a'),
        n(<String, Object?>{'x': 1}),
        const Tag(1),
      );
      log.clear();
      tree.applyTaggedQueryOverwrite(p('a/x'), n(2), const Tag(1));
      tree.applyTaggedQueryMerge(p('a'), <Path, Node>{
        p('x'): n(3),
      }, const Tag(1));
      expect(log, <String>[
        'begin',
        'updateServerCache ${QuerySpec.defaultAt(p('a/x'))}',
        'end',
        'begin',
        'updateServerCacheWithMerge /a',
        'end',
      ]);
    });

    test('removing the last listener: inactive, then the stop', () {
      final Reg reg = Reg(defaultA);
      tree.addEventRegistration(reg);
      log.clear();
      tree.removeEventRegistration(reg);
      expect(log, <String>[
        'begin',
        'setQueryInactive $defaultA',
        'end',
        'stop $defaultA null',
      ]);
    });

    test('setQueryInactive is called for each removed query (iOS)', () {
      final Object token = Object();
      tree.addEventRegistration(Reg(firstA, token));
      tree.addEventRegistration(Reg(lastA, token));
      log.clear();
      tree.removeEventRegistration(Reg(defaultA, token));
      expect(log, <String>[
        'begin',
        'setQueryInactive $firstA',
        'setQueryInactive $lastA',
        'end',
        'stop $firstA 1',
        'stop $lastA 2',
      ]);
      expect(tree.isEmpty, isTrue);
    });

    test('a preloaded server cache replaces the persistence lookup', () {
      final List<Event> events = tree.addEventRegistration(
        Reg(defaultA),
        preloadedServerCache: CacheNode(
          n(<String, Object?>{'x': 1}),
          fullyInitialized: true,
          filtered: false,
        ),
      );
      expect(log, isNot(contains('serverCache $defaultA')));
      expect(valuesOf(events), <Object?>[
        <String, Object?>{'x': 1},
      ]);
    });

    test('a complete persisted cache gives the initial value', () {
      persistence.cache = CacheNode(
        n(<String, Object?>{'x': 1}),
        fullyInitialized: true,
        filtered: false,
      );
      expect(valuesOf(tree.addEventRegistration(Reg(defaultA))), <Object?>[
        <String, Object?>{'x': 1},
      ]);
    });

    test(
      'setQueryActive and setQueryInactive run in their own transaction',
      () {
        tree.setQueryActive(defaultA);
        tree.setQueryInactive(defaultA);
        expect(log, <String>[
          'begin',
          'setQueryActive $defaultA',
          'end',
          'begin',
          'setQueryInactive $defaultA',
          'end',
        ]);
      },
    );
  });

  group('keepSynced (Android SyncTree.keepSynced)', () {
    test('listens once without events and stops on release', () {
      tree.keepSynced(defaultA, keep: true);
      tree.keepSynced(defaultA, keep: true);
      expect(provider.started, hasLength(1));
      expect(provider.started.single.query, defaultA);
      expect(tree.applyServerOverwrite(p('a'), n(1)), isEmpty);
      tree.keepSynced(defaultA, keep: false);
      tree.keepSynced(defaultA, keep: false);
      expect(provider.stopped, hasLength(1));
      expect(tree.isEmpty, isTrue);
    });

    test('keeps the data cached for a later listener', () {
      tree.keepSynced(defaultA, keep: true);
      tree.applyServerOverwrite(p('a'), n(1));
      expect(valuesOf(tree.addEventRegistration(Reg(defaultA))), <Object?>[1]);
      // The view existed: no second listen.
      expect(provider.started, hasLength(1));
    });

    test('a user listener stays when keepSynced is released', () {
      final Reg reg = Reg(defaultA);
      tree.addEventRegistration(reg);
      tree.keepSynced(defaultA, keep: true);
      tree.keepSynced(defaultA, keep: false);
      expect(provider.stopped, isEmpty);
      expect(tree.isEmpty, isFalse);
    });

    test('registrations on the same query are equal', () {
      expect(
        KeepSyncedEventRegistration(defaultA),
        KeepSyncedEventRegistration(defaultA),
      );
      expect(
        KeepSyncedEventRegistration(defaultA).hashCode,
        KeepSyncedEventRegistration(defaultA).hashCode,
      );
      expect(
        KeepSyncedEventRegistration(defaultA),
        isNot(KeepSyncedEventRegistration(firstA)),
      );
    });
  });

  group('tags (Android SyncTree tagToQueryMap, queryToTagMap)', () {
    test('the tag given to the provider is tagForQuery; the default listen '
        'has none', () {
      tree.addEventRegistration(Reg(defaultA));
      tree.addEventRegistration(Reg(QuerySpec.defaultAt(p('b'))));
      tree.addEventRegistration(
        Reg(QuerySpec(p('c'), QueryParams.defaultParams.limitToFirst(2))),
      );
      for (final ({
            QuerySpec query,
            Tag? tag,
            ListenHashProvider hash,
            ListenCompletion onComplete,
          })
          s
          in provider.started) {
        expect(s.tag, tree.tagForQuery(s.query));
        expect(s.tag == null, s.query.isDefault);
      }
      expect(provider.started.last.tag, const Tag(1));
    });

    test('a tag lives until the last listener of its query goes', () {
      final Reg one = Reg(firstA);
      final Reg two = Reg(firstA);
      tree.addEventRegistration(one);
      tree.addEventRegistration(two);
      expect(provider.started, hasLength(1));
      tree.removeEventRegistration(one);
      expect(tree.tagForQuery(firstA), const Tag(1));
      tree.removeEventRegistration(two);
      expect(tree.tagForQuery(firstA), isNull);
      expect(provider.stopped.single.tag, const Tag(1));
      // queryForTag is gone too: data for the old tag is ignored.
      expect(
        tree.applyTaggedQueryOverwrite(p('a'), n(1), const Tag(1)),
        isEmpty,
      );
      expect(tree.applyTaggedListenComplete(const Tag(1)), isEmpty);
    });

    test('a new listen after removal gets a new tag', () {
      final Reg one = Reg(firstA);
      tree.addEventRegistration(one);
      tree.removeEventRegistration(one);
      tree.addEventRegistration(Reg(firstA));
      expect(tree.tagForQuery(firstA), const Tag(2));
      expect(provider.started.last.tag, const Tag(2));
    });

    test('a failed listen removes the registrations and the tag', () {
      tree.addEventRegistration(Reg(firstA));
      final List<Event> events = provider.started.single.onComplete(
        const DatabaseError(DatabaseErrorCode.permissionDenied, 'denied'),
      );
      expect(events.whereType<CancelEvent>(), hasLength(1));
      expect(tree.tagForQuery(firstA), isNull);
      // The provider already dropped a failed listen.
      expect(provider.stopped, isEmpty);
      expect(tree.isEmpty, isTrue);
    });
  });

  group('idempotent server data (emulator: overlapping listens)', () {
    test('the same overwrite twice raises nothing the second time', () {
      tree.addEventRegistration(Reg(defaultA));
      final Node data = n(<String, Object?>{'x': 1, 'y': 2});
      expect(tree.applyServerOverwrite(p('a'), data), isNotEmpty);
      expect(tree.applyServerOverwrite(p('a'), data), isEmpty);
    });

    test('the same merge twice raises nothing the second time', () {
      tree.addEventRegistration(Reg(defaultA));
      tree.applyServerOverwrite(p('a'), n(<String, Object?>{'x': 1}));
      final Map<Path, Node> merge = <Path, Node>{p('x'): n(2), p('y/z'): n(3)};
      expect(tree.applyServerMerge(p('a'), merge), isNotEmpty);
      expect(tree.applyServerMerge(p('a'), merge), isEmpty);
    });

    test('the same tagged overwrite twice raises nothing the second time', () {
      tree.addEventRegistration(Reg(firstA));
      final Node data = n(<String, Object?>{'x': 1});
      expect(
        tree.applyTaggedQueryOverwrite(p('a'), data, const Tag(1)),
        isNotEmpty,
      );
      expect(
        tree.applyTaggedQueryOverwrite(p('a'), data, const Tag(1)),
        isEmpty,
      );
    });
  });

  group('pending writes count as complete data (JS SyncTree.ts:646-657)', () {
    test('a new listener gets an unacknowledged write as its value', () {
      tree.applyUserOverwrite(
        p('a'),
        n(<String, Object?>{'x': 1}),
        n(<String, Object?>{'x': 1}),
        1,
        visible: true,
        persist: false,
      );
      expect(valuesOf(tree.addEventRegistration(Reg(defaultA))), <Object?>[
        <String, Object?>{'x': 1},
      ]);
    });

    test('a write above the listener covers it too', () {
      tree.applyUserOverwrite(
        Path.empty,
        n(<String, Object?>{
          'a': <String, Object?>{'x': 1},
        }),
        n(<String, Object?>{
          'a': <String, Object?>{'x': 1},
        }),
        1,
        visible: true,
        persist: false,
      );
      expect(valuesOf(tree.addEventRegistration(Reg(defaultA))), <Object?>[
        <String, Object?>{'x': 1},
      ]);
    });

    test('getServerValue answers from the pending write and leaves the tree '
        'empty', () {
      tree.applyUserOverwrite(
        p('a'),
        n(5),
        n(5),
        1,
        visible: true,
        persist: false,
      );
      expect(tree.getServerValue(defaultA)?.toJson(), 5);
      expect(tree.isEmpty, isTrue);
    });

    test('without data or writes there is no value event', () {
      expect(valuesOf(tree.addEventRegistration(Reg(defaultA))), isEmpty);
      expect(tree.getServerValue(defaultA), isNull);
    });
  });

  test(
    'orderByValue().limitToFirst(1) orders integers above 2^53 exactly',
    () {
      final int small = int.parse('9007199254740992');
      final int big = int.parse('9007199254740993');
      final QuerySpec query = QuerySpec(
        p('a'),
        QueryParams.defaultParams.orderBy(valueIndex).limitToFirst(1),
      );
      tree.addEventRegistration(Reg(query));
      final Tag tag = tree.tagForQuery(query)!;
      expect(provider.started.single.tag, tag);
      final List<Event> events = tree.applyTaggedQueryOverwrite(
        p('a'),
        n(<String, Object?>{'a': big, 'b': small}),
        tag,
      );
      expect(valuesOf(events), <Object?>[
        <String, Object?>{'b': small},
      ]);
    },
    testOn: '!js',
  );
}

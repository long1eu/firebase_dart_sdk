// A reverted write that a remaining pending write shadows (ViewProcessor.revertUserWrite). JS
// viewProcessorRevertUserWrite returns the view unchanged then, which is right for a write made
// after the reverted one but leaves the reverted data in the view when the shadowing write was
// made before it. Here the view takes what the write tree holds. Sequences from the SyncTree
// fuzzer of review 2 (rtdb/from_helper/reports/sync_tree_fuzz_classes.md, groups i and ii).
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/listen_provider.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/path_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/sync_tree.dart';
import 'package:firebase_database_dart/src/core/tag.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:test/test.dart';

/// Keeps the listens the tree starts so a test can answer them.
final class Provider implements ListenProvider {
  final List<({QuerySpec query, ListenCompletion onComplete})> started =
      <({QuerySpec query, ListenCompletion onComplete})>[];

  @override
  List<Event> startListening(
    QuerySpec query,
    Tag? tag,
    ListenHashProvider hash,
    ListenCompletion onComplete,
  ) {
    started.add((query: query, onComplete: onComplete));
    return const <Event>[];
  }

  @override
  void stopListening(QuerySpec query, Tag? tag) {}
}

/// A registration for every event type.
final class Reg extends EventRegistration {
  Reg(this.querySpec);

  @override
  final QuerySpec querySpec;

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
  EventRegistration clone(QuerySpec newQuery) => Reg(newQuery);

  @override
  bool isSameListener(EventRegistration other) => identical(other, this);
}

Node n(Object? json) => nodeFromJson(json);

/// The events as `V(json)`, `A(key)`, `R(key)`, `C(key)`; moves are left out.
List<String> describe(List<Event> events) => <String>[
  for (final Event e in events)
    if (e is DataEvent)
      switch (e.eventType) {
        EventType.value => 'V(${e.snapshot.toJson()})',
        EventType.childAdded => 'A(${e.snapshotPath.back})',
        EventType.childRemoved => 'R(${e.snapshotPath.back})',
        EventType.childChanged => 'C(${e.snapshotPath.back})',
        EventType.childMoved => '',
      },
].where((String s) => s.isNotEmpty).toList();

void main() {
  late Provider provider;
  late SyncTree tree;

  setUp(() {
    provider = Provider();
    tree = SyncTree(listenProvider: provider);
  });

  List<Event> set(String path, Object? value, int id) =>
      tree.applyUserOverwrite(
        Path(path),
        n(value),
        n(value),
        id,
        visible: true,
        persist: false,
      );

  List<Event> revert(int id) => tree.ackUserWrite(
    id,
    revert: true,
    persist: false,
    serverValues: const <String, Object?>{},
  );

  List<Event> listen(QuerySpec query) => tree.addEventRegistration(Reg(query));

  /// The server answers the listen at [query] with [value].
  List<Event> answer(QuerySpec query, Object? value) {
    final ({QuerySpec query, ListenCompletion onComplete}) s = provider.started
        .firstWhere(
          (({QuerySpec query, ListenCompletion onComplete}) s) =>
              s.query == query,
        );
    return <Event>[
      ...tree.applyServerOverwrite(query.path, n(value)),
      ...s.onComplete(null),
    ];
  }

  final QuerySpec atR = QuerySpec.defaultAt(Path('r'));
  final QuerySpec atRB = QuerySpec.defaultAt(Path('r/b'));

  group('group i: an earlier pending write shadows the reverted one', () {
    test('a revert at the path of an earlier pending set shows that set '
        '(listen not answered)', () {
      listen(atR);
      expect(describe(set('r', 0, 1)), <String>['V(0)']);
      expect(describe(set('r', 1, 2)), <String>['V(1)']);
      expect(describe(revert(2)), <String>['V(0)']);
    });

    test('a revert below an earlier pending set drops the reverted data', () {
      listen(atR);
      answer(atR, 1);
      set('r', <String, Object?>{'a': 1}, 1);
      set('r/b/c', 2, 2);
      expect(describe(revert(2)), <String>['R(b)', 'V({a: 1})']);
    });

    test(
      'a revert below an earlier pending set at the root, view below it',
      () {
        listen(atRB);
        set('', <String, Object?>{
          'r': <String, Object?>{'b': 1},
        }, 1);
        set('r/b/c', 2, 2);
        // The view held {c: 2}; the leaf 1 replaces it.
        expect(describe(revert(2)), <String>['R(c)', 'V(1)']);
      },
    );

    test('an orderByChild limitToFirst listener drops the reverted child '
        'and takes back the one it pushed out', () {
      final QuerySpec firstTwo = QuerySpec(
        Path('r'),
        QueryParams.defaultParams.orderBy(PathIndex(Path('v'))).limitToFirst(2),
      );
      listen(atR);
      answer(atR, <String, Object?>{
        'a': <String, Object?>{'v': 1},
      });
      listen(firstTwo);
      set('r', <String, Object?>{
        'a': <String, Object?>{'v': 5},
        'd': <String, Object?>{'v': 0},
      }, 1);
      set('r/e', <String, Object?>{'v': -1}, 2);
      final List<String> events = describe(revert(2));
      expect(events, containsAll(<String>['R(e)', 'A(a)']));
      expect(events.where((String e) => e.startsWith('V(')).toList(), <String>[
        'V({a: {v: 5}, d: {v: 0}})',
        'V({a: {v: 5}, d: {v: 0}})',
      ]);
    });
  });

  group('group ii: a later pending write still holds the view', () {
    test('refusing a set above a later pending set raises nothing and keeps '
        'the later value (listen not answered)', () {
      listen(atRB);
      set('r', <String, Object?>{'b': 1, 'c': 1}, 1);
      expect(describe(set('r/b', 5, 2)), <String>['V(5)']);
      expect(describe(revert(1)), isEmpty);
      expect(describe(answer(atRB, null)), isEmpty);
      expect(describe(listen(atRB)), <String>['V(5)']);
    });

    test('refusing a root delete under a later set at the view keeps that '
        'set (listen not answered)', () {
      listen(atR);
      set('', null, 1);
      expect(describe(set('r', 1, 2)), <String>['V(1)']);
      expect(describe(revert(1)), isEmpty);
      expect(describe(listen(atR)), <String>['V(1)']);
    });

    test('a merge refused under a later set at the view raises nothing', () {
      listen(atR);
      answer(atR, 3);
      tree.applyUserMerge(
        Path('r'),
        CompoundWrite.fromValue(<String, Object?>{'a': 1}),
        CompoundWrite.fromValue(<String, Object?>{'a': 1}),
        1,
        persist: false,
      );
      expect(describe(set('r', 7, 2)), <String>['R(a)', 'V(7)']);
      expect(describe(revert(1)), isEmpty);
    });
  });
}

// A refused (or reverted) write that emptied a prioritised node. The node keeps its priority
// while empty (ChildrenNode.keptPriority), so the revert that refills it shows the priority again:
// the listener, a new listener and the cache agree. JS loses it here (viewProcessorRevertUserWrite
// puts the child back without the priority; measured on the emulator,
// rtdb/from_helper/reports/sync_tree_fuzz_classes.md).
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/listen_provider.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/sync_tree.dart';
import 'package:firebase_database_dart/src/core/tag.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
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
        EventType.value => 'V(${e.snapshot.toJson(exportFormat: true)})',
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

  List<Event> update(String path, Map<String, Object?> children, int id) {
    final CompoundWrite merge = CompoundWrite.fromValue(children);
    return tree.applyUserMerge(Path(path), merge, merge, id, persist: false);
  }

  List<Event> refuse(int id) => tree.ackUserWrite(
    id,
    revert: true,
    persist: false,
    serverValues: const <String, Object?>{},
  );

  List<Event> listen(QuerySpec query) => tree.addEventRegistration(Reg(query));

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

  List<String> values(List<Event> events) =>
      describe(events).where((String e) => e.startsWith('V(')).toList();

  final QuerySpec atR = QuerySpec.defaultAt(Path('r'));

  group('a refused write that emptied a node gives its priority back', () {
    test('a refused deletion of the only child', () {
      listen(atR);
      answer(atR, <String, Object?>{'a': 1, '.priority': 2});
      expect(values(set('r/a', null, 1)), <String>['V(null)']);
      expect(values(refuse(1)), <String>['V({a: 1, .priority: 2})']);
      expect(values(listen(atR)), <String>['V({a: 1, .priority: 2})']);
    });

    test('a refused update that deleted the only child', () {
      listen(atR);
      answer(atR, <String, Object?>{
        'a': <String, Object?>{'v': 1},
        '.priority': 0,
      });
      update('r', <String, Object?>{'a/v': null}, 1);
      expect(values(refuse(1)), <String>['V({a: {v: 1}, .priority: 0})']);
    });

    test('a node below the view root', () {
      listen(atR);
      answer(atR, <String, Object?>{
        'x': <String, Object?>{'a': 1, '.priority': 2},
      });
      set('r/x/a', null, 1);
      expect(values(refuse(1)), <String>['V({x: {a: 1, .priority: 2}})']);
    });

    test('a refused deletion under an earlier pending write keeps that '
        "write's priority", () {
      listen(atR);
      answer(atR, null);
      set('r', <String, Object?>{'a': 1, '.priority': 3}, 1);
      set('r/a', null, 2);
      expect(values(refuse(2)), <String>['V({a: 1, .priority: 3})']);
    });
  });
}

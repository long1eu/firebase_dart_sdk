// A node emptied and refilled keeps its priority, as the server keeps it (production,
// rtdb/from_boss/prodkit_production_run3_2026-11-25.txt check 38, and run 2 check 22): one update
// (local, or the server's merge) that deletes the children of a node and adds others, two
// separate writes, writes layered in the write tree, and the three forms measured on production
// at the node, one level up and at the root. JS applies the children one by one and an empty node
// drops its priority, also in the server cache.
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/listen_provider.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
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

  List<Event> serverMerge(String path, Map<String, Object?> children) =>
      tree.applyServerMerge(Path(path), <Path, Node>{
        for (final MapEntry<String, Object?> e in children.entries)
          Path(e.key): nodeFromServerJson(e.value),
      });

  List<Event> serverSet(String path, Object? value) =>
      tree.applyServerOverwrite(Path(path), nodeFromServerJson(value));

  List<Event> ack(int id) => tree.ackUserWrite(
    id,
    revert: false,
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
      ...tree.applyServerOverwrite(query.path, nodeFromServerJson(value)),
      ...s.onComplete(null),
    ];
  }

  List<String> values(List<Event> events) =>
      describe(events).where((String e) => e.startsWith('V(')).toList();

  final QuerySpec atR = QuerySpec.defaultAt(Path('r'));
  final Map<String, Object?> prioritised = <String, Object?>{
    'a': 1,
    '.priority': 1,
  };

  group('one update that empties and refills a node keeps its priority', () {
    test('a local update', () {
      listen(atR);
      answer(atR, prioritised);
      expect(
        values(update('r', <String, Object?>{'a': null, 'b': 1}, 1)),
        <String>['V({b: 1, .priority: 1})'],
      );
    });

    test('the server merge another client sent', () {
      listen(atR);
      answer(atR, prioritised);
      expect(
        values(serverMerge('r', <String, Object?>{'a': null, 'b': 1})),
        <String>['V({b: 1, .priority: 1})'],
      );
      expect(describe(listen(atR)), <String>[
        'A(b)',
        'V({b: 1, .priority: 1})',
      ]);
    });

    test('the writer: local update, the server merge, the ack', () {
      listen(atR);
      answer(atR, prioritised);
      update('r', <String, Object?>{'a': null, 'b': 1}, 1);
      expect(
        values(serverMerge('r', <String, Object?>{'a': null, 'b': 1})),
        isEmpty,
      );
      expect(values(ack(1)), isEmpty);
      expect(values(listen(atR)), <String>['V({b: 1, .priority: 1})']);
    });

    test(
      'an update folded into an earlier pending set (listen not answered)',
      () {
        listen(atR);
        set('r', <String, Object?>{
          'a': <String, Object?>{'v': 1},
          '.priority': 0,
        }, 1);
        expect(
          values(update('r', <String, Object?>{'a': null, 'c': 1}, 2)),
          <String>['V({c: 1, .priority: 0})'],
        );
        expect(values(listen(atR)), <String>['V({c: 1, .priority: 0})']);
      },
    );

    test('a node below the view root, local and from the server', () {
      listen(atR);
      answer(atR, <String, Object?>{
        'x': <String, Object?>{'a': 1, '.priority': 2},
        'y': <String, Object?>{'a': 1, '.priority': 3},
      });
      expect(
        values(update('r/x', <String, Object?>{'a': null, 'b': 1}, 1)),
        <String>['V({x: {b: 1, .priority: 2}, y: {a: 1, .priority: 3}})'],
      );
      expect(
        values(serverMerge('r/y', <String, Object?>{'a': null, 'b': 1})),
        <String>['V({x: {b: 1, .priority: 2}, y: {b: 1, .priority: 3}})'],
      );
    });

    test('an update that only deletes leaves no node and no priority', () {
      listen(atR);
      answer(atR, prioritised);
      expect(values(update('r', <String, Object?>{'a': null}, 1)), <String>[
        'V(null)',
      ]);
      expect(values(serverMerge('r', <String, Object?>{'a': null})), isEmpty);
    });

    test('an update that writes the priority itself sets that priority', () {
      listen(atR);
      answer(atR, prioritised);
      expect(
        values(
          update('r', <String, Object?>{'a': null, 'b': 1, '.priority': 5}, 1),
        ),
        <String>['V({b: 1, .priority: 5})'],
      );
    });
  });

  test('two pending writes layered when the listen is answered, both orders', () {
    // set r/d 1 then set r/b null, or the reverse: the write tree holds both as one layered
    // tree {b: null, d: 1}. The node keeps its priority either way, as the server does.
    for (final bool deleteFirst in <bool>[false, true]) {
      provider = Provider();
      tree = SyncTree(listenProvider: provider);
      if (deleteFirst) {
        set('r/b', null, 1);
        set('r/d', 1, 2);
      } else {
        set('r/d', 1, 1);
        set('r/b', null, 2);
      }
      listen(atR);
      expect(
        values(answer(atR, <String, Object?>{'b': 1, '.priority': 1})),
        <String>['V({d: 1, .priority: 1})'],
        reason: deleteFirst ? 'delete first' : 'add first',
      );
    }
  });

  group('the production forms (check 38, check 22): event sequences', () {
    // n = {a: 1, .priority: 1} at p/n; a listener at the node, one level up, and the root. Each
    // form runs the local writes, the server's echoes as forwarded to the listen, then the acks.
    final QuerySpec atN = QuerySpec.defaultAt(Path('p/n'));
    final QuerySpec atP = QuerySpec.defaultAt(Path('p'));
    final QuerySpec atRoot = QuerySpec.defaultAt(Path(''));
    final Map<String, Object?> root = <String, Object?>{
      'p': <String, Object?>{
        'n': <String, Object?>{'a': 1, '.priority': 1},
      },
    };

    /// Listens at [q], answers with the server's data at its path; returns the value events.
    List<String> start(QuerySpec q) {
      final List<String> seen = values(listen(q));
      Object? data = root;
      for (final String key in q.path.segments.map((k) => k.name)) {
        data = (data! as Map<String, Object?>)[key];
      }
      seen.addAll(values(answer(q, data)));
      return seen;
    }

    String wrap(QuerySpec q, String nodeJson) => switch (q.path.length) {
      2 => nodeJson,
      1 => '{n: $nodeJson}',
      _ => '{p: {n: $nodeJson}}',
    };

    for (final QuerySpec q in <QuerySpec>[atN, atP, atRoot]) {
      test('update {a: null, b: 1} at ${q.path}', () {
        final List<String> seen = start(q)
          ..addAll(
            values(update('p/n', <String, Object?>{'a': null, 'b': 1}, 1)),
          )
          ..addAll(
            values(serverMerge('p/n', <String, Object?>{'a': null, 'b': 1})),
          )
          ..addAll(values(ack(1)));
        expect(seen, <String>[
          'V(${wrap(q, '{a: 1, .priority: 1}')})',
          'V(${wrap(q, '{b: 1, .priority: 1}')})',
        ]);
        expect(values(listen(q)), <String>[
          'V(${wrap(q, '{b: 1, .priority: 1}')})',
        ]);
      });

      test('two writes (set a null, set b 1) at ${q.path}', () {
        final List<String> seen = start(q)
          ..addAll(values(set('p/n/a', null, 1)))
          ..addAll(values(set('p/n/b', 1, 2)))
          ..addAll(values(serverSet('p/n/a', null)))
          ..addAll(values(serverSet('p/n/b', 1)))
          ..addAll(values(ack(1)))
          ..addAll(values(ack(2)));
        expect(seen, <String>[
          'V(${wrap(q, '{a: 1, .priority: 1}')})',
          'V(null)',
          'V(${wrap(q, '{b: 1, .priority: 1}')})',
        ]);
        expect(values(listen(q)), <String>[
          'V(${wrap(q, '{b: 1, .priority: 1}')})',
        ]);
      });

      test('update {a: null, .priority: 7}, then a child at ${q.path}', () {
        final List<String> seen = start(q)
          ..addAll(
            values(
              update('p/n', <String, Object?>{'a': null, '.priority': 7}, 1),
            ),
          )
          ..addAll(
            values(
              serverMerge('p/n', <String, Object?>{'a': null, '.priority': 7}),
            ),
          )
          ..addAll(values(ack(1)))
          ..addAll(values(set('p/n/b', 1, 2)));
        expect(seen, <String>[
          'V(${wrap(q, '{a: 1, .priority: 1}')})',
          'V(null)',
          'V(${wrap(q, '{b: 1, .priority: 7}')})',
        ]);
      });

      test('setPriority on the emptied node, then a child at ${q.path}', () {
        final List<String> seen = start(q)
          ..addAll(values(set('p/n/a', null, 1)))
          ..addAll(values(set('p/n/.priority', 9, 2)))
          ..addAll(values(serverSet('p/n/a', null)))
          ..addAll(values(serverSet('p/n/.priority', 9)))
          ..addAll(values(ack(1)))
          ..addAll(values(ack(2)))
          ..addAll(values(set('p/n/b', 1, 3)));
        expect(seen, <String>[
          'V(${wrap(q, '{a: 1, .priority: 1}')})',
          'V(null)',
          'V(${wrap(q, '{b: 1, .priority: 9}')})',
        ]);
      });

      test(
        'set(n, null) then a child: the priority stays gone at ${q.path}',
        () {
          final List<String> seen = start(q)
            ..addAll(values(set('p/n', null, 1)))
            ..addAll(values(set('p/n/b', 1, 2)))
            ..addAll(values(serverSet('p/n', null)))
            ..addAll(values(serverSet('p/n/b', 1)))
            ..addAll(values(ack(1)))
            ..addAll(values(ack(2)));
          expect(seen, <String>[
            'V(${wrap(q, '{a: 1, .priority: 1}')})',
            'V(null)',
            'V(${wrap(q, '{b: 1}')})',
          ]);
        },
      );
    }

    test('a listen answer carrying {".priority": 5} for the emptied node', () {
      // Check 38 (a): the parent's listen answers {"n": {".priority": 5.0}}.
      listen(atP);
      expect(
        values(
          answer(atP, <String, Object?>{
            'n': <String, Object?>{'.priority': 5.0},
          }),
        ),
        <String>['V(null)'],
      );
      expect(
        tree.calcCompleteEventCache(Path('p/n'))!.hash(),
        nodeFromServerJson(<String, Object?>{'.priority': 5}).hash(),
      );
      expect(values(set('p/n/b', 1, 1)), <String>[
        // 5.0 prints as 5.0 on the VM and as 5 on the web: render it the same way.
        'V({n: {b: 1, .priority: ${5.0}}})',
      ]);
      expect(
        (tree.calcCompleteEventCache(Path('p'))! as ChildrenNode)
            .toServerJson(),
        <String, Object?>{
          'n': <String, Object?>{'b': 1, '.priority': 5.0},
        },
      );
    });
  });

  group('an emptied child under priority order and a limit', () {
    // r: a, b, c with priorities 1, 2, 3; b is emptied (it keeps 2), given priority 0 while
    // empty, then refilled.
    final QuerySpec limit = QuerySpec(
      Path('r'),
      QueryParams.defaultParams.orderBy(priorityIndex).limitToFirst(2),
    );
    final QuerySpec byPriority = QuerySpec(
      Path('r'),
      QueryParams.defaultParams.orderBy(priorityIndex),
    );

    final Reg limitReg = Reg(limit);
    // A query by priority without limits shares the default view; its own registration.
    final Reg priorityReg = Reg(byPriority);

    List<String> of(Reg reg, List<Event> events) => describe(<Event>[
      for (final Event e in events)
        if (e is DataEvent && identical(e.eventRegistration, reg)) e,
    ]);

    test('is no window member and raises nothing until refilled', () {
      listen(atR);
      answer(atR, <String, Object?>{
        'a': <String, Object?>{'x': 1, '.priority': 1},
        'b': <String, Object?>{'x': 1, '.priority': 2},
        'c': <String, Object?>{'x': 1, '.priority': 3},
      });
      tree
        ..addEventRegistration(limitReg)
        ..addEventRegistration(priorityReg);
      final List<Event> emptied = set('r/b/x', null, 1);
      expect(of(limitReg, emptied), <String>[
        'R(b)',
        'A(c)',
        'V({a: {x: 1, .priority: 1}, c: {x: 1, .priority: 3}})',
      ]);
      expect(of(priorityReg, emptied), <String>[
        'R(b)',
        'V({a: {x: 1, .priority: 1}, c: {x: 1, .priority: 3}})',
      ]);
      final List<Event> prioritised = set('r/b/.priority', 0, 2);
      expect(of(limitReg, prioritised), isEmpty);
      expect(of(priorityReg, prioritised), isEmpty);
      final List<Event> refilled = set('r/b/x', 2, 3);
      expect(of(limitReg, refilled), <String>[
        'R(c)',
        'A(b)',
        'V({b: {x: 2, .priority: 0}, a: {x: 1, .priority: 1}})',
      ]);
      expect(of(priorityReg, refilled), <String>[
        'A(b)',
        'V({b: {x: 2, .priority: 0}, a: {x: 1, .priority: 1}, '
            'c: {x: 1, .priority: 3}})',
      ]);
    });
  });

  group('a server priority on a node a pending write empties', () {
    // The event cache holds the node empty only because of a pending write; the server node took
    // the priority (it had a value then) and keeps it when that write empties it. The event cache
    // is rebuilt from the writes over the server cache, so the refill shows the priority.
    ChildrenNode eventAt(QuerySpec q) =>
        tree.syncPointTree.get(q.path)!.viewForQuery(q)!.eventCache
            as ChildrenNode;

    final Map<String, Object?> start = <String, Object?>{
      'p': <String, Object?>{
        'n': <String, Object?>{'a': 1},
        'z': 1,
      },
    };
    for (final String at in <String>['p/n', 'p', '']) {
      test('another client prioritises n while set n/a null is pending, '
          'listener at /$at', () {
        final QuerySpec q = QuerySpec.defaultAt(Path(at));
        Object? data = start;
        for (final String k
            in at.split('/').where((String k) => k.isNotEmpty)) {
          data = (data! as Map<String, Object?>)[k];
        }
        listen(q);
        answer(q, data);
        set('p/n/a', null, 1);
        serverSet('p/n/.priority', 2);
        set('p/n/b', 1, 2);
        serverSet('p/n/a', null);
        ack(1);
        serverSet('p/n/b', 1);
        ack(2);
        final Object? n = eventAt(q).toServerJson();
        Object? got = n;
        for (final String k
            in 'p/n'
                .substring(at.length)
                .split('/')
                .where((k) => k.isNotEmpty)) {
          got = (got! as Map<String, Object?>)[k];
        }
        expect(got, <String, Object?>{'b': 1, '.priority': 2});
        expect(tree.calcCompleteEventCache(Path('p/n'))!.priority.value, 2);
      });
    }

    test('A1b: the hidden form, last ack on another path', () {
      final QuerySpec atRoot = QuerySpec.defaultAt(Path(''));
      listen(atRoot);
      answer(atRoot, <String, Object?>{
        'a': 1,
        'b': <String, Object?>{
          'k': 1,
          'x': <String, Object?>{'v': 2},
        },
      });
      set('b/x/v', null, 3);
      set('z', 1, 4);
      serverSet('b/x/.priority', 1);
      serverSet('b/x/v', null);
      ack(3);
      serverSet('z', 1);
      ack(4);
      expect(
        eventAt(atRoot).hash(),
        tree.syncPointTree
            .get(Path.empty)!
            .viewForQuery(atRoot)!
            .serverCache
            .hash(),
      );
      expect(values(set('b/x/y', 1, 5)), <String>[
        'V({a: 1, b: {k: 1, x: {y: 1, .priority: 1}}, z: 1})',
      ]);
    });

    test('seed 77640: a child added, a priority, the child removed', () {
      final QuerySpec atA = QuerySpec.defaultAt(Path('a'));
      final QuerySpec atRoot = QuerySpec.defaultAt(Path(''));
      set('', null, 1);
      listen(atA);
      listen(atRoot);
      update('a', <String, Object?>{
        'x': <String, Object?>{'u': 3, 'v': 2},
      }, 2);
      update('', <String, Object?>{'a/.priority': 3}, 3);
      set('a/x', null, 4);
      ack(1);
      answer(atA, null);
      answer(atRoot, null);
      serverMerge('a', <String, Object?>{
        'x': <String, Object?>{'u': 3, 'v': 2},
      });
      ack(2);
      serverMerge('', <String, Object?>{'a/.priority': 3});
      ack(3);
      serverSet('a/x', null);
      ack(4);
      expect(eventAt(atA).toServerJson(), <String, Object?>{'.priority': 3});
      expect(values(set('a/y', 1, 5)), <String>[
        'V({y: 1, .priority: 3})',
        'V({a: {y: 1, .priority: 3}})',
      ]);
    });

    test(
      'seed 24434: another client prioritises a node this client empties',
      () {
        final QuerySpec atRoot = QuerySpec.defaultAt(Path(''));
        set('b', null, 1);
        listen(atRoot);
        set('b/x', <String, Object?>{'v': 2}, 2);
        ack(1);
        answer(atRoot, <String, Object?>{'a': 1});
        serverSet('b/x', <String, Object?>{'v': 2});
        ack(2);
        set('b/x', null, 3);
        serverSet('b/.priority', 1);
        serverSet('b/x', null);
        ack(3);
        expect(eventAt(atRoot).toServerJson(), <String, Object?>{
          'a': 1,
          'b': <String, Object?>{'.priority': 1},
        });
        expect(values(set('b/y', 1, 4)), <String>[
          'V({a: 1, b: {y: 1, .priority: 1}})',
        ]);
      },
    );
  });
}

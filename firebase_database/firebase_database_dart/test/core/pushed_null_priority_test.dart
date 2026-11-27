// A server push of null at a `.priority` path. The Database emulator pushes
// {"t":"d","d":{"b":{"p":"r/x/.priority","d":null},"a":"d"}} to a listener at r after every
// accepted set of a null priority at r/x, also when x is missing or has no priority; production
// pushes it only when the write changed something (production kit check 40, measured by the lead
// on 2026-11-26). The client must take the frame in each case.
//
// The frame is decoded by decodeServerMessage (the `.priority` segment is accepted as the last
// one), Repo turns the path into a Path unchanged, and the `.priority` segment is handled in the
// sync tree's view processor. The tests below follow it at each of these levels.
//
// Not covered: a node emptied but keeping its priority (the emulator's b5 case). The trunk's node
// model cannot hold one: nodeFromJson gives ChildrenNode.empty for a value without children, and
// ChildrenNode.updatePriority keeps no priority on an empty node.
import 'dart:convert';

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
import 'package:firebase_database_dart/src/realtime/server_message.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

import 'repo_harness.dart';

Node n(Object? json) => nodeFromJson(json);
Path p(String path) => Path(path);

/// [node] in the export form (priorities shown), or `missing` for null.
String export(Node? node) =>
    node == null ? 'missing' : jsonEncode(node.toJson(exportFormat: true));

/// A listen provider that only accepts listens.
final class _Listens implements ListenProvider {
  @override
  List<Event> startListening(
    QuerySpec query,
    Tag? tag,
    ListenHashProvider hash,
    ListenCompletion onComplete,
  ) => const <Event>[];

  @override
  void stopListening(QuerySpec query, Tag? tag) {}
}

/// A registration for every event type.
final class _Reg extends EventRegistration {
  _Reg(this.querySpec);

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
  EventRegistration clone(QuerySpec newQuery) => _Reg(newQuery);

  @override
  bool isSameListener(EventRegistration other) => identical(other, this);
}

/// Each data event as `<type> <path> <export>`.
List<String> described(List<Event> events) => <String>[
  for (final Event e in events)
    if (e is DataEvent)
      '${e.eventType.name} ${e.snapshotPath} ${export(e.snapshot)}',
];

/// The persisted server cache of [engine] in the export form.
String stored(InMemoryPersistenceStorageEngine engine) {
  engine.disableTransactionCheck = true;
  try {
    return export(engine.serverCache(Path.empty));
  } finally {
    engine.disableTransactionCheck = false;
  }
}

void main() {
  final QuerySpec atR = QuerySpec.defaultAt(p('r'));
  final QuerySpec atX = QuerySpec.defaultAt(p('r/x'));
  late SyncTree tree;

  setUp(() => tree = SyncTree(listenProvider: _Listens()));

  /// A listener at [query] whose listen the server answered with [value].
  void listenAnswered(QuerySpec query, Object? value) {
    tree.addEventRegistration(_Reg(query));
    tree.applyServerOverwrite(query.path, n(value));
    tree.applyListenComplete(query.path);
  }

  group('sync tree: null at r/x/.priority with nothing cached at x', () {
    for (final (String label, Object? r) in <(String, Object?)>[
      ('r null', null),
      ('r {k:1}, x missing', <String, Object?>{'k': 1}),
    ]) {
      test('$label: no event, the value and the cache unchanged', () {
        listenAnswered(atR, r);
        expect(tree.applyServerOverwrite(p('r/x/.priority'), n(null)), isEmpty);
        expect(export(tree.calcCompleteEventCache(p('r'))), jsonEncode(r));
        expect(export(tree.getServerValue(atR)), jsonEncode(r));
        expect(export(tree.calcCompleteEventCache(p('r/x'))), 'null');

        // Nothing was left behind for x: a later value for x shows as any other.
        expect(
          described(
            tree.applyServerOverwrite(p('r/x'), n(<String, Object?>{'v': 2})),
          ),
          <String>[
            'childAdded /r/x {"v":2}',
            'value /r ${jsonEncode(<String, Object?>{
              if (r != null) 'k': 1,
              'x': <String, Object?>{'v': 2},
            })}',
          ],
        );
      });
    }

    test('a listener at x itself (x missing): no event, x stays null', () {
      listenAnswered(atX, null);
      expect(tree.applyServerOverwrite(p('r/x/.priority'), n(null)), isEmpty);
      expect(export(tree.calcCompleteEventCache(p('r/x'))), 'null');
      expect(described(tree.applyServerOverwrite(p('r/x'), n(3))), <String>[
        'value /r/x 3',
      ]);
    });

    test('a listen at r not answered yet: no event, the later answer shows '
        'as sent', () {
      tree.addEventRegistration(_Reg(atR));
      expect(tree.applyServerOverwrite(p('r/x/.priority'), n(null)), isEmpty);
      expect(
        described(
          tree.applyServerOverwrite(p('r'), n(<String, Object?>{'k': 1})),
        ),
        <String>['childAdded /r/k 1', 'value /r {"k":1}'],
      );
    });
  });

  group('sync tree: null at r/x/.priority with x present', () {
    test('x {v:1} without priority: no event, no change', () {
      const Map<String, Object?> r = <String, Object?>{
        'k': 1,
        'x': <String, Object?>{'v': 1},
      };
      listenAnswered(atR, r);
      expect(tree.applyServerOverwrite(p('r/x/.priority'), n(null)), isEmpty);
      expect(export(tree.calcCompleteEventCache(p('r'))), jsonEncode(r));
    });

    // child_moved comes although x keeps its place after k: as in the JS SDK's EventGenerator, a
    // changed child whose indexed value (here the priority) changed is also reported as moved.
    test('x {v:1} with priority 2: the priority goes, with child_moved, '
        'child_changed and value events', () {
      listenAnswered(atR, <String, Object?>{
        'k': 1,
        'x': <String, Object?>{'v': 1, '.priority': 2},
      });
      expect(
        export(tree.calcCompleteEventCache(p('r'))),
        '{"k":1,"x":{"v":1,".priority":2}}',
      );
      expect(
        described(tree.applyServerOverwrite(p('r/x/.priority'), n(null))),
        <String>[
          'childMoved /r/x {"v":1}',
          'childChanged /r/x {"v":1}',
          'value /r {"k":1,"x":{"v":1}}',
        ],
      );
      expect(
        export(tree.calcCompleteEventCache(p('r'))),
        '{"k":1,"x":{"v":1}}',
      );
    });

    test('a listener at x with priority 2: the priority goes, one value '
        'event', () {
      listenAnswered(atX, <String, Object?>{'v': 1, '.priority': 2});
      expect(
        described(tree.applyServerOverwrite(p('r/x/.priority'), n(null))),
        <String>['value /r/x {"v":1}'],
      );
    });
  });

  group('the frame through decodeServerMessage and Repo', () {
    test(
      'the emulator\'s frame decodes to a d push of null at /r/x/.priority',
      () {
        final ServerMessage message = decodeServerMessage(<String, Object?>{
          'b': <String, Object?>{'p': 'r/x/.priority', 'd': null},
          'a': 'd',
        });
        expect(
          message,
          isA<DataPush>()
              .having((DataPush d) => d.path, 'path', '/r/x/.priority')
              .having((DataPush d) => d.data, 'data', isNull)
              .having((DataPush d) => d.isMerge, 'isMerge', isFalse)
              .having((DataPush d) => d.tag, 'tag', isNull),
        );
      },
    );

    for (final (String label, Object? r) in <(String, Object?)>[
      ('r null', null),
      ('r {k:1}, x missing', <String, Object?>{'k': 1}),
      (
        'x {v:1} without priority',
        <String, Object?>{
          'k': 1,
          'x': <String, Object?>{'v': 1},
        },
      ),
    ]) {
      test(
        '$label: no event, nothing persisted for x, no error logged',
        () async {
          final InMemoryPersistenceStorageEngine engine = persistedEngine(
            const <String, Object?>{},
          );
          final RepoHarness h = RepoHarness(persistence: managerOver(engine));
          h.listen('S', 'r');
          h.answer('r', r);
          await settle();
          final String before = stored(engine);
          h.log.clear();

          h.server.deliverDataUpdate('r/x/.priority', null);
          await settle();
          expect(h.log, isEmpty);
          expect(stored(engine), before);
          expect(h.logs.where((String l) => l.startsWith('error')), isEmpty);

          h.server.deliverDataUpdate('r/x', <String, Object?>{'v': 2});
          await settle();
          expect(h.log, <String>[
            'S:V(${jsonEncode(<String, Object?>{
              if (r != null) 'k': 1,
              'x': <String, Object?>{'v': 2},
            })})',
          ]);
        },
      );
    }

    test('x with priority 2: one value event without the priority, the '
        'cache loses it too', () async {
      final InMemoryPersistenceStorageEngine engine = persistedEngine(
        const <String, Object?>{},
      );
      final RepoHarness h = RepoHarness(persistence: managerOver(engine));
      final List<String> exports = <String>[];
      h.listen(
        'S',
        'r',
        after: (DataEvent e) => exports.add(export(e.snapshot)),
      );
      h.answer('r', <String, Object?>{
        'k': 1,
        'x': <String, Object?>{'v': 1, '.priority': 2},
      });
      await settle();
      expect(stored(engine), '{"r":{"k":1,"x":{"v":1,".priority":2}}}');
      exports.clear();
      h.log.clear();

      h.server.deliverDataUpdate('r/x/.priority', null);
      await settle();
      expect(h.log, <String>['S:V({"k":1,"x":{"v":1}})']);
      expect(exports, <String>['{"k":1,"x":{"v":1}}']);
      expect(stored(engine), '{"r":{"k":1,"x":{"v":1}}}');
    });
  });
}

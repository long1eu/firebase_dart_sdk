// ViewProcessor (JS `core/view/ViewProcessor.ts`, Android `core/view/ViewProcessor.java`) against
// the real WriteTree, each operation with an unfiltered view (default query) and a filtered one
// (orderByValue().limitToFirst(2)). Expected values are derived from the upstream code paths.
import 'package:firebase_database_dart/src/core/callback_event_registration.dart';
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/operation/operation.dart';
import 'package:firebase_database_dart/src/core/operation/operation_source.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/value_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/util/immutable_tree.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/filter/node_filter.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/view/view.dart';
import 'package:firebase_database_dart/src/core/view/view_cache.dart';
import 'package:firebase_database_dart/src/core/view/view_processor.dart';
import 'package:firebase_database_dart/src/core/write_tree.dart';
import 'package:test/test.dart';

import 'view_helpers.dart';

final QueryParams unfiltered = QueryParams.defaultParams;

final QueryParams limit2 = QueryParams.defaultParams
    .orderBy(valueIndex)
    .limitToFirst(2);

/// A view cache, its processor and the write tree at the root.
final class Harness {
  Harness(this.params) : processor = ViewProcessor(nodeFilterFor(params)) {
    final Node empty = ChildrenNode.empty.withIndex(params.index);
    cache = ViewCache(
      CacheNode(
        empty,
        fullyInitialized: false,
        filtered: processor.filter.filtersNodes,
      ),
      CacheNode(empty, fullyInitialized: false, filtered: false),
    );
  }

  final QueryParams params;
  final ViewProcessor processor;
  final WriteTree writes = WriteTree();
  late ViewCache cache;

  /// Applies [op] and returns its changes as text.
  List<String> apply(Operation op) {
    final ProcessorResult result = processor.applyOperation(
      cache,
      op,
      writes.childWrites(Path.empty),
      null,
    );
    cache = result.viewCache;
    return describeAll(result.changes);
  }

  List<String> serverOverwrite(String path, Object? json) =>
      apply(Overwrite(OperationSource.server, Path(path), n(json)));

  List<String> userOverwrite(String path, Object? json, int writeId) {
    writes.addOverwrite(Path(path), n(json), writeId, visible: true);
    return apply(Overwrite(OperationSource.user, Path(path), n(json)));
  }

  List<String> ack(String path, int writeId, {bool revert = false}) {
    writes.removeWrite(writeId);
    return apply(
      AckUserWrite(Path(path), ImmutableTree<bool>(true), revert: revert),
    );
  }
}

const Map<String, Object?> ab = <String, Object?>{'a': 1, 'b': 2};

void main() {
  group('server overwrite', () {
    test('unfiltered: at the root', () {
      final Harness h = Harness(unfiltered);
      expect(
        h.serverOverwrite('', <String, Object?>{'a': 1, 'b': 2, 'c': 3}),
        <String>[
          'childAdded a 1',
          'childAdded b 2',
          'childAdded c 3',
          'value {a: 1, b: 2, c: 3}',
        ],
      );
      expect(h.cache.eventCache.fullyInitialized, isTrue);
      expect(h.cache.serverCache.fullyInitialized, isTrue);
      expect(h.cache.eventCache.filtered, isFalse);
    });

    test('filtered: untagged keeps the server cache unfiltered', () {
      final Harness h = Harness(limit2);
      expect(
        h.serverOverwrite('', <String, Object?>{'a': 1, 'b': 2, 'c': 3}),
        <String>['childAdded a 1', 'childAdded b 2', 'value {a: 1, b: 2}'],
      );
      expect(
        h.cache.serverCache.node,
        n(<String, Object?>{'a': 1, 'b': 2, 'c': 3}),
      );
      expect(h.cache.serverCache.filtered, isFalse);
      expect(h.cache.eventCache.filtered, isTrue);
      expect(h.cache.eventCache.node.isIndexed(valueIndex), isTrue);
    });

    test('filtered: tagged filters the server cache', () {
      final Harness h = Harness(limit2);
      expect(
        h.apply(
          Overwrite(
            OperationSource.forServerTaggedQuery(limit2),
            Path.empty,
            n(<String, Object?>{'a': 1, 'b': 2, 'c': 3}),
          ),
        ),
        <String>['childAdded a 1', 'childAdded b 2', 'value {a: 1, b: 2}'],
      );
      expect(h.cache.serverCache.node, n(ab));
      expect(h.cache.serverCache.filtered, isTrue);
    });

    for (final QueryParams params in <QueryParams>[unfiltered, limit2]) {
      test(
        '${params == unfiltered ? 'unfiltered' : 'filtered'}: a child into an '
        'empty cache raises no value event (rule 7)',
        () {
          final Harness h = Harness(params);
          expect(h.serverOverwrite('a', 1), <String>['childAdded a 1']);
          expect(h.cache.eventCache.fullyInitialized, isFalse);
          expect(h.cache.serverCache.fullyInitialized, isFalse);
        },
      );
    }
  });

  group('user overwrite', () {
    test('unfiltered: a new child', () {
      final Harness h = Harness(unfiltered)..serverOverwrite('', ab);
      expect(h.userOverwrite('c', 3, 1), <String>[
        'childAdded c 3',
        'value {a: 1, b: 2, c: 3}',
      ]);
      expect(h.cache.serverCache.node, n(ab));
    });

    test('filtered: a new child pushes the window boundary out', () {
      final Harness h = Harness(limit2)..serverOverwrite('', ab);
      expect(h.userOverwrite('c', 0, 1), <String>[
        'childRemoved b 2',
        'childAdded c 0',
        'value {a: 1, c: 0}',
      ]);
    });

    test('filtered: a new child after the window changes nothing', () {
      final Harness h = Harness(limit2)..serverOverwrite('', ab);
      expect(h.userOverwrite('c', 3, 1), isEmpty);
    });

    test('unfiltered: a deep write changes the child', () {
      final Harness h = Harness(unfiltered)..serverOverwrite('', ab);
      expect(h.userOverwrite('a/x', 5, 1), <String>[
        'childChanged a {x: 5} old 1',
        'value {a: {x: 5}, b: 2}',
      ]);
    });

    test(
      'unfiltered: at the root of an empty cache completes the event cache',
      () {
        final Harness h = Harness(unfiltered);
        expect(h.userOverwrite('', <String, Object?>{'a': 1}, 1), <String>[
          'childAdded a 1',
          'value {a: 1}',
        ]);
        expect(h.cache.eventCache.fullyInitialized, isTrue);
        expect(h.cache.serverCache.fullyInitialized, isFalse);
      },
    );
  });

  group('user merge', () {
    final CompoundWrite merge = CompoundWrite.fromValue(<String, Object?>{
      'a': 10,
      'c': 3,
    });

    List<String> userMerge(Harness h) {
      h.writes.addMerge(Path.empty, merge, 1);
      return h.apply(Merge(OperationSource.user, Path.empty, merge));
    }

    test('unfiltered', () {
      final Harness h = Harness(unfiltered)..serverOverwrite('', ab);
      expect(userMerge(h), <String>[
        'childChanged a 10 old 1',
        'childAdded c 3',
        'value {a: 10, b: 2, c: 3}',
      ]);
    });

    test(
      'filtered: a child leaving the window is replaced from the writes',
      () {
        final Harness h = Harness(limit2)..serverOverwrite('', ab);
        expect(userMerge(h), <String>[
          'childRemoved a 1',
          'childAdded c 3',
          'value {b: 2, c: 3}',
        ]);
      },
    );
  });

  group('server merge', () {
    List<String> serverMerge(Harness h) => h.apply(
      Merge(
        OperationSource.server,
        Path.empty,
        CompoundWrite.fromValue(<String, Object?>{'b': 20, 'c': 3}),
      ),
    );

    test('unfiltered', () {
      final Harness h = Harness(unfiltered)..serverOverwrite('', ab);
      expect(serverMerge(h), <String>[
        'childChanged b 20 old 2',
        'childAdded c 3',
        'value {a: 1, b: 20, c: 3}',
      ]);
    });

    test('filtered: the changes of one child merge in the accumulator', () {
      final Harness h = Harness(limit2)..serverOverwrite('', ab);
      expect(serverMerge(h), <String>[
        'childRemoved b 2',
        'childAdded c 3',
        'value {a: 1, c: 3}',
      ]);
      expect(
        h.cache.serverCache.node,
        n(<String, Object?>{'a': 1, 'b': 20, 'c': 3}),
      );
    });

    test('a merge before any data is ignored', () {
      final Harness h = Harness(unfiltered);
      expect(serverMerge(h), isEmpty);
      expect(h.cache.serverCache.node.isEmpty, isTrue);
    });
  });

  group('ack (the server cache is applied again)', () {
    test('unfiltered: the server value that arrived under the write shows', () {
      final Harness h = Harness(unfiltered)..serverOverwrite('', ab);
      h.userOverwrite('c', 3, 1);
      // Shadowed by the write: no event.
      expect(h.serverOverwrite('c', 4), isEmpty);
      expect(h.ack('c', 1), <String>[
        'childChanged c 4 old 3',
        'value {a: 1, b: 2, c: 4}',
      ]);
    });

    test('unfiltered: an ack the server confirmed raises nothing', () {
      final Harness h = Harness(unfiltered)..serverOverwrite('', ab);
      h.userOverwrite('c', 3, 1);
      expect(h.serverOverwrite('c', 3), isEmpty);
      expect(h.ack('c', 1), isEmpty);
    });

    test('filtered: the server value moves the child out of the window', () {
      final Harness h = Harness(limit2)..serverOverwrite('', ab);
      h.userOverwrite('c', 0, 1);
      expect(h.serverOverwrite('c', 5), isEmpty);
      expect(h.ack('c', 1), <String>[
        'childRemoved c 0',
        'childAdded b 2',
        'value {a: 1, b: 2}',
      ]);
    });
  });

  group('revert', () {
    test('unfiltered: the written child goes away', () {
      final Harness h = Harness(unfiltered)..serverOverwrite('', ab);
      h.userOverwrite('c', 3, 1);
      expect(h.ack('c', 1, revert: true), <String>[
        'childRemoved c 3',
        'value {a: 1, b: 2}',
      ]);
    });

    test('filtered: the pushed-out child comes back', () {
      final Harness h = Harness(limit2)..serverOverwrite('', ab);
      h.userOverwrite('c', 0, 1);
      expect(h.ack('c', 1, revert: true), <String>[
        'childRemoved c 0',
        'childAdded b 2',
        'value {a: 1, b: 2}',
      ]);
    });
  });

  group('listen complete', () {
    test('unfiltered: no data is an empty value', () {
      final Harness h = Harness(unfiltered);
      expect(
        h.apply(ListenComplete(OperationSource.server, Path.empty)),
        <String>['value null'],
      );
      expect(h.cache.eventCache.fullyInitialized, isTrue);
      expect(h.cache.serverCache.fullyInitialized, isTrue);
    });

    test('filtered (tagged): no data is an empty value', () {
      final Harness h = Harness(limit2);
      expect(
        h.apply(
          ListenComplete(
            OperationSource.forServerTaggedQuery(limit2),
            Path.empty,
          ),
        ),
        <String>['value null'],
      );
    });

    test('unfiltered: a partial cache gets its value event once complete', () {
      final Harness h = Harness(unfiltered);
      expect(h.serverOverwrite('a', 1), <String>['childAdded a 1']);
      expect(
        h.apply(ListenComplete(OperationSource.server, Path.empty)),
        <String>['value {a: 1}'],
      );
    });
  });

  group('View.applyOperation', () {
    test('turns the changes into events for the registrations', () {
      final QuerySpec query = QuerySpec(Path('q'), unfiltered);
      final View view = View(
        query,
        ViewCache(
          CacheNode(
            ChildrenNode.empty,
            fullyInitialized: false,
            filtered: false,
          ),
          CacheNode(
            ChildrenNode.empty,
            fullyInitialized: false,
            filtered: false,
          ),
        ),
      );
      view.addEventRegistration(
        CallbackEventRegistration(
          query,
          EventType.values.toSet(),
          onEvent: (DataEvent _) {},
          onCancel: (DatabaseError _) {},
        ),
      );
      final ViewOperationResult result = view.applyOperation(
        Overwrite(OperationSource.server, Path.empty, n(ab)),
        WriteTree().childWrites(Path('q')),
        null,
      );
      expect(
        result.events
            .map(
              (DataEvent e) =>
                  '${e.eventType.name} ${e.snapshotPath} ${e.previousName}',
            )
            .toList(),
        <String>['childAdded /q/a null', 'childAdded /q/b a', 'value /q null'],
      );
      expect(result.changes, hasLength(3));
      expect(view.completeNode, n(ab));
    });
  });
}

// The indexed and ranged node filters. Expected values follow JS `core/view/filter/IndexedFilter.ts`
// and `RangedFilter.ts` (authoritative for startAfter and endBefore).
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/path_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/value_index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/filter/child_change_accumulator.dart';
import 'package:firebase_database_dart/src/core/view/filter/indexed_filter.dart';
import 'package:firebase_database_dart/src/core/view/filter/limited_filter.dart';
import 'package:firebase_database_dart/src/core/view/filter/node_filter.dart';
import 'package:firebase_database_dart/src/core/view/filter/ranged_filter.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:test/test.dart';
import 'view_helpers.dart';

void main() {
  group('nodeFilterFor', () {
    test('indexed for all data, limited with a limit, else ranged', () {
      expect(nodeFilterFor(def), isA<IndexedFilter>());
      expect(nodeFilterFor(byValue), isA<IndexedFilter>());
      expect(nodeFilterFor(def.limitToFirst(1)), isA<LimitedFilter>());
      expect(nodeFilterFor(def.startAt(n(1))), isA<RangedFilter>());
      expect(nodeFilterFor(def.endBefore(n(1))), isA<RangedFilter>());
    });
  });

  group('IndexedFilter', () {
    final IndexedFilter filter = IndexedFilter(priorityIndex);
    final Node snap = indexed(<String, Object?>{'a': 1, 'b': 2}, priorityIndex);

    test('properties', () {
      expect(filter.filtersNodes, isFalse);
      expect(identical(filter.indexedFilter, filter), isTrue);
      expect(filter.index, priorityIndex);
    });

    test('updateChild adds, changes and removes', () {
      final ({Node node, List<String> changes}) added = child(
        filter,
        snap,
        'c',
        3,
      );
      expect(added.node, n(<String, Object?>{'a': 1, 'b': 2, 'c': 3}));
      expect(added.changes, <String>['childAdded c 3']);

      final ({Node node, List<String> changes}) changed = child(
        filter,
        snap,
        'a',
        5,
      );
      expect(changed.node, n(<String, Object?>{'a': 5, 'b': 2}));
      expect(changed.changes, <String>['childChanged a 5 old 1']);

      final ({Node node, List<String> changes}) removed = child(
        filter,
        snap,
        'a',
        null,
      );
      expect(removed.node, n(<String, Object?>{'b': 2}));
      expect(removed.changes, <String>['childRemoved a 1']);
    });

    test('updateChild without a change returns the same node', () {
      final ({Node node, List<String> changes}) same = child(
        filter,
        snap,
        'a',
        1,
      );
      expect(identical(same.node, snap), isTrue);
      expect(same.changes, isEmpty);
    });

    test('updateChild keeps the result indexed', () {
      final IndexedFilter byValueFilter = IndexedFilter(valueIndex);
      final Node result = child(
        byValueFilter,
        indexed(<String, Object?>{'a': 1}, valueIndex),
        'b',
        0,
      ).node;
      expect(result.isIndexed(valueIndex), isTrue);
    });

    test('removing a child of a leaf keeps the leaf', () {
      final Node leaf = n(5);
      expect(identical(child(filter, leaf, 'a', null).node, leaf), isTrue);
    });

    test('updateFullNode reports removed, changed and added children', () {
      final ChildChangeAccumulator acc = ChildChangeAccumulator();
      final Node result = IndexedFilter(
        valueIndex,
      ).updateFullNode(snap, n(<String, Object?>{'b': 3, 'c': 4}), acc);
      expect(result, n(<String, Object?>{'b': 3, 'c': 4}));
      expect(result.isIndexed(valueIndex), isTrue);
      expect(describeAll(acc.changes), <String>[
        'childRemoved a 1',
        'childChanged b 3 old 2',
        'childAdded c 4',
      ]);
    });

    test('updateFullNode from a leaf and to a leaf', () {
      final ChildChangeAccumulator acc = ChildChangeAccumulator();
      filter.updateFullNode(n(5), snap, acc);
      expect(describeAll(acc.changes), <String>[
        'childAdded a 1',
        'childAdded b 2',
      ]);
      final ChildChangeAccumulator acc2 = ChildChangeAccumulator();
      expect(filter.updateFullNode(snap, n(5), acc2), n(5));
      expect(describeAll(acc2.changes), <String>[
        'childRemoved a 1',
        'childRemoved b 2',
      ]);
    });

    test('updatePriority sets the priority, but not on an empty node', () {
      expect(filter.updatePriority(snap, n(7)).priority, n(7));
      expect(filter.updatePriority(ChildrenNode.empty, n(7)).isEmpty, isTrue);
      expect(
        filter.updatePriority(ChildrenNode.empty, n(7)).priority.isEmpty,
        isTrue,
      );
    });
  });

  group('RangedFilter', () {
    final Map<String, Object?> data = <String, Object?>{
      'a': 1,
      'b': 2,
      'c': 3,
      'd': 4,
      'e': 5,
    };

    test('posts default to the index min and max posts', () {
      final RangedFilter filter = RangedFilter(byValue.startAt(n(2)));
      expect(filter.startPost, NamedNode(k('[MIN_NAME]'), n(2)));
      expect(filter.endPost, valueIndex.maxPost);
      expect(filter.filtersNodes, isTrue);
      expect(filter.indexedFilter, isA<IndexedFilter>());
      expect(filter.index, valueIndex);
    });

    test('startAt and endAt include the bounds (value index)', () {
      final ({Node node, List<String> changes}) r = full(
        RangedFilter(byValue.startAt(n(2)).endAt(n(4))),
        data,
      );
      expect(r.node, n(<String, Object?>{'b': 2, 'c': 3, 'd': 4}));
      expect(r.changes, <String>[
        'childAdded b 2',
        'childAdded c 3',
        'childAdded d 4',
      ]);
    });

    test('startAfter and endBefore exclude the bounds (value index)', () {
      final RangedFilter filter = RangedFilter(
        byValue.startAfter(n(2)).endBefore(n(4)),
      );
      expect(full(filter, data).node, n(<String, Object?>{'c': 3}));
      expect(filter.matches(NamedNode(k('b'), n(2))), isFalse);
      expect(filter.matches(NamedNode(k('c'), n(3))), isTrue);
      expect(filter.matches(NamedNode(k('d'), n(4))), isFalse);
    });

    test('startAfter with a key excludes up to that key', () {
      final RangedFilter filter = RangedFilter(
        byValue.startAfter(n(2), k('b')),
      );
      expect(
        full(filter, <String, Object?>{'a': 2, 'b': 2, 'c': 2}).node,
        n(<String, Object?>{'c': 2}),
      );
    });

    test('endBefore with a key excludes from that key', () {
      final RangedFilter filter = RangedFilter(byValue.endBefore(n(2), k('b')));
      expect(
        full(filter, <String, Object?>{'a': 2, 'b': 2, 'c': 2}).node,
        n(<String, Object?>{'a': 2}),
      );
    });

    test('key index: startAfter and endBefore', () {
      final QueryParams byKey = def.orderBy(keyIndex);
      expect(
        full(
          RangedFilter(byKey.startAfter(n('b')).endBefore(n('d'))),
          data,
        ).node,
        n(<String, Object?>{'c': 3}),
      );
      expect(
        full(RangedFilter(byKey.startAt(n('b')).endAt(n('d'))), data).node,
        n(<String, Object?>{'b': 2, 'c': 3, 'd': 4}),
      );
    });

    test('priority index: startAt, endAt and startAfter', () {
      final Map<String, Object?> withPriorities = <String, Object?>{
        'a': <String, Object?>{'.value': 1, '.priority': 1},
        'b': <String, Object?>{'.value': 1, '.priority': 2},
        'c': <String, Object?>{'.value': 1, '.priority': 3},
        'd': <String, Object?>{'.value': 1, '.priority': 4},
      };
      expect(
        full(RangedFilter(def.startAt(n(2)).endAt(n(3))), withPriorities).node,
        n(<String, Object?>{
          'b': <String, Object?>{'.value': 1, '.priority': 2},
          'c': <String, Object?>{'.value': 1, '.priority': 3},
        }),
      );
      expect(
        full(
          RangedFilter(def.startAfter(n(2)).endAt(n(3))),
          withPriorities,
        ).node,
        n(<String, Object?>{
          'c': <String, Object?>{'.value': 1, '.priority': 3},
        }),
      );
      expect(
        full(RangedFilter(def.endBefore(n(2))), withPriorities).node,
        n(<String, Object?>{
          'a': <String, Object?>{'.value': 1, '.priority': 1},
        }),
      );
    });

    test('child index: startAt and endBefore', () {
      final QueryParams byAge = def.orderBy(PathIndex(Path('age')));
      final Map<String, Object?> people = <String, Object?>{
        'a': <String, Object?>{'age': 10},
        'b': <String, Object?>{'age': 20},
        'c': <String, Object?>{'age': 25},
        'd': <String, Object?>{'age': 30},
      };
      expect(
        full(RangedFilter(byAge.startAt(n(20)).endBefore(n(30))), people).node,
        n(<String, Object?>{
          'b': <String, Object?>{'age': 20},
          'c': <String, Object?>{'age': 25},
        }),
      );
      expect(
        full(RangedFilter(byAge.startAfter(n(20))), people).node,
        n(<String, Object?>{
          'c': <String, Object?>{'age': 25},
          'd': <String, Object?>{'age': 30},
        }),
      );
    });

    test('a leaf becomes empty and the priority is dropped', () {
      final RangedFilter filter = RangedFilter(byValue.startAt(n(2)));
      expect(full(filter, 5).node.isEmpty, isTrue);
      final Node result = full(filter, <String, Object?>{
        'b': 2,
        '.priority': 5,
      }).node;
      expect(result, n(<String, Object?>{'b': 2}));
      expect(result.priority.isEmpty, isTrue);
      expect(result.isIndexed(valueIndex), isTrue);
    });

    test(
      'updateChild removes a child leaving the range, ignores one outside',
      () {
        final RangedFilter filter = RangedFilter(
          byValue.startAt(n(2)).endAt(n(4)),
        );
        final Node snap = full(filter, data).node;
        final ({Node node, List<String> changes}) out = child(
          filter,
          snap,
          'c',
          9,
        );
        expect(out.node, n(<String, Object?>{'b': 2, 'd': 4}));
        expect(out.changes, <String>['childRemoved c 3']);

        final ({Node node, List<String> changes}) outside = child(
          filter,
          snap,
          'z',
          9,
        );
        expect(identical(outside.node, snap), isTrue);
        expect(outside.changes, isEmpty);

        final ({Node node, List<String> changes}) inside = child(
          filter,
          snap,
          'x',
          3,
        );
        expect(inside.changes, <String>['childAdded x 3']);
      },
    );

    test('updatePriority keeps the node', () {
      final RangedFilter filter = RangedFilter(byValue.startAt(n(2)));
      final Node snap = n(<String, Object?>{'b': 2});
      expect(identical(filter.updatePriority(snap, n(1)), snap), isTrue);
    });
  });
}

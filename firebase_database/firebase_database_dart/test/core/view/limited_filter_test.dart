// The limited node filter. Expected values follow JS `core/view/filter/LimitedFilter.ts`
// (authoritative for startAfter and endBefore).
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/value_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/filter/child_change_accumulator.dart';
import 'package:firebase_database_dart/src/core/view/filter/indexed_filter.dart';
import 'package:firebase_database_dart/src/core/view/filter/limited_filter.dart';
import 'package:test/test.dart';
import 'view_helpers.dart';

void main() {
  group('LimitedFilter', () {
    final Map<String, Object?> abc = <String, Object?>{'a': 1, 'b': 2, 'c': 3};
    final Map<String, Object?> six = <String, Object?>{
      'a': 1,
      'b': 2,
      'c': 3,
      'd': 4,
      'e': 5,
      'f': 6,
    };

    test('properties', () {
      final LimitedFilter filter = LimitedFilter(def.limitToFirst(1));
      expect(filter.filtersNodes, isTrue);
      expect(filter.indexedFilter, isA<IndexedFilter>());
      expect(filter.index, priorityIndex);
      final Node snap = n(<String, Object?>{'a': 1});
      expect(identical(filter.updatePriority(snap, n(1)), snap), isTrue);
    });

    test('limitToFirst and limitToLast keep the anchored side', () {
      expect(
        full(LimitedFilter(def.limitToFirst(2)), abc).node,
        n(<String, Object?>{'a': 1, 'b': 2}),
      );
      expect(
        full(LimitedFilter(def.limitToLast(2)), abc).node,
        n(<String, Object?>{'b': 2, 'c': 3}),
      );
    });

    test('a large indexed snapshot is built up from the anchor', () {
      final ChildChangeAccumulator acc = ChildChangeAccumulator();
      final Node first = LimitedFilter(def.limitToFirst(1)).updateFullNode(
        ChildrenNode.empty.withIndex(priorityIndex),
        indexed(abc, priorityIndex),
        acc,
      );
      expect(first, n(<String, Object?>{'a': 1}));
      expect(describeAll(acc.changes), <String>['childAdded a 1']);
      final Node last = LimitedFilter(def.limitToLast(1)).updateFullNode(
        ChildrenNode.empty.withIndex(priorityIndex),
        indexed(abc, priorityIndex),
        null,
      );
      expect(last, n(<String, Object?>{'c': 3}));
    });

    for (final bool isIndexed in <bool>[true, false]) {
      final String name = isIndexed
          ? 'indexed (build up)'
          : 'not indexed (delete)';
      Node data() => isIndexed ? indexed(six, valueIndex) : n(six);

      test('$name: startAt with limitToFirst', () {
        final Node result = LimitedFilter(byValue.startAt(n(2)).limitToFirst(2))
            .updateFullNode(
              ChildrenNode.empty.withIndex(valueIndex),
              data(),
              null,
            );
        expect(result, n(<String, Object?>{'b': 2, 'c': 3}));
      });

      test('$name: startAfter with limitToFirst', () {
        final Node result =
            LimitedFilter(
              byValue.startAfter(n(2)).limitToFirst(2),
            ).updateFullNode(
              ChildrenNode.empty.withIndex(valueIndex),
              data(),
              null,
            );
        expect(result, n(<String, Object?>{'c': 3, 'd': 4}));
      });

      test('$name: endBefore with limitToLast', () {
        final Node result =
            LimitedFilter(
              byValue.endBefore(n(5)).limitToLast(2),
            ).updateFullNode(
              ChildrenNode.empty.withIndex(valueIndex),
              data(),
              null,
            );
        expect(result, n(<String, Object?>{'c': 3, 'd': 4}));
      });

      test('$name: endAt with limitToLast', () {
        final Node result = LimitedFilter(byValue.endAt(n(5)).limitToLast(2))
            .updateFullNode(
              ChildrenNode.empty.withIndex(valueIndex),
              data(),
              null,
            );
        expect(result, n(<String, Object?>{'d': 4, 'e': 5}));
      });
    }

    test('a leaf or empty node becomes an empty indexed node', () {
      final LimitedFilter filter = LimitedFilter(byValue.limitToFirst(2));
      final Node result = full(filter, 5).node;
      expect(result.isEmpty, isTrue);
      expect(result.isIndexed(valueIndex), isTrue);
    });

    group('updateChild (limitToFirst(2), value index)', () {
      final LimitedFilter filter = LimitedFilter(byValue.limitToFirst(2));
      final Map<String, Object?> all = <String, Object?>{
        'a': 1,
        'b': 2,
        'c': 3,
        'd': 4,
      };
      final Node window = indexed(<String, Object?>{
        'a': 1,
        'b': 2,
      }, valueIndex);

      test('below the limit adds the child', () {
        final ({Node node, List<String> changes}) r = child(
          filter,
          indexed(<String, Object?>{'a': 1}, valueIndex),
          'b',
          2,
        );
        expect(r.node, n(<String, Object?>{'a': 1, 'b': 2}));
        expect(r.changes, <String>['childAdded b 2']);
      });

      test('a new child before the boundary pushes the boundary out', () {
        final ({Node node, List<String> changes}) r = child(
          filter,
          window,
          'z',
          0,
        );
        expect(r.node, n(<String, Object?>{'a': 1, 'z': 0}));
        expect(r.changes, <String>['childRemoved b 2', 'childAdded z 0']);
      });

      test('a new child after the boundary is ignored', () {
        final ({Node node, List<String> changes}) r = child(
          filter,
          window,
          'z',
          9,
        );
        expect(identical(r.node, window), isTrue);
        expect(r.changes, isEmpty);
      });

      test('removing a child outside the window is ignored', () {
        final ({Node node, List<String> changes}) r = child(
          filter,
          window,
          'c',
          null,
        );
        expect(identical(r.node, window), isTrue);
      });

      test('a child leaving fills the window from the source', () {
        final ({Node node, List<String> changes}) r = child(
          filter,
          window,
          'a',
          null,
          source: FullSource(n(all)),
        );
        expect(r.node, n(<String, Object?>{'b': 2, 'c': 3}));
        expect(r.changes, <String>['childRemoved a 1', 'childAdded c 3']);
      });

      test('a child leaving without a source shrinks the window', () {
        final ({Node node, List<String> changes}) r = child(
          filter,
          window,
          'a',
          null,
        );
        expect(r.node, n(<String, Object?>{'b': 2}));
        expect(r.changes, <String>['childRemoved a 1']);
      });

      test('a child changing within the window stays', () {
        final ({Node node, List<String> changes}) r = child(
          filter,
          window,
          'b',
          1.5,
          source: FullSource(n(all)),
        );
        expect(r.node, n(<String, Object?>{'a': 1, 'b': 1.5}));
        expect(r.changes, <String>['childChanged b 1.5 old 2']);
      });

      test('a child moving past the next one is swapped for it', () {
        final ({Node node, List<String> changes}) r = child(
          filter,
          window,
          'b',
          10,
          source: FullSource(n(all)),
        );
        expect(r.node, n(<String, Object?>{'a': 1, 'c': 3}));
        expect(r.changes, <String>['childRemoved b 2', 'childAdded c 3']);
      });

      test('an unchanged child is no change', () {
        final ({Node node, List<String> changes}) r = child(
          filter,
          window,
          'a',
          1,
        );
        expect(identical(r.node, window), isTrue);
        expect(r.changes, isEmpty);
      });
    });

    group('updateChild (limitToLast(2), value index: reverse)', () {
      final LimitedFilter filter = LimitedFilter(byValue.limitToLast(2));
      final Map<String, Object?> all = <String, Object?>{
        'a': 1,
        'b': 2,
        'c': 3,
        'd': 4,
      };
      final Node window = indexed(<String, Object?>{
        'c': 3,
        'd': 4,
      }, valueIndex);

      test('a child leaving fills the window from before', () {
        final ({Node node, List<String> changes}) r = child(
          filter,
          window,
          'd',
          null,
          source: FullSource(n(all)),
        );
        expect(r.node, n(<String, Object?>{'b': 2, 'c': 3}));
        expect(r.changes, <String>['childRemoved d 4', 'childAdded b 2']);
      });

      test('a new last child pushes the first one out', () {
        final ({Node node, List<String> changes}) r = child(
          filter,
          window,
          'e',
          5,
        );
        expect(r.node, n(<String, Object?>{'d': 4, 'e': 5}));
        expect(r.changes, <String>['childRemoved c 3', 'childAdded e 5']);
      });

      test('a new child before the window is ignored', () {
        final ({Node node, List<String> changes}) r = child(
          filter,
          window,
          'z',
          0,
        );
        expect(identical(r.node, window), isTrue);
      });
    });

    test('a child outside startAfter is never added', () {
      final LimitedFilter filter = LimitedFilter(
        byValue.startAfter(n(2)).limitToFirst(2),
      );
      final Node snap = ChildrenNode.empty.withIndex(valueIndex);
      final ({Node node, List<String> changes}) r = child(filter, snap, 'b', 2);
      expect(identical(r.node, snap), isTrue);
      expect(r.changes, isEmpty);
      expect(child(filter, snap, 'c', 3).changes, <String>['childAdded c 3']);
    });
  });
}

// The merge table of JS `core/view/ChildChangeAccumulator.ts` (Android
// `ChildChangeAccumulator.java`): every pair of child change types for one child.
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/filter/child_change_accumulator.dart';
import 'package:test/test.dart';

import 'view_helpers.dart';

final ChildKey a = k('a');

Change added(int v) => Change.childAdded(a, n(v));

Change changed(int v, int old) => Change.childChanged(a, n(v), n(old));

Change removed(int old) => Change.childRemoved(a, n(old));

List<String> track(List<Change> changes) {
  final ChildChangeAccumulator acc = ChildChangeAccumulator();
  changes.forEach(acc.trackChildChange);
  return describeAll(acc.changes);
}

void main() {
  test('a single change is kept', () {
    expect(track(<Change>[added(1)]), <String>['childAdded a 1']);
    expect(track(<Change>[changed(2, 1)]), <String>['childChanged a 2 old 1']);
    expect(track(<Change>[removed(1)]), <String>['childRemoved a 1']);
  });

  group('legal pairs', () {
    test('added then changed: added with the new node', () {
      expect(track(<Change>[added(1), changed(2, 1)]), <String>[
        'childAdded a 2',
      ]);
    });

    test('added then removed: nothing', () {
      expect(track(<Change>[added(1), removed(1)]), isEmpty);
    });

    test(
      'changed then changed: the new node of the second, the old of the first',
      () {
        expect(track(<Change>[changed(2, 1), changed(3, 2)]), <String>[
          'childChanged a 3 old 1',
        ]);
      },
    );

    test('changed then removed: removed with the old node of the change', () {
      expect(track(<Change>[changed(2, 1), removed(2)]), <String>[
        'childRemoved a 1',
      ]);
    });

    test('removed then added: changed from the removed node', () {
      expect(track(<Change>[removed(1), added(2)]), <String>[
        'childChanged a 2 old 1',
      ]);
    });

    test('a chain: removed, added, removed', () {
      // removed+added = changed(2, old 1); changed+removed = removed(1).
      expect(track(<Change>[removed(1), added(2), removed(2)]), <String>[
        'childRemoved a 1',
      ]);
    });
  });

  group('illegal pairs throw', () {
    final Map<String, List<Change>> illegal = <String, List<Change>>{
      'added then added': <Change>[added(1), added(2)],
      'changed then added': <Change>[changed(2, 1), added(3)],
      'removed then changed': <Change>[removed(1), changed(2, 1)],
      'removed then removed': <Change>[removed(1), removed(1)],
    };
    illegal.forEach((String name, List<Change> changes) {
      test(name, () {
        expect(() => track(changes), throwsStateError);
      });
    });
  });

  test('only child changes of non-priority children are tracked', () {
    final ChildChangeAccumulator acc = ChildChangeAccumulator();
    expect(() => acc.trackChildChange(Change.value(n(1))), throwsStateError);
    expect(
      () => acc.trackChildChange(Change.childMoved(a, n(1))),
      throwsStateError,
    );
    expect(
      () => acc.trackChildChange(Change.childAdded(ChildKey.priority, n(1))),
      throwsStateError,
    );
  });

  test('changes of different children keep their first-tracked order', () {
    final ChildChangeAccumulator acc = ChildChangeAccumulator()
      ..trackChildChange(Change.childAdded(k('z'), n(1)))
      ..trackChildChange(Change.childRemoved(k('b'), n(2)))
      ..trackChildChange(Change.childChanged(k('z'), n(3), n(1)));
    expect(describeAll(acc.changes), <String>[
      'childAdded z 3',
      'childRemoved b 2',
    ]);
  });
}

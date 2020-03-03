// File created by
// Lung Razvan <long1eu>
// on 27/09/2018

import 'package:firebase_core/firebase_core_vm.dart';

/// Tests that a given [Comparator] (or the implementation of [Comparable]) is
/// correct. To use, repeatedly call [addEqualityGroup] with sets of objects
/// that should be equal. The calls to [addEqualityGroup] must be made in sorted
/// order. Then call [testCompare] to test the comparison.
class ComparatorTester<T> {
  final Comparator<T> _comparator;

  /// The items that we are checking, stored as a sorted set of equivalence
  /// classes.
  final List<List<Object>> _equalityGroups;

  /// Whether to enforce a.equals(b) == (a.compareTo(b) == 0)
  bool _testForEqualsCompatibility;

  /// Creates a new instance that tests the order of objects using the given
  /// comparator. Or, if the comparator is null, the natural ordering (as
  /// defined by [Comparable])
  ComparatorTester([this._comparator])
      : _equalityGroups = <List<Object>>[],
        _testForEqualsCompatibility = _comparator == null;

  /// Activates enforcement of [a.equals(b) == (a.compareTo(b) == 0)]. This is
  /// off by default when testing [Comparator]s, but can be turned on if
  /// required.
  ComparatorTester<T> requireConsistencyWithEquals() {
    _testForEqualsCompatibility = true;
    return this;
  }

  /// Deactivates enforcement of [@code a.equals(b) == (a.compareTo(b) == 0)].
  /// This is on by default when testing [Comparable]s, but can be turned off if
  /// required.
  ComparatorTester<T> permitInconsistencyWithEquals() {
    _testForEqualsCompatibility = false;
    return this;
  }

  /// Adds a set of objects to the test which should all compare as equal. All
  /// of the elements in [objects] must be greater than any element of [objects]
  /// in a previous call to [addEqualityGroup].
  ComparatorTester<T> addEqualityGroup(List<T> objects) {
    Preconditions.checkNotNull(objects);
    Preconditions.checkArgument(objects.isNotEmpty, 'Array must not be empty');
    _equalityGroups.add(objects.toList(growable: false));
    return this;
  }

  /// Adds a set of objects to the test which should all compare as equal. All
  /// of the elements in [objects] must be greater than any element of [objects]
  /// in a previous call to [addEqualityGroup].
  ComparatorTester<T> addItem(T object) {
    Preconditions.checkNotNull(object);
    _equalityGroups.add(<T>[object]);
    return this;
  }

  int _compare(T a, T b) {
    int compareValue;
    if (_comparator == null) {
      compareValue = (a as Comparable<Object>).compareTo(b);
    } else {
      compareValue = _comparator(a, b);
    }
    return compareValue;
  }

  void testCompare() {
    _doTestEquivalanceGroupOrdering();
    if (_testForEqualsCompatibility) {
      _doTestEqualsCompatibility();
    }
  }

  void _doTestEquivalanceGroupOrdering() {
    for (int referenceIndex = 0; referenceIndex < _equalityGroups.length; referenceIndex++) {
      for (T reference in _equalityGroups[referenceIndex]) {
        for (int otherIndex = 0; otherIndex < _equalityGroups.length; otherIndex++) {
          for (T other in _equalityGroups[otherIndex]) {
            assert(_compare(reference, other).sign == referenceIndex
                .compareTo(otherIndex)
                .sign);
          }
        }
      }
    }
  }

  void _doTestEqualsCompatibility() {
    for (List<Object> referenceGroup in _equalityGroups) {
      for (T reference in referenceGroup) {
        for (List<Object> otherGroup in _equalityGroups) {
          for (T other in otherGroup) {
            assert(
            reference == other && _compare(reference, other) == 0,
            'Testing equals() for compatibility with '
                'compare()/compareTo(), add a call to '
                'doNotRequireEqualsCompatibility() if this is not required');
          }
        }
      }
    }
  }
}

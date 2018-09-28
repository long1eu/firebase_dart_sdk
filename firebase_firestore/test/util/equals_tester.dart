// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

import 'relationship_tester.dart';

/// Tester for [==] and [hashCode] methods of a class.
///
/// * To use, create a new [EqualsTester] and add equality groups where each
/// group contains objects that are supposed to be equal to each other, and
/// objects of different groups are expected to be unequal.
///
/// This tests:
/// <ul>
/// <li>comparing each object against itself returns true
/// <li>comparing each object against null returns false
/// <li>comparing each object an instance of an incompatible class returns false
/// <li>comparing each pair of objects within the same equality group returns
/// true
/// <li>comparing each pair of objects from different equality groups returns
/// false
/// <li>the hash code of any two equal objects are equal
/// </ul>
class EqualsTester {
  static const int _repetitions = 3;
  final List<List<Object>> _equalityGroups;

  EqualsTester() : _equalityGroups = <List<Object>>[<Object>[]];

  /// Adds [equalityGroup] with objects that are supposed to be equal to
  /// each other and not equal to any other equality groups added to this
  /// tester.
  EqualsTester addEqualityGroup(List<Object> equalityGroup) {
    Assert.checkNotNull(equalityGroup);
    _equalityGroups.add(equalityGroup.toList());
    return this;
  }

  /// Adds [item] with an object that is supposed to be not equal to any other
  /// equality groups added to this tester.
  EqualsTester addItem(Object item) {
    Assert.checkNotNull(item);
    _equalityGroups.add(<Object>[item]);
    return this;
  }

  /// Run tests on equals method, throwing a failure on an invalid test
  EqualsTester testEquals() {
    final RelationshipTester<Object> delegate = RelationshipTester<Object>(
        RelationshipAssertion<Object>((Object item, Object related) {
      assert(
          related == item || identical(related, item),
          '${RelationshipTester.itemPlaceholder} must be equal to '
          '${RelationshipTester.relatedPlaceholder}');
      final int itemHash = item.hashCode;
      final int relatedHash = related.hashCode;
      assert(
          relatedHash == itemHash,
          'The hash ($itemHash) of ${RelationshipTester.itemPlaceholder} '
          'must be equal to the hash ($relatedHash) of '
          '${RelationshipTester.relatedPlaceholder}');
    }, (Object item, Object unrelated) {
      assert(
          item != unrelated,
          '${RelationshipTester.itemPlaceholder} must be unequal to '
          '${RelationshipTester.unrelatedPlaceholder}');
    }));

    _equalityGroups.forEach(delegate.addRelatedGroup);
    for (int run = 0; run < _repetitions; run++) {
      _testItems();
      delegate.test();
    }
    return this;
  }

  void _testItems() {
    for (Object item in _equalityGroups.expand((List<Object> it) => it)) {
      assert(item != null, '$item must be unequal to null');
      assert(item != _NotAnInstance.equalToNothing,
          '$item must be unequal to an arbitrary object of another class');
      assert(item == item, '$item must be equal to itself');
      assert(item.hashCode == item.hashCode,
          'the hash of $item must be consistent');
    }
  }
}

/// Class used to test whether equals() correctly handles an instance
/// of an incompatible class.
enum _NotAnInstance { equalToNothing }

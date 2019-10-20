// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

/// Tests a collection of objects according to the rules specified in a
/// [RelationshipAssertion].
class RelationshipTester<T> {
  RelationshipTester(this._assertion) : _groups = <List<T>>[<T>[]];

  static const String itemPlaceholder = '#item';
  static const String relatedPlaceholder = '#related';
  static const String unrelatedPlaceholder = '#unrelated';

  final List<List<T>> _groups;
  final RelationshipAssertion<T> _assertion;

  RelationshipTester<T> addRelatedGroup(Iterable<T> group) {
    _groups.add(group.toList(growable: false));
    return this;
  }

  RelationshipTester<T> addItem(T item) {
    _groups.add(<T>[item]);
    return this;
  }

  void test() {
    for (int groupNumber = 0; groupNumber < _groups.length; groupNumber++) {
      final List<T> group = _groups[groupNumber];
      for (int itemNumber = 0; itemNumber < group.length; itemNumber++) {
        // check related items in same group
        for (int relatedItemNumber = 0; relatedItemNumber < group.length; relatedItemNumber++) {
          if (itemNumber != relatedItemNumber) {
            _assertRelated(groupNumber, itemNumber, relatedItemNumber);
          }
        }
        // check unrelated items in all other groups
        for (int unrelatedGroupNumber = 0;
            unrelatedGroupNumber < _groups.length;
            unrelatedGroupNumber++) {
          if (groupNumber != unrelatedGroupNumber) {
            final List<T> unrelatedGroup = _groups[unrelatedGroupNumber];
            for (int unrelatedItemNumber = 0;
                unrelatedItemNumber < unrelatedGroup.length;
                unrelatedItemNumber++) {
              _assertUnrelated(groupNumber, itemNumber, unrelatedGroupNumber, unrelatedItemNumber);
            }
          }
        }
      }
    }
  }

  void _assertRelated(int groupNumber, int itemNumber, int relatedItemNumber) {
    final List<T> group = _groups[groupNumber];
    final T item = group[itemNumber];
    final T related = group[relatedItemNumber];
    try {
      _assertion.assertRelated(item, related);
    } on AssertionError catch (e) {
      final String message = (e.message as String)
          .replaceAll(itemPlaceholder, _itemString(item, groupNumber, itemNumber))
          .replaceAll(relatedPlaceholder, _itemString(related, groupNumber, relatedItemNumber));

      throw StateError(message);
    }
  }

  void _assertUnrelated(
      int groupNumber, int itemNumber, int unrelatedGroupNumber, int unrelatedItemNumber) {
    final T item = _groups[groupNumber][itemNumber];
    final T unrelated = _groups[unrelatedGroupNumber][unrelatedItemNumber];
    try {
      _assertion.assertUnrelated(item, unrelated);
    } on AssertionError catch (e) {
      final String message = (e.message as String)
          .replaceAll(itemPlaceholder, _itemString(item, groupNumber, itemNumber))
          .replaceAll(unrelatedPlaceholder,
              _itemString(unrelated, unrelatedGroupNumber, unrelatedItemNumber));
      throw StateError(message);
    }
  }

  static String _itemString(Object item, int groupNumber, int itemNumber) {
    return (StringBuffer()
          ..write(item)
          ..write(' [group ')
          ..write(groupNumber + 1)
          ..write(', item ')
          ..write(itemNumber + 1)
          ..write(']'))
        .toString();
  }
}

/// A strategy for testing the relationship between objects.  Methods are
/// expected to throw [AssertionError] whenever the relationship is
/// violated.
///
/// As a convenience, any occurrence of [RelationshipTester.itemPlaceholder],
/// [RelationshipTester.relatedPlaceholder] or
/// [RelationshipTester.unrelatedPlaceholder] in the error message will be
/// replaced with a string that combines the [Object.toString], item number and
/// group number of the respective item.
class RelationshipAssertion<T> {
  const RelationshipAssertion(this.assertRelated, this.assertUnrelated);

  final void Function(T item, T related) assertRelated;

  final void Function(T item, T unrelated) assertUnrelated;
}

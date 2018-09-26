// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

import 'order_by.dart';

/// Represents a bound of a query.
///
/// * The bound is specified with the given components representing a position
/// and whether it's just before or just after the position (relative to
/// whatever the query order is).
/// * The position represents a logical index position for a query. It's a
/// prefix of values for the (potentially implicit) order by clauses of a query.
/// * Bound provides a function to determine whether a document comes before or
/// after a bound. This is influenced by whether the position is just before or
/// just after the provided values.
class Bound {
  /// Whether this bound is just before or just after the provided position
  final bool before;

  /// The index position of this bound
  final List<FieldValue> position;

  Bound(this.position, this.before);

  String canonicalString() {
    // TODO: Make this collision robust.
    final StringBuffer builder = StringBuffer();
    if (before) {
      builder.write('b:');
    } else {
      builder.write('a:');
    }
    position.forEach(builder.write);
    return builder.toString();
  }

  /// Returns true if a document sorts before a bound using the provided sort order.
  bool sortsBeforeDocument(List<OrderBy> orderBy, Document document) {
    Assert.hardAssert(position.length <= orderBy.length,
        'Bound has more components than query\'s orderBy');
    int comparison = 0;
    for (int i = 0; i < position.length; i++) {
      final OrderBy orderByComponent = orderBy[i];
      final FieldValue component = position[i];
      if (orderByComponent.field == FieldPath.keyPath) {
        final Object refValue = component.value;
        Assert.hardAssert(refValue is DocumentKey,
            'Bound has a non-key value where the key path is being used $component');
        comparison = (refValue as DocumentKey).compareTo(document.key);
      } else {
        final FieldValue docValue = document.getField(orderByComponent.field);
        Assert.hardAssert(docValue != null,
            'Field should exist since document matched the orderBy already.');
        comparison = component.compareTo(docValue);
      }

      if (orderByComponent.direction == OrderByDirection.descending) {
        comparison = comparison * -1;
      }

      if (comparison != 0) {
        break;
      }
    }

    return before ? comparison <= 0 : comparison < 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Bound &&
          runtimeType == other.runtimeType &&
          before == other.before &&
          position == other.position;

  @override
  int get hashCode => before.hashCode ^ position.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('before', before)
          ..add('position', position))
        .toString();
  }
}

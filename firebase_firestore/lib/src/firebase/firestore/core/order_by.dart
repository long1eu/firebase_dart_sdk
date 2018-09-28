// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

/// The direction of the ordering
class OrderByDirection {
  final int _comparisonModifier;

  const OrderByDirection._(this._comparisonModifier);

  static const OrderByDirection ascending = OrderByDirection._(1);
  static const OrderByDirection descending = OrderByDirection._(-1);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderByDirection &&
          runtimeType == other.runtimeType &&
          _comparisonModifier == other._comparisonModifier;

  @override
  int get hashCode => _comparisonModifier.hashCode;
}

/// Represents a sort order for a Firestore Query
class OrderBy {
  final OrderByDirection direction;
  final FieldPath field;

  const OrderBy(this.direction, this.field);

  factory OrderBy.getInstance(OrderByDirection direction, FieldPath path) {
    return OrderBy(direction, path);
  }

  int compare(Document d1, Document d2) {
    if (field == FieldPath.keyPath) {
      return direction._comparisonModifier * d1.key.compareTo(d2.key);
    } else {
      final FieldValue v1 = d1.getField(field);
      final FieldValue v2 = d2.getField(field);
      Assert.hardAssert(v1 != null && v2 != null,
          'Trying to compare documents on fields that don\'t exist.');
      return direction._comparisonModifier * v1.compareTo(v2);
    }
  }

  @override
  String toString() {
    return (direction == OrderByDirection.ascending ? '' : '-') +
        field.canonicalString;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderBy &&
          runtimeType == other.runtimeType &&
          direction == other.direction &&
          field == other.field;

  @override
  int get hashCode => direction.hashCode * 31 + field.hashCode * 31;
}

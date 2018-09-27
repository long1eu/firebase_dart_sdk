// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/array_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

/// Represents a filter to be applied to query.
class RelationFilter extends Filter {
  final FilterOperator operator;
  final FieldValue value;
  @override
  final FieldPath field;

  /// Creates a new filter that compares fields and values. Only intended to be
  /// called from [Filter.create()].
  const RelationFilter(this.field, this.operator, this.value);

  @override
  bool matches(Document doc) {
    if (field.isKeyField) {
      final DocumentKey refValue = value.value;
      Assert.hardAssert(refValue is DocumentKey,
          'Comparing on key, but filter value not a DocumentKey');
      Assert.hardAssert(operator != FilterOperator.arrayContains,
          'ARRAY_CONTAINS queries don\'t make sense on document keys.');
      final int comparison = doc.key.compareTo(refValue);
      return _matchesComparison(comparison);
    } else {
      final FieldValue value = doc.getField(field);
      return value != null && _matchesValue(value);
    }
  }

  bool _matchesValue(FieldValue other) {
    if (operator == FilterOperator.arrayContains) {
      return other is ArrayValue && other.internalValue.contains(value);
    } else {
      // Only compare types with matching backend order (such as double and int).
      return value.typeOrder == other.typeOrder &&
          _matchesComparison(other.compareTo(value));
    }
  }

  bool _matchesComparison(int comp) {
    switch (operator) {
      case FilterOperator.lessThan:
        return comp < 0;
      case FilterOperator.lessThanOrEqual:
        return comp <= 0;
      case FilterOperator.equal:
        return comp == 0;
      case FilterOperator.graterThan:
        return comp > 0;
      case FilterOperator.graterThanOrEqual:
        return comp >= 0;
      default:
        throw Assert.fail('Unknown operator: $operator');
    }
  }

  bool get isInequality =>
      operator != FilterOperator.equal &&
      operator != FilterOperator.arrayContains;

  // TODO: Technically, this won't be unique if two values have the same
  // description, such as the int 3 and the string "3". So we should add the
  // types in here somehow, too.
  @override
  String get canonicalId => '${field.canonicalString} $operator $value';

  @override
  String toString() => canonicalId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RelationFilter &&
          runtimeType == other.runtimeType &&
          operator == other.operator &&
          value == other.value &&
          field == other.field;

  @override
  int get hashCode => operator.hashCode ^ value.hashCode ^ field.hashCode;
}

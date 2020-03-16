// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of filter;

/// A Filter that implements the array-contains-any operator.
class KeyFieldInFilter extends FieldFilter {
  KeyFieldInFilter(FieldPath field, FieldValue value)
      : super._(field, FilterOperator.IN, value) {
    final ArrayValue arrayValue = value;
    for (FieldValue refValue in arrayValue.internalValue) {
      hardAssert(refValue is ReferenceValue,
          'Comparing on key with IN, but an array value was not a ReferenceValue');
    }
  }

  @override
  bool matches(Document doc) {
    final ArrayValue arrayValue = value;
    for (FieldValue refValue in arrayValue.internalValue) {
      if (doc.key == refValue.value) {
        return true;
      }
    }

    return false;
  }
}

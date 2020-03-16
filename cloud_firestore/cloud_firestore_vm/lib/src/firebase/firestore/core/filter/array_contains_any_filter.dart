// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of filter;

/// A Filter that implements the array-contains-any operator.
class ArrayContainsAnyFilter extends FieldFilter {
  ArrayContainsAnyFilter(FieldPath field, FieldValue value)
      : super._(field, FilterOperator.arrayContainsAny, value);

  @override
  bool matches(Document doc) {
    final ArrayValue arrayValue = value;
    final FieldValue other = doc.getField(field);
    if (other is ArrayValue) {
      for (FieldValue val in other.internalValue) {
        if (arrayValue.internalValue.contains(val)) {
          return true;
        }
      }
    }

    return false;
  }
}

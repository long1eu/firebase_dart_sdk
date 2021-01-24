// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of filter;

/// A Filter that implements the array-contains-any operator.
class ArrayContainsAnyFilter extends FieldFilter {
  ArrayContainsAnyFilter(FieldPath field, Value value) : super._(field, FilterOperator.arrayContainsAny, value) {
    hardAssert(isArray(value), 'ArrayContainsAnyFilter expects an ArrayValue');
  }

  @override
  bool matches(Document doc) {
    final Value other = doc.getField(field);
    if (!isArray(other)) {
      return false;
    }
    for (Value val in other.arrayValue.values) {
      if (contains(value.arrayValue, val)) {
        return true;
      }
    }
    return false;
  }
}

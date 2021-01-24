// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of filter;

/// A Filter that implements the array-contains operator.
class ArrayContainsFilter extends FieldFilter {
  ArrayContainsFilter(FieldPath field, Value value) : super._(field, FilterOperator.arrayContains, value);

  @override
  bool matches(Document doc) {
    final Value other = doc.getField(field);
    return isArray(other) && contains(other.arrayValue, value);
  }
}

// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of filter;

/// A Filter that implements the IN operator.
class NotInFilter extends FieldFilter {
  NotInFilter(FieldPath field, Value value) : super._(field, FilterOperator.notIn, value) {
    hardAssert(isArray(value), 'NotInFilter expects an ArrayValue');
  }

  @override
  bool matches(Document doc) {
    if (contains(value.arrayValue, NULL_VALUE)) {
      return false;
    }
    final Value other = doc.getField(field);
    return other != null && !contains(value.arrayValue, other);
  }
}

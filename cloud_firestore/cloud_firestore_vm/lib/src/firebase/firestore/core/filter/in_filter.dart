// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of filter;

/// A Filter that implements the IN operator.
class InFilter extends FieldFilter {
  InFilter(FieldPath field, Value value) : super._(field, FilterOperator.IN, value) {
    hardAssert(isArray(value), 'InFilter expects an ArrayValue');
  }

  @override
  bool matches(Document doc) {
    final Value other = doc.getField(field);
    return other != null && contains(value.arrayValue, other);
  }
}

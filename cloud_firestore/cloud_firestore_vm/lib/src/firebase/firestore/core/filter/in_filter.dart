// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of filter;

/// A Filter that implements the IN operator.
class InFilter extends FieldFilter {
  InFilter(FieldPath field, FieldValue value)
      : super._(field, FilterOperator.IN, value);

  @override
  bool matches(Document doc) {
    final ArrayValue arrayValue = value;
    final FieldValue other = doc.getField(field);
    return other != null && arrayValue.internalValue.contains(other);
  }
}

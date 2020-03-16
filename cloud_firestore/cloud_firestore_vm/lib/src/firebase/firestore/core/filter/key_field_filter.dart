// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of filter;

/// Filter that matches on key fields (i.e. '__name__').
class KeyFieldFilter extends FieldFilter {
  KeyFieldFilter(FieldPath field, FilterOperator operator, FieldValue value)
      : super._(field, operator, value);

  @override
  bool matches(Document doc) {
    final ReferenceValue referenceValue = value;
    final int comparator = doc.key.compareTo(referenceValue.value);
    return _matchesComparison(comparator);
  }
}

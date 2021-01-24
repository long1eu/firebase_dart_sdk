// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of filter;

/// Filter that matches on key fields (i.e. '__name__').
class KeyFieldFilter extends FieldFilter {
  KeyFieldFilter(FieldPath field, FilterOperator operator, Value value)
      : _key = DocumentKey.fromName(value.referenceValue),
        super._(field, operator, value) {
    hardAssert(isReferenceValue(value), 'KeyFieldFilter expects a ReferenceValue');
  }

  final DocumentKey _key;

  @override
  bool matches(Document doc) {
    final int comparator = doc.key.compareTo(_key);
    return _matchesComparison(comparator);
  }
}

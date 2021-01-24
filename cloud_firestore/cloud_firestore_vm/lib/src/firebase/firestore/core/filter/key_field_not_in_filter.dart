// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of filter;

/// A Filter that implements the array-contains-any operator.
class KeyFieldNotInFilter extends FieldFilter {
  KeyFieldNotInFilter(FieldPath field, Value value)
      : _keys = KeyFieldInFilter.extractDocumentKeysFromArrayValue(FilterOperator.notIn, value),
        super._(field, FilterOperator.notIn, value);

  final List<DocumentKey> _keys;

  @override
  bool matches(Document doc) => !_keys.contains(doc.key);
}

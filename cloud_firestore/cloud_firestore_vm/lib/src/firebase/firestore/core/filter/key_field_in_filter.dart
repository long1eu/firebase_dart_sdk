// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of filter;

/// A Filter that implements the array-contains-any operator.
class KeyFieldInFilter extends FieldFilter {
  KeyFieldInFilter(FieldPath field, Value value)
      : _keys = extractDocumentKeysFromArrayValue(FilterOperator.IN, value),
        super._(field, FilterOperator.IN, value);

  final List<DocumentKey> _keys;

  @override
  bool matches(Document doc) => _keys.contains(doc.key);

  static List<DocumentKey> extractDocumentKeysFromArrayValue(FilterOperator operator, Value value) {
    hardAssert(operator == FilterOperator.IN || operator == FilterOperator.notIn,
        'extractDocumentKeysFromArrayValue requires IN or NOT_IN operators');
    hardAssert(isArray(value), 'KeyFieldInFilter/KeyFieldNotInFilter expects an ArrayValue');
    final List<DocumentKey> keys = <DocumentKey>[];
    for (Value element in value.arrayValue.values) {
      hardAssert(
        isReferenceValue(element),
        'Comparing on key with $operator, but an array value was not a ReferenceValue',
      );
      keys.add(DocumentKey.fromName(element.referenceValue));
    }
    return keys;
  }
}

// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of 'filter.dart';

/// Filter that matches on key fields (i.e. '__name__').
class KeyFieldFilter extends FieldFilter {
  KeyFieldFilter(super.field, super.operator, super.value) : super._();

  @override
  bool matches(Document doc) {
    final ReferenceValue referenceValue = value as ReferenceValue;
    final int comparator = doc.key.compareTo(referenceValue.value);
    return _matchesComparison(comparator);
  }
}

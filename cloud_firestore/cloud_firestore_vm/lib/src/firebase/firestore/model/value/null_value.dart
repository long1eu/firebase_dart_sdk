// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

part of field_value;

/// A wrapper for null values in Firestore.
class NullValue extends FieldValue {
  const NullValue._();

  factory NullValue.nullValue() => _instance;

  static const NullValue _instance = NullValue._();

  @override
  int get typeOrder => FieldValue.typeOrderNull;

  @override
  Object get value => null;

  @override
  int compareTo(FieldValue other) {
    if (other is NullValue || other == null) {
      return 0;
    } else {
      return defaultCompareTo(other);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NullValue && runtimeType == other.runtimeType;

  @override
  int get hashCode => -1;
}

// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

part of field_value;

/// A wrapper for blob values in Firestore.
class BlobValue extends FieldValue {
  const BlobValue(this._value);

  factory BlobValue.valueOf(Blob blob) => BlobValue(blob);

  final Blob _value;

  @override
  int get typeOrder => FieldValue.typeOrderBlob;

  @override
  Blob get value => _value;

  @override
  int compareTo(FieldValue other) {
    if (other is BlobValue) {
      return _value.compareTo(other._value);
    } else {
      return defaultCompareTo(other);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlobValue &&
          runtimeType == other.runtimeType &&
          _value == other._value;

  @override
  int get hashCode => _value.hashCode;
}

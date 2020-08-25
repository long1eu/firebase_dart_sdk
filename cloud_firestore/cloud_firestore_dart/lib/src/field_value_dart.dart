// File created by
// Lung Razvan <long1eu>
// on 18/04/2020

part of cloud_firestore_dart_implementation;

/// Implementation of [FieldValuePlatform] that is compatible with firestore dart
/// plugin
class FieldValueDart {
  /// Constructs a dart version of [FieldValuePlatform] wrapping a dart
  /// [FieldValue].
  FieldValueDart(this.data);

  /// The dart delegate for this [FieldValuePlatform]
  dart.FieldValue data;

  @override
  bool operator ==(dynamic other) =>
      other is FieldValueDart && other.data == data;

  @override
  int get hashCode => data.hashCode;
}

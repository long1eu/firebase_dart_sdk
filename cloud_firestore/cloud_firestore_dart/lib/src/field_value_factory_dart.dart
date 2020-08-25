// File created by
// Lung Razvan <long1eu>
// on 18/04/2020

part of cloud_firestore_dart_implementation;

/// An implementation of [FieldValueFactoryPlatform] which builds
/// [FieldValuePlatform] instance
class FieldValueFactoryDart extends FieldValueFactoryPlatform {
  @override
  FieldValueDart arrayRemove(List<dynamic> elements) => FieldValueDart(
      dart.FieldValue.arrayRemove(CodecUtility.valueEncode(elements)));

  @override
  FieldValueDart arrayUnion(List<dynamic> elements) => FieldValueDart(
      dart.FieldValue.arrayUnion(CodecUtility.valueEncode(elements)));

  @override
  FieldValueDart delete() => FieldValueDart(dart.FieldValue.delete());

  @override
  FieldValueDart increment(num value) =>
      FieldValueDart(dart.FieldValue.increment(value));

  @override
  FieldValueDart serverTimestamp() =>
      FieldValueDart(dart.FieldValue.serverTimestamp());
}

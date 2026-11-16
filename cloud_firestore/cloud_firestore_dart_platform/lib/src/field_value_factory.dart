import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as fs;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'value_codec.dart';

/// A [FieldValueFactoryPlatform] whose values are `cloud_firestore_dart`
/// [fs.FieldValue]s.
///
/// `cloud_firestore`'s `FieldValue` reads `FieldValueFactoryPlatform.instance`
/// once, on its first use; register this factory before that (the
/// registration functions of this package do).
class DartFieldValueFactory extends FieldValueFactoryPlatform {
  @override
  fs.FieldValue arrayUnion(List<dynamic> elements) =>
      fs.FieldValue.arrayUnion(elements.map(ValueCodec.encode).toList());

  @override
  fs.FieldValue arrayRemove(List<dynamic> elements) =>
      fs.FieldValue.arrayRemove(elements.map(ValueCodec.encode).toList());

  @override
  fs.FieldValue delete() => fs.FieldValue.delete();

  @override
  fs.FieldValue serverTimestamp() => fs.FieldValue.serverTimestamp();

  @override
  fs.FieldValue increment(num value) => fs.FieldValue.increment(value);

  @override
  fs.FieldValue minimum(num value) => fs.FieldValue.minimum(value);

  @override
  fs.FieldValue maximum(num value) => fs.FieldValue.maximum(value);
}

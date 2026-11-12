import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/set_options.dart';

/// Turns [data] into the raw map to write, applying [converter] if present.
Map<String, Object?> toRawData<T>(
    T data, FirestoreDataConverter<T>? converter, SetOptions? options) {
  if (converter == null) {
    return data as Map<String, Object?>;
  }
  return converter.toFirestore(data, options);
}

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as fs;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'document_reference.dart';
import 'errors.dart';
import 'firestore.dart';
import 'value_codec.dart';

/// A [WriteBatchPlatform] backed by `cloud_firestore_dart`.
class DartWriteBatch extends WriteBatchPlatform {
  /// A new batch of [firestore].
  DartWriteBatch(this._firestore) : _batch = _firestore.delegate.batch();

  final DartFirebaseFirestore _firestore;
  final fs.WriteBatch _batch;

  @override
  Future<void> commit() => guard(_batch.commit);

  @override
  void delete(String documentPath) {
    guardSync(() => _batch.delete(_firestore.delegate.doc(documentPath)));
  }

  @override
  void set(
    String documentPath,
    Map<String, dynamic> data, [
    SetOptions? options,
  ]) {
    guardSync(() {
      final fs.DocumentReference<Map<String, Object?>> ref = _firestore.delegate
          .doc(documentPath);
      final Map<String, Object?> encoded = ValueCodec.encodeMap(data);
      final fs.SetOptions? setOptions = setOptionsOf(options);
      return setOptions == null
          ? _batch.set(ref, encoded)
          : _batch.set(ref, encoded, setOptions);
    });
  }

  @override
  void update(String documentPath, Map<FieldPath, dynamic> data) {
    guardSync(() {
      final fs.DocumentReference<Map<String, Object?>> ref = _firestore.delegate
          .doc(documentPath);
      return data.isEmpty
          ? _batch.update(ref, <String, Object?>{})
          : _batch.updateFromList(ref, ValueCodec.encodeUpdate(data));
    });
  }
}

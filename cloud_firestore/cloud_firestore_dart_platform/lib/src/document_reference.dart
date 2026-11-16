import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as fs;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'errors.dart';
import 'firestore.dart';
import 'snapshots.dart';
import 'value_codec.dart';

/// The `cloud_firestore_dart` set options for [options] of the platform
/// interface, or null for an overwrite.
fs.SetOptions? setOptionsOf(SetOptions? options) {
  if (options == null) {
    return null;
  }
  final List<FieldPath>? fields = options.mergeFields;
  if (fields != null) {
    return fs.SetOptions.mergeFieldPaths(<fs.FieldPath>[
      for (final FieldPath field in fields) fs.FieldPath.of(field.components),
    ]);
  }
  return options.merge ?? false
      ? fs.SetOptions.mergeAllFields
      : fs.SetOptions.overwrite;
}

/// A [DocumentReferencePlatform] backed by `cloud_firestore_dart`.
class DartDocumentReference extends DocumentReferencePlatform {
  /// The document at [path] of [firestore].
  DartDocumentReference(DartFirebaseFirestore super.firestore, super.path);

  DartFirebaseFirestore get _firestore => firestore as DartFirebaseFirestore;

  fs.DocumentReference<Map<String, Object?>> get _delegate =>
      _firestore.delegate.doc(path);

  @override
  Future<void> delete() => guard(() => _delegate.delete());

  @override
  Future<DocumentSnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) {
    return guard(() async {
      final fs.DocumentSnapshot<Map<String, Object?>> snapshot = await _delegate
          .get(sourceOf(options.source));
      return documentSnapshotOf(
        _firestore,
        snapshot,
        options.serverTimestampBehavior,
      );
    });
  }

  @override
  Stream<DocumentSnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required ListenSource listenSource,
  }) {
    return guardStream(
      _firestore.lazyStream(
        () => _delegate.getSnapshotsWithOptions(
          listenOptionsOf(
            includeMetadataChanges: includeMetadataChanges,
            listenSource: listenSource,
          ),
        ),
      ),
    ).map(
      (fs.DocumentSnapshot<Map<String, Object?>> snapshot) =>
          documentSnapshotOf(_firestore, snapshot),
    );
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) {
    return guard(() {
      final Map<String, Object?> encoded = ValueCodec.encodeMap(data);
      final fs.SetOptions? setOptions = setOptionsOf(options);
      return setOptions == null
          ? _delegate.set(encoded)
          : _delegate.set(encoded, setOptions);
    });
  }

  @override
  Future<void> update(Map<FieldPath, dynamic> data) {
    return guard(() {
      if (data.isEmpty) {
        // updateFromList needs at least one field and value pair.
        return _delegate.update(<String, Object?>{});
      }
      return _delegate.updateFromList(ValueCodec.encodeUpdate(data));
    });
  }
}

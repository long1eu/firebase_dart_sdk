// File created by
// Lung Razvan <long1eu>
// on 17/04/2020

part of cloud_firestore_dart_implementation;

/// Dart implementation for firestore [DocumentReferencePlatform]
class DocumentReferenceDart extends DocumentReferencePlatform {
  /// Creates an instance of [CollectionReferenceDart] which represents path
  /// at [pathComponents] and uses implementation of [_firestoreDart]
  DocumentReferenceDart(
    this._firestoreDart,
    FirestorePlatform firestore,
    List<String> pathComponents,
  )   : _delegate = _firestoreDart.document(pathComponents.join('/')),
        super(firestore, pathComponents);

  /// instance of Firestore from the dart plugin
  // ignore: unused_field
  final dart.Firestore _firestoreDart;

  /// instance of DocumentReference from the dart plugin
  final dart.DocumentReference _delegate;

  @override
  Future<void> setData(
    Map<String, dynamic> data, {
    bool merge = false,
  }) {
    return _delegate.set(
      CodecUtility.encodeMapData(data),
      merge ? dart.SetOptions.mergeAllFields : null,
    );
  }

  @override
  Future<void> updateData(Map<String, dynamic> data) {
    return _delegate.update(CodecUtility.encodeMapData(data));
  }

  @override
  Future<DocumentSnapshotPlatform> get({
    Source source = Source.serverAndCache,
  }) async {
    return fromDartDocumentSnapshotToPlatformDocumentSnapshot(
        await _delegate.get(), firestore);
  }

  @override
  Future<void> delete() => _delegate.delete();

  @override
  Stream<DocumentSnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
  }) {
    return _delegate
        .getSnapshots(includeMetadataChanges
            ? dart.MetadataChanges.include
            : dart.MetadataChanges.exclude)
        .map((dart.DocumentSnapshot dartSnapshot) =>
            fromDartDocumentSnapshotToPlatformDocumentSnapshot(
                dartSnapshot, firestore));
  }
}

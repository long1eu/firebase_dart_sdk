import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as fs;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'firestore.dart';
import 'value_codec.dart';

/// The behaviour of `cloud_firestore_dart` for a [ServerTimestampBehavior] of
/// the platform interface.
fs.ServerTimestampBehavior serverTimestampBehaviorOf(
  ServerTimestampBehavior behavior,
) {
  return switch (behavior) {
    ServerTimestampBehavior.none => fs.ServerTimestampBehavior.none,
    ServerTimestampBehavior.estimate => fs.ServerTimestampBehavior.estimate,
    ServerTimestampBehavior.previous => fs.ServerTimestampBehavior.previous,
  };
}

/// The `cloud_firestore_dart` get options for [options] of the platform
/// interface. The server timestamp behaviour is applied when the data is read
/// (see [documentSnapshotOf]).
fs.GetOptions getOptionsOf(GetOptions options) {
  return fs.GetOptions(
    source: switch (options.source) {
      Source.serverAndCache => fs.Source.serverAndCache,
      Source.server => fs.Source.server,
      Source.cache => fs.Source.cache,
    },
  );
}

/// The `cloud_firestore_dart` listen source for [source].
fs.ListenSource listenSourceOf(ListenSource source) {
  return switch (source) {
    ListenSource.defaultSource => fs.ListenSource.defaultSource,
    ListenSource.cache => fs.ListenSource.cache,
  };
}

/// A [DocumentSnapshotPlatform] for a `cloud_firestore_dart` snapshot.
///
/// The data is read once, with [behavior] for the server timestamps that are
/// not set yet, and converted to the platform interface types.
DocumentSnapshotPlatform documentSnapshotOf(
  DartFirebaseFirestore firestore,
  fs.DocumentSnapshot<Map<String, Object?>> snapshot, [
  ServerTimestampBehavior behavior = ServerTimestampBehavior.none,
]) {
  final Map<String, Object?>? data = snapshot.data(
    serverTimestamps: serverTimestampBehaviorOf(behavior),
  );
  return DocumentSnapshotPlatform(
    firestore,
    snapshot.reference.path,
    data == null ? null : ValueCodec.decodeMap(data, firestore),
    InternalSnapshotMetadata(
      hasPendingWrites: snapshot.metadata.hasPendingWrites,
      isFromCache: snapshot.metadata.isFromCache,
    ),
  );
}

/// A [QuerySnapshotPlatform] for a `cloud_firestore_dart` query snapshot.
///
/// Its document changes follow the listen that produced it: with
/// `includeMetadataChanges`, documents whose only change is in their metadata
/// are listed as `modified`, as with the official plugin.
QuerySnapshotPlatform querySnapshotOf(
  DartFirebaseFirestore firestore,
  fs.QuerySnapshot<Map<String, Object?>> snapshot, {
  ServerTimestampBehavior behavior = ServerTimestampBehavior.none,
}) {
  final Map<String, DocumentSnapshotPlatform> converted =
      <String, DocumentSnapshotPlatform>{};
  DocumentSnapshotPlatform convert(
    fs.DocumentSnapshot<Map<String, Object?>> document,
  ) {
    return converted[document.reference.path] ??= documentSnapshotOf(
      firestore,
      document,
      behavior,
    );
  }

  final List<DocumentSnapshotPlatform> docs = <DocumentSnapshotPlatform>[
    for (final fs.QueryDocumentSnapshot<Map<String, Object?>> document
        in snapshot.docs)
      convert(document),
  ];
  final List<DocumentChangePlatform> changes = <DocumentChangePlatform>[
    for (final fs.DocumentChange<Map<String, Object?>> change
        in snapshot.docChanges)
      DocumentChangePlatform(
        switch (change.type) {
          fs.DocumentChangeType.added => DocumentChangeType.added,
          fs.DocumentChangeType.modified => DocumentChangeType.modified,
          fs.DocumentChangeType.removed => DocumentChangeType.removed,
        },
        change.oldIndex,
        change.newIndex,
        // A removed document is not in docs; convert it on its own.
        convert(change.doc),
      ),
  ];
  return QuerySnapshotPlatform(
    docs,
    changes,
    SnapshotMetadataPlatform(
      snapshot.metadata.hasPendingWrites,
      snapshot.metadata.isFromCache,
    ),
  );
}

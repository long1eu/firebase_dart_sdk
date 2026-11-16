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

/// The `cloud_firestore_dart` source of a [Source] of the platform interface.
fs.Source sourceOf(Source source) {
  return switch (source) {
    Source.serverAndCache => fs.Source.serverAndCache,
    Source.server => fs.Source.server,
    Source.cache => fs.Source.cache,
  };
}

/// The `cloud_firestore_dart` listen options for the arguments of `snapshots`.
fs.SnapshotListenOptions listenOptionsOf({
  required bool includeMetadataChanges,
  required ListenSource listenSource,
}) {
  return fs.SnapshotListenOptions(
    metadataChanges: includeMetadataChanges
        ? fs.MetadataChanges.include
        : fs.MetadataChanges.exclude,
    source: switch (listenSource) {
      ListenSource.defaultSource => fs.ListenSource.defaultSource,
      ListenSource.cache => fs.ListenSource.cache,
    },
  );
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
  final Map<String, Object?>? data = snapshot.getData(
    serverTimestampBehaviorOf(behavior),
  );
  return DocumentSnapshotPlatform(
    firestore,
    snapshot.ref.path,
    data == null ? null : ValueCodec.decodeMap(data, firestore),
    InternalSnapshotMetadata(
      hasPendingWrites: snapshot.metadata.hasPendingWrites,
      isFromCache: snapshot.metadata.isFromCache,
    ),
  );
}

/// A [QuerySnapshotPlatform] for a `cloud_firestore_dart` query snapshot.
///
/// [includeMetadataChanges] selects the document changes: with it, documents
/// whose only change is in their metadata are listed as `modified`, as the
/// official plugin does for a listener with metadata changes.
QuerySnapshotPlatform querySnapshotOf(
  DartFirebaseFirestore firestore,
  fs.QuerySnapshot<Map<String, Object?>> snapshot, {
  ServerTimestampBehavior behavior = ServerTimestampBehavior.none,
  bool includeMetadataChanges = false,
}) {
  final Map<String, DocumentSnapshotPlatform> converted =
      <String, DocumentSnapshotPlatform>{};
  DocumentSnapshotPlatform convert(
    fs.DocumentSnapshot<Map<String, Object?>> document,
  ) {
    return converted[document.ref.path] ??= documentSnapshotOf(
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
        in snapshot.getDocumentChanges(
          includeMetadataChanges
              ? fs.MetadataChanges.include
              : fs.MetadataChanges.exclude,
        ))
      DocumentChangePlatform(
        switch (change.type) {
          fs.DocumentChangeType.added => DocumentChangeType.added,
          fs.DocumentChangeType.modified => DocumentChangeType.modified,
          fs.DocumentChangeType.removed => DocumentChangeType.removed,
        },
        change.oldIndex,
        change.newIndex,
        // A removed document is not in docs; convert it on its own.
        convert(change.document),
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

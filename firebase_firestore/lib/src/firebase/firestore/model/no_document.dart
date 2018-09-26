// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';

/// Represents that no documents exists for the key at the given version.
class NoDocument extends MaybeDocument {
  const NoDocument(DocumentKey key, SnapshotVersion version)
      : super(key, version);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoDocument &&
          runtimeType == other.runtimeType &&
          key == other.key &&
          version == other.version;

  @override
  int get hashCode => key.hashCode ^ version.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('key', key)
          ..add('version', version))
        .toString();
  }
}

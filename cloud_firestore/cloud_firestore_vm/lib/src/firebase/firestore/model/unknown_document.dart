// File created by
// Lung Razvan <long1eu>
// on 15/10/2018

import 'package:firebase_core/firebase_core_vm.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';

/// A class representing an existing document whose data is unknown (e.g. a document that was
/// updated without a known base document).
class UnknownDocument extends MaybeDocument {
  UnknownDocument(DocumentKey key, SnapshotVersion version) : super(key, version);

  @override
  bool get hasPendingWrites => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnknownDocument && runtimeType == other.runtimeType && version == other.version && key == other.key;

  @override
  int get hashCode => key.hashCode ^ version.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)..add('key', key)..add('version', version)).toString();
  }
}

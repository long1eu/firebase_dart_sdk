// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/object_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/document.pb.dart';

/// Describes the hasPendingWrites state of a document.
enum DocumentState {
  /// Local mutations applied via the mutation queue. Document is potentially inconsistent.
  localMutations,

  /// Mutations applied based on a write acknowledgment. Document is potentially inconsistent.
  committedMutations,

  /// No mutations applied. Document was sent to us by Watch.
  synced
}

class Document extends MaybeDocument implements Comparable<Document> {
  Document(
    DocumentKey key,
    SnapshotVersion version,
    this._objectValue,
    this.documentState,
  ) : super(key, version);

  final DocumentState documentState;
  final ObjectValue _objectValue;

  ObjectValue get data => _objectValue;

  Value getField(FieldPath path) => _objectValue[path];

  bool get hasLocalMutations {
    return documentState == DocumentState.localMutations;
  }

  bool get hasCommittedMutations {
    return documentState == DocumentState.committedMutations;
  }

  @override
  bool get hasPendingWrites => hasLocalMutations || hasCommittedMutations;

  static int keyComparator(Document left, Document right) => left.key.compareTo(right.key);

  @override
  int compareTo(Document other) => key.compareTo(other.key);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Document &&
          runtimeType == other.runtimeType &&
          version == other.version &&
          key == other.key &&
          documentState == other.documentState &&
          _objectValue == other._objectValue;

  @override
  int get hashCode {
    return key.hashCode ^ //
        version.hashCode ^
        documentState.hashCode ^
        _objectValue.hashCode;
  }

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('key', key)
          ..add('data', data)
          ..add('version', version)
          ..add('documentState', documentState))
        .toString();
  }
}

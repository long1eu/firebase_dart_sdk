// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';

/// Describes the hasPendingWrites state of a document.
enum DocumentState {
  /// Local mutations applied via the mutation queue. Document is potentially
  /// inconsistent.
  localMutations,

  /// Mutations applied based on a write acknowledgment. Document is potentially
  /// inconsistent.
  committedMutations,

  /// No mutations applied. Document was sent to us by Watch.
  synced
}

class Document extends MaybeDocument implements Comparable<Document> {
  final ObjectValue data;
  final DocumentState documentState;

  const Document(
      DocumentKey key, SnapshotVersion version, this.data, this.documentState)
      : super(key, version);

  static int keyComparator(Document left, Document right) =>
      left.key.compareTo(right.key);

  FieldValue getField(FieldPath path) => data.get(path);

  Object getFieldValue(FieldPath path) {
    final FieldValue value = getField(path);
    return value?.value;
  }

  bool get hasLocalMutations {
    return documentState == DocumentState.localMutations;
  }

  bool get hasCommittedMutations {
    return documentState == DocumentState.committedMutations;
  }

  @override
  bool get hasPendingWrites => hasLocalMutations || hasCommittedMutations;

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
          data == other.data;

  @override
  int get hashCode =>
      key.hashCode ^ data.hashCode ^ version.hashCode ^ documentState.hashCode;

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

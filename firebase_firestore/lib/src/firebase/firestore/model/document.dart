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

class Document extends MaybeDocument implements Comparable<Document> {
  final ObjectValue data;
  final bool hasLocalMutations;

  static final Comparator<Document> keyComparator =
      (Document left, Document right) => left.key.compareTo(right.key);

  const Document(DocumentKey key, SnapshotVersion version, this.data,
      this.hasLocalMutations)
      : super(key, version);

  FieldValue getField(FieldPath path) => data.get(path);

  Object getFieldValue(FieldPath path) {
    final FieldValue value = getField(path);
    return value?.value;
  }

  @override
  int compareTo(Document other) => key.compareTo(other.key);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Document &&
          runtimeType == other.runtimeType &&
          version == other.version &&
          key == other.key &&
          hasLocalMutations == other.hasLocalMutations &&
          data == other.data;

  @override
  int get hashCode =>
      data.hashCode ^
      hasLocalMutations.hashCode ^
      key.hashCode ^
      version.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('key', key)
          ..add('data', data)
          ..add('version', version)
          ..add('hasLocalMutations', hasLocalMutations))
        .toString();
  }
}

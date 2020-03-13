// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';

/// A wrapper for reference values in Firestore.
class ReferenceValue extends FieldValue {
  const ReferenceValue(this.databaseId, this.key);

  factory ReferenceValue.valueOf(DatabaseId databaseId, DocumentKey key) {
    return ReferenceValue(databaseId, key);
  }

  final DatabaseId databaseId;
  final DocumentKey key;

  @override
  int get typeOrder => FieldValue.typeOrderReference;

  @override
  DocumentKey get value => key;

  @override
  int compareTo(FieldValue other) {
    if (other is ReferenceValue) {
      final int cmp = databaseId.compareTo(other.databaseId);
      return cmp != 0 ? cmp : key.compareTo(other.key);
    } else {
      return defaultCompareTo(other);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReferenceValue &&
          runtimeType == other.runtimeType &&
          databaseId == other.databaseId &&
          key == other.key;

  @override
  int get hashCode => databaseId.hashCode ^ key.hashCode;
}

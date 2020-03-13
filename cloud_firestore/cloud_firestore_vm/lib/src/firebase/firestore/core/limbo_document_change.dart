// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';

/// The type of the change.
enum LimboDocumentChangeType { added, removed }

/// Change to a particular document wrt to whether it is in 'limbo'.
class LimboDocumentChange {
  const LimboDocumentChange(this.type, this.key);

  final LimboDocumentChangeType type;
  final DocumentKey key;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LimboDocumentChange &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          key == other.key;

  @override
  int get hashCode => type.hashCode ^ key.hashCode;
}

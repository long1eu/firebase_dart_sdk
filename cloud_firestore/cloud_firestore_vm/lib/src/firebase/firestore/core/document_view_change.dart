// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';

/// The types of changes that can happen to a document with respect to a view.
class DocumentViewChangeType implements Comparable<DocumentViewChangeType> {
  const DocumentViewChangeType._(this._i);

  final int _i;

  static const DocumentViewChangeType removed = DocumentViewChangeType._(0);
  static const DocumentViewChangeType added = DocumentViewChangeType._(1);
  static const DocumentViewChangeType modified = DocumentViewChangeType._(2);
  static const DocumentViewChangeType metadata = DocumentViewChangeType._(3);

  @override
  int compareTo(DocumentViewChangeType other) => _i.compareTo(other._i);

  static const List<DocumentViewChangeType> values = <DocumentViewChangeType>[
    removed,
    added,
    modified,
    metadata,
  ];

  static const List<String> _values = <String>[
    'removed',
    'added',
    'modified',
    'metadata',
  ];

  @override
  String toString() => _values[_i];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentViewChangeType &&
          runtimeType == other.runtimeType &&
          _i == other._i;

  @override
  int get hashCode => _i.hashCode;
}

class DocumentViewChange {
  const DocumentViewChange(this.type, this.document);

  final DocumentViewChangeType type;
  final Document document;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentViewChange &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          document == other.document;

  @override
  int get hashCode => type.hashCode ^ document.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType) //
          ..add('type', type)
          ..add('document', document))
        .toString();
  }
}

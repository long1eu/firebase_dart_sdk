// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';

/// The types of changes that can happen to a document with respect to a view.
/// * NOTE: We sort document changes by their type, so the ordering of this enum
/// is significant.
class DocumentViewChangeType implements Comparable<DocumentViewChangeType> {
  final int _i;

  const DocumentViewChangeType._(this._i);

  static const DocumentViewChangeType removed =
      const DocumentViewChangeType._(0);
  static const DocumentViewChangeType added = //
      const DocumentViewChangeType._(1);
  static const DocumentViewChangeType modified =
      const DocumentViewChangeType._(2);
  static const DocumentViewChangeType metadata =
      const DocumentViewChangeType._(3);

  @override
  int compareTo(DocumentViewChangeType other) => _i.compareTo(other._i);

  static const List<String> _values = const <String>[
    'removed',
    'added',
    'modified',
    'metadata'
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
  final DocumentViewChangeType type;
  final Document document;

  const DocumentViewChange(this.type, this.document);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentViewChange &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          document == other.document;

  @override
  int get hashCode => type.hashCode * 31 + document.hashCode * 31;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('type', type)
          ..add('document', document))
        .toString();
  }
}

// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:collection/collection.dart';
import 'package:firebase_app_dart/internal.dart';

import 'order_by.dart';

/// Represents a bound of a query.
///
/// The bound is specified with the given components representing a position and
/// whether it's just before or just after the position (relative to whatever
/// the query order is). The position represents a logical index position for a
/// query. It's a prefix of values for the (potentially implicit) order by
/// clauses of a query. Bound provides a function to determine whether a
/// document comes before or after a bound. This is influenced by whether the
/// position is just before or just after the provided values.
class Bound {
  const Bound({required this.position, required this.inclusive});

  /// Whether this bound includes the provided position: true for `startAt()`
  /// and `endAt()`, false for `startAfter()` and `endBefore()`.
  final bool inclusive;

  /// The index position of this bound
  final List<FieldValue> position;

  /// The position as it is written into the canonical id of a target.
  ///
  /// PORTING NOTE: upstream separates the values with a comma. The port never
  /// did, and canonical ids are persisted with the targets, so it stays.
  String positionString() {
    // TODO(long1eu): Make this collision robust.
    final StringBuffer builder = StringBuffer();
    position.forEach(builder.write);
    return builder.toString();
  }

  /// Returns true if a document sorts before a bound using the provided sort
  /// order.
  bool sortsBeforeDocument(List<OrderBy> orderBy, Document document) {
    final int comparison = _compareToDocument(orderBy, document);
    return inclusive ? comparison <= 0 : comparison < 0;
  }

  /// Returns true if a document sorts after a bound using the provided sort
  /// order.
  bool sortsAfterDocument(List<OrderBy> orderBy, Document document) {
    final int comparison = _compareToDocument(orderBy, document);
    return inclusive ? comparison >= 0 : comparison > 0;
  }

  int _compareToDocument(List<OrderBy> orderBy, Document document) {
    hardAssert(position.length <= orderBy.length,
        'Bound has more components than query\'s orderBy');
    int comparison = 0;
    for (int i = 0; i < position.length; i++) {
      final OrderBy orderByComponent = orderBy[i];
      final FieldValue component = position[i];
      if (orderByComponent.field == FieldPath.keyPath) {
        final Object? refValue = component.value;
        hardAssertLazy(
            refValue is DocumentKey,
            () =>
                'Bound has a non-key value where the key path is being used $component');

        final DocumentKey documentKey = refValue as DocumentKey;
        comparison = documentKey.compareTo(document.key);
      } else {
        final FieldValue? docValue = document.getField(orderByComponent.field);
        hardAssert(docValue != null,
            'Field should exist since document matched the orderBy already.');
        comparison = component.compareTo(docValue!);
      }

      if (orderByComponent.direction == OrderByDirection.descending) {
        comparison = comparison * -1;
      }

      if (comparison != 0) {
        break;
      }
    }

    return comparison;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Bound &&
          runtimeType == other.runtimeType &&
          inclusive == other.inclusive &&
          const ListEquality<FieldValue>().equals(position, other.position);

  @override
  int get hashCode =>
      inclusive.hashCode ^ const ListEquality<FieldValue>().hash(position);

  @override
  String toString() {
    return (ToStringHelper(runtimeType) //
          ..add('inclusive', inclusive)
          ..add('position', position))
        .toString();
  }
}

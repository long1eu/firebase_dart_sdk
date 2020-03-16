// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

library filter;

import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';

part 'array_contains_any_filter.dart';
part 'array_contains_filter.dart';
part 'field_filter.dart';
part 'filter_operator.dart';
part 'in_filter.dart';
part 'key_field_filter.dart';
part 'key_field_in_filter.dart';

/// Interface used for all query filters.
abstract class Filter {
  const Filter._();

  /// Returns the field the Filter operates over.
  FieldPath get field;

  /// A unique ID identifying the filter; used when serializing queries.
  String get canonicalId;

  /// Returns true if a document matches the filter.
  bool matches(Document doc);
}

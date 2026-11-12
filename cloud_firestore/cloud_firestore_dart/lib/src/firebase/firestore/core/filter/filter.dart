// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

library filter;

import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:collection/collection.dart';

part 'array_contains_any_filter.dart';
part 'array_contains_filter.dart';
part 'composite_filter.dart';
part 'field_filter.dart';
part 'filter_operator.dart';
part 'in_filter.dart';
part 'key_field_filter.dart';
part 'key_field_in_filter.dart';
part 'key_field_not_in_filter.dart';
part 'not_in_filter.dart';

/// Interface used for all query filters.
abstract class Filter {
  const Filter._();

  /// A unique ID identifying the filter; used when serializing queries.
  String get canonicalId;

  /// Returns true if a document matches the filter.
  bool matches(Document doc);

  /// Returns a list of all field filters that are contained within this filter
  /// (a [FieldFilter] returns itself).
  List<FieldFilter> get flattenedFilters;

  /// Returns a list of all filters that are contained within this filter (a
  /// [FieldFilter] returns itself, a [CompositeFilter] its direct children).
  List<Filter> get filters;
}

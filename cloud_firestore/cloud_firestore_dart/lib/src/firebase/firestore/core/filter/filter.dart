// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

library;

import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/canonical_value.dart';
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

/// Whether [value] is a NaN (a double or a 128-bit decimal).
bool _isNaN(FieldValue? value) =>
    value is DoubleValue && value.value.isNaN ||
    value is Decimal128FieldValue && value.isNaN;

/// Whether the backend considers [a] and [b] the same value in a membership
/// filter (`in`, `not-in`, `array-contains`, `array-contains-any`).
///
/// Numbers are the same if they have the same numeric value, whatever their
/// type: the integer 1 is the double 1.0, and 0.0 is -0.0. `==` of
/// [FieldValue] tells these apart.
///
/// PORTING NOTE: the JS and Android SDKs use the strict equality of values
/// here (1 is not 1.0) and then disagree with the backend. A cached document
/// that only the SDK matches stays in limbo forever: the query never gets in
/// sync and `get(Source.server)` does not complete.
///
/// Null and NaN are the same as themselves here, as in the other SDKs. That
/// is what an Enterprise edition database does; a Standard edition database
/// never matches them in these filters (`in [null]` matches nothing). There
/// a cached null or NaN document is a result for the client only, until the
/// view drops it (see `View.backendMismatches`).
bool _sameForBackend(FieldValue a, FieldValue b) => a.compareTo(b) == 0;

bool _containsForBackend(List<FieldValue> values, FieldValue value) =>
    values.any((FieldValue element) => _sameForBackend(element, value));

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

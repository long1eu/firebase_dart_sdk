// File created by
// Lung Razvan <long1eu>
// on 24/09/2018

import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;

/// Simplest form of existence filter, optionally carrying the bloom filter the
/// backend sends in `unchanged_names`.
class ExistenceFilter {
  const ExistenceFilter(this.count, [this.unchangedNames]);

  final int count;

  /// The bloom filter of the documents that did not change since the resume
  /// token, or `null` if the backend did not provide one.
  final proto.BloomFilter? unchangedNames;

  @override
  String toString() =>
      'ExistenceFilter{count:$count, unchangedNames:$unchangedNames}';
}

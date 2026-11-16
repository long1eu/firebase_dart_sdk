import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as fs;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'errors.dart';
import 'query.dart';

/// One aggregation that `cloud_firestore` asked for: its type and, for a sum or
/// an average, the field as `cloud_firestore` named it.
typedef Aggregation = ({AggregateType type, String? field});

/// An [AggregateQueryPlatform] backed by `cloud_firestore_dart`.
class DartAggregateQuery extends AggregateQueryPlatform {
  /// The [aggregations] over [query].
  DartAggregateQuery(DartQuery super.query, this.aggregations);

  /// The aggregations, in the order they were requested.
  final List<Aggregation> aggregations;

  DartAggregateQuery _with(Aggregation aggregation) {
    return DartAggregateQuery(query as DartQuery, <Aggregation>[
      ...aggregations,
      aggregation,
    ]);
  }

  static fs.AggregateField _fieldOf(Aggregation aggregation) {
    return switch (aggregation.type) {
      AggregateType.count => fs.AggregateField.count(),
      AggregateType.sum => fs.AggregateField.sum(aggregation.field!),
      AggregateType.average => fs.AggregateField.average(aggregation.field!),
    };
  }

  @override
  Future<AggregateQuerySnapshotPlatform> get({
    required AggregateSource source,
  }) {
    return guard(() async {
      final List<fs.AggregateField> fields = aggregations
          .map(_fieldOf)
          .toList();
      final fs.AggregateQuerySnapshot snapshot = await (query as DartQuery)
          .buildQuery()
          .aggregate(fields)
          .get(
            source: switch (source) {
              AggregateSource.server => fs.AggregateSource.server,
            },
          );
      final List<AggregateQueryResponse> sums = <AggregateQueryResponse>[];
      final List<AggregateQueryResponse> averages = <AggregateQueryResponse>[];
      for (int i = 0; i < aggregations.length; i++) {
        final Aggregation aggregation = aggregations[i];
        if (aggregation.type == AggregateType.count) {
          continue;
        }
        final AggregateQueryResponse response = AggregateQueryResponse(
          type: aggregation.type,
          field: aggregation.field,
          // FlutterFire reports sums and averages as doubles.
          value: (snapshot.get(fields[i]) as num?)?.toDouble(),
        );
        (aggregation.type == AggregateType.sum ? sums : averages).add(response);
      }
      return AggregateQuerySnapshotPlatform(
        count: snapshot.count,
        sum: sums,
        average: averages,
      );
    });
  }

  @override
  AggregateQueryPlatform count() =>
      _with((type: AggregateType.count, field: null));

  @override
  AggregateQueryPlatform sum(String field) =>
      _with((type: AggregateType.sum, field: field));

  @override
  AggregateQueryPlatform average(String field) =>
      _with((type: AggregateType.average, field: field));
}

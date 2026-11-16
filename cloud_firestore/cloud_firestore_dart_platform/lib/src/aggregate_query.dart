import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as fs;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'errors.dart';
import 'query.dart';

/// An [AggregateQueryPlatform] backed by `cloud_firestore_dart`.
class DartAggregateQuery extends AggregateQueryPlatform {
  /// The aggregation of [fields] over [query].
  DartAggregateQuery(DartQuery super.query, this.fields);

  /// The aggregations, in the order they were requested.
  final List<fs.AggregateField> fields;

  DartAggregateQuery _with(fs.AggregateField field) {
    return DartAggregateQuery(query as DartQuery, <fs.AggregateField>[
      ...fields,
      field,
    ]);
  }

  @override
  Future<AggregateQuerySnapshotPlatform> get({
    required AggregateSource source,
  }) {
    return guard(() async {
      final fs.AggregateQuerySnapshot snapshot = await (query as DartQuery)
          .buildQuery()
          .aggregate(fields)
          .get(switch (source) {
            AggregateSource.server => fs.AggregateSource.server,
          });
      int? count;
      final List<AggregateQueryResponse> sums = <AggregateQueryResponse>[];
      final List<AggregateQueryResponse> averages = <AggregateQueryResponse>[];
      for (final fs.AggregateField field in fields) {
        switch (field) {
          case fs.CountAggregateField():
            count = snapshot.getInt(field);
          case fs.SumAggregateField():
            sums.add(
              AggregateQueryResponse(
                type: AggregateType.sum,
                field: field.fieldPath,
                value: snapshot.getDouble(field),
              ),
            );
          case fs.AverageAggregateField():
            averages.add(
              AggregateQueryResponse(
                type: AggregateType.average,
                field: field.fieldPath,
                value: snapshot.getDouble(field),
              ),
            );
          default:
            throw StateError('Unknown aggregate field $field');
        }
      }
      return AggregateQuerySnapshotPlatform(
        count: count,
        sum: sums,
        average: averages,
      );
    });
  }

  @override
  AggregateQueryPlatform count() => _with(fs.AggregateField.count());

  @override
  AggregateQueryPlatform sum(String field) =>
      _with(fs.AggregateField.sum(field));

  @override
  AggregateQueryPlatform average(String field) =>
      _with(fs.AggregateField.average(field));
}

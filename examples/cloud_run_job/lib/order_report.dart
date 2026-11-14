import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

/// What the aggregation queries found.
class OrderSummary {
  const OrderSummary(this.count, this.revenue, this.average);

  final int count;
  final double revenue;

  /// Null when there are no orders.
  final double? average;

  @override
  String toString() =>
      '$count paid orders, revenue ${revenue.toStringAsFixed(2)}, average '
      '${average?.toStringAsFixed(2) ?? '-'}';
}

/// Counts the paid orders of [orders] and sums and averages their `amount`
/// with one aggregation query. The backend computes the result
/// (`RunAggregationQuery`): no order document is downloaded.
Future<OrderSummary> summarizePaidOrders(
  CollectionReference<Map<String, Object?>> orders,
) async {
  final AggregateField count = AggregateField.count();
  final AggregateField revenue = AggregateField.sum('amount');
  final AggregateField average = AggregateField.average('amount');
  final AggregateQuerySnapshot result = await orders
      .where('status', isEqualTo: 'paid')
      .aggregate(<AggregateField>[count, revenue, average])
      .get();
  return OrderSummary(
    result.getCount(),
    result.getDouble(revenue) ?? 0,
    result.getDouble(average),
  );
}

/// Whether [writeReport] wrote the report or found it written already.
enum ReportOutcome { written, alreadyWritten }

/// Writes [summary] to [report] in a transaction, once per [executionId].
///
/// A retry, by [withRetries] in this process or by Cloud Run after a failed
/// task, may run this again after a commit whose acknowledgement was lost.
/// The report remembers the execution that wrote it last, so that the second
/// attempt finds it and leaves `runs` as it is: the write is idempotent.
Future<ReportOutcome> writeReport(
  Firestore firestore,
  DocumentReference<Map<String, Object?>> report,
  OrderSummary summary,
  String executionId,
) {
  return firestore.runTransaction<ReportOutcome>((
    Transaction transaction,
  ) async {
    final DocumentSnapshot<Map<String, Object?>> current = await transaction
        .get(report);
    final Map<String, Object?> data = current.data ?? <String, Object?>{};
    if (data['lastExecution'] == executionId) {
      return ReportOutcome.alreadyWritten;
    }
    transaction.set(report, <String, Object?>{
      'paidOrders': summary.count,
      'revenue': summary.revenue,
      'averageOrder': summary.average,
      'runs': ((data['runs'] as int?) ?? 0) + 1,
      'lastExecution': executionId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ReportOutcome.written;
  });
}

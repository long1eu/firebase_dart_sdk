// A one-shot job: summarizes the paid orders with an aggregation query and
// writes the summary to a report document in a transaction, retrying while
// the backend is unreachable. Exits 0 on success and 1 on failure, so that
// Cloud Run Jobs (or cron, or CI) can retry the task. See README.md.

import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_run_job/firestore_from_env.dart';
import 'package:cloud_run_job/order_report.dart';
import 'package:cloud_run_job/retry.dart';

Future<void> main() async {
  final Map<String, String> env = Platform.environment;
  final String ordersPath = env['ORDERS_COLLECTION'] ?? 'orders';
  final String reportPath = env['REPORT_DOCUMENT'] ?? 'reports/orders';
  final int maxAttempts = int.parse(env['MAX_ATTEMPTS'] ?? '5');
  // Cloud Run Jobs sets CLOUD_RUN_EXECUTION; all the tasks and retries of
  // one execution share it, so the report is written once per execution.
  final String executionId =
      env['CLOUD_RUN_EXECUTION'] ??
      'local-${DateTime.now().toUtc().toIso8601String()}';

  final Firestore firestore;
  try {
    firestore = firestoreFromEnvironment();
  } on ConfigurationError catch (e) {
    stderr.writeln(e);
    exitCode = 78;
    return;
  }

  try {
    final OrderSummary summary = await withRetries(
      'aggregation',
      () => summarizePaidOrders(firestore.collection(ordersPath)),
      maxAttempts: maxAttempts,
      log: stderr.writeln,
    );
    print('summary: $summary');

    final ReportOutcome outcome = await withRetries(
      'report',
      () => writeReport(
        firestore,
        firestore.doc(reportPath),
        summary,
        executionId,
      ),
      maxAttempts: maxAttempts,
      log: stderr.writeln,
    );
    print(switch (outcome) {
      ReportOutcome.written => 'report $reportPath written for $executionId',
      ReportOutcome.alreadyWritten =>
        'report $reportPath was already written for $executionId',
    });
  } on RetriesExhausted catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  } on FirestoreError catch (e) {
    stderr.writeln('Firestore: ${e.message}');
    exitCode = 1;
  } finally {
    await firestore.terminate();
  }
}

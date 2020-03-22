// File created by
// Lung Razvan <long1eu>
// on 22/03/2020

/// Collects the operation count from the persistence layer. Implementing
/// subclasses can expose this information to measure the efficiency of
/// persistence operations.
///
/// The only consumer of operation counts is currently the [LocalStoreTestCase]
/// (via [AccumulatingStatsCollector]). If you are not interested in the stats,
/// you can use [noOp] for the default empty stats collector.
class StatsCollector {
  const StatsCollector();

  static const StatsCollector noOp = StatsCollector();

  /// Records the number of rows read for the given tag.
  void recordRowsRead(String tag, int count) {}

  /// Records the number of rows deleted for the given tag.
  void recordRowsDeleted(String tag, int count) {}

  /// Records the number of rows written for the given tag.
  void recordRowsWritten(String tag, int count) {}
}

// File created by
// Lung Razvan <long1eu>
// on 22/03/2020

import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/stats_collector.dart';

/// A test-only collector of operation counts from the persistence layer.
class AccumulatingStatsCollector extends StatsCollector {
  final Map<String, int> _rowsRead = <String, int>{};
  final Map<String, int> _rowsDeleted = <String, int>{};
  final Map<String, int> _rowsWritten = <String, int>{};

  @override
  void recordRowsRead(String tag, int count) {
    final int currentValue = _rowsRead[tag];
    _rowsRead[tag] = currentValue != null ? currentValue + count : count;
  }

  @override
  void recordRowsDeleted(String tag, int count) {
    final int currentValue = _rowsDeleted[tag];
    _rowsDeleted[tag] = currentValue != null ? currentValue + count : count;
  }

  @override
  void recordRowsWritten(String tag, int count) {
    final int currentValue = _rowsWritten[tag];
    _rowsWritten[tag] = currentValue != null ? currentValue + count : count;
  }

  /// Reset all operation counts
  void reset() {
    _rowsRead.clear();
    _rowsDeleted.clear();
    _rowsWritten.clear();
  }

  /// Returns the number of rows read for the given tag since the last call to
  /// [reset].
  int getRowsRead(String tag) {
    return _rowsRead.containsKey(tag) ? _rowsRead[tag] : 0;
  }

  /// Returns the number of rows written for the given tag since the last call
  /// to [reset].
  int getRowsWritten(String tag) {
    return _rowsWritten.containsKey(tag) ? _rowsWritten[tag] : 0;
  }

  /// Returns the number of rows deleted for the given tag since the last call
  /// to [reset].
  int getRowsDeleted(String tag) {
    return _rowsDeleted.containsKey(tag) ? _rowsDeleted[tag] : 0;
  }
}

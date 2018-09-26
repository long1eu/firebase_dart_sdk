// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/listent_sequence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/lru_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';

/// Implements the steps for LRU garbage collection.
class LruGarbageCollector {
  final LruDelegate delegate;

  LruGarbageCollector(this.delegate);

  /// Given a percentile of target to collect, returns the number of targets to
  /// collect.
  int calculateQueryCount(int percentile) {
    final int targetCount = delegate.targetCount;
    return (percentile ~/ 100.0) * targetCount;
  }

  /// Returns the nth sequence number, counting in order from the smallest.
  Future<int> nthSequenceNumber(int count) async {
    if (count == 0) {
      return ListenSequence.INVALID;
    }
    final _RollingSequenceNumberBuffer buffer =
        _RollingSequenceNumberBuffer(count);
    await delegate.forEachTarget(null,
        (QueryData queryData) => buffer.addElement(queryData.sequenceNumber));
    await delegate.forEachOrphanedDocumentSequenceNumber(
        null, (int it) => buffer.addElement(it));
    return buffer.maxValue;
  }

  /// Removes targets with a sequence number equal to or less than the given
  /// upper bound, and removes document associations with those targets.
  Future<int> removeQueries(int upperBound, Set<int> liveQueries) {
    return delegate.removeQueries(null, upperBound, liveQueries);
  }

  /// Removes documents that have a sequence number equal to or less than the
  /// upper bound and are not otherwise pinned.
  Future<int> removeOrphanedDocuments(int upperBound) {
    return delegate.removeOrphanedDocuments(null, upperBound);
  }
}

/// Used to calculate the nth sequence number. Keeps a rolling buffer of the
/// lowest n values passed to [addElement], and finally reports the largest of
/// them in [maxValue].
class _RollingSequenceNumberBuffer {
  // Invert the comparison because we want to keep the smallest values.
  static final Comparator<int> comparator = (int a, int b) => b.compareTo(a);
  final PriorityQueue<int> queue;
  final int maxElements;

  _RollingSequenceNumberBuffer(this.maxElements)
      : queue = PriorityQueue<int>(comparator);

  void addElement(int sequenceNumber) {
    if (queue.length < maxElements) {
      queue.add(sequenceNumber);
    } else {
      final int highestValue = queue.first;
      if (sequenceNumber < highestValue) {
        queue.removeFirst();
        queue.add(sequenceNumber);
      }
    }
  }

  int get maxValue => queue.first;
}

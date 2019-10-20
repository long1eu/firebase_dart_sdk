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
  LruGarbageCollector(this.delegate);

  final LruDelegate delegate;

  /// Given a percentile of target to collect, returns the number of targets to collect.
  int calculateQueryCount(int percentile) {
    return (percentile / 100.0 * delegate.targetCount).toInt();
  }

  /// Returns the nth sequence number, counting in order from the smallest.
  Future<int> nthSequenceNumber(int count) async {
    if (count == 0) {
      return ListenSequence.invalid;
    }
    final _RollingSequenceNumberBuffer buffer = _RollingSequenceNumberBuffer(count);
    await delegate.forEachTarget((QueryData queryData) => buffer.addElement(queryData.sequenceNumber));
    await delegate.forEachOrphanedDocumentSequenceNumber(buffer.addElement);
    return buffer.maxValue;
  }

  /// Removes targets with a sequence number equal to or less than the given upper bound, and
  /// removes document associations with those targets.
  Future<int> removeTargets(int upperBound, Set<int> activeTargetIds) {
    return delegate.removeTargets(upperBound, activeTargetIds);
  }

  /// Removes documents that have a sequence number equal to or less than the upper bound and are
  /// not otherwise pinned.
  Future<int> removeOrphanedDocuments(int upperBound) {
    return delegate.removeOrphanedDocuments(upperBound);
  }
}

/// Used to calculate the nth sequence number. Keeps a rolling buffer of the lowest n values passed
/// to [addElement], and finally reports the largest of them in [maxValue].
class _RollingSequenceNumberBuffer {
  _RollingSequenceNumberBuffer(this.maxElements) : queue = PriorityQueue<int>(comparator);

  final PriorityQueue<int> queue;
  final int maxElements;

  // Invert the comparison because we want to keep the smallest values.
  static int comparator(int a, int b) => b.compareTo(a);

  void addElement(int sequenceNumber) {
    if (queue.length < maxElements) {
      queue.add(sequenceNumber);
    } else {
      final int highestValue = queue.first;
      if (sequenceNumber < highestValue) {
        queue
          ..removeFirst()
          ..add(sequenceNumber);
      }
    }
  }

  int get maxValue => queue.first;
}

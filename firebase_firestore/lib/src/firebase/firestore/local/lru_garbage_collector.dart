// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/listent_sequence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/lru_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';

import 'local_store.dart';

/// Implements the steps for LRU garbage collection.
class LruGarbageCollector {
  LruGarbageCollector(this.delegate, this._params);

  final LruDelegate delegate;
  final LruGarbageCollectorParams _params;

  /// A helper method to create a new scheduler.
  LruGarbageCollectorScheduler newScheduler(AsyncQueue asyncQueue, LocalStore localStore) {
    return LruGarbageCollectorScheduler(this, asyncQueue, localStore);
  }

  /// Given a percentile of target to collect, returns the number of targets to collect.
  Future<int> calculateQueryCount(int percentile) async {
    final int targetCount = await delegate.getSequenceNumberCount();
    return ((percentile / 100.0) * targetCount).toInt();
  }

  /// Returns the nth sequence number, counting in order from the smallest.
  Future<int> getNthSequenceNumber(int count) async {
    if (count == 0) {
      return ListenSequence.invalid;
    }
    final _RollingSequenceNumberBuffer buffer = _RollingSequenceNumberBuffer(count);
    await delegate.forEachTarget((QueryData queryData) => buffer.addElement(queryData.sequenceNumber));
    await delegate.forEachOrphanedDocumentSequenceNumber(buffer.addElement);
    return buffer.maxValue;
  }

  /// Removes targets with a sequence number equal to or less than the given upper bound, and removes document
  /// associations with those targets.
  Future<int> removeTargets(int upperBound, Set<int> activeTargetIds) {
    return delegate.removeTargets(upperBound, activeTargetIds);
  }

  /// Removes documents that have a sequence number equal to or less than the upper bound and are not otherwise pinned.
  Future<int> removeOrphanedDocuments(int upperBound) {
    return delegate.removeOrphanedDocuments(upperBound);
  }

  Future<LruGarbageCollectorResults> collect(Set<int> activeTargetIds) async {
    if (_params.minBytesThreshold == LruGarbageCollectorParams._collectionDisabled) {
      Log.d('LruGarbageCollector', 'Garbage collection skipped; disabled');
      return LruGarbageCollectorResults.didNotRun;
    }

    final int cacheSize = byteSize;
    if (cacheSize < _params.minBytesThreshold) {
      Log.d('LruGarbageCollector',
          'Garbage collection skipped; Cache size $cacheSize is lower than threshold ${_params.minBytesThreshold}');
      return LruGarbageCollectorResults.didNotRun;
    } else {
      return _runGarbageCollection(activeTargetIds);
    }
  }

  Future<LruGarbageCollectorResults> _runGarbageCollection(Set<int> liveTargetIds) async {
    final DateTime startTs = DateTime.now();
    int sequenceNumbers = await calculateQueryCount(_params.percentileToCollect);
    // Cap at the configured max
    if (sequenceNumbers > _params.maximumSequenceNumbersToCollect) {
      Log.d(
          'LruGarbageCollector',
          'Capping sequence numbers to collect down to the maximum of ${_params.maximumSequenceNumbersToCollect} from '
              '$sequenceNumbers');
      sequenceNumbers = _params.maximumSequenceNumbersToCollect;
    }
    final DateTime countedTargetsTs = DateTime.now();

    final int upperBound = await getNthSequenceNumber(sequenceNumbers);
    final DateTime foundUpperBoundTs = DateTime.now();

    final int numTargetsRemoved = await removeTargets(upperBound, liveTargetIds);
    final DateTime removedTargetsTs = DateTime.now();

    final int numDocumentsRemoved = await removeOrphanedDocuments(upperBound);
    final DateTime removedDocumentsTs = DateTime.now();

    if (Log.isDebugEnabled) {
      final StringBuffer desc = StringBuffer('LRU Garbage Collection:\n')
        ..writeln('\tCounted targets in ${countedTargetsTs.difference(startTs)}')
        ..writeln('\tDetermined least recently used $sequenceNumbers sequence numbers in '
            '${foundUpperBoundTs.difference(countedTargetsTs)}')
        ..writeln('\tRemoved $numTargetsRemoved targets in ${removedTargetsTs.difference(foundUpperBoundTs)}')
        ..writeln('\tRemoved $numDocumentsRemoved documents in ${removedDocumentsTs.difference(removedTargetsTs)}')
        ..writeln('Total Duration: ${removedDocumentsTs.difference(startTs)}');

      Log.d('LruGarbageCollector', desc);
    }
    return LruGarbageCollectorResults(
      hasRun: true,
      sequenceNumbersCollected: sequenceNumbers,
      targetsRemoved: numTargetsRemoved,
      documentsRemoved: numDocumentsRemoved,
    );
  }

  int get byteSize => delegate.byteSize;
}

/// Used to calculate the nth sequence number. Keeps a rolling buffer of the lowest n values passed to [addElement], and
/// finally reports the largest of them in [maxValue].
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

class LruGarbageCollectorParams {
  const LruGarbageCollectorParams({
    this.minBytesThreshold = _defaultCacheSizeBytes,
    this.percentileToCollect = _defaultCollectionPercentile,
    this.maximumSequenceNumbersToCollect = _defaultMaxSequenceNumbersToCollect,
  });

  LruGarbageCollectorParams.disabled()
      : this(minBytesThreshold: _collectionDisabled, percentileToCollect: 0, maximumSequenceNumbersToCollect: 0);

  LruGarbageCollectorParams.withCacheSizeBytes(int cacheSizeBytes) : this(minBytesThreshold: cacheSizeBytes);

  final int minBytesThreshold;
  final int percentileToCollect;
  final int maximumSequenceNumbersToCollect;

  static const int _collectionDisabled = FirebaseFirestoreSettings.cacheSizeUnlimited;

  static const int _defaultCacheSizeBytes = 100 * 1024 * 1024; // 100mb
  /// The following two constants are estimates for how we want to tune the garbage collector. If we encounter a large
  /// cache, we don't want to spend a large chunk of time GCing all of it, we would rather make some progress and then
  /// try again later. We also don't want to collect everything that we possibly could, as our thesis is that recently
  /// used items are more likely to be used again.
  static const int _defaultCollectionPercentile = 10;

  static const int _defaultMaxSequenceNumbersToCollect = 1000;
}

class LruGarbageCollectorResults {
  const LruGarbageCollectorResults({
    this.hasRun,
    this.sequenceNumbersCollected,
    this.targetsRemoved,
    this.documentsRemoved,
  });

  static const LruGarbageCollectorResults didNotRun =
      LruGarbageCollectorResults(hasRun: false, sequenceNumbersCollected: 0, targetsRemoved: 0, documentsRemoved: 0);

  final bool hasRun;
  final int sequenceNumbersCollected;
  final int targetsRemoved;
  final int documentsRemoved;

  @override
  String toString() {
    return (ToStringHelper(LruGarbageCollectorResults)
          ..add('hasRun', hasRun)
          ..add('sequenceNumbersCollected', sequenceNumbersCollected)
          ..add('targetsRemoved', targetsRemoved)
          ..add('documentsRemoved', documentsRemoved))
        .toString();
  }
}

/// This class is responsible for the scheduling of LRU garbage collection. It handles checking whether or not GC is
/// enabled, as well as which delay to use before the next run.
class LruGarbageCollectorScheduler {
  LruGarbageCollectorScheduler(this._garbageCollector, this._asyncQueue, this._localStore);

  final LruGarbageCollector _garbageCollector;
  final AsyncQueue _asyncQueue;
  final LocalStore _localStore;

  bool _hasRun = false;
  DelayedTask<void> _gcTask;

  /// How long we wait to try running LRU GC after SDK initialization.
  static const Duration _initialGcDelay = Duration(minutes: 1);

  /// Minimum amount of time between GC checks, after the first one.
  static const Duration _regularGcDelay = Duration(minutes: 5);

  void start() {
    if (_garbageCollector._params.minBytesThreshold != LruGarbageCollectorParams._collectionDisabled) {
      _scheduleGC();
    }
  }

  void stop() {
    if (_gcTask != null) {
      _gcTask.cancel();
    }
  }

  void _scheduleGC() {
    final Duration delay = _hasRun ? _regularGcDelay : _initialGcDelay;
    _gcTask = _asyncQueue.enqueueAfterDelay<void>(TimerId.garbageCollection, delay, () async {
      await _localStore.collectGarbage(_garbageCollector);
      _hasRun = true;
      _scheduleGC();
    });
  }
}

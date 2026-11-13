// ignore_for_file: avoid_implementing_value_types

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/encoded_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_delegate.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/types.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

/// An LRU delegate over [targets] sequence numbers (one target each) and
/// [orphans] orphaned document sequence numbers, recording the upper bounds
/// the collector asks to remove.
class _FakeDelegate implements LruDelegate {
  _FakeDelegate(this.targets, this.orphans, {this.size = 1 << 30});

  final List<int> targets;
  final List<int> orphans;
  final int size;
  final List<int> removedTargetBounds = <int>[];
  final List<int> removedDocumentBounds = <int>[];

  @override
  Future<void> forEachTarget(Consumer<QueryData> consumer) async {
    for (int i = 0; i < targets.length; i++) {
      consumer(
        QueryData(
          query('c').toTarget(),
          i + 1,
          targets[i],
          QueryPurpose.listen,
        ),
      );
    }
  }

  @override
  Future<int> getSequenceNumberCount() async => targets.length + orphans.length;

  @override
  Future<void> forEachOrphanedDocumentSequenceNumber(
    Consumer<int> consumer,
  ) async {
    orphans.forEach(consumer);
  }

  @override
  Future<int> removeTargets(int upperBound, Set<int> activeTargetIds) async {
    removedTargetBounds.add(upperBound);
    return targets.where((int s) => s <= upperBound).length;
  }

  @override
  Future<int> removeOrphanedDocuments(int upperBound) async {
    removedDocumentBounds.add(upperBound);
    return orphans.where((int s) => s <= upperBound).length;
  }

  @override
  LruGarbageCollector get garbageCollector => throw UnimplementedError();

  @override
  Future<int> get byteSize async => size;
}

/// A local store whose garbage collection always fails.
class _FailingLocalStore implements LocalStore {
  int calls = 0;

  @override
  Future<LruGarbageCollectorResults> collectGarbage(
    LruGarbageCollector garbageCollector,
  ) {
    calls++;
    return Future<LruGarbageCollectorResults>.error(
      StateError('database is locked'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('LruGarbageCollector', () {
    test(
      'caps the sequence numbers collected at the configured maximum',
      () async {
        // 100 sequence numbers, 50% would be 50, the cap is 7.
        final _FakeDelegate delegate = _FakeDelegate(
          <int>[for (int i = 1; i <= 60; i++) i * 2],
          <int>[for (int i = 1; i <= 40; i++) i * 2 + 1],
        );
        final LruGarbageCollector gc = LruGarbageCollector(
          delegate,
          const LruGarbageCollectorParams(
            minBytesThreshold: 0,
            percentileToCollect: 50,
            maximumSequenceNumbersToCollect: 7,
          ),
        );

        final LruGarbageCollectorResults results = await gc.collect(<int>{});
        expect(results.hasRun, isTrue);
        expect(results.sequenceNumbersCollected, 7);
        // The 7 smallest of {2, 3, 4, ...} end at 8.
        expect(delegate.removedTargetBounds, <int>[8]);
        expect(delegate.removedDocumentBounds, <int>[8]);
        expect(results.targetsRemoved, 4); // 2, 4, 6, 8
        expect(results.documentsRemoved, 3); // 3, 5, 7
      },
    );

    test('does not run below the size threshold or when disabled', () async {
      final _FakeDelegate delegate = _FakeDelegate(<int>[1], <int>[], size: 10);
      expect(
        (await LruGarbageCollector(
          delegate,
          const LruGarbageCollectorParams(minBytesThreshold: 11),
        ).collect(<int>{})).hasRun,
        isFalse,
      );
      expect(
        (await LruGarbageCollector(
          delegate,
          LruGarbageCollectorParams.disabled(),
        ).collect(<int>{})).hasRun,
        isFalse,
      );
      expect(delegate.removedTargetBounds, isEmpty);
      expect(
        LruGarbageCollectorResults.didNotRun.toString(),
        contains('hasRun'),
      );
    });
  });

  group('LruGarbageCollectorScheduler', () {
    test(
      'a failed collection is logged and the next one is still scheduled',
      () async {
        final TaskScheduler scheduler = TaskScheduler('gc');
        final _FailingLocalStore store = _FailingLocalStore();
        final LruGarbageCollectorScheduler gcScheduler = LruGarbageCollector(
          _FakeDelegate(<int>[], <int>[]),
          const LruGarbageCollectorParams(),
        ).newScheduler(scheduler, store)..start();

        final TimerTask first = scheduler.getTask(TaskId.garbageCollection)!;
        scheduler.runUntil(TaskId.garbageCollection);
        await Future<void>.delayed(Duration.zero);

        expect(store.calls, 1);
        final TimerTask? next = scheduler.getTask(TaskId.garbageCollection);
        expect(next, isNotNull);
        expect(identical(next, first), isFalse);

        gcScheduler.stop();
        expect(scheduler.getTask(TaskId.garbageCollection), isNull);
      },
    );

    test('a disabled collector is never scheduled', () {
      final TaskScheduler scheduler = TaskScheduler('gc');
      LruGarbageCollector(
        _FakeDelegate(<int>[], <int>[]),
        LruGarbageCollectorParams.disabled(),
      ).newScheduler(scheduler, _FailingLocalStore()).start();
      expect(scheduler.getTask(TaskId.garbageCollection), isNull);
    });
  });

  group('EncodedPath', () {
    test('field paths round trip', () {
      final FieldPath fieldPath = FieldPath.fromSegments(<String>[
        'a',
        'b\u0000c',
        'd\u0001',
      ]);
      expect(
        EncodedPath.decodeFieldPath(EncodedPath.encode(fieldPath)),
        fieldPath,
      );
    });

    test('a segment that is not terminated is rejected', () {
      expect(
        () => EncodedPath.decodeResourcePath('abc\u0001\u0001def'),
        throwsArgumentError,
      );
    });

    test('an unknown escape sequence is rejected', () {
      expect(
        () => EncodedPath.decodeResourcePath('a\u0001\u0005\u0001\u0001'),
        throwsArgumentError,
      );
    });

    test('a short path must be the empty path', () {
      expect(EncodedPath.decodeResourcePath('\u0001\u0001').isEmpty, isTrue);
      expect(
        () => EncodedPath.decodeResourcePath('ab'),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => EncodedPath.decodeResourcePath('a'),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}

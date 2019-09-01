// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/query_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

/// Event accumulator for integration test
class EventAccumulator<T> {
  EventAccumulator()
      : _events = <T>[],
        _maxEvents = 0;

  final List<T> _events;

  Completer<void> _completion;
  int _maxEvents;

  void onData(T data) {
    Log.i('EventAccumulator', 'Received new event: $data');
    _events.add(data);
    _checkFulfilled();
  }

  void onError(dynamic error, [StackTrace stackTrace]) {
    Assert.hardAssert(false, 'Unexpected error: $error');
  }

  Future<List<T>> waitFor([int numEvents = 1]) async {
    Assert.hardAssert(
        _completion == null, 'calling await while another await is running');
    _completion = Completer<void>();
    _maxEvents = _maxEvents + numEvents;
    _checkFulfilled();

    await _completion.future;
    _completion = null;

    final List<T> events = _events.sublist(_maxEvents - numEvents, _maxEvents);

    return events;
  }

  Future<T> wait() async => (await waitFor(1)).first;

  /// Waits for a snapshot with pending writes.
  Future<T> awaitLocalEvent() async {
    T event;
    do {
      event = await wait();
    } while (!_hasPendingWrites(event));
    return event;
  }

  /// Waits for a snapshot that has no pending writes.
  Future<T> awaitRemoteEvent() async {
    T event;
    do {
      event = await wait();
    } while (_hasPendingWrites(event));
    return event;
  }

  bool _hasPendingWrites(T event) {
    if (event is DocumentSnapshot) {
      return event.metadata.hasPendingWrites;
    } else {
      Assert.hardAssert(event is QuerySnapshot,
          'hasPendingWrites called on unknown event: $event');
      return (event as QuerySnapshot).metadata.hasPendingWrites;
    }
  }

  void _checkFulfilled() {
    if (_completion != null && _events.length >= _maxEvents) {
      _completion.complete(null);
    }
  }
}

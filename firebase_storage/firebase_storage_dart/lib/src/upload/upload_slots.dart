/// The limit on the uploads of one `FirebaseStorage` that run at the same time.
@internal
library;

import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

/// A first-in, first-out queue of [limit] upload slots.
@internal
final class UploadSlots {
  /// Creates [limit] slots (at least one).
  UploadSlots(this.limit) {
    RangeError.checkValueInInterval(limit, 1, 1 << 30, 'limit');
  }

  /// How many uploads may run at once.
  final int limit;

  int _active = 0;
  final Queue<Completer<bool>> _waiting = Queue<Completer<bool>>();

  /// The slots in use.
  int get active => _active;

  /// The uploads waiting for a slot.
  int get waiting => _waiting.length;

  /// Takes a slot, waiting behind the earlier callers when none is free. Completes with true once the slot is
  /// taken, or with false when [abortTrigger] fires first (the caller then leaves the queue and holds nothing).
  Future<bool> acquire({Future<void>? abortTrigger}) {
    if (_active < limit && _waiting.isEmpty) {
      _active++;
      return Future<bool>.value(true);
    }
    final Completer<bool> waiter = Completer<bool>();
    _waiting.add(waiter);
    abortTrigger?.then((_) {
      if (_waiting.remove(waiter)) {
        waiter.complete(false);
      }
    });
    return waiter.future;
  }

  /// Gives a slot back: to the first waiter, or to the pool.
  void release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete(true);
      return;
    }
    if (_active > 0) {
      _active--;
    }
  }

  /// Runs [action] in a slot.
  Future<T> run<T>(Future<T> Function() action) async {
    await acquire();
    try {
      return await action();
    } finally {
      release();
    }
  }
}

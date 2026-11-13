// File created by
// Lung Razvan <long1eu>
// on 13/11/2026

import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';

/// Makes the transactions of a [Persistence] fail, by the name of their action, with the error a database throws when
/// it is not available right now ([TransientDatabaseException]). The counterpart of `injectFailures` of the JS
/// `MockMemoryPersistence` / `MockIndexedDbPersistence`, used by the `failDatabase` spec step.
///
/// It hooks into [Persistence.beforeTransaction] instead of wrapping the persistence, so that the persistence keeps
/// its type (the spec runner shares and restarts a SQLite persistence differently from a memory one). A failed
/// transaction does not run at all, as in JS.
class PersistenceFaultInjector {
  PersistenceFaultInjector(this.persistence) {
    persistence.beforeTransaction = _beforeTransaction;
  }

  final Persistence persistence;

  /// The actions (as passed to [Persistence.runTransaction]) whose transactions fail. Empty: nothing fails.
  List<String> failActions = <String>[];

  void _beforeTransaction(String action) {
    if (failActions.contains(action)) {
      throw TransientDatabaseException(
        'Simulated error',
        'Simulated retryable error: $action',
      );
    }
  }

  /// Removes the hook from [persistence].
  void detach() {
    if (persistence.beforeTransaction == _beforeTransaction) {
      persistence.beforeTransaction = null;
    }
  }
}

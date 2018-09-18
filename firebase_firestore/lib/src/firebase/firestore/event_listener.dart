// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';

/// An interface for event listeners.
@publicApi
abstract class EventListener<T> {
  /// onEvent will be called with the new value or the error if an error
  /// occurred. It's guaranteed that exactly one of value or error will be
  /// non-null.
  ///
  /// The [value] of the event. null if there was an error.
  /// The [error] if there was error. null otherwise.
  @publicApi
  void onEvent(T value, FirebaseFirestoreError error);
}

// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/types.dart';

/// A wrapper event listener that uses an Executor to dispatch events. Exposes a
/// mute() call to immediately silence the event listener when events are
/// dispatched on different threads.
class ExecutorEventListener<T> {
  final EventListener<T> eventListener;

  bool muted = false;

  ExecutorEventListener(this.eventListener);

  void call(T value, FirebaseFirestoreError error) {
    if (!muted) {
      eventListener(value, error);
    }
  }

  void mute() {
    muted = true;
  }
}

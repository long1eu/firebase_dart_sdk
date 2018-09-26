// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/firestore_client.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query_listener.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/listener_registration.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/executor_event_listener.dart';

/// Implements the [ListenerRegistration] interface by removing a query from the
/// listener.
class ListenerRegistrationImpl implements ListenerRegistration {
  final FirestoreClient client;

  /// The internal query listener object that is used to unlisten from the
  /// query.
  final QueryListener queryListener;

  /// The event listener for the query that raises events asynchronously.
  final ExecutorEventListener<ViewSnapshot> asyncEventListener;

  /// Creates a new ListenerRegistration. Is activity-scoped if and only if activity is non-null. */
  ListenerRegistrationImpl(
      this.client, this.queryListener, this.asyncEventListener);

  // TODO:{26/09/2018 03:26}-long1eu: add a way to reach dispose from the MaterialApp widget

  /*
    if (activity != null) {
      ActivityLifecycleObserver.of(activity).onStopCallOnce(this::remove);
    }
  */

  @override
  void remove() {
    asyncEventListener.mute();
    client.stopListening(queryListener);
  }
}

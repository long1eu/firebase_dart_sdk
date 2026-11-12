// Licensed under the Apache License, Version 2.0 (the "License");

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query_stream.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';

/// Listens to [query] through [client], the way Java's `addSnapshotListener`
/// does: the listener is registered when the returned stream is listened to
/// (not when it is created) and removed again when the subscription is
/// cancelled, even if that happens before the registration finished.
Stream<ViewSnapshot> listenToQuery(
  FirestoreClient client,
  Query query,
  ListenOptions options,
) {
  late final StreamController<ViewSnapshot> controller;
  StreamSubscription<ViewSnapshot>? subscription;
  bool cancelled = false;

  controller = StreamController<ViewSnapshot>(
    onListen: () {
      final Future<QueryStream> pending = client.listen(query, options);
      pending.then(
        (QueryStream queryStream) {
          if (cancelled) {
            // Cancelled while registering: listening and cancelling removes the
            // listener through the QueryStream's own cancel hook.
            queryStream.listen(null).cancel();
            return;
          }
          final StreamSubscription<ViewSnapshot> sub = queryStream.listen(
            controller.add,
            onError: controller.addError,
          );
          subscription = sub;
          if (controller.isPaused) {
            sub.pause();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!cancelled) {
            controller.addError(error, stackTrace);
            controller.close();
          }
        },
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () async {
      cancelled = true;
      await subscription?.cancel();
      subscription = null;
      // A registration that is still queued is not waited for: it cleans up
      // after itself (see above).
    },
  );
  return controller.stream;
}

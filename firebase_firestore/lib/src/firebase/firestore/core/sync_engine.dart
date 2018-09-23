// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/event_manager.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_store.dart';
import 'package:grpc/grpc.dart';

class SyncEngine implements RemoteStoreCallback {
  void setCallback(EventManager eventManager) {}

  int listen(Query query) {}

  void stopListening(Query query) {}

  void handleCredentialChange(User user) {}
}

/// A callback used to handle events from the SyncEngine
abstract class SyncEngineCallback {
  void onViewSnapshots(List<ViewSnapshot> snapshotList);

  void onError(Query query, GrpcError error);
}

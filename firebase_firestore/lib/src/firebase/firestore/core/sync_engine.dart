// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/event_manager.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:grpc/grpc.dart';

class SyncEngine {
  void setCallback(EventManager eventManager) {}

  int listen(Query query) {}

  void stopListening(Query query) {}
}

/// A callback used to handle events from the SyncEngine
abstract class SyncEngineCallback {
  void onViewSnapshots(List<ViewSnapshot> snapshotList);

  void onError(Query query, GrpcError error);
}

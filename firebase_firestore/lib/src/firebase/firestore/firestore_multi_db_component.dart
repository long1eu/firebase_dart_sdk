// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore.dart';

/// Multi-resource container for Firestore.
class FirestoreMultiDbComponent {
  /// A static map from instance key to [FirebaseFirestore] instances. Instance
  /// keys are database names.
  static final Map<String, FirebaseFirestore> instances =
      <String, FirebaseFirestore>{};

  final FirebaseApp app;

  final InternalAuthProvider authProvider;

  FirestoreMultiDbComponent(this.app, this.authProvider);

  /// Provides instances of Firestore for given database names. */
  Future<FirebaseFirestore> get(String databaseName) async {
    return instances[databaseName] ??=
        await FirebaseFirestore.newInstance(app, databaseName, authProvider);
  }
}

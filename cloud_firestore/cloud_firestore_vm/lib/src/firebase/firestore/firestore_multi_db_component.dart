// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'dart:async';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/database.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart';

/// Multi-resource container for Firestore.
class FirestoreMultiDbComponent {
  FirestoreMultiDbComponent(this.app, this.authProvider, this.settings);

  /// A static map from instance key to [Firestore] instances. Instance keys are database names.
  static final Map<String, Firestore> instances = <String, Firestore>{};

  final FirebaseApp app;

  final InternalTokenProvider authProvider;

  final FirestoreSettings settings;

  /// Provides instances of Firestore for given database names.
  Future<Firestore> get(String databaseName, OpenDatabase openDatabase) async {
    return Firestore.newInstance(
      app,
      databaseName,
      authProvider: authProvider,
      openDatabase: openDatabase,
      settings: settings,
    );
  }

  /// Remove the instance of a given database ID from this component, such that if [FirestoreMultiDbComponent.get]
  /// is called again with the same name, a new instance of [Firestore] is created.
  ///
  /// <p>It is a no-op if there is no instance associated with the given database name.
  Future<void> remove(String databaseId) async {
    instances.remove(databaseId);
  }

  void onDeleted(String firebaseAppName, FirebaseOptions options) {
    // Shuts down all database instances and remove them from registry map when App is deleted.
    for (MapEntry<String, Firestore> entry in instances.entries) {
      entry.value.shutdown();
      instances.remove(entry.key);
    }
  }
}

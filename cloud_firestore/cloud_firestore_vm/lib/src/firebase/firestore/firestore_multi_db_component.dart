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
    return instances[databaseName] ??= await Firestore.newInstance(
      app,
      databaseName,
      authProvider: authProvider,
      openDatabase: openDatabase,
      settings: settings,
    );
  }
}

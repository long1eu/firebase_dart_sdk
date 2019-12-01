// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'dart:async';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_settings.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/database.dart';
import 'package:firebase_internal/firebase_internal.dart';

/// Multi-resource container for Firestore.
class FirestoreMultiDbComponent {
  FirestoreMultiDbComponent(this.app, this.authProvider, this.settings);

  /// A static map from instance key to [FirebaseFirestore] instances. Instance keys are database names.
  static final Map<String, FirebaseFirestore> instances = <String, FirebaseFirestore>{};

  final FirebaseApp app;

  final InternalTokenProvider authProvider;

  final FirebaseFirestoreSettings settings;

  /// Provides instances of Firestore for given database names.
  Future<FirebaseFirestore> get(String databaseName, OpenDatabase openDatabase) async {
    return instances[databaseName] ??= await FirebaseFirestore.newInstance(app, databaseName,
        authProvider: authProvider, openDatabase: openDatabase, settings: settings);
  }
}

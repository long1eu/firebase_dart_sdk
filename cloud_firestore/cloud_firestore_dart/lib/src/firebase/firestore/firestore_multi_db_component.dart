// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/internal.dart' show Log;

/// Multi-resource container for Firestore.
class FirestoreMultiDbComponent {
  FirestoreMultiDbComponent(this.app, this.authProvider, this.settings,
      {this.appCheckProvider});

  /// A static map from instance key (see [keyFor]) to [Firestore] instances.
  static final Map<String, Firestore> instances = <String, Firestore>{};

  /// Instances that are still being created, so that concurrent callers share
  /// one instance.
  static final Map<String, Future<Firestore>> _pending =
      <String, Future<Firestore>>{};

  /// Deleting a [FirebaseApp] shuts down the instances created for it.
  static final Map<String, StreamSubscription<String>> _deleteSubscriptions =
      <String, StreamSubscription<String>>{};

  /// The key of the instance for the given app and database.
  static String keyFor(String appName, String database) =>
      '$appName/$database';

  /// Makes [firestore] the instance returned for [app] and [database], and
  /// releases it again when [app] is deleted.
  static void register(FirebaseApp app, String database, Firestore firestore) {
    final String key = keyFor(app.name, database);
    instances[key] = firestore;
    _deleteSubscriptions.remove(key)?.cancel();
    _deleteSubscriptions[key] = app.onDeleteApp.listen((_) {
      if (identical(instances[key], firestore)) {
        // Nobody awaits this: report a failure instead of raising an unhandled error.
        firestore.shutdown().catchError((Object e) {
          Log.w('FirebaseFirestore',
              'Shutting down the instance of the deleted app failed: $e');
        });
      }
    });
  }

  /// Whether an instance for [appName] and [database] exists or is being created.
  static bool hasInstance(String appName, String database) {
    final String key = keyFor(appName, database);
    return instances.containsKey(key) || _pending.containsKey(key);
  }

  /// Forgets [firestore] (called when it is shut down), so the next
  /// `getInstance` builds a fresh one.
  static void deregister(Firestore firestore) {
    final List<String> keys = instances.keys
        .where((String key) => identical(instances[key], firestore))
        .toList();
    for (final String key in keys) {
      instances.remove(key);
      _deleteSubscriptions.remove(key)?.cancel();
    }
  }

  final FirebaseApp app;

  final InternalTokenProvider authProvider;

  final FirestoreSettings? settings;

  /// Source of App Check tokens; null sends no App Check header.
  final InternalAppCheckTokenProvider? appCheckProvider;

  /// Provides the instance of Firestore for the given database name, creating
  /// it on first use. Later calls return the same instance until it is shut
  /// down ([openDatabase] and [settings] only apply to the first call).
  Future<Firestore> get(String databaseName, OpenDatabase? openDatabase) {
    final String key = keyFor(app.name, databaseName);
    final Firestore? existing = instances[key];
    if (existing != null) {
      return Future<Firestore>.value(existing);
    }

    return _pending[key] ??= Firestore.newInstance(
      app,
      databaseName,
      authProvider: authProvider,
      appCheckProvider: appCheckProvider,
      openDatabase: openDatabase,
      settings: settings,
    ).whenComplete(() {
      // Not an arrow: remove() returns this very future, which whenComplete
      // would then wait for.
      _pending.remove(key);
    });
  }
}

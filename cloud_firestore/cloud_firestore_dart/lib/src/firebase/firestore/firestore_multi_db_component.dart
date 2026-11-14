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
  FirestoreMultiDbComponent(
    this.app,
    this.authProvider,
    this.settings, {
    this.appCheckProvider,
  });

  /// A static map from instance key (see [keyFor]) to [Firestore] instances.
  static final Map<String, Firestore> instances = <String, Firestore>{};

  /// Deleting a [FirebaseApp] shuts down the instances created for it.
  static final Map<String, StreamSubscription<String>> _deleteSubscriptions =
      <String, StreamSubscription<String>>{};

  /// The key of the instance for the given app and database.
  static String keyFor(String appName, String database) => '$appName/$database';

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
          Log.w(
            'FirebaseFirestore',
            'Shutting down the instance of the deleted app failed: $e',
          );
        });
      }
    });
  }

  /// Whether an instance for [appName] and [database] exists.
  static bool hasInstance(String appName, String database) {
    final String key = keyFor(appName, database);
    return instances.containsKey(key);
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
  /// down, unless they ask for other [settings]: that throws a [StateError],
  /// like `initializeFirestore` with different options in the JS SDK and
  /// `setFirestoreSettings` after the start on Android. [openDatabase] only
  /// applies to the first call.
  Firestore get(String databaseName, OpenDatabase? openDatabase) {
    final String key = keyFor(app.name, databaseName);
    final Firestore? existing = instances[key];
    if (existing != null && identical(existing.firebaseApp, app)) {
      final FirestoreSettings? requested = settings;
      if (requested != null && requested != existing.settings) {
        throw StateError(
          'Firestore.instanceFor() has already been called with different '
          'settings for this app and database. Call it without settings to '
          'get the existing instance, or terminate() that instance first.',
        );
      }
      return existing;
    }

    // The instance of another FirebaseApp object with the same name: app names are unique among live apps, so that
    // app was deleted and its delete event (which is delivered asynchronously) has not terminated the instance yet.
    // Terminate it; the new instance opens the same persistence only once it is closed.
    final Future<void>? closing = existing?.terminate();
    return FirestoreInternal.newInstance(
      app,
      databaseName,
      authProvider: authProvider,
      appCheckProvider: appCheckProvider,
      openDatabase: openDatabase,
      settings: settings,
      after: closing,
    );
  }
}

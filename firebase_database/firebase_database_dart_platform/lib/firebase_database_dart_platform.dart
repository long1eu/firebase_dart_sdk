/// An implementation of FlutterFire's Realtime Database platform interface on
/// top of the pure-Dart client `firebase_database_dart`.
///
/// An app keeps the official `firebase_database` API
/// (`FirebaseDatabase.instance.ref('notes').onValue`), and
/// `firebase_database_dart` does the work underneath, over the Realtime
/// Database WebSocket protocol:
///
/// * On Linux, where neither `firebase_database` nor `firebase_core` has an
///   implementation, adding this package is enough: Flutter calls
///   [FirebaseDatabaseDart.registerWith] before `main`. That registration
///   has no token provider and no persistence: the connection carries no
///   user and keeps its data in memory, unless `main` calls
///   [FirebaseDatabaseDart.use] with them before the first use.
/// * On Windows, the same when the app lists this package as a direct
///   dependency: it replaces the native `firebase_database` plugin.
/// * On any other platform, call [FirebaseDatabaseDart.use] at the start of
///   `main`, before the first use of Firebase, to replace the official
///   implementation.
///
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   FirebaseDatabaseDart.use(
///     tokenProviderFor: (FirebaseApp app) => FirebaseAuthDart.userAuthFor(app),
///   );
///   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
///   await FirebaseDatabase.instance.ref('notes/today').set('Hello');
/// }
/// ```
library;

import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;
import 'package:firebase_database_dart_platform/src/app.dart';
import 'package:firebase_database_dart_platform/src/core.dart';
import 'package:firebase_database_dart_platform/src/firebase_database.dart';
import 'package:firebase_database_platform_interface/firebase_database_platform_interface.dart';
import 'package:flutter/foundation.dart';

export 'package:firebase_database_dart_platform/src/app.dart'
    show AppCheckProviderFactory, TokenProviderFactory;
export 'package:firebase_database_dart_platform/src/firebase_database.dart'
    show DartFirebaseDatabase, DatabasePersistenceFactory;

/// Selects `firebase_database_dart` as the implementation of the official
/// `firebase_database` package.
abstract final class FirebaseDatabaseDart {
  static DartFirebaseDatabase? _registered;

  /// Whether [use] (or [registerWith]) made this package the Realtime
  /// Database implementation, and nothing replaced it since. Never reads
  /// [DatabasePlatform.instance] before this package set it (its getter
  /// would install the method-channel implementation).
  static bool get isRegistered {
    final DartFirebaseDatabase? registered = _registered;
    return registered != null &&
        identical(DatabasePlatform.instance, registered);
  }

  /// Called by Flutter's plugin registrant on the platforms this package
  /// declares in its pubspec (Linux and Windows), before `main` runs. Same as
  /// [use] without arguments, except under `flutter test` (`FLUTTER_TEST` is
  /// set), where it leaves `firebase_core` alone so that
  /// `setupFirebaseCoreMocks` keeps working; a test that wants the Dart core
  /// calls [use].
  static void registerWith() {
    use(useDartCore: _runningUnderFlutterTest() ? false : null);
  }

  /// Makes `firebase_database_dart` the implementation of `firebase_database`
  /// on any platform. Call it at the start of `main`, before `Firebase` or
  /// `FirebaseDatabase` is used. Calling it again replaces the whole
  /// configuration: [tokenProviderFor], [appCheckProviderFor] and
  /// [persistenceFor] left out of the later call are unset, not kept from the
  /// earlier one. A Dart core an earlier call installed stays installed.
  ///
  /// * [tokenProviderFor] returns the token provider of the connection of a
  ///   FlutterFire app: `FirebaseAuthDart.userAuthFor(app)` of
  ///   `firebase_auth_dart_platform`, or a `FlutterFireAuthTokenProvider` of
  ///   `cloud_firestore_dart_flutterfire`. Called when a client is created
  ///   and the `firebase_app_dart` app of its FlutterFire app has no token
  ///   provider yet: while it returns null, for every client created (each
  ///   database, each new client after a delete); once it returned a
  ///   provider, not again for that `firebase_app_dart` app. The Dart core
  ///   of Linux deletes that app with the FlutterFire app, so a delete and
  ///   create calls it again; the native and web cores keep it, with its
  ///   provider. Without it, or when it returns null, the connection carries
  ///   no user. The provider
  ///   is installed as a `TokenOnChangeProvider`, whose change events carry
  ///   the token. A `firebase_app_dart` app that already exists with the
  ///   name of the FlutterFire app keeps its own providers, and gets these
  ///   only where it has none.
  /// * [appCheckProviderFor] returns the App Check token provider of the
  ///   connection of a FlutterFire app (`FlutterFireAppCheckProvider` of
  ///   `cloud_firestore_dart_flutterfire` for the official
  ///   `firebase_app_check`). Called as [tokenProviderFor] is, when the
  ///   `firebase_app_dart` app has no App Check provider yet.
  /// * [persistenceFor] makes the clients keep their cache and pending writes
  ///   on disk (see [DatabasePersistenceFactory]); without it every client is
  ///   in memory. `FirebaseDatabase.setPersistenceEnabled(false)` turns it
  ///   off for an instance; `setPersistenceEnabled(true)` without it prints a
  ///   warning and stays in memory.
  /// * [useDartCore] replaces the implementation of `firebase_core` with a
  ///   small pure-Dart one, only while `firebase_core` has its default
  ///   method-channel implementation (a core another package installed is
  ///   kept). By default (null) that happens only on Linux; pass true to do
  ///   it on any platform (for example in tests), false to never do it.
  ///
  /// Throws a [StateError] once an instance has created its client: the
  /// configuration is read then.
  static void use({
    TokenProviderFactory? tokenProviderFor,
    AppCheckProviderFactory? appCheckProviderFor,
    DatabasePersistenceFactory? persistenceFor,
    bool? useDartCore,
  }) {
    if (DartFirebaseDatabase.anyStarted) {
      throw StateError(
        'FirebaseDatabaseDart.use must be called before the first use of '
        'FirebaseDatabase.',
      );
    }
    DartFirebaseDatabase.config = DartDatabaseConfig(
      tokenProviderFor: tokenProviderFor,
      appCheckProviderFor: appCheckProviderFor,
      persistenceFor: persistenceFor,
    );
    installCoreIfNeeded(force: useDartCore);
    if (!isRegistered) {
      final DartFirebaseDatabase platform = DartFirebaseDatabase();
      DatabasePlatform.instance = platform;
      _registered = platform;
    }
  }

  /// The `firebase_database_dart` client behind
  /// `FirebaseDatabase.instanceFor(app: app, databaseURL: databaseURL)`, for
  /// what the official API does not have: `onConnected`, `isConnected`,
  /// `serverTimeOffset`, `onChildEvents`, `close`, or `serverStatus` on the
  /// errors. Creates the client when the instance has none yet, which fixes
  /// its settings. Only for an app whose `FirebaseDatabase` this package
  /// implements. Throws a [StateError], and creates no client, when [app] was
  /// deleted and created again under the same name with other options while
  /// an instance of the earlier app is kept, for any database.
  static fs.FirebaseDatabase clientFor(
    FirebaseApp app, {
    String? databaseURL,
  }) => DartFirebaseDatabase.forApp(app, databaseURL).client;
}

/// Whether the program runs under `flutter test`, which sets `FLUTTER_TEST`.
bool _runningUnderFlutterTest() =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

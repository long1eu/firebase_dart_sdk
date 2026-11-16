import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/platform_dependencies.dart';
import 'package:firebase_auth/firebase_auth.dart' as flutterfire;
import 'package:firebase_core/firebase_core.dart' as flutterfire;

import 'auth_token_provider.dart';
import 'options.dart';

/// The common case in one call: a `cloud_firestore_dart` instance for a FlutterFire app and its signed-in user.
///
/// ```dart
/// await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
/// final Firestore firestore = await FlutterFireBridge.firestore();
/// ```
abstract final class FlutterFireBridge {
  /// The default timeout of [firestore] for the first event of `idTokenChanges()`.
  static const Duration defaultReadyTimeout = Duration(seconds: 5);

  /// The `firebase_app_dart` app with the name and the options of the FlutterFire [app] (default:
  /// `Firebase.app()`), created on the first call and returned by later ones. See [dartAppFor].
  static FirebaseApp app({
    flutterfire.FirebaseApp? app,
    PlatformDependencies? dependencies,
  }) {
    final flutterfire.FirebaseApp source = app ?? flutterfire.Firebase.app();
    return dartAppFor(source.name, source.options, dependencies: dependencies);
  }

  /// The `cloud_firestore_dart` instance of [database] for the FlutterFire [app] (default: `Firebase.app()`),
  /// authenticated as the user of [auth] (default: the `FirebaseAuth` of [app]).
  ///
  /// On the first call for an app it creates the `firebase_app_dart` app with the same name and options
  /// ([dartAppFor]), with a [FlutterFireAuthTokenProvider] for [auth] and [appCheckProvider] (for example a
  /// `FlutterFireAppCheckProvider`) as its token providers. Before it creates the Firestore instance it waits, up
  /// to [readyTimeout], for the plugin to report its user, so that the instance starts with the restored user
  /// instead of switching to it a moment later.
  ///
  /// Later calls return the same instance for the same [database], as `Firestore.instanceFor` does; [settings]
  /// and [openDatabase] follow the rules of `Firestore.instanceFor`.
  ///
  /// Throws a [StateError] when a `firebase_app_dart` app of that name exists with other options, or with a
  /// token provider that is not a [FlutterFireAuthTokenProvider].
  static Future<Firestore> firestore({
    flutterfire.FirebaseApp? app,
    flutterfire.FirebaseAuth? auth,
    String database = '(default)',
    FirestoreSettings? settings,
    OpenDatabase? openDatabase,
    PlatformDependencies? dependencies,
    InternalAppCheckTokenProvider? appCheckProvider,
    Duration readyTimeout = defaultReadyTimeout,
  }) async {
    final flutterfire.FirebaseApp source = app ?? flutterfire.Firebase.app();
    final FirebaseApp dartApp;
    FlutterFireAuthTokenProvider? created;
    final FirebaseApp? existing = existingDartApp(source.name);
    if (existing == null) {
      created = FlutterFireAuthTokenProvider(
        auth ?? flutterfire.FirebaseAuth.instanceFor(app: source),
      );
      dartApp = dartAppFor(
        source.name,
        source.options,
        dependencies: dependencies,
        authProvider: created,
        appCheckProvider: appCheckProvider,
      );
    } else {
      dartApp = dartAppFor(source.name, source.options);
      final InternalTokenProvider current = dartApp.authProvider;
      if (identical(current, dartApp)) {
        // The app has no token provider yet.
        dartApp.appCheckProvider ??= appCheckProvider;
        created = FlutterFireAuthTokenProvider(
          auth ?? flutterfire.FirebaseAuth.instanceFor(app: source),
        );
        dartApp.authProvider = created;
      } else if (current is! FlutterFireAuthTokenProvider) {
        throw StateError(
          'The firebase_app_dart app "${dartApp.name}" already has the token provider '
          '${current.runtimeType}.',
        );
      }
    }
    if (created != null) {
      await created.ready.timeout(readyTimeout, onTimeout: () {});
    }
    return Firestore.instanceFor(
      app: dartApp,
      database: database,
      settings: settings,
      openDatabase: openDatabase,
    );
  }

  /// Completes when the Firestore instances of the FlutterFire [app] (default: `Firebase.app()`) work for the
  /// user that `FirebaseAuth.currentUser` returns now. Call it after a sign-in or a sign-out when the next write
  /// must belong to the new user (see [FlutterFireAuthTokenProvider.waitForCurrentUser]).
  ///
  /// ```dart
  /// await FirebaseAuth.instance.signInAnonymously();
  /// await FlutterFireBridge.waitForCurrentUser();
  /// ```
  ///
  /// Throws a [StateError] when the app was not set up by [firestore] (or has another token provider), and a
  /// [TimeoutException] when the plugin does not report the user in time.
  static Future<void> waitForCurrentUser({flutterfire.FirebaseApp? app}) {
    final String name = (app ?? flutterfire.Firebase.app()).name;
    final InternalTokenProvider? provider = existingDartApp(name)?.authProvider;
    if (provider is! FlutterFireAuthTokenProvider) {
      throw StateError(
        'The firebase_app_dart app "$name" has no FlutterFireAuthTokenProvider: create it with '
        'FlutterFireBridge.firestore.',
      );
    }
    return provider.waitForCurrentUser();
  }
}

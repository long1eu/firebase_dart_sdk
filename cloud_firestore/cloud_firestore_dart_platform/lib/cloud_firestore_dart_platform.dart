/// An implementation of FlutterFire's Cloud Firestore platform interface on top
/// of the pure-Dart client `cloud_firestore_dart`.
///
/// An app keeps the official `cloud_firestore` API
/// (`FirebaseFirestore.instance.collection(...)`), and `cloud_firestore_dart`
/// does the work underneath:
///
/// * On Linux, where neither `cloud_firestore` nor `firebase_core` has an
///   implementation, adding this package is enough: Flutter calls
///   [CloudFirestoreDart.registerWith] before `main`.
/// * On any other platform, call [CloudFirestoreDart.use] at the start of
///   `main`, before the first use of Firebase, to replace the official
///   implementation.
///
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   CloudFirestoreDart.use();
///   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
///   await FirebaseFirestore.instance.doc('cities/SF').set({'name': 'SF'});
/// }
/// ```
library;

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as fs;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/foundation.dart';

import 'src/app.dart';
import 'src/core.dart';
import 'src/field_value_factory.dart';
import 'src/firestore.dart';

export 'src/app.dart' show TokenProviderFactory, dartOptionsOf;
export 'src/core.dart' show DartFirebaseAppPlatform, DartFirebaseCore;
export 'src/field_value_factory.dart' show DartFieldValueFactory;
export 'src/firestore.dart' show DartFirebaseFirestore;

/// Selects `cloud_firestore_dart` as the implementation of the official
/// `cloud_firestore` package.
abstract final class CloudFirestoreDart {
  static DartFirebaseFirestore? _registered;

  /// Whether [use] (or [registerWith]) made this package the Firestore
  /// implementation, and nothing replaced it since.
  ///
  /// It does not read `FirebaseFirestorePlatform.instance` when this package
  /// did not register, because that getter needs an initialized default app.
  static bool get isRegistered {
    final DartFirebaseFirestore? registered = _registered;
    return registered != null &&
        identical(FirebaseFirestorePlatform.instance, registered);
  }

  /// Called by Flutter's plugin registrant on the platforms this package
  /// declares in its pubspec (Linux only), before `main` runs. Same as [use]
  /// without arguments.
  static void registerWith() => use();

  /// Makes `cloud_firestore_dart` the implementation of `cloud_firestore` on
  /// any platform. Call it at the start of `main`, before `Firebase` or
  /// `FirebaseFirestore` is used; calling it again changes the configuration.
  ///
  /// * [openDatabase] opens the SQLite database of the offline cache (see
  ///   `Firestore.instanceFor` of `cloud_firestore_dart`). Without it the
  ///   cache is in memory, whatever `Settings.persistenceEnabled` says.
  /// * [tokenProviderFor] returns the token provider for the requests of a
  ///   FlutterFire app, for example a `FlutterFireAuthTokenProvider` of
  ///   `cloud_firestore_dart_flutterfire` (the user of the official
  ///   `firebase_auth`) or a `FirebaseUserAuth` of
  ///   `firebase_auth_providers_dart`. It is called once per app, when the
  ///   first Firestore instance of the app starts. Without it, or when it
  ///   returns null, requests carry no user (enough for the emulator and for
  ///   open rules). A `firebase_app_dart` app that already exists with the
  ///   name of the FlutterFire app is used as it is, with its own providers.
  /// * [useDartCore] replaces the implementation of `firebase_core` with
  ///   [DartFirebaseCore]. By default (null) that happens only on Linux, and
  ///   only while `firebase_core` has no other implementation; pass true to
  ///   force it (for example in tests), false to never do it.
  ///
  /// Throws a [StateError] when a Firestore instance has already started:
  /// the configuration is read when an instance starts.
  static void use({
    fs.OpenDatabase? openDatabase,
    TokenProviderFactory? tokenProviderFor,
    bool? useDartCore,
  }) {
    if (DartFirebaseFirestore.anyStarted) {
      throw StateError(
        'CloudFirestoreDart.use must be called before the first Firestore '
        'operation.',
      );
    }
    DartFirebaseFirestore.config = DartFirestoreConfig(
      openDatabase: openDatabase,
      tokenProviderFor: tokenProviderFor,
    );
    final bool replaceCore =
        useDartCore ??
        (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.linux &&
            FirebasePlatform.instance is MethodChannelFirebase);
    if (replaceCore && FirebasePlatform.instance is! DartFirebaseCore) {
      FirebasePlatform.instance = DartFirebaseCore();
    }
    if (!isRegistered) {
      final DartFirebaseFirestore platform = DartFirebaseFirestore();
      FirebaseFirestorePlatform.instance = platform;
      _registered = platform;
    }
    if (FieldValueFactoryPlatform.instance is! DartFieldValueFactory) {
      FieldValueFactoryPlatform.instance = DartFieldValueFactory();
    }
  }
}

/// An implementation of FlutterFire's Cloud Storage platform interface on top
/// of the pure-Dart client `firebase_storage_dart`.
///
/// An app keeps the official `firebase_storage` API
/// (`FirebaseStorage.instance.ref('a.png').putData(...)`), and
/// `firebase_storage_dart` does the work underneath, over the Cloud Storage for
/// Firebase REST API:
///
/// * On Linux, where neither `firebase_storage` nor `firebase_core` has an
///   implementation, adding this package is enough: Flutter calls
///   [FirebaseStorageDart.registerWith] before `main`.
/// * On any other platform, call [FirebaseStorageDart.use] at the start of
///   `main`, before the first use of Firebase, to replace the official
///   implementation.
///
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   FirebaseStorageDart.use(
///     tokenProviderFor: (FirebaseApp app) => FirebaseAuthDart.userAuthFor(app),
///   );
///   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
///   await FirebaseStorage.instance.ref('notes/today.txt').putString('Hello');
/// }
/// ```
library;

import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart' as fs;
import 'package:firebase_storage_platform_interface/firebase_storage_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'src/app.dart';
import 'src/core.dart';
import 'src/firebase_storage.dart';

export 'src/app.dart' show TokenProviderFactory;
export 'src/firebase_storage.dart' show DartFirebaseStorage;

/// Selects `firebase_storage_dart` as the implementation of the official
/// `firebase_storage` package.
abstract final class FirebaseStorageDart {
  static DartFirebaseStorage? _registered;

  /// Whether [use] (or [registerWith]) made this package the Storage
  /// implementation, and nothing replaced it since.
  static bool get isRegistered {
    final DartFirebaseStorage? registered = _registered;
    return registered != null &&
        identical(FirebaseStoragePlatform.instance, registered);
  }

  /// Called by Flutter's plugin registrant on the platforms this package
  /// declares in its pubspec (Linux only), before `main` runs. Same as [use]
  /// without arguments, except under `flutter test` (`FLUTTER_TEST` is set),
  /// where it leaves `firebase_core` alone so that `setupFirebaseCoreMocks`
  /// keeps working; a test that wants the Dart core calls [use].
  static void registerWith() {
    use(useDartCore: _runningUnderFlutterTest() ? false : null);
  }

  /// Makes `firebase_storage_dart` the implementation of `firebase_storage`
  /// on any platform. Call it at the start of `main`, before `Firebase` or
  /// `FirebaseStorage` is used; calling it again changes the configuration.
  ///
  /// * [tokenProviderFor] returns the token provider for the requests of a
  ///   FlutterFire app: `FirebaseAuthDart.userAuthFor(app)` of
  ///   `firebase_auth_dart_platform`, or a `FlutterFireAuthTokenProvider` of
  ///   `cloud_firestore_dart_flutterfire` (the user of the official
  ///   `firebase_auth`). It is called once per app. Without it, or when it
  ///   returns null, requests carry no user (enough for the emulator and for
  ///   open rules). A `firebase_app_dart` app that already exists with the
  ///   name of the FlutterFire app (the Firestore platform package creates
  ///   one) is used as it is, with its own providers.
  /// * [httpClient] sends the requests (for tests and proxies); by default
  ///   one client is shared by all instances.
  /// * [maxConcurrentUploads] and [maxUploadChunkSize] are those of the
  ///   `firebase_storage_dart` client: at most that many uploads of one app
  ///   and bucket run at once (8), and on the VM an upload of bytes or a file
  ///   goes as one streamed request unless [maxUploadChunkSize] sets chunks.
  /// * [useDartCore] replaces the implementation of `firebase_core` with a
  ///   small pure-Dart one. By default (null) that happens only on Linux, and
  ///   only while `firebase_core` has no other implementation; pass true to
  ///   force it (for example in tests), false to never do it.
  ///
  /// Throws a [StateError] once an instance has sent a request: the
  /// configuration is read then.
  static void use({
    TokenProviderFactory? tokenProviderFor,
    http.Client? httpClient,
    int maxConcurrentUploads = 8,
    int? maxUploadChunkSize,
    bool? useDartCore,
  }) {
    if (DartFirebaseStorage.anyStarted) {
      throw StateError(
        'FirebaseStorageDart.use must be called before the first use of '
        'FirebaseStorage.',
      );
    }
    DartFirebaseStorage.config = DartStorageConfig(
      tokenProviderFor: tokenProviderFor,
      httpClient: httpClient,
      maxConcurrentUploads: maxConcurrentUploads,
      maxUploadChunkSize: maxUploadChunkSize,
    );
    installCoreIfNeeded(force: useDartCore);
    if (!isRegistered) {
      final DartFirebaseStorage platform = DartFirebaseStorage();
      FirebaseStoragePlatform.instance = platform;
      _registered = platform;
    }
  }

  /// The `firebase_storage_dart` client behind
  /// `FirebaseStorage.instanceFor(app: app, bucket: bucket)` with its current
  /// settings, for what the official API does not have: `openRead` (a
  /// streamed, ranged download), `listPages`, `putBytes` without a task, or
  /// `httpStatus` and `serverResponse` on the errors. [bucket] is the default
  /// bucket of the app by default. Only for an app whose `FirebaseStorage`
  /// this package implements.
  static fs.FirebaseStorage clientFor(FirebaseApp app, {String? bucket}) {
    String? name = bucket ?? app.options.storageBucket;
    if (name == null) {
      throw ArgumentError.value(
        bucket,
        'bucket',
        'The app "${app.name}" has no storageBucket',
      );
    }
    if (name.startsWith('gs://')) {
      name = name.substring('gs://'.length);
    }
    return DartFirebaseStorage.forApp(app, name).client;
  }
}

/// Whether the program runs under `flutter test`, which sets `FLUTTER_TEST`.
bool _runningUnderFlutterTest() =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

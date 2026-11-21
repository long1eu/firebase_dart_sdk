import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';

/// The plugin name FlutterFire puts on the exceptions of Storage.
const String storagePlugin = 'firebase_storage';

/// [error] as the official plugin would report it.
///
/// `firebase_storage_dart` throws a `FirebaseStorageException`, which extends
/// the `FirebaseException` of `firebase_app_dart` and carries the plugin
/// `firebase_storage` and the code of the JS SDK without its `storage/` prefix
/// (`object-not-found`, `unauthorized`, ...), as the official plugin reports
/// them. Apps catch the `FirebaseException` of `firebase_core`, a different
/// class, so the fields are copied over. Anything else is returned unchanged.
Object convertError(Object error, [StackTrace? stackTrace]) {
  if (error is dart_app.FirebaseException) {
    return FirebaseException(
      plugin: error.plugin,
      code: error.code,
      message: error.message,
      stackTrace: error.stackTrace ?? stackTrace,
    );
  }
  return error;
}

/// Runs [body] and rethrows its `firebase_app_dart` exceptions as
/// [FirebaseException]s.
Future<T> guard<T>(Future<T> Function() body) async {
  try {
    return await body();
  } catch (error, stackTrace) {
    final Object converted = convertError(error, stackTrace);
    if (identical(converted, error)) {
      rethrow;
    }
    Error.throwWithStackTrace(converted, stackTrace);
  }
}

/// A [FirebaseException] of this plugin with [code], for the errors this
/// package detects itself.
FirebaseException storageException(String code, String message) =>
    FirebaseException(plugin: storagePlugin, code: code, message: message);

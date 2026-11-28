import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';

/// The plugin name FlutterFire puts on the exceptions of Analytics.
const String analyticsPlugin = 'firebase_analytics';

/// [error] as an app of the official plugin catches it.
///
/// A `firebase_app_dart` exception (the client's `FirebaseAnalyticsException`,
/// thrown when an event, a parameter, a user property or the user id breaks a
/// rule) becomes a [FirebaseException] of `firebase_core` with the plugin
/// `firebase_analytics`, the same code (`reserved-name`, `invalid-parameter`
/// and the others the client documents) and the same message. Anything else
/// is returned unchanged.
Object convertError(Object error) {
  if (error is! dart_app.FirebaseException) {
    return error;
  }
  return FirebaseException(
    plugin: analyticsPlugin,
    code: error.code,
    message: error.message,
    stackTrace: error.stackTrace,
  );
}

/// Runs [body] and rethrows what it throws as converted by [convertError].
Future<T> guard<T>(Future<T> Function() body) async {
  try {
    return await body();
  } catch (error, stackTrace) {
    final Object converted = convertError(error);
    if (identical(converted, error)) {
      rethrow;
    }
    Error.throwWithStackTrace(converted, stackTrace);
  }
}

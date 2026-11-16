// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

import 'package:meta/meta.dart';

/// The exception thrown by the Firebase packages of this repository when an operation fails, with the shape of
/// FlutterFire's `FirebaseException`.
///
/// [plugin] names the package (`cloud_firestore`, `firebase_auth`, `core`), [code] says what went wrong in kebab
/// case (`not-found`, `permission-denied`), and [message] describes it for people.
/// `FirestoreException` of `cloud_firestore_dart` and `FirebaseAuthException` of
/// `firebase_auth_providers_dart` extend it.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// void main() {
///   try {
///     throw FirebaseException(plugin: 'core', code: 'no-app', message: 'No app.');
///   } on FirebaseException catch (e) {
///     print(e); // [core/no-app] No app.
///   }
/// }
/// ```
@immutable
class FirebaseException implements Exception {
  /// Creates an exception of [plugin]; [code] defaults to `unknown`.
  const FirebaseException({
    required this.plugin,
    this.message,
    String? code,
    this.stackTrace,
  }) : code = code ?? 'unknown';

  /// The package that threw the exception, for example `cloud_firestore`.
  final String plugin;

  /// A description of what went wrong.
  final String? message;

  /// What went wrong, in kebab case, for example `not-found`.
  final String code;

  /// The stack trace captured where the exception originated, if any.
  final StackTrace? stackTrace;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirebaseException &&
          other.plugin == plugin &&
          other.code == code &&
          other.message == message;

  @override
  int get hashCode => Object.hash(plugin, code, message);

  @override
  String toString() {
    final StackTrace? trace = stackTrace;
    return '[$plugin/$code] $message${trace == null ? '' : '\n\n$trace'}';
  }
}

/// Thrown by `AuthTokenProvider.getAccessToken` when nobody is signed in.
///
/// Firestore catches it and sends the request without a token, so the security rules see no
/// user. Throw it from a token provider of your own in that case; any other error fails the
/// request with `unauthenticated`.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// Future<GetTokenResult> tokenOf(String? idToken) async {
///   if (idToken == null) {
///     throw FirebaseNoSignedInUserException('No user is signed in.');
///   }
///   return GetTokenResult(idToken);
/// }
/// ```
class FirebaseNoSignedInUserException extends FirebaseException {
  /// Creates the exception with a [message]; its [code] is `no-signed-in-user`.
  const FirebaseNoSignedInUserException([String? message])
    : super(plugin: 'core', code: 'no-signed-in-user', message: message);
}

/// Thrown when a Firebase service or feature that an operation needs is not available.
///
/// When an auth or App Check token provider throws it, Firestore sends the request without that
/// token and logs nothing above the debug level.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// final FirebaseApiNotAvailableException error =
///     FirebaseApiNotAvailableException('App Check is not available.');
/// ```
class FirebaseApiNotAvailableException extends FirebaseException {
  /// Creates the exception with a [message]; its [code] is `api-not-available`.
  const FirebaseApiNotAvailableException([String? message])
    : super(plugin: 'core', code: 'api-not-available', message: message);
}

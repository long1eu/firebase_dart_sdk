import 'package:firebase_app_dart/firebase_app_dart.dart';

/// Thrown when a Cloud Storage operation fails.
///
/// It extends [FirebaseException] with the [plugin] `firebase_storage`, like FlutterFire's exception of the same
/// package, so `on FirebaseException catch (e)` catches it too. Branch on [code]; [message] is for people,
/// [httpStatus] and [serverResponse] are for logs.
///
/// The codes are those of the Firebase JS SDK without the `storage/` prefix:
///
/// | Code | Meaning |
/// | --- | --- |
/// | `object-not-found` | there is no object at the reference (HTTP 404 on an object operation) |
/// | `unauthenticated` | the security rules need a signed-in user, or the token was refused (HTTP 401) |
/// | `unauthorized-app` | the backend refused the App Check token (HTTP 401) |
/// | `unauthorized` | the security rules deny the operation (HTTP 403) |
/// | `quota-exceeded` | the quota of the bucket is used up (HTTP 402) |
/// | `retry-limit-exceeded` | the operation kept failing with retryable errors for longer than the time of its [StorageRetryPolicy](see `FirebaseStorage`) |
/// | `canceled` | the operation was canceled |
/// | `invalid-argument` | an argument is out of range (`maxResults` of `Reference.list`, `maxSize` of `Reference.getBytes`) |
/// | `invalid-format` | the string of `Reference.putString` does not match its format |
/// | `invalid-url` | `FirebaseStorage.refFromUrl` was given something that is not a Cloud Storage URL |
/// | `invalid-root-operation` | the operation needs an object and the reference is the root of the bucket |
/// | `no-download-url` | the object has no download token |
/// | `download-size-exceeded` | the object is larger than the `maxSize` of `Reference.getBytes` |
/// | `unknown` | anything else, for example HTTP 400 or a response that cannot be read; see [httpStatus] and [serverResponse] |
///
/// Unlike the JS SDK, every error that comes from a response carries its [httpStatus], and [serverResponse]
/// holds the body of that response.
///
/// ```dart
/// try {
///   await storage.ref('avatars/me.png').metadata();
/// } on FirebaseStorageException catch (e) {
///   if (e.code == 'object-not-found') {
///     print('No avatar yet.');
///   } else {
///     rethrow;
///   }
/// }
/// ```
class FirebaseStorageException extends FirebaseException {
  /// Creates an exception with the [code] (for example `object-not-found`) and a [message]. The package creates
  /// them; you need this only in tests.
  const FirebaseStorageException({
    required String code,
    required String message,
    this.httpStatus,
    this.serverResponse,
    super.stackTrace,
  }) : super(plugin: 'firebase_storage', code: code, message: message);

  /// The HTTP status of the response that caused the error, or null when there was no response (a network
  /// error, a cancellation, a check before the request).
  final int? httpStatus;

  /// The body of the response that caused the error, cut at 16 KiB. It never holds request or response
  /// headers, so no token.
  final String? serverResponse;

  @override
  String toString() {
    final String? body = serverResponse;
    final String status = httpStatus == null ? '' : ' (HTTP $httpStatus)';
    final String base = '[$plugin/$code] $message$status';
    return body == null || body.isEmpty ? base : '$base\n$body';
  }
}

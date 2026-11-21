/// The errors of the package, with the messages of the JS SDK (`implementation/error.ts`) and the status mapping
/// of its request handlers (`implementation/requests.ts`).
@internal
library;

import 'package:meta/meta.dart';

import 'exception.dart';

/// Maps a response that is not a success to an exception, from its HTTP status and its body (at most 16 KiB).
@internal
typedef StorageErrorMapper =
    FirebaseStorageException Function(int status, String body);

/// The mapping of `sharedErrorHandler`: 401, 402 and 403 get their own codes, anything else is `unknown`.
///
/// [bucket] and [path] name the target in the messages. Every exception carries the HTTP status and the body, unlike
/// the JS SDK (which reports status 0 for `object-not-found` and never reads the body).
@internal
StorageErrorMapper sharedErrorMapper(String bucket, String path) {
  return (int status, String body) {
    final (String code, String message) = switch (status) {
      401 when body.contains('Firebase App Check token is invalid') => (
        'unauthorized-app',
        'This app does not have permission to access Firebase Storage on '
            'this project.',
      ),
      401 => (
        'unauthenticated',
        'User is not authenticated, please authenticate using Firebase '
            'Authentication and try again.',
      ),
      402 => (
        'quota-exceeded',
        "Quota for bucket '$bucket' exceeded, please view quota on "
            'https://firebase.google.com/pricing/.',
      ),
      403 => (
        'unauthorized',
        "User does not have permission to access '$path'.",
      ),
      _ => (
        'unknown',
        'An unknown error occurred, please check the error payload for '
            'server response.',
      ),
    };
    return FirebaseStorageException(
      code: code,
      message: message,
      httpStatus: status,
      serverResponse: body,
    );
  };
}

/// The mapping of `objectErrorHandler`: [sharedErrorMapper], and `object-not-found` for a 404.
@internal
StorageErrorMapper objectErrorMapper(String bucket, String path) {
  final StorageErrorMapper shared = sharedErrorMapper(bucket, path);
  return (int status, String body) {
    if (status == 404) {
      return FirebaseStorageException(
        code: 'object-not-found',
        message: "Object '$path' does not exist.",
        httpStatus: status,
        serverResponse: body,
      );
    }
    return shared(status, body);
  };
}

/// A response that the package cannot read (`unknown` without a mapping).
@internal
FirebaseStorageException unknownResponse(String detail, {int? httpStatus}) {
  return FirebaseStorageException(
    code: 'unknown',
    message: 'An unknown error occurred: $detail',
    httpStatus: httpStatus,
  );
}

/// The operation kept failing for longer than its retry time.
@internal
FirebaseStorageException retryLimitExceeded({int? httpStatus, Object? cause}) {
  final String detail = cause == null ? '' : ' Last error: $cause';
  return FirebaseStorageException(
    code: 'retry-limit-exceeded',
    message: 'Max retry time for operation exceeded, please try again.$detail',
    httpStatus: httpStatus,
  );
}

/// The operation was canceled.
@internal
FirebaseStorageException canceled() {
  return const FirebaseStorageException(
    code: 'canceled',
    message: 'User canceled the upload/download.',
  );
}

/// [url] is not a Cloud Storage URL. The message leaves out the query and the fragment, which can hold a
/// download token.
@internal
FirebaseStorageException invalidUrl(String url) {
  final String shown = url.split(RegExp('[?#]')).first;
  return FirebaseStorageException(
    code: 'invalid-url',
    message: "Invalid URL '$shown'.",
  );
}

/// An argument is out of range.
@internal
FirebaseStorageException invalidArgument(String message) {
  return FirebaseStorageException(code: 'invalid-argument', message: message);
}

/// The operation [name] needs an object and was called on the root of the bucket.
@internal
FirebaseStorageException invalidRootOperation(String name) {
  return FirebaseStorageException(
    code: 'invalid-root-operation',
    message:
        "The operation '$name' cannot be performed on a root reference, "
        "create a non-root reference using child, such as .child('file.png').",
  );
}

/// The string of `putString` does not match [format] (the name of the format in the JS SDK).
@internal
FirebaseStorageException invalidFormat(String format, String message) {
  return FirebaseStorageException(
    code: 'invalid-format',
    message: "String does not match format '$format': $message",
  );
}

/// The object has no download token.
@internal
FirebaseStorageException noDownloadUrl() {
  return const FirebaseStorageException(
    code: 'no-download-url',
    message: 'The given file does not have any download URLs.',
  );
}

/// The object is larger than the `maxSize` of `getBytes`.
@internal
FirebaseStorageException downloadSizeExceeded(String path, int maxSize) {
  return FirebaseStorageException(
    code: 'download-size-exceeded',
    message: "Object '$path' is larger than the maximum of $maxSize bytes.",
  );
}

/// The token provider failed with something other than "nobody is signed in".
///
/// Only the type of [error] goes into the message: the text of a provider's error may hold a token. [error]
/// and [stackTrace] are kept as the `cause` and `stackTrace` of the exception.
@internal
FirebaseStorageException tokenFailed(Object error, StackTrace stackTrace) {
  return FirebaseStorageException(
    code: 'unauthenticated',
    message:
        'Could not get the token of the signed-in user (${error.runtimeType}).',
    cause: error,
    stackTrace: stackTrace,
  );
}

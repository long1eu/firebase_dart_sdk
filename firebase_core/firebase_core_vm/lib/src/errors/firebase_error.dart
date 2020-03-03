// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

class FirebaseError implements Error {
  const FirebaseError(this.message, [this.stackTrace]) : assert(message != null, 'Detail message must not be empty.');

  final String message;

  @override
  final StackTrace stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}

/// Internal use only, indicates that no signed-in user and operations like
/// [InternalTokenProvider.getAccessToken] will fail.
class FirebaseNoSignedInUserError extends FirebaseError {
  FirebaseNoSignedInUserError(String message) : super(message);
}

class FirebaseApiNotAvailableError extends FirebaseError {
  const FirebaseApiNotAvailableError(String message) : super(message);
}

/// Exception thrown when a request to a Firebase service has failed due to a
/// network error. Inspect the device's network connectivity state or retry
/// later to resolve.
class FirebaseNetworkError extends FirebaseError {
  const FirebaseNetworkError(String message) : super(message);
}

/// Exception thrown when a request to a Firebase service has been blocked due
/// to having received too many consecutive requests from the same device. Retry
/// the request later to resolve.
class FirebaseTooManyRequestsError extends FirebaseError {
  const FirebaseTooManyRequestsError(String message) : super(message);
}

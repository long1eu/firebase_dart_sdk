// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

import 'package:firebase_common_dart/src/errors/firebase_error.dart';

/// Exception thrown when a request to a Firebase service has been blocked due
/// to having received too many consecutive requests from the same device. Retry
/// the request later to resolve.
class FirebaseTooManyRequestsError extends FirebaseError {
  const FirebaseTooManyRequestsError(String message) : super(message);
}

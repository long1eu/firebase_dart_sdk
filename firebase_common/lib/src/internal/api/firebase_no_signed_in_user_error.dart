// File created by
// Lung Razvan <long1eu>
// on 24/09/2018

import 'package:firebase_common/src/annotations.dart';
import 'package:firebase_common/src/errors/firebase_error.dart';
import 'package:firebase_common/src/internal/internal_token_provider.dart';

/// Internal use only, indicates that no signed-in user and operations like
/// [InternalTokenProvider.getAccessToken] will fail.
@keepForSdk
class FirebaseNoSignedInUserError extends FirebaseError {
  @keepForSdk
  FirebaseNoSignedInUserError(String message) : super(message);
}

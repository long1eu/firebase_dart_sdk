// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

import 'dart:async';

import 'package:firebase_common/src/annotations.dart';
import 'package:firebase_common/src/auth/get_token_result.dart';
import 'package:firebase_common/src/firebase_app.dart';
import 'package:firebase_common/src/internal/internal_token_result.dart';

/// Provides a way for [FirebaseApp] to get an access token if there exists
/// a logged in user.
@keepForSdk
abstract class InternalTokenProvider {
  /// Fetch a valid STS Token.
  ///
  /// [forceRefresh[ force refreshes the token. Should only be set to true if
  /// the token is invalidated out of band.
  @keepForSdk
  Future<GetTokenResult> getAccessToken(bool forceRefresh);

  /// A synchronous way to get the current Firebase User's UID.
  /// Returns the String representation of the UID. Returns null if FirebaseAuth
  /// is not linked, or if there is no currently signed-in user.
  @keepForSdk
  String get uid;

  /// Stream that will emit when the user auth state changes, when the user logs
  /// out or the token has been invalidated and it's refreshed.
  Stream<InternalTokenResult> get onTokenChanged;
}

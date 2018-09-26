// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_common/firebase_common.dart';

import '../firebase_firestore_error.dart';
import '../util/listener.dart';
import 'credentials_provider.dart';
import 'user.dart';

class FirebaseAuthCredentialsProvider extends CredentialsProvider {
  final InternalAuthProvider authProvider;

  /// The listener registered with FirebaseApp; used to stop receiving auth
  /// changes once changeListener is removed.
  OnIdTokenChanged idTokenObserver;

  /// The listener to be notified of credential changes
  /// (sign-in / sign-out, token changes).
  Listener<User> changeListener;

  /// The current user as reported to us via our IdTokenObserver.
  User currentUser;

  /// Counter used to detect if the token changed while a getToken request was
  /// outstanding.
  int tokenCounter;

  bool forceRefresh;

  FirebaseAuthCredentialsProvider(this.authProvider) {
    idTokenObserver = tokenObserver;
    currentUser = getUser();
    tokenCounter = 0;
    authProvider.addIdTokenObserver(idTokenObserver);
  }

  void tokenObserver(InternalTokenResult tokenResult) {
    currentUser = getUser();
    tokenCounter++;

    if (changeListener != null) {
      changeListener(currentUser);
    }
  }

  @override
  Future<String> get token async {
    final bool doForceRefresh = forceRefresh;
    forceRefresh = false;

    // Take note of the current value of the tokenCounter so that this method
    // can fail (with a FirebaseFirestoreException) if there is a token change
    // while the request is outstanding.
    final int savedCounter = tokenCounter;

    final GetTokenResult result =
        await authProvider.getAccessToken(doForceRefresh);

    // Cancel the request since the token changed while the request was outstanding so the
    // response is potentially for a previous user (which user, we can't be sure).
    if (savedCounter != tokenCounter) {
      throw FirebaseFirestoreError(
        'getToken aborted due to token change',
        FirebaseFirestoreErrorCode.aborted,
      );
    }

    return result.token;
  }

  @override
  void invalidateToken() => forceRefresh = true;

  @override
  void setChangeListener(Listener<User> changeListener) {
    this.changeListener = changeListener;

    // Fire the initial event.
    changeListener(currentUser);
  }

  @override
  void removeChangeListener() {
    changeListener = null;
    authProvider.removeIdTokenObserver(idTokenObserver);
  }

  /// Returns the current [User] as obtained from the given FirebaseApp
  /// instance.
  User getUser() {
    final String uid = authProvider.uid;
    return uid != null ? User(uid) : User.unauthenticated;
  }
}

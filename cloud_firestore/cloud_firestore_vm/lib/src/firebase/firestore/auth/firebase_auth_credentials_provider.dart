// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:rxdart/rxdart.dart';

/// [FirebaseAuthCredentialsProvider] uses Firebase Auth via [FirebaseApp] to
/// get an auth token.
class FirebaseAuthCredentialsProvider extends CredentialsProvider {
  FirebaseAuthCredentialsProvider(this.authProvider)
      : _onUserChange = BehaviorSubject<User>.seeded(authProvider.uid != null
            ? User(authProvider.uid)
            : User.unauthenticated);

  /// Stream that will receive credential changes (sign-in / sign-out, token
  /// changes).
  final BehaviorSubject<User> _onUserChange;

  final InternalTokenProvider authProvider;

  /// Counter used to detect if the token changed while a getToken request was
  /// outstanding.
  int _tokenCounter = 0;
  bool _forceRefresh = false;

  /// The listener registered with FirebaseApp; used to stop receiving auth
  /// changes once changeListener is removed.
  void tokenObserver(InternalTokenResult tokenResult) {
    _tokenCounter++;
    _onUserChange.add(getUser());
  }

  @override
  Future<String> get token async {
    final bool doForceRefresh = _forceRefresh;
    _forceRefresh = false;

    // Take note of the current value of the tokenCounter so that this method
    // can fail (with a FirebaseFirestoreError) if there is a token change while
    // the request is outstanding.
    final int savedCounter = _tokenCounter;

    final GetTokenResult result =
        await authProvider.getAccessToken(forceRefresh: doForceRefresh);

    // Cancel the request since the token changed while the request was
    // outstanding so the response is potentially for a previous user (which
    // user, we can't be sure).
    if (savedCounter != _tokenCounter) {
      throw FirestoreError('getToken aborted due to token change',
          FirestoreErrorCode.aborted);
    }

    return result?.token;
  }

  @override
  void invalidateToken() => _forceRefresh = true;

  /// Returns the current [User] as obtained from the given [FirebaseApp]
  /// instance.
  User getUser() {
    final String uid = authProvider.uid;
    return uid != null ? User(uid) : User.unauthenticated;
  }

  @override
  Stream<User> get onChange => _onUserChange;
}

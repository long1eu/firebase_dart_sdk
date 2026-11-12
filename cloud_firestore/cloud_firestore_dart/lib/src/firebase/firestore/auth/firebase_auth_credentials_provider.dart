// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:rxdart/rxdart.dart';

/// [FirebaseAuthCredentialsProvider] uses Firebase Auth via [FirebaseApp] to
/// get an auth token.
class FirebaseAuthCredentialsProvider extends CredentialsProvider {
  FirebaseAuthCredentialsProvider(this.authProvider) {
    _onUserChange = BehaviorSubject<User>.seeded(
      getUser(),
      // A listener that comes back after the last one left must get updates
      // again, so tracking restarts on listen.
      onListen: _subscribeToTokenChanges,
      // Like Java's removeChangeListener: stop receiving auth changes once the
      // (only) listener is gone.
      onCancel: _unsubscribeFromTokenChanges,
    );
    // Like Java's addIdTokenListener: get notified of sign-in, sign-out and
    // token changes from now on, even before somebody listens to [onChange].
    _subscribeToTokenChanges();
  }

  void _subscribeToTokenChanges() {
    if (_tokenSubscription != null) {
      return;
    }
    _tokenSubscription = authProvider.onTokenChanged.listen(
      tokenObserver,
      onError: (Object error) => Log.w(
          'FirebaseAuthCredentialsProvider', 'Token stream error: $error'),
    );
    if (_wasUnsubscribed) {
      // Changes may have been missed while not listening: invalidate any
      // outstanding token request and publish the current user.
      _wasUnsubscribed = false;
      _tokenCounter++;
      scheduleMicrotask(() {
        if (!_onUserChange.isClosed) {
          _onUserChange.add(getUser());
        }
      });
    }
  }

  void _unsubscribeFromTokenChanges() {
    _tokenSubscription?.cancel();
    _tokenSubscription = null;
    _wasUnsubscribed = true;
  }

  /// Stream that will receive credential changes (sign-in / sign-out, token
  /// changes).
  late final BehaviorSubject<User> _onUserChange;

  StreamSubscription<InternalTokenResult>? _tokenSubscription;
  bool _wasUnsubscribed = false;

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
  Future<String?> get token async {
    final bool doForceRefresh = _forceRefresh;
    _forceRefresh = false;

    // Take note of the current value of the tokenCounter so that this method
    // can retry if there is a token change while the request is outstanding.
    final int savedCounter = _tokenCounter;

    final GetTokenResult result =
        await authProvider.getAccessToken(forceRefresh: doForceRefresh);

    // Discard the response since the token changed while the request was
    // outstanding, so it is potentially for a previous user (which user, we
    // can't be sure), and fetch the token again.
    if (savedCounter != _tokenCounter) {
      Log.d('FirebaseAuthCredentialsProvider',
          'getToken aborted due to token change');
      return token;
    }

    return result.token;
  }

  @override
  void invalidateToken() => _forceRefresh = true;

  /// Returns the current [User] as obtained from the given [FirebaseApp]
  /// instance.
  User getUser() {
    final String? uid = authProvider.uid;
    return uid != null ? User(uid) : User.unauthenticated;
  }

  @override
  Stream<User> get onChange => _onUserChange;
}

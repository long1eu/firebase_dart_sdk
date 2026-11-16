import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth/firebase_auth.dart' as flutterfire;

/// What [FlutterFireAuthTokenProvider] needs of a signed-in user: the id and the ID token.
///
/// The provider made with [FlutterFireAuthTokenProvider.new] wraps the `User` of `firebase_auth`. Implement it
/// yourself to drive the provider from another source, or from a test:
///
/// ```dart
/// class FakeUser implements IdTokenUser {
///   FakeUser(this.uid);
///
///   @override
///   final String uid;
///
///   @override
///   Future<String?> getIdToken({required bool forceRefresh}) async =>
///       'token-of-$uid';
/// }
/// ```
abstract interface class IdTokenUser {
  /// The id of the user.
  String get uid;

  /// The ID token of the user, refreshed when it expired or when [forceRefresh] is set.
  Future<String?> getIdToken({required bool forceRefresh});
}

/// A token provider for `cloud_firestore_dart` that takes the user and the ID token from the official
/// `firebase_auth` plugin.
///
/// Firestore sends the ID token of the plugin's signed-in user with every request, so the security rules see the
/// same `request.auth` as with the official Firestore plugin, and it follows sign-in, sign-out and a switch of
/// users the way it does with `FirebaseUserAuth` of `firebase_auth_providers_dart`: the streams restart with the
/// new identity and the pending writes of each user stay with that user.
///
/// Make it the token provider of the `firebase_app_dart` app before the Firestore instance of that app is
/// created. `FlutterFireBridge.firestore` does that for you.
///
/// ```dart
/// final FlutterFireAuthTokenProvider provider =
///     FlutterFireAuthTokenProvider(FirebaseAuth.instance);
/// dartApp.authProvider = provider;
/// final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(app: dartApp);
/// ```
///
/// **How it follows the user.** The provider listens to `idTokenChanges()` of the plugin. When the uid changes
/// (a sign-in, a sign-out, another user) it takes the new user over and emits on [onTokenChanged], in the same
/// call, so Firestore reads the new [uid] when it handles the event. A refresh of the token of the same user is
/// emitted too (Firestore restarts its streams with the fresh token, as it does with `FirebaseUserAuth`).
///
/// **The gap after a sign-in.** The plugin completes `signInWith...()` before its `idTokenChanges()` event arrives.
/// Until that event, Firestore still works for the previous user (or for nobody). [getAccessToken] does not hand
/// out the token of the new user in that gap: it waits for the event, which switches Firestore first. A write
/// that you issue right after `await signIn...()` is still recorded for the previous user; call
/// [waitForCurrentUser] first.
class FlutterFireAuthTokenProvider implements AuthTokenProvider {
  /// Creates the provider for [auth], for example `FirebaseAuth.instance`.
  ///
  /// It starts listening to `auth.idTokenChanges()` at once and stops in [dispose].
  factory FlutterFireAuthTokenProvider(
    flutterfire.FirebaseAuth auth, {
    Duration userChangeTimeout = const Duration(seconds: 10),
  }) {
    return FlutterFireAuthTokenProvider.fromSource(
      currentUser: () => _FlutterFireUser.wrap(auth.currentUser),
      idTokenChanges: auth.idTokenChanges().map(_FlutterFireUser.wrap),
      userChangeTimeout: userChangeTimeout,
    );
  }

  /// Creates the provider from a user source: [currentUser] returns the user that is signed in now, and
  /// [idTokenChanges] emits the user (null when signed out) after a sign-in, a sign-out and a token refresh.
  ///
  /// [idTokenChanges] may start with the current user, as the stream of `firebase_auth` does; that first event is
  /// not passed on when it is the user [currentUser] returned at construction.
  ///
  /// [userChangeTimeout] bounds the waits for an event that [currentUser] announces (see [getAccessToken] and
  /// [waitForCurrentUser]).
  FlutterFireAuthTokenProvider.fromSource({
    required IdTokenUser? Function() currentUser,
    required Stream<IdTokenUser?> idTokenChanges,
    this.userChangeTimeout = const Duration(seconds: 10),
  }) : _currentUser = currentUser,
       _user = currentUser() {
    _subscription = idTokenChanges.listen(
      _onIdTokenChanged,
      onError: _onSourceError,
    );
  }

  /// The text of the [AuthTokenChange] that [onTokenChanged] emits for a signed-in user.
  ///
  /// `firebase_auth` reports a change of the token without the token itself, and the event must be emitted
  /// right away (see the class documentation), so the event does not carry the ID token: call [getAccessToken]
  /// for it. After a sign-out the event holds an empty token, as the interface says.
  static const String changedTokenMarker = 'flutterfire-bridge:token-changed';

  /// How long [getAccessToken] and [waitForCurrentUser] wait for the plugin to report a user it already
  /// returns from `currentUser`.
  final Duration userChangeTimeout;

  final IdTokenUser? Function() _currentUser;

  /// Synchronous, like the stream of `FirebaseUserAuth`: Firestore hears about a new user in the call that
  /// changed [_user].
  final StreamController<AuthTokenChange> _tokenChanges =
      StreamController<AuthTokenChange>.broadcast(sync: true);
  final Completer<void> _firstEvent = Completer<void>();
  final List<Completer<void>> _userWaiters = <Completer<void>>[];
  late final StreamSubscription<IdTokenUser?> _subscription;

  /// The user Firestore works for: the one of the last event (or of [_currentUser] at construction).
  IdTokenUser? _user;
  bool _sawFirstEvent = false;
  bool _disposed = false;

  /// Counts the changes of the uid, so that a token fetched for a user that was replaced meanwhile is dropped.
  int _generation = 0;

  /// The id of the user Firestore works for, or null when nobody is signed in.
  ///
  /// It changes when the plugin reports a new user through `idTokenChanges()`, which can be a moment after
  /// `FirebaseAuth.currentUser` changed.
  @override
  String? get uid => _user?.uid;

  /// Emits after a sign-in, a sign-out (an empty token), a switch of users and a refresh of the token. The token
  /// of a signed-in user is [changedTokenMarker], not the ID token.
  @override
  Stream<AuthTokenChange> get onTokenChanged => _tokenChanges.stream;

  /// Completes when the plugin has reported its user once (the first event of `idTokenChanges()`). On the web the
  /// plugin restores a stored session only then.
  Future<void> get ready => _firstEvent.future;

  /// Returns the ID token of the user Firestore works for ([uid]), refreshed when [forceRefresh] is set.
  ///
  /// * Throws a [FirebaseNoSignedInUserException] when nobody is signed in: Firestore then sends the request without a
  ///   token.
  /// * When the plugin has another user than [uid] (its event is on its way), it waits for that event, up to
  ///   [userChangeTimeout], and answers for the user of the event. It throws a [TimeoutException] when the event
  ///   does not come.
  /// * When the user changes while the token is fetched, the token is dropped and the token of the new user is
  ///   returned.
  /// * Errors of the plugin (a `FirebaseAuthException`, for example `network-request-failed` or
  ///   `user-token-expired`) are passed on: Firestore fails the request with `unauthenticated`. The plugin signs
  ///   the user out by itself when the session ended, and the provider follows its event.
  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
    final IdTokenUser? user = _user;
    if (user == null) {
      throw FirebaseNoSignedInUserException('No user is signed in.');
    }
    if (_currentUser()?.uid != user.uid) {
      await _nextUserChange();
      return getAccessToken(forceRefresh: forceRefresh);
    }
    final int generation = _generation;
    final String? token = await user.getIdToken(forceRefresh: forceRefresh);
    if (generation != _generation) {
      // The user changed while the token was fetched: answer for the current user.
      return getAccessToken(forceRefresh: false);
    }
    if (_currentUser()?.uid != user.uid) {
      // The plugin switched users during the fetch, and the token may be of the new user.
      await _nextUserChange();
      return getAccessToken(forceRefresh: false);
    }
    if (token == null || token.isEmpty) {
      throw StateError('firebase_auth returned no ID token for the user.');
    }
    return GetTokenResult(token);
  }

  /// Completes when the provider works for the user that `FirebaseAuth.currentUser` returns now, and Firestore had
  /// a turn of the event loop to queue the switch. Call it after a sign-in or a sign-out when the next Firestore
  /// write must belong to the new user:
  ///
  /// ```dart
  /// await FirebaseAuth.instance.signInAnonymously();
  /// await provider.waitForCurrentUser();
  /// await firestore.doc('users/${provider.uid}').set(<String, Object?>{'seen': true});
  /// ```
  ///
  /// Throws a [TimeoutException] when the plugin does not report the user within [userChangeTimeout].
  Future<void> waitForCurrentUser() async {
    while (_currentUser()?.uid != uid) {
      await _nextUserChange();
    }
    await Future<void>.delayed(Duration.zero);
  }

  /// Stops listening to the plugin and closes [onTokenChanged]. Terminate the Firestore instances that use the
  /// provider first: they keep calling [getAccessToken], which keeps answering for the last user.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _subscription.cancel();
    for (final Completer<void> waiter in _userWaiters) {
      waiter.completeError(StateError('The provider was disposed.'));
    }
    _userWaiters.clear();
    await _tokenChanges.close();
  }

  void _onIdTokenChanged(IdTokenUser? user) {
    final String? previous = _user?.uid;
    final bool first = !_sawFirstEvent;
    _sawFirstEvent = true;
    if (!_firstEvent.isCompleted) {
      _firstEvent.complete();
    }
    if (user?.uid == previous) {
      _user = user;
      if (first || user == null) {
        // The replay of the current state when listening starts, or a sign-out while signed out.
        return;
      }
      // A refresh of the token of the same user.
      _emit(changedTokenMarker);
      return;
    }
    _user = user;
    _generation++;
    _emit(user == null ? '' : changedTokenMarker);
    final List<Completer<void>> waiters = List<Completer<void>>.of(
      _userWaiters,
    );
    _userWaiters.clear();
    for (final Completer<void> waiter in waiters) {
      waiter.complete();
    }
  }

  void _onSourceError(Object error, StackTrace stackTrace) {
    if (!_tokenChanges.isClosed) {
      _tokenChanges.addError(error, stackTrace);
    }
  }

  void _emit(String token) {
    if (!_tokenChanges.isClosed) {
      _tokenChanges.add(AuthTokenChange(token));
    }
  }

  Future<void> _nextUserChange() {
    if (_disposed) {
      throw StateError('The provider was disposed.');
    }
    final Completer<void> waiter = Completer<void>();
    _userWaiters.add(waiter);
    return waiter.future.timeout(
      userChangeTimeout,
      onTimeout: () {
        _userWaiters.remove(waiter);
        throw TimeoutException(
          'firebase_auth did not report its current user through idTokenChanges().',
          userChangeTimeout,
        );
      },
    );
  }
}

class _FlutterFireUser implements IdTokenUser {
  _FlutterFireUser(this._user);

  static IdTokenUser? wrap(flutterfire.User? user) =>
      user == null ? null : _FlutterFireUser(user);

  final flutterfire.User _user;

  @override
  String get uid => _user.uid;

  @override
  Future<String?> getIdToken({required bool forceRefresh}) =>
      _user.getIdToken(forceRefresh);
}

// The contract of AuthTokenProvider.onTokenChanged, as its documentation states
// it: an event is a signal. A consumer written to that contract works with a
// provider that emits the token and with one that emits a placeholder.

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

/// A provider with users. [emitToken] chooses what a signed-in event holds: the
/// token itself or a placeholder, both of which the contract allows.
class _Provider extends AuthTokenProvider {
  _Provider({required this.emitToken});

  final bool emitToken;
  final StreamController<AuthTokenChange> _changes =
      StreamController<AuthTokenChange>.broadcast(sync: true);
  String? _uid;
  int _generation = 0;

  void signIn(String uid) {
    _uid = uid;
    _generation++;
    _changes.add(AuthTokenChange(emitToken ? _token : 'placeholder'));
  }

  void signOut() {
    _uid = null;
    _changes.add(const AuthTokenChange(''));
  }

  String get _token => 'token-of-$_uid-$_generation';

  @override
  String? get uid => _uid;

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
    if (_uid == null) {
      throw FirebaseNoSignedInUserException('No user is signed in.');
    }
    return GetTokenResult(_token);
  }

  @override
  Stream<AuthTokenChange> get onTokenChanged => _changes.stream;
}

/// What a client does with the provider: on every event it reads the state
/// from the provider, never from the event (except "empty means signed out").
class _Consumer {
  _Consumer(this.provider) {
    provider.onTokenChanged.listen((AuthTokenChange change) {
      signedIn = change.token.isNotEmpty;
      users.add(provider.uid);
    });
  }

  final _Provider provider;
  final List<String?> users = <String?>[];
  bool signedIn = false;

  /// The token to send, or null for a request without one.
  Future<String?> tokenToSend() async {
    try {
      return (await provider.getAccessToken(forceRefresh: false)).token;
    } on FirebaseNoSignedInUserException {
      return null;
    }
  }
}

void main() {
  for (final bool emitToken in <bool>[true, false]) {
    final String kind = emitToken ? 'the token' : 'a placeholder';

    test('a consumer of the signal works when the event holds $kind', () async {
      final _Provider provider = _Provider(emitToken: emitToken);
      final _Consumer consumer = _Consumer(provider);

      provider.signIn('alice');
      expect(consumer.signedIn, isTrue);
      expect(await consumer.tokenToSend(), 'token-of-alice-1');

      provider.signIn('bob');
      expect(consumer.signedIn, isTrue);
      expect(await consumer.tokenToSend(), 'token-of-bob-2');

      provider.signOut();
      expect(consumer.signedIn, isFalse);
      expect(await consumer.tokenToSend(), isNull);

      // The provider answers for the new state before the listener runs.
      expect(consumer.users, <String?>['alice', 'bob', null]);
    });
  }

  test('only an empty token says signed out', () {
    expect(const AuthTokenChange('').token, isEmpty);
    expect(const AuthTokenChange('placeholder').token, isNotEmpty);
  });
}

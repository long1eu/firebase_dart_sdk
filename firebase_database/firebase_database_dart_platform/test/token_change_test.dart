// Sign-in, user switch and token refresh with a token provider whose change
// events hold a marker instead of the token, as FlutterFireAuthTokenProvider
// of cloud_firestore_dart_flutterfire does.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// The text of the change events of `FlutterFireAuthTokenProvider`.
const String marker = 'flutterfire-bridge:token-changed';

/// A JWT-shaped ID token of [user] (header, payload and signature, base64url
/// without padding); not signed.
String idTokenOf(String user) {
  String part(String text) =>
      base64Url.encode(utf8.encode(text)).replaceAll('=', '');
  return '${part('{"alg":"RS256","typ":"JWT"}')}.'
      '${part('{"user_id":"$user"}')}.${part('signature-of-$user')}';
}

/// Null (no user) or a JWT-shaped token: three non-empty base64url parts.
final Matcher noUserOrJwt = anyOf(
  isNull,
  matches(RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$')),
);

/// A user source whose change events hold [marker], never the token.
class MarkerUser extends dart_app.AuthTokenProvider {
  /// Nobody is signed in.
  MarkerUser();

  final StreamController<dart_app.AuthTokenChange> _changes =
      StreamController<dart_app.AuthTokenChange>.broadcast(sync: true);

  String? _token;

  /// Signs in with [token], switches to it, or refreshes to it; null signs
  /// out. Emits [marker], or an empty token for a sign-out.
  void change(String? token) {
    _token = token;
    _changes.add(dart_app.AuthTokenChange(token == null ? '' : marker));
  }

  @override
  Future<dart_app.GetTokenResult> getAccessToken({
    required bool forceRefresh,
  }) async {
    final String? token = _token;
    if (token == null) {
      throw dart_app.FirebaseNoSignedInUserException('No user is signed in.');
    }
    return dart_app.GetTokenResult(token);
  }

  @override
  String? get uid => _token == null ? null : 'user';

  @override
  Stream<dart_app.AuthTokenChange> get onTokenChanged => _changes.stream;
}

void main() {
  registerForTests();

  test('the change events of the installed provider carry the token, never '
      'the marker', () async {
    final FirebaseApp app = await newApp();
    final MarkerUser user = MarkerUser();
    providers[app.name] = user;
    final dart_app.AuthTokenProvider installed = FirebaseDatabaseDart.clientFor(
      app,
    ).app.authProvider;
    final List<String> events = <String>[];
    final StreamSubscription<dart_app.AuthTokenChange> subscription = installed
        .onTokenChanged
        .listen((dart_app.AuthTokenChange change) => events.add(change.token));
    addTearDown(subscription.cancel);

    for (final String? token in <String?>[
      idTokenOf('a'),
      idTokenOf('b'),
      '${idTokenOf('b')}2',
      null,
    ]) {
      user.change(token);
      await settle();
    }

    expect(events, <String>[
      idTokenOf('a'),
      idTokenOf('b'),
      '${idTokenOf('b')}2',
      '',
    ]);
  });

  test('sign-in, user switch, refresh and sign-out each send the real token '
      'or none, never a marker or another placeholder', () async {
    final FirebaseApp app = await newApp();
    final MarkerUser user = MarkerUser();
    providers[app.name] = user;
    await FirebaseDatabase.instanceFor(app: app).goOnline();
    await settle();
    final String refreshed = idTokenOf('b-refreshed');

    user.change(idTokenOf('a'));
    await settle();
    user.change(idTokenOf('b'));
    await settle();
    user.change(refreshed);
    await settle();
    user.change(null);
    await settle();

    expect(server.receivedAuthTokens, <String?>[
      null,
      idTokenOf('a'),
      idTokenOf('b'),
      refreshed,
      null,
    ]);
    expect(server.receivedAuthTokens, everyElement(noUserOrJwt));
    expect(server.receivedAuthTokens, isNot(contains(marker)));
    expect(server.connectionAttempts, 1, reason: 'no change drops it');
  });

  test('a provider failure after a change drops that event only', () async {
    final FirebaseApp app = await newApp();
    final FailingAfterChange user = FailingAfterChange();
    providers[app.name] = user;
    final List<String> events = <String>[];
    final StreamSubscription<dart_app.AuthTokenChange> subscription =
        FirebaseDatabaseDart.clientFor(
          app,
        ).app.authProvider.onTokenChanged.listen(
          (dart_app.AuthTokenChange change) => events.add(change.token),
        );
    addTearDown(subscription.cancel);

    user.emit(marker);
    await settle();
    user.emit('');
    await settle();

    expect(events, <String>['']);
  });
}

/// A provider whose token fetch fails with a network error.
class FailingAfterChange extends dart_app.AuthTokenProvider {
  final StreamController<dart_app.AuthTokenChange> _changes =
      StreamController<dart_app.AuthTokenChange>.broadcast(sync: true);

  /// Emits a change holding [token].
  void emit(String token) => _changes.add(dart_app.AuthTokenChange(token));

  @override
  Future<dart_app.GetTokenResult> getAccessToken({
    required bool forceRefresh,
  }) async => throw StateError('network-request-failed');

  @override
  String? get uid => 'user';

  @override
  Stream<dart_app.AuthTokenChange> get onTokenChanged => _changes.stream;
}

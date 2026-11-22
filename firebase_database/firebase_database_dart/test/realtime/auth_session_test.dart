// Owner K. AuthSession, ProviderTokenSource, authActionFor and isAdminCredential
// (rtdb_protocol.md 4.6 to 4.8, 8.1, 8.3; threat model T7, T14; test plan B-4.6, B-4.8, B-8.2d,
// B-8.3).
import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/src/realtime/auth_session.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:test/test.dart';

import '../util/fakes.dart';

/// An unsigned JWT with [claims], as the emulator accepts it (probe, "Notes for the tests").
String _jwt(Map<String, Object?> claims) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part(<String, Object?>{'alg': 'none', 'typ': 'JWT'})}.${part(claims)}.';
}

final String _idToken = _jwt(<String, Object?>{
  'sub': 'u1',
  'iat': 1,
  'exp': 9999999999,
});
final String _idToken2 = _jwt(<String, Object?>{
  'sub': 'u2',
  'iat': 2,
  'exp': 9999999999,
});

/// A session over a [RecordingSender] and a [FakeTokenSource], with the statuses it reports.
final class _Rig {
  _Rig({bool emulator = false}) {
    session = AuthSession(
      sender.send,
      tokens,
      invalidTokenThreshold: 3,
      protocol: RealtimeProtocol(isUsingEmulator: emulator),
      onAuthStatus: (String status, String? explanation) =>
          authStatuses.add((status, explanation)),
      onAppCheckStatus: (String status, String? explanation) =>
          appCheckStatuses.add((status, explanation)),
    );
    session.connectionMustClose.listen((_) => closes++);
  }

  final RecordingSender sender = RecordingSender();
  final FakeTokenSource tokens = FakeTokenSource();
  final List<(String, String?)> authStatuses = <(String, String?)>[];
  final List<(String, String?)> appCheckStatuses = <(String, String?)>[];
  late final AuthSession session;
  int closes = 0;

  /// Stores the tokens offline, as before an attempt, then connects.
  void connect({String? auth, String? appCheck}) {
    session.authChanged(auth);
    session.appCheckChanged(appCheck);
    session.onConnected();
  }
}

void main() {
  group('auth action (B-4.6a)', () {
    test('a JWT whose claims have iat is sent as auth', () {
      expect(authActionFor(_idToken), 'auth');
      expect(
        authActionFor(_jwt(<String, Object?>{'sub': 'u1', 'iat': 0})),
        'auth',
      );
    });

    test(
      'everything else is gauth: owner, opaque tokens, a JWT without iat',
      () {
        expect(authActionFor('owner'), 'gauth');
        expect(authActionFor('ya29.an-oauth-access-token'), 'gauth');
        expect(authActionFor(_jwt(<String, Object?>{'sub': 'u1'})), 'gauth');
        expect(authActionFor('a.b.c'), 'gauth');
        expect(
          authActionFor('${base64Url.encode(utf8.encode('[]'))}.e30.'),
          'gauth',
        );
        expect(authActionFor(''), 'gauth');
      },
    );

    test('standard base64 with padding is read as well', () {
      final String header = base64.encode(utf8.encode('{"alg":"none"}'));
      final String claims = base64.encode(utf8.encode('{"iat":1,"x":"??>"}'));
      expect(authActionFor('$header.$claims.sig'), 'auth');
    });
  });

  group('admin credential (B-8.2d)', () {
    test('a 40-character secret or a JWT with admin true', () {
      expect(isAdminCredential('a' * 40), isTrue);
      expect(
        isAdminCredential(_jwt(<String, Object?>{'iat': 1, 'admin': true})),
        isTrue,
      );
    });

    test('anything else is not', () {
      expect(isAdminCredential('a' * 39), isFalse);
      expect(
        isAdminCredential(_jwt(<String, Object?>{'iat': 1, 'admin': 'true'})),
        isFalse,
      );
      expect(isAdminCredential(_idToken), isFalse);
      expect(isAdminCredential('owner'), isFalse);
    });
  });

  group('sending credentials (B-8.3a, B-4.8)', () {
    test('on connect: auth then appcheck, without waiting', () {
      final _Rig rig = _Rig();
      rig.connect(auth: _idToken, appCheck: 'ac-1');
      expect(rig.sender.actions, <String>['auth', 'appcheck']);
      expect(rig.sender.sent[0].body, <String, Object?>{'cred': _idToken});
      expect(rig.sender.sent[1].body, <String, Object?>{'token': 'ac-1'});
    });

    test('owner goes as gauth', () {
      final _Rig rig = _Rig();
      rig.connect(auth: 'owner');
      expect(rig.sender.actions, <String>['gauth']);
    });

    test('nothing stored, nothing sent; empty tokens count as none', () {
      final _Rig rig = _Rig();
      rig.connect(auth: '', appCheck: '');
      expect(rig.sender.sent, isEmpty);
    });

    test('offline changes are only stored', () {
      final _Rig rig = _Rig();
      rig.session.authChanged(_idToken);
      rig.session.appCheckChanged('ac-1');
      rig.session.authChanged(null);
      expect(rig.sender.sent, isEmpty);
      rig.session.onConnected();
      expect(rig.sender.actions, <String>['appcheck']);
    });

    test('an ok answer reports ok', () {
      final _Rig rig = _Rig();
      rig.connect(auth: _idToken, appCheck: 'ac-1');
      rig.sender.respond(0, 'ok', <String, Object?>{'auth': null});
      rig.sender.respond(1, 'ok');
      expect(rig.authStatuses, <(String, String?)>[('ok', null)]);
      expect(rig.appCheckStatuses, <(String, String?)>[('ok', null)]);
    });
  });

  group('token changes while connected (B-8.3b, B-4.6b, B-4.8)', () {
    test('a new token is a new auth on the same connection', () async {
      final _Rig rig = _Rig();
      rig.connect(auth: _idToken);
      rig.session.authChanged(_idToken2);
      expect(rig.sender.actions, <String>['auth', 'auth']);
      expect(rig.sender.sent[1].body, <String, Object?>{'cred': _idToken2});
      rig.sender.respond(1, 'ok');
      await pumpEventQueue();
      expect(rig.closes, 0);
    });

    test('a sign-out sends unauth without a callback', () {
      final _Rig rig = _Rig();
      rig.connect(auth: _idToken);
      rig.session.authChanged(null);
      expect(rig.sender.actions, <String>['auth', 'unauth']);
      expect(rig.sender.sent[1].body, isEmpty);
      expect(rig.sender.sent[1].onResponse, isNull);
    });

    test(
      'App Check removal: unappeck in production, unappcheck on the emulator',
      () {
        final _Rig production = _Rig();
        production.connect(appCheck: 'ac-1');
        production.session.appCheckChanged(null);
        expect(production.sender.actions, <String>['appcheck', 'unappeck']);
        expect(production.sender.sent[1].onResponse, isNull);

        final _Rig emulator = _Rig(emulator: true);
        emulator.connect(appCheck: 'ac-1');
        emulator.session.appCheckChanged('');
        expect(emulator.sender.actions, <String>['appcheck', 'unappcheck']);
      },
    );

    test('a new App Check token is a new appcheck', () {
      final _Rig rig = _Rig();
      rig.connect();
      rig.session.appCheckChanged('ac-2');
      expect(rig.sender.actions, <String>['appcheck']);
      expect(rig.sender.sent.single.body, <String, Object?>{'token': 'ac-2'});
    });
  });

  group('stale replies (B-8.3a, PersistentConnection.ts:397)', () {
    test('the answer to a replaced token is ignored', () async {
      final _Rig rig = _Rig();
      rig.connect(auth: _idToken);
      rig.session.authChanged(_idToken2);
      rig.sender.respond(0, 'invalid_token', 'old token');
      await pumpEventQueue();
      expect(rig.authStatuses, isEmpty);
      expect(rig.closes, 0);
      expect(rig.session.forceRefreshNext, isFalse);
      rig.sender.respond(1, 'ok');
      expect(rig.authStatuses, <(String, String?)>[('ok', null)]);
    });

    test(
      'the answer from an earlier connection is ignored, same token',
      () async {
        final _Rig rig = _Rig();
        rig.connect(auth: _idToken);
        rig.session.onDisconnected();
        rig.session.onConnected();
        rig.sender.respond(0, 'invalid_token');
        await pumpEventQueue();
        expect(rig.authStatuses, isEmpty);
        expect(rig.closes, 0);
      },
    );

    test('an App Check answer to a replaced token is ignored', () {
      final _Rig rig = _Rig();
      rig.connect(appCheck: 'ac-1');
      rig.session.appCheckChanged('ac-2');
      rig.sender.respond(0, 'invalid_token');
      expect(rig.appCheckStatuses, isEmpty);
      expect(rig.tokens.invalid, isEmpty);
    });

    test('an answer after a disconnect is ignored', () {
      final _Rig rig = _Rig();
      rig.connect(auth: _idToken, appCheck: 'ac-1');
      rig.session.onDisconnected();
      rig.sender.respond(0, 'invalid_token');
      rig.sender.respond(1, 'invalid_token');
      expect(rig.authStatuses, isEmpty);
      expect(rig.appCheckStatuses, isEmpty);
      expect(rig.session.forceRefreshNext, isFalse);
    });
  });

  group('auth revoked (B-8.3c)', () {
    test('a non-ok auth answer closes and forces a refresh', () async {
      final _Rig rig = _Rig();
      rig.connect(auth: _idToken);
      rig.sender.respond(0, 'invalid_token', 'Could not parse auth token.');
      await pumpEventQueue();
      expect(rig.closes, 1);
      expect(rig.session.forceRefreshNext, isTrue);
      expect(rig.tokens.invalid, <TokenKind>[TokenKind.auth]);
      expect(rig.authStatuses, <(String, String?)>[
        ('invalid_token', 'Could not parse auth token.'),
      ]);
    });

    test(
      'the revoked token is forgotten: the next connection sends no auth',
      () {
        final _Rig rig = _Rig();
        rig.connect(auth: _idToken);
        rig.sender.respond(0, 'invalid_token');
        rig.session.onDisconnected();
        rig.session.onConnected();
        expect(rig.sender.actions, <String>['auth']);
        expect(rig.session.forceRefreshNext, isFalse);
      },
    );

    test('an ac push closes and forces a refresh', () async {
      final _Rig rig = _Rig();
      rig.connect(auth: _idToken);
      rig.session.onAuthRevoked('expired_token', 'expired');
      await pumpEventQueue();
      expect(rig.closes, 1);
      expect(rig.session.forceRefreshNext, isTrue);
      expect(rig.authStatuses.single, ('expired_token', 'expired'));
      expect(rig.session.invalidTokenThresholdReached, isFalse);
    });

    test(
      'three invalid_token or permission_denied failures reach the threshold',
      () {
        final _Rig rig = _Rig();
        for (final String status in <String>[
          'invalid_token',
          'permission_denied',
        ]) {
          rig.connect(auth: _idToken);
          rig.sender.respond(rig.sender.sent.length - 1, status);
          rig.session.onDisconnected();
          expect(rig.session.invalidTokenThresholdReached, isFalse);
        }
        rig.connect(auth: _idToken);
        rig.session.onAuthRevoked('invalid_token', '');
        expect(rig.session.invalidTokenThresholdReached, isTrue);
      },
    );

    test('other statuses do not count', () {
      final _Rig rig = _Rig();
      for (int i = 0; i < 5; i++) {
        rig.session.onAuthRevoked('expired_token', '');
      }
      expect(rig.session.invalidTokenThresholdReached, isFalse);
    });

    test('a successful auth resets the counter', () {
      final _Rig rig = _Rig();
      rig.session.onAuthRevoked('invalid_token', '');
      rig.session.onAuthRevoked('invalid_token', '');
      rig.connect(auth: _idToken);
      rig.sender.respond(0, 'ok');
      rig.session.onAuthRevoked('invalid_token', '');
      rig.session.onAuthRevoked('invalid_token', '');
      expect(rig.session.invalidTokenThresholdReached, isFalse);
      rig.session.onAuthRevoked('invalid_token', '');
      expect(rig.session.invalidTokenThresholdReached, isTrue);
    });

    test('a status that is not a string counts as a failure', () async {
      final _Rig rig = _Rig();
      rig.connect(auth: _idToken);
      rig.sender.sent[0].onResponse!(<String, Object?>{'s': 5});
      await pumpEventQueue();
      expect(rig.closes, 1);
      expect(rig.authStatuses.single.$1, 'failure');
    });
  });

  group('App Check revoked (B-8.3d)', () {
    test('a failed appcheck forces a refresh but does not close', () async {
      final _Rig rig = _Rig();
      rig.connect(auth: _idToken, appCheck: 'ac-1');
      rig.sender.respond(1, 'invalid_token', 'Could not parse token.');
      await pumpEventQueue();
      expect(rig.closes, 0);
      expect(rig.session.forceRefreshNext, isTrue);
      expect(rig.tokens.invalid, <TokenKind>[TokenKind.appCheck]);
      expect(rig.appCheckStatuses.single, (
        'invalid_token',
        'Could not parse token.',
      ));
      expect(rig.authStatuses, isEmpty);
    });

    test(
      'an apc push does not close; three reach the App Check threshold',
      () async {
        final _Rig rig = _Rig();
        rig.connect(appCheck: 'ac-1');
        for (int i = 0; i < 3; i++) {
          expect(rig.session.invalidAppCheckThresholdReached, isFalse);
          rig.session.onAppCheckRevoked('invalid_token', 'revoked');
        }
        await pumpEventQueue();
        expect(rig.closes, 0);
        expect(rig.session.invalidAppCheckThresholdReached, isTrue);
        expect(rig.session.invalidTokenThresholdReached, isFalse);
      },
    );

    test('the revoked App Check token is not sent on the next connection', () {
      final _Rig rig = _Rig();
      rig.connect(appCheck: 'ac-1');
      rig.session.onAppCheckRevoked('invalid_token', '');
      rig.session.onDisconnected();
      rig.session.onConnected();
      expect(rig.sender.actions, <String>['appcheck']);
    });

    test('an ok appcheck resets the App Check counter', () {
      final _Rig rig = _Rig();
      rig.session.onAppCheckRevoked('invalid_token', '');
      rig.session.onAppCheckRevoked('invalid_token', '');
      rig.connect(appCheck: 'ac-1');
      rig.sender.respond(0, 'ok');
      rig.session.onAppCheckRevoked('invalid_token', '');
      expect(rig.session.invalidAppCheckThresholdReached, isFalse);
    });
  });

  group('ProviderTokenSource (8.1, T14)', () {
    late DateTime now;
    setUp(() => now = DateTime.utc(2026, 11, 22));

    ProviderTokenSource source({
      AuthTokenProvider? auth,
      AppCheckTokenProvider? appCheck,
    }) => ProviderTokenSource(
      auth: auth,
      appCheck: appCheck,
      forcedRefreshMinInterval: const Duration(seconds: 60),
      now: () => now,
    );

    test('no providers: null tokens and empty change streams', () async {
      final ProviderTokenSource tokens = source();
      expect(await tokens.authToken(forceRefresh: false), isNull);
      expect(await tokens.appCheckToken(forceRefresh: true), isNull);
      expect(await tokens.authChanges.isEmpty, isTrue);
      expect(await tokens.appCheckChanges.isEmpty, isTrue);
    });

    test('nobody signed in and an empty token are null', () async {
      expect(
        await source(
          auth: FakeAuth(<String?>[null]),
        ).authToken(forceRefresh: false),
        isNull,
      );
      expect(
        await source(
          auth: FakeAuth(<String?>['']),
        ).authToken(forceRefresh: false),
        isNull,
      );
      expect(
        await source(
          appCheck: FakeAppCheck(''),
        ).appCheckToken(forceRefresh: false),
        isNull,
      );
    });

    test('an unavailable API is null', () async {
      final FakeAuth auth = FakeAuth(<String?>[
        't',
      ], error: const FirebaseApiNotAvailableException('no auth'));
      expect(await source(auth: auth).authToken(forceRefresh: false), isNull);
    });

    test('tokens are handed through with the forceRefresh asked for', () async {
      final FakeAuth auth = FakeAuth(<String?>[_idToken]);
      final FakeAppCheck appCheck = FakeAppCheck('ac-1');
      final ProviderTokenSource tokens = source(auth: auth, appCheck: appCheck);
      expect(await tokens.authToken(forceRefresh: false), _idToken);
      expect(await tokens.appCheckToken(forceRefresh: true), 'ac-1');
      expect(auth.calls, <bool>[false]);
      expect(appCheck.calls, <bool>[true]);
    });

    test(
      'an App Check result with an error still gives its placeholder',
      () async {
        final _ErrorAppCheck appCheck = _ErrorAppCheck();
        expect(
          await source(appCheck: appCheck).appCheckToken(forceRefresh: false),
          'placeholder',
        );
      },
    );

    test('at most one forced refresh per provider per 60 s', () async {
      final FakeAuth auth = FakeAuth(<String?>[_idToken]);
      final FakeAppCheck appCheck = FakeAppCheck('ac-1');
      final ProviderTokenSource tokens = source(auth: auth, appCheck: appCheck);
      await tokens.authToken(forceRefresh: true);
      await tokens.appCheckToken(forceRefresh: true);
      now = now.add(const Duration(seconds: 59));
      await tokens.authToken(forceRefresh: true);
      await tokens.appCheckToken(forceRefresh: true);
      now = now.add(const Duration(seconds: 1));
      await tokens.authToken(forceRefresh: true);
      expect(auth.calls, <bool>[true, false, true]);
      expect(appCheck.calls, <bool>[true, false]);
    });

    test(
      'a refused force is owed: the first fetch after the interval forces',
      () async {
        final FakeAuth auth = FakeAuth(<String?>[_idToken]);
        final ProviderTokenSource tokens = source(auth: auth);
        await tokens.authToken(forceRefresh: true);
        now = now.add(const Duration(seconds: 10));
        await tokens.authToken(forceRefresh: true);
        now = now.add(const Duration(seconds: 60));
        await tokens.authToken(forceRefresh: false);
        await tokens.authToken(forceRefresh: false);
        expect(auth.calls, <bool>[true, false, true, false]);
      },
    );

    test('notifyInvalid makes the next fetch of that kind force', () async {
      final FakeAuth auth = FakeAuth(<String?>[_idToken]);
      final FakeAppCheck appCheck = FakeAppCheck('ac-1');
      final ProviderTokenSource tokens = source(auth: auth, appCheck: appCheck);
      tokens.notifyInvalid(TokenKind.appCheck);
      await tokens.authToken(forceRefresh: false);
      await tokens.appCheckToken(forceRefresh: false);
      await tokens.appCheckToken(forceRefresh: false);
      expect(auth.calls, <bool>[false]);
      expect(appCheck.calls, <bool>[true, false]);
    });

    test('change streams map empty tokens to null', () async {
      final FakeAuth auth = FakeAuth(<String?>[_idToken]);
      final FakeAppCheck appCheck = FakeAppCheck('ac-1');
      final ProviderTokenSource tokens = source(auth: auth, appCheck: appCheck);
      final List<String?> authSeen = <String?>[];
      final List<String?> appCheckSeen = <String?>[];
      final StreamSubscription<String?> a = tokens.authChanges.listen(
        authSeen.add,
      );
      final StreamSubscription<String?> b = tokens.appCheckChanges.listen(
        appCheckSeen.add,
      );
      auth.emit(_idToken2);
      auth.emit('');
      appCheck.emit(const AppCheckTokenResult('ac-2'));
      appCheck.emit(const AppCheckTokenResult(''));
      await pumpEventQueue();
      await a.cancel();
      await b.cancel();
      expect(authSeen, <String?>[_idToken2, null]);
      expect(appCheckSeen, <String?>['ac-2', null]);
    });

    test('a fetch in flight completes when the provider answers', () async {
      final FakeAuth auth = FakeAuth(<String?>[_idToken])
        ..gate = Completer<void>();
      final Future<String?> token = source(
        auth: auth,
      ).authToken(forceRefresh: false);
      await pumpEventQueue();
      expect(auth.calls, <bool>[false]);
      auth.gate!.complete();
      expect(await token, _idToken);
    });
  });
}

/// An App Check provider whose result carries an error and a placeholder token.
final class _ErrorAppCheck extends AppCheckTokenProvider {
  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async =>
      AppCheckTokenResult('placeholder', error: StateError('attestation down'));

  @override
  Stream<AppCheckTokenResult> get onTokenChanged =>
      const Stream<AppCheckTokenResult>.empty();
}

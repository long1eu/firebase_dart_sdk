// Authenticator app (TOTP) multi-factor authentication against a fake Identity Toolkit backend that checks real
// RFC 6238 codes: enrolment, sign-in and reauthentication with the resolver, unenrolment, the factor list, SMS-only
// accounts, and both wire formats of the v2 calls (JSON, and protocol buffers with `$alt=proto`).

import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_auth_providers_dart/src/multi_factor_api.dart';
import 'package:firebase_auth_providers_dart/src/proto/google/cloud/identitytoolkit/v2/account_management_service.pb.dart'
    as v2;
import 'package:firebase_auth_providers_dart/src/proto/google/rpc/error_details.pb.dart'
    as rpc;
import 'package:firebase_auth_providers_dart/src/proto/google/rpc/status.pb.dart'
    as rpc;
import 'package:http/http.dart' as http;
import 'package:protobuf/well_known_types/google/protobuf/any.pb.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'harness.dart';
import 'totp.dart';

const String email = 'ada@example.com';
const String uid = 'uid-of-$email';
const String storageKey = 'firebase_auth_providers_dart:$apiKey';

/// The secret the fake backend hands out (base32 of "12345678901234567890", the key of RFC 6238's test vectors).
const String secretKey = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

http.Response protobufResponse(List<int> bytes, [int status = 200]) =>
    http.Response.bytes(
      bytes,
      status,
      headers: <String, String>{'content-type': 'application/x-protobuf'},
    );

/// A fake Identity Platform with TOTP: the v2 multi-factor methods in JSON and, for `mfaEnrollment:withdraw`, in
/// protocol buffers; a password sign-in of an account with factors answers with a pending credential.
class TotpBackend {
  TotpBackend() {
    backend.handler = (http.Request request) async {
      if (request.headers['content-type'] == 'application/x-protobuf') {
        return protobufHandler(request);
      }
      return backend.answer(request);
    };
    backend
      ..on('accounts:signInWithPassword', _signInWithPassword)
      ..on('mfaEnrollment:start', _start)
      ..on('mfaEnrollment:finalize', _finalize)
      ..on('mfaEnrollment:withdraw', (Map<String, Object?> body) {
        return _withdraw(
              body['idToken']! as String,
              body['mfaEnrollmentId']! as String,
            ) ??
            errorResponse('MFA_ENROLLMENT_NOT_FOUND');
      })
      ..on('mfaSignIn:finalize', _finalizeSignIn);
    protobufHandler = _protobufWithdraw;
  }

  final FakeBackend backend = FakeBackend();
  late Future<http.Response> Function(http.Request request) protobufHandler;
  int _enrolled = 0;

  /// The time the codes are computed for: the fake clock of the client.
  DateTime get now => backend.clock.now;

  String codeNow() => totpCode(base32Decode(secretKey), now);

  List<Object?> factorsOf(String user) =>
      (backend.accounts[user]?['mfaInfo'] as List<Object?>?) ??
      const <Object?>[];

  void addFactor(String user, Map<String, Object?> factor) {
    backend.accounts[user] = <String, Object?>{
      ...?backend.accounts[user],
      'mfaInfo': <Object?>[...factorsOf(user), factor],
    };
  }

  void _ensureAccount() => backend.accounts[uid] ??= <String, Object?>{
    'email': email,
    'emailVerified': true,
    'passwordHash': 'hash',
    'providerUserInfo': <Object?>[
      <String, Object?>{
        'providerId': 'password',
        'rawId': email,
        'email': email,
      },
    ],
  };

  http.Response _signInWithPassword(Map<String, Object?> body) {
    _ensureAccount();
    final List<Object?> factors = factorsOf(uid);
    if (factors.isEmpty) {
      return jsonResponse(<String, Object?>{
        'kind': 'identitytoolkit#VerifyPasswordResponse',
        'email': email,
        'registered': true,
        ...backend.tokensFor(uid, email: email),
      });
    }
    return jsonResponse(<String, Object?>{
      'kind': 'identitytoolkit#VerifyPasswordResponse',
      'localId': uid,
      'email': email,
      'registered': true,
      'mfaPendingCredential': 'pending:$uid',
      'mfaInfo': <Object?>[
        for (final Object? f in factors)
          <String, Object?>{
            ...f! as Map<String, Object?>,
            if ((f as Map<String, Object?>).containsKey('phoneInfo'))
              'phoneInfo': '+*******0100',
          },
      ],
    });
  }

  String _uidOf(Object? idToken) =>
      GetTokenResult(idToken! as String).claims['sub']! as String;

  http.Response _start(Map<String, Object?> body) {
    _uidOf(body['idToken']);
    return jsonResponse(<String, Object?>{
      'totpSessionInfo': <String, Object?>{
        'sharedSecretKey': secretKey,
        'verificationCodeLength': 6,
        'hashingAlgorithm': 'SHA1',
        'periodSec': 30,
        'sessionInfo': 'enrollment-session',
        'finalizeEnrollmentTime': '2026-01-01T12:10:00.123456789Z',
      },
    });
  }

  http.Response _finalize(Map<String, Object?> body) {
    final String user = _uidOf(body['idToken']);
    final Map<String, Object?> info =
        body['totpVerificationInfo']! as Map<String, Object?>;
    if (info['sessionInfo'] != 'enrollment-session') {
      return errorResponse('INVALID_SESSION_INFO');
    }
    if (info['verificationCode'] != codeNow()) {
      return errorResponse('INVALID_CODE');
    }
    addFactor(user, <String, Object?>{
      'mfaEnrollmentId': 'totp-${++_enrolled}',
      'displayName': ?body['displayName'],
      'totpInfo': <String, Object?>{},
      'enrolledAt': '2026-01-01T12:00:00Z',
    });
    return jsonResponse(<String, Object?>{
      'idToken': backend.tokensFor(user, email: email)['idToken'],
      'refreshToken': 'refresh:$user:enrolled',
    });
  }

  /// Withdraws [enrollmentId]; null when the account has no such factor.
  http.Response? _withdraw(String idToken, String enrollmentId) {
    final String user = _uidOf(idToken);
    final List<Object?> factors = factorsOf(user);
    final List<Object?> left = <Object?>[
      for (final Object? f in factors)
        if ((f! as Map<String, Object?>)['mfaEnrollmentId'] != enrollmentId) f,
    ];
    if (left.length == factors.length) {
      return null;
    }
    backend.accounts[user] = <String, Object?>{
      ...backend.accounts[user]!,
      'mfaInfo': left,
    };
    if (left.isEmpty) {
      backend.accounts[user]!.remove('mfaInfo');
    }
    return jsonResponse(<String, Object?>{
      'idToken': backend.tokensFor(user, email: email)['idToken'],
      'refreshToken': 'refresh:$user:withdrawn',
    });
  }

  Future<http.Response> _protobufWithdraw(http.Request request) async {
    final v2.WithdrawMfaRequest withdraw = v2.WithdrawMfaRequest.fromBuffer(
      request.bodyBytes,
    );
    final http.Response? json = _withdraw(
      withdraw.idToken,
      withdraw.mfaEnrollmentId,
    );
    if (json == null) {
      // What the owner saw from the real backend: a generic message; the code only in an ErrorInfo here.
      return protobufResponse(
        (rpc.Status()
              ..code = 3
              ..message = 'Request contains an invalid argument.'
              ..details.add(
                Any.pack(
                  rpc.ErrorInfo()
                    ..reason = 'MFA_ENROLLMENT_NOT_FOUND'
                    ..domain = 'identitytoolkit.googleapis.com',
                ),
              ))
            .writeToBuffer(),
        400,
      );
    }
    final Map<String, Object?> body =
        jsonDecode(json.body) as Map<String, Object?>;
    return protobufResponse(
      v2.WithdrawMfaResponse(
        idToken: body['idToken']! as String,
        refreshToken: body['refreshToken']! as String,
      ).writeToBuffer(),
    );
  }

  http.Response _finalizeSignIn(Map<String, Object?> body) {
    final Object? pending = body['mfaPendingCredential'];
    if (pending is! String || !pending.startsWith('pending:')) {
      return errorResponse('INVALID_MFA_PENDING_CREDENTIAL');
    }
    final String user = pending.substring('pending:'.length);
    final bool known = factorsOf(user).any(
      (Object? f) =>
          (f! as Map<String, Object?>)['mfaEnrollmentId'] ==
          body['mfaEnrollmentId'],
    );
    if (!known) {
      return errorResponse('MFA_ENROLLMENT_NOT_FOUND');
    }
    final Map<String, Object?> info =
        body['totpVerificationInfo']! as Map<String, Object?>;
    if (info['verificationCode'] != codeNow()) {
      return errorResponse('INVALID_CODE');
    }
    return jsonResponse(<String, Object?>{
      'idToken': backend.tokensFor(user, email: email)['idToken'],
      'refreshToken': 'refresh:$user:second-factor',
    });
  }
}

void main() {
  late TotpBackend server;
  late FakeBackend backend;
  late FirebaseUserAuth auth;

  setUp(() {
    server = TotpBackend();
    backend = server.backend;
    auth = backend.create();
  });

  tearDown(() => auth.dispose());

  Future<void> signIn() =>
      auth.signInWithEmailAndPassword(email: email, password: 'secret');

  Future<void> enroll({String? displayName = 'Phone'}) async {
    final TotpSecret secret = await auth.startTotpEnrollment();
    await auth.finalizeTotpEnrollment(
      secret,
      code: server.codeNow(),
      displayName: displayName,
    );
  }

  Future<FirebaseAuthMultiFactorException> secondFactorRequired(
    Future<Object?> operation,
  ) async {
    try {
      await operation;
    } on FirebaseAuthMultiFactorException catch (e) {
      return e;
    }
    fail('No FirebaseAuthMultiFactorException');
  }

  group('the RFC 6238 generator of the tests', () {
    test('matches the SHA1 test vectors of RFC 6238', () {
      final List<int> key = base32Decode(secretKey);
      expect(String.fromCharCodes(key), '12345678901234567890');
      expect(base32Encode(key), secretKey);
      for (final (int seconds, String code) in <(int, String)>[
        (59, '94287082'),
        (1111111109, '07081804'),
        (1234567890, '89005924'),
        (20000000000, '65353130'),
      ]) {
        expect(
          totpCode(
            key,
            DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
            digits: 8,
          ),
          code,
        );
      }
    });
  });

  group('enrolment', () {
    test('start returns the secret with its parameters', () async {
      await signIn();
      final TotpSecret secret = await auth.startTotpEnrollment();
      expect(secret.secretKey, secretKey);
      expect(secret.hashingAlgorithm, 'SHA1');
      expect(secret.codeLength, 6);
      expect(secret.codeIntervalSeconds, 30);
      // Nine fractional digits, kept to the microsecond.
      expect(
        secret.enrollmentCompletionDeadline,
        DateTime.utc(2026, 1, 1, 12, 10, 0, 123, 456),
      );
      expect('$secret', isNot(contains(secretKey)));
      final Map<String, Object?> body = backend
          .bodiesOf('mfaEnrollment:start')
          .single;
      expect(
        body.keys,
        unorderedEquals(<String>['idToken', 'totpEnrollmentInfo']),
      );
      expect(body['totpEnrollmentInfo'], <String, Object?>{});
      final http.Request request = backend.requests.lastWhere(
        (http.Request r) => r.url.path.endsWith('mfaEnrollment:start'),
      );
      expect(
        request.url.toString(),
        startsWith(
          'https://identitytoolkit.googleapis.com/v2/accounts/mfaEnrollment:start?',
        ),
      );
      expect(
        request.headers['X-Client-Version'],
        FirebaseUserAuth.clientVersion,
      );
    });

    test('the otpauth URI', () async {
      await signIn();
      final TotpSecret secret = await auth.startTotpEnrollment();
      expect(
        '${secret.otpauthUri(issuer: 'Example')}',
        'otpauth://totp/Example:ada@example.com?secret=$secretKey&issuer=Example&algorithm=SHA1&digits=6',
      );
      expect(
        '${secret.otpauthUri(issuer: 'My App', accountName: 'Ada L')}',
        'otpauth://totp/My%20App:Ada%20L?secret=$secretKey&issuer=My%20App&algorithm=SHA1&digits=6',
      );
      final TotpSecret bare = TotpSecret.fromResponse(<String, Object?>{
        'sharedSecretKey': 'ABC',
        'periodSec': 60,
      })!;
      expect(bare.hashingAlgorithm, isNull);
      expect(bare.codeLength, 0);
      expect(bare.enrollmentCompletionDeadline, isNull);
      expect(
        '${bare.otpauthUri(issuer: 'X')}',
        'otpauth://totp/X:unknownuser?secret=ABC&issuer=X&period=60',
      );
      expect(TotpSecret.fromResponse(<String, Object?>{}), isNull);
      expect(TotpSecret.fromResponse('x'), isNull);
    });

    test(
      'finalize enrols the factor, renews the tokens and stores the factor',
      () async {
        await signIn();
        final List<AuthUser?> users = <AuthUser?>[];
        final List<String> tokens = <String>[];
        final StreamSubscription<AuthUser?> userSub = auth.userChanges().listen(
          users.add,
        );
        final StreamSubscription<AuthTokenChange> tokenSub = auth.onTokenChanged
            .listen((AuthTokenChange c) => tokens.add(c.token));
        await enroll();
        await pump();
        await userSub.cancel();
        await tokenSub.cancel();

        final MultiFactorInfo factor = auth.currentUser!.enrolledFactors.single;
        expect(factor.factorId, MultiFactorInfo.totpFactorId);
        expect(factor.uid, 'totp-1');
        expect(factor.displayName, 'Phone');
        expect(factor.enrollmentTime, DateTime.utc(2026, 1, 1, 12));
        expect(users.last?.enrolledFactors, <MultiFactorInfo>[factor]);
        expect(tokens, isNotEmpty);
        expect(
          (await auth.getAccessToken(forceRefresh: false)).token,
          tokens.last,
        );

        final Map<String, Object?> body = backend
            .bodiesOf('mfaEnrollment:finalize')
            .single;
        expect(body['displayName'], 'Phone');
        expect(body['totpVerificationInfo'], <String, Object?>{
          'sessionInfo': 'enrollment-session',
          'verificationCode': server.codeNow(),
        });
        expect(body.containsKey('tenantId'), isFalse);

        // The new refresh token and the factor are stored, and read back by a new instance.
        final Map<String, Object?> stored =
            jsonDecode(backend.storage.read(storageKey)!)
                as Map<String, Object?>;
        expect(stored['refreshToken'], 'refresh:$uid:enrolled');
        final FirebaseUserAuth restored = backend.create();
        await restored.restore();
        expect(restored.currentUser!.enrolledFactors, <MultiFactorInfo>[
          factor,
        ]);
        await restored.dispose();
      },
    );

    test('a wrong code is refused and nothing changes', () async {
      await signIn();
      final TotpSecret secret = await auth.startTotpEnrollment();
      await expectLater(
        auth.finalizeTotpEnrollment(secret, code: '000000'),
        throwsAuth('invalid-verification-code'),
      );
      expect(auth.currentUser!.enrolledFactors, isEmpty);
      expect(auth.uid, uid);
    });

    test('needs a signed-in user', () async {
      await expectLater(auth.startTotpEnrollment(), throwsAuth('null-user'));
      await expectLater(
        auth.unenrollMultiFactor('totp-1'),
        throwsAuth('null-user'),
      );
    });

    test('an answer without a secret is an internal-error', () async {
      await signIn();
      backend.on(
        'mfaEnrollment:start',
        (Map<String, Object?> body) => jsonResponse(<String, Object?>{
          'phoneSessionInfo': <String, Object?>{},
        }),
      );
      await expectLater(
        auth.startTotpEnrollment(),
        throwsAuth('internal-error'),
      );
    });

    test('the tenant goes into every request', () async {
      auth.tenantId = 'tenant-1';
      backend.accounts[uid] = <String, Object?>{'tenantId': 'tenant-1'};
      await signIn();
      await enroll();
      await auth.unenrollMultiFactor('totp-1');
      for (final String method in <String>[
        'mfaEnrollment:start',
        'mfaEnrollment:finalize',
      ]) {
        expect(backend.bodiesOf(method).single['tenantId'], 'tenant-1');
      }
      final http.Request withdraw = backend.requests.lastWhere(
        (http.Request r) => r.url.path.endsWith('mfaEnrollment:withdraw'),
      );
      expect(
        v2.WithdrawMfaRequest.fromBuffer(withdraw.bodyBytes).tenantId,
        'tenant-1',
      );
    });
  });

  group('sign-in with a second factor', () {
    setUp(() async {
      await signIn();
      await enroll();
      await auth.signOut();
      backend.requests.clear();
    });

    test('the exception carries the hints and a resolver', () async {
      final FirebaseAuthMultiFactorException e = await secondFactorRequired(
        signIn(),
      );
      expect(e.code, 'multi-factor-auth-required');
      expect(e.message, FirebaseAuthMultiFactorException.defaultMessage);
      expect(e.pendingCredential, 'pending:$uid');
      expect(e.hints.single.factorId, MultiFactorInfo.totpFactorId);
      expect(e.resolver, isNotNull);
      expect(e.resolver!.hints, e.hints);
      expect('$e', isNot(contains('pending:')));
      expect(auth.uid, isNull);
    });

    test('the resolver signs in with a code of the app', () async {
      final List<AuthUser?> states = <AuthUser?>[];
      final StreamSubscription<AuthUser?> sub = auth.authStateChanges().listen(
        states.add,
      );
      await pump();
      final FirebaseAuthMultiFactorException e = await secondFactorRequired(
        signIn(),
      );
      final UserCredential result = await e.resolver!.resolveSignInWithTotp(
        server.codeNow(),
      );
      await sub.cancel();

      expect(result.user?.uid, uid);
      expect(auth.uid, uid);
      expect(result.user?.enrolledFactors.single.uid, 'totp-1');
      // The first factor's answer gives the additional information.
      expect(result.additionalUserInfo?.providerId, 'password');
      expect(states, <Object?>[isNull, isA<AuthUser>()]);
      expect(
        jsonDecode(backend.storage.read(storageKey)!)['refreshToken'],
        'refresh:$uid:second-factor',
      );
      final Map<String, Object?> body = backend
          .bodiesOf('mfaSignIn:finalize')
          .single;
      expect(body, <String, Object?>{
        'mfaPendingCredential': 'pending:$uid',
        'mfaEnrollmentId': 'totp-1',
        'totpVerificationInfo': <String, Object?>{
          'verificationCode': server.codeNow(),
        },
      });
    });

    test('a wrong code is refused and nobody is signed in', () async {
      final FirebaseAuthMultiFactorException e = await secondFactorRequired(
        signIn(),
      );
      await expectLater(
        e.resolver!.resolveSignInWithTotp('000000'),
        throwsAuth('invalid-verification-code'),
      );
      expect(auth.uid, isNull);
      // The pending sign-in can still be finished.
      await e.resolver!.resolveSignInWithTotp(server.codeNow());
      expect(auth.uid, uid);
    });

    test('an expired pending credential', () async {
      final FirebaseAuthMultiFactorException e = await secondFactorRequired(
        signIn(),
      );
      backend.on(
        'mfaSignIn:finalize',
        (Map<String, Object?> body) =>
            errorResponse('INVALID_MFA_PENDING_CREDENTIAL'),
      );
      await expectLater(
        e.resolver!.resolveSignInWithTotp(server.codeNow()),
        throwsAuth('invalid-multi-factor-session'),
      );
    });

    test('an enrollmentId picks the factor', () async {
      final FirebaseAuthMultiFactorException e = await secondFactorRequired(
        signIn(),
      );
      await e.resolver!.resolveSignInWithTotp(
        server.codeNow(),
        enrollmentId: 'totp-1',
      );
      expect(auth.uid, uid);
    });

    test('a sign-in started meanwhile overtakes the resolution', () async {
      final FirebaseAuthMultiFactorException e = await secondFactorRequired(
        signIn(),
      );
      final Future<UserCredential> resolving = e.resolver!
          .resolveSignInWithTotp(server.codeNow());
      final Future<UserCredential> anonymous = auth.signInAnonymously();
      await expectLater(resolving, throwsAuth('cancelled'));
      await anonymous;
      expect(auth.uid, 'anon-user');
    });

    test('reauthentication with the resolver keeps the user', () async {
      final FirebaseAuthMultiFactorException first = await secondFactorRequired(
        signIn(),
      );
      await first.resolver!.resolveSignInWithTotp(server.codeNow());
      final String before = (await auth.getAccessToken(
        forceRefresh: false,
      )).token;

      final FirebaseAuthMultiFactorException e = await secondFactorRequired(
        auth.reauthenticateWithEmailAndPassword(
          email: email,
          password: 'secret',
        ),
      );
      expect(auth.uid, uid);
      final UserCredential result = await e.resolver!.resolveSignInWithTotp(
        server.codeNow(),
      );
      expect(result.user?.uid, uid);
      expect(
        (await auth.getAccessToken(forceRefresh: false)).token,
        isNot(before),
      );
    });

    test('reauthentication refuses the tokens of another account', () async {
      final FirebaseAuthMultiFactorException first = await secondFactorRequired(
        signIn(),
      );
      await first.resolver!.resolveSignInWithTotp(server.codeNow());
      final FirebaseAuthMultiFactorException e = await secondFactorRequired(
        auth.reauthenticateWithEmailAndPassword(
          email: email,
          password: 'secret',
        ),
      );
      backend.on(
        'mfaSignIn:finalize',
        (Map<String, Object?> body) => jsonResponse(<String, Object?>{
          'idToken': backend.tokensFor('someone-else')['idToken'],
          'refreshToken': 'refresh:someone-else',
        }),
      );
      await expectLater(
        e.resolver!.resolveSignInWithTotp(server.codeNow()),
        throwsAuth('user-mismatch'),
      );
      expect(auth.uid, uid);
    });
  });

  group('SMS second factors', () {
    setUp(() {
      backend.accounts[uid] = <String, Object?>{
        'email': email,
        'phoneNumber': '+15555550100',
      };
      server.addFactor(uid, <String, Object?>{
        'mfaEnrollmentId': 'phone-1',
        'phoneInfo': '+15555550100',
        'enrolledAt': '2026-01-01T12:00:00.5Z',
      });
    });

    test('an SMS-only account says it cannot be finished here', () async {
      final FirebaseAuthMultiFactorException e = await secondFactorRequired(
        signIn(),
      );
      expect(e.code, 'multi-factor-auth-required');
      expect(
        e.message,
        FirebaseAuthMultiFactorException.unsupportedFactorsMessage,
      );
      expect(e.hints.single.phoneNumber, '+*******0100');
      final int sent = backend.requests.length;
      await expectLater(
        e.resolver!.resolveSignInWithTotp('123456'),
        throwsA(
          isA<FirebaseAuthException>()
              .having(
                (FirebaseAuthException e) => e.code,
                'code',
                'multi-factor-info-not-found',
              )
              .having(
                (FirebaseAuthException e) => e.message,
                'message',
                contains('SMS'),
              ),
        ),
      );
      await expectLater(
        e.resolver!.resolveSignInWithTotp('123456', enrollmentId: 'phone-1'),
        throwsAuth('multi-factor-info-not-found'),
      );
      expect(backend.requests.length, sent);
    });

    test('an account with SMS and TOTP can be finished with TOTP', () async {
      server.addFactor(uid, <String, Object?>{
        'mfaEnrollmentId': 'totp-9',
        'totpInfo': <String, Object?>{},
      });
      final FirebaseAuthMultiFactorException e = await secondFactorRequired(
        signIn(),
      );
      expect(e.message, FirebaseAuthMultiFactorException.defaultMessage);
      await e.resolver!.resolveSignInWithTotp(server.codeNow());
      expect(auth.uid, uid);
      expect(
        auth.currentUser!.enrolledFactors.map(
          (MultiFactorInfo f) => f.factorId,
        ),
        <String>[MultiFactorInfo.phoneFactorId, MultiFactorInfo.totpFactorId],
      );
      // The user's own record has the full number.
      expect(
        auth.currentUser!.enrolledFactors.first.phoneNumber,
        '+15555550100',
      );
    });

    test('a link that needs a second factor has no resolver', () async {
      await auth.signInAnonymously();
      backend.on(
        'accounts:signUp',
        (Map<String, Object?> body) => jsonResponse(<String, Object?>{
          'mfaPendingCredential': 'pending:$uid',
          'mfaInfo': server.factorsOf(uid),
        }),
      );
      final FirebaseAuthMultiFactorException e = await secondFactorRequired(
        auth.linkWithCredential(
          EmailAuthProvider.credential(email: email, password: 'secret'),
        ),
      );
      expect(e.resolver, isNull);
    });
  });

  for (final MultiFactorWireFormat format in MultiFactorWireFormat.values) {
    group('unenrolment over ${format.name}', () {
      setUp(() async {
        auth.multiFactorWireFormat = format;
        await signIn();
        await enroll();
        backend.requests.clear();
      });

      test('removes the factor and renews the tokens', () async {
        final List<AuthUser?> users = <AuthUser?>[];
        final StreamSubscription<AuthUser?> sub = auth.userChanges().listen(
          users.add,
        );
        await auth.unenrollMultiFactor('totp-1');
        await pump();
        await sub.cancel();
        expect(auth.currentUser!.enrolledFactors, isEmpty);
        expect(users.last?.enrolledFactors, isEmpty);
        expect(
          jsonDecode(backend.storage.read(storageKey)!)['refreshToken'],
          'refresh:$uid:withdrawn',
        );
        final http.Request request = backend.requests.firstWhere(
          (http.Request r) => r.url.path.endsWith('mfaEnrollment:withdraw'),
        );
        expect(request.url.path, '/v2/accounts/mfaEnrollment:withdraw');
        if (format == MultiFactorWireFormat.protobuf) {
          expect(request.headers['content-type'], 'application/x-protobuf');
          expect(request.url.toString(), contains(r'&$alt=proto'));
          expect(request.url.queryParameters['key'], apiKey);
          final v2.WithdrawMfaRequest sent = v2.WithdrawMfaRequest.fromBuffer(
            request.bodyBytes,
          );
          expect(sent.mfaEnrollmentId, 'totp-1');
          expect(sent.idToken, isNotEmpty);
          expect(sent.hasTenantId(), isFalse);
        } else {
          expect(
            (jsonDecode(request.body)
                as Map<String, Object?>)['mfaEnrollmentId'],
            'totp-1',
          );
        }
        // Signing in again needs no second factor.
        await auth.signOut();
        await signIn();
        expect(auth.uid, uid);
      });

      test('an unknown factor is multi-factor-info-not-found', () async {
        await expectLater(
          auth.unenrollMultiFactor('nope'),
          throwsAuth('multi-factor-info-not-found'),
        );
        expect(auth.currentUser!.enrolledFactors, hasLength(1));
      });

      test('the language goes as X-Firebase-Locale', () async {
        auth.languageCode = 'fr';
        await auth.unenrollMultiFactor('totp-1');
        expect(
          backend.requests
              .firstWhere(
                (http.Request r) =>
                    r.url.path.endsWith('mfaEnrollment:withdraw'),
              )
              .headers['X-Firebase-Locale'],
          'fr',
        );
      });
    });
  }

  group('protocol buffer errors', () {
    setUp(() async {
      auth.multiFactorWireFormat = MultiFactorWireFormat.protobuf;
      await signIn();
    });

    Future<FirebaseAuthException> errorOf(http.Response response) async {
      server.protobufHandler = (http.Request request) async => response;
      try {
        await auth.unenrollMultiFactor('totp-1');
      } on FirebaseAuthException catch (e) {
        return e;
      }
      fail('No error');
    }

    List<int> status(
      int code,
      String message, [
      List<GeneratedMessageForAny> details = const <GeneratedMessageForAny>[],
    ]) {
      final rpc.Status status = rpc.Status()
        ..code = code
        ..message = message;
      for (final GeneratedMessageForAny detail in details) {
        status.details.add(Any.pack(detail.message));
      }
      return status.writeToBuffer();
    }

    test('a generic status keeps its canonical code and message', () async {
      final FirebaseAuthException e = await errorOf(
        protobufResponse(
          status(3, 'Request contains an invalid argument.'),
          400,
        ),
      );
      expect(e.code, 'invalid-argument');
      expect(e.serverCode, 'INVALID_ARGUMENT');
      expect(e.message, 'Request contains an invalid argument.');
      expect(e.httpStatus, 400);
      expect(auth.uid, uid);
    });

    test('a server code in the message is mapped', () async {
      final FirebaseAuthException e = await errorOf(
        protobufResponse(status(16, 'TOKEN_EXPIRED'), 400),
      );
      expect(e.code, 'user-token-expired');
      // Like the JSON form: the session ended, the user is signed out.
      expect(auth.uid, isNull);
    });

    test('a server code in the details is mapped', () async {
      for (final (GeneratedMessageForAny detail, String code)
          in <(GeneratedMessageForAny, String)>[
            (
              GeneratedMessageForAny(
                rpc.ErrorInfo()..reason = 'INVALID_ID_TOKEN',
              ),
              'invalid-user-token',
            ),
            (
              GeneratedMessageForAny(
                rpc.LocalizedMessage()..message = 'MFA_ENROLLMENT_NOT_FOUND',
              ),
              'multi-factor-info-not-found',
            ),
            (
              GeneratedMessageForAny(
                rpc.DebugInfo()..detail = 'CREDENTIAL_TOO_OLD_LOGIN_AGAIN',
              ),
              'requires-recent-login',
            ),
            (
              GeneratedMessageForAny(
                rpc.BadRequest()
                  ..fieldViolations.add(
                    rpc.BadRequest_FieldViolation()
                      ..field_1 = 'mfa_enrollment_id'
                      ..description = 'MISSING_MFA_ENROLLMENT_ID',
                  ),
              ),
              'missing-multi-factor-info',
            ),
            (
              GeneratedMessageForAny(
                rpc.ErrorInfo()
                  ..reason = 'API_KEY_INVALID'
                  ..domain = 'googleapis.com',
              ),
              'invalid-api-key',
            ),
          ]) {
        final FirebaseAuthException e = await errorOf(
          protobufResponse(
            status(
              3,
              'Request contains an invalid argument.',
              <GeneratedMessageForAny>[detail],
            ),
            400,
          ),
        );
        expect(e.code, code, reason: '${detail.message}');
      }
    });

    test('a body that is not a status is an internal-error', () async {
      final FirebaseAuthException e = await errorOf(
        protobufResponse(<int>[0xff, 0xff, 0xff], 500),
      );
      expect(e.code, 'internal-error');
      expect(e.httpStatus, 500);
    });

    test('a JSON answer to a protobuf request is read as JSON', () async {
      final FirebaseAuthException e = await errorOf(
        errorResponse('MFA_ENROLLMENT_NOT_FOUND'),
      );
      expect(e.code, 'multi-factor-info-not-found');
    });

    test('a malformed success is an internal-error', () async {
      final FirebaseAuthException e = await errorOf(
        protobufResponse(<int>[0xff, 0xff, 0xff]),
      );
      expect(e.code, 'internal-error');
    });

    test('a network error', () async {
      server.protobufHandler = (http.Request request) async =>
          throw http.ClientException('offline', request.url);
      await expectLater(
        auth.unenrollMultiFactor('totp-1'),
        throwsAuth('network-request-failed'),
      );
    });
  });

  test('the emulator uses JSON', () {
    final FirebaseUserAuth emulated = backend.create(
      emulatorHost: '127.0.0.1:9099',
    );
    expect(emulated.multiFactorWireFormat, MultiFactorWireFormat.json);
    expect(auth.multiFactorWireFormat, MultiFactorWireFormat.protobuf);
    unawaited(emulated.dispose());
  });

  test('MultiFactorInfo reads RFC 3339 timestamps strictly', () {
    MultiFactorInfo? read(Object? enrolledAt) =>
        MultiFactorInfo.fromResponse(<String, Object?>{
          'mfaEnrollmentId': 'e',
          'totpInfo': <String, Object?>{},
          'enrolledAt': enrolledAt,
        });
    final DateTime base = DateTime.utc(2026, 11, 9, 14, 40);
    expect(read('2026-11-09T14:40:00Z')!.enrollmentTime, base);
    expect(
      read('2026-11-09T14:40:00.123Z')!.enrollmentTime,
      base.add(const Duration(milliseconds: 123)),
    );
    expect(
      read('2026-11-09T14:40:00.123456789Z')!.enrollmentTime,
      base.add(const Duration(microseconds: 123456)),
    );
    expect(read('2026-11-09T16:40:00+02:00')!.enrollmentTime, base);
    for (final Object? invalid in <Object?>[
      '',
      'not a date',
      '2026-11-09',
      '2026-11-09T14:40:00',
      null,
    ]) {
      expect(read(invalid)!.enrollmentTime, isNull, reason: '$invalid');
      expect(read(invalid)!.uid, 'e');
    }
  });
}

/// A message to pack into an `Any`, for the table of details.
class GeneratedMessageForAny {
  GeneratedMessageForAny(this.message);

  final dynamic message;
}

import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    as dart_auth;

import 'convert.dart';
import 'firebase_auth.dart';

// Multi-factor authentication with an authenticator app (TOTP) or SMS, on top
// of the client's startTotpEnrollment, finalizeTotpEnrollment,
// startPhoneEnrollment, finalizePhoneEnrollment, unenrollMultiFactor and its
// MultiFactorResolver. The SMS codes are sent by
// DartFirebaseAuth.verifyPhoneNumber with one of the sessions here.

/// The multi-factor API of the user [uid]. Each member throws
/// `no-current-user` once another user (or nobody) is signed in.
class DartMultiFactor extends MultiFactorPlatform {
  DartMultiFactor(DartFirebaseAuth super.auth, this.uid) : _auth = auth;

  final DartFirebaseAuth _auth;

  /// The user whose factors these are.
  final String uid;

  dart_auth.FirebaseUserAuth get _client => _auth.clientFor(uid);

  /// A session for enrolling a factor of this user: pass it to
  /// `TotpMultiFactorGenerator.generateSecret`, or to
  /// `FirebaseAuth.verifyPhoneNumber` with the number of an SMS factor.
  /// Nothing is sent: the backend session starts with either of those.
  @override
  Future<MultiFactorSession> getSession() => guard(_auth, () async {
    _client;
    return DartMultiFactorSession(this);
  });

  /// Finishes the enrolment of a TOTP assertion of
  /// `TotpMultiFactorGenerator.getAssertionForEnrollment`, or of an SMS
  /// assertion of `PhoneMultiFactorGenerator.getAssertion` (the verification
  /// id that `verifyPhoneNumber` passed to `codeSent` with the session of
  /// [getSession], and the code of the SMS). [displayName] is required for a
  /// TOTP factor: the backend refuses one without it.
  @override
  Future<void> enroll(
    MultiFactorAssertionPlatform assertion, {
    String? displayName,
  }) => guard(_auth, () async {
    if (assertion is DartPhoneAssertion) {
      await _client.finalizePhoneEnrollment(
        assertion.credential,
        displayName: displayName,
      );
      return;
    }
    if (assertion is! DartTotpEnrollmentAssertion) {
      throw _wrongAssertion(
        assertion,
        'enroll takes an assertion of '
        'TotpMultiFactorGenerator.getAssertionForEnrollment or '
        'PhoneMultiFactorGenerator.getAssertion',
      );
    }
    if (displayName == null || displayName.isEmpty) {
      throw FirebaseAuthException(
        code: 'argument-error',
        message: 'Enrolling a TOTP second factor needs a displayName.',
      );
    }
    await _client.finalizeTotpEnrollment(
      assertion.secret,
      code: assertion.oneTimePassword,
      displayName: displayName,
    );
  });

  /// Removes the factor [factorUid], or that of [multiFactorInfo]; SMS
  /// factors too.
  @override
  Future<void> unenroll({
    String? factorUid,
    MultiFactorInfo? multiFactorInfo,
  }) => guard(_auth, () async {
    final String? id = factorUid ?? multiFactorInfo?.uid;
    if (id == null) {
      throw FirebaseAuthException(
        code: 'argument-error',
        message: 'unenroll needs a factorUid or a multiFactorInfo.',
      );
    }
    await _client.unenrollMultiFactor(id);
  });

  /// The factors of the signed-in user as the client has them now, so a
  /// factor enrolled or removed through any `User` object is reflected.
  @override
  Future<List<MultiFactorInfo>> getEnrolledFactors() => guard(_auth, () async {
    return <MultiFactorInfo>[
      for (final dart_auth.MultiFactorInfo info
          in _client.currentUser!.enrolledFactors)
        multiFactorInfoOf(info),
    ];
  });

  /// Sends the SMS code of an enrolment of [phoneNumber] for this user and
  /// returns the verification id (`verifyPhoneNumber` with the session of
  /// [getSession]).
  Future<String> startPhoneEnrollment(
    String phoneNumber,
    dart_auth.AppVerification appVerification,
  ) => _client.startPhoneEnrollment(
    phoneNumber,
    appVerification: appVerification,
  );

  Future<DartTotpSecret> _startTotpEnrollment() => guard(
    _auth,
    () async =>
        DartTotpSecret(await _client.startTotpEnrollment(), _auth.app.name),
  );
}

/// The session of [DartMultiFactor.getSession]: it keeps the user it was made
/// for, and its [id] is that user's uid. The backend session (the
/// `sessionInfo` of `mfaEnrollment:start`) lives in the [DartTotpSecret].
class DartMultiFactorSession extends MultiFactorSession {
  DartMultiFactorSession(this.multiFactor) : super(multiFactor.uid);

  /// The multi-factor API of the user the session is for.
  final DartMultiFactor multiFactor;
}

/// The session of a [DartMultiFactorResolver]: `FirebaseAuth.verifyPhoneNumber`
/// with it sends the SMS code of an SMS factor through the client's resolver,
/// [source], whose `session` wraps the backend's pending credential. Its [id]
/// is opaque (`sign-in-<n>`, numbered in the order the sessions were made): it
/// is not the pending credential, so printing or logging it shows no secret.
class DartMultiFactorSignInSession extends MultiFactorSession {
  DartMultiFactorSignInSession(this.source)
    : super('sign-in-${++_signInSessions}');

  static int _signInSessions = 0;

  /// The resolver of `firebase_auth_providers_dart`; null for a challenge the
  /// client cannot finish (a link of a credential).
  final dart_auth.MultiFactorResolver? source;

  /// Sends the SMS code of the factor [enrollmentId] (the single SMS factor
  /// when null) and returns the verification id.
  Future<String> startPhoneSignIn(
    String? enrollmentId,
    dart_auth.AppVerification appVerification,
  ) => _resolverOf(source).startPhoneSignIn(
    enrollmentId: enrollmentId,
    appVerification: appVerification,
  );
}

/// [source], or the `internal-error` of a challenge that cannot be finished.
dart_auth.MultiFactorResolver _resolverOf(
  dart_auth.MultiFactorResolver? source,
) =>
    source ??
    (throw FirebaseAuthException(
      code: 'internal-error',
      message:
          'This second-factor challenge cannot be finished: it came from '
          'linking a credential. Sign in or reauthenticate instead.',
    ));

/// The resolver of a `multi-factor-auth-required` error: [hints] lists the
/// enrolled factors, the [session] is a [DartMultiFactorSignInSession], and
/// [resolveSignIn] finishes the sign-in (or the reauthentication) with a TOTP
/// or SMS assertion through the client's resolver, [source].
class DartMultiFactorResolver extends MultiFactorResolverPlatform {
  DartMultiFactorResolver(
    super.hints,
    super.session, {
    required DartFirebaseAuth auth,
    required this.source,
  }) : _auth = auth;

  final DartFirebaseAuth _auth;

  /// The resolver of `firebase_auth_providers_dart`; null for a challenge
  /// the client cannot finish (a link of a credential).
  final dart_auth.MultiFactorResolver? source;

  /// Takes an assertion of `TotpMultiFactorGenerator.getAssertionForSignIn`,
  /// or of `PhoneMultiFactorGenerator.getAssertion` (the verification id that
  /// `verifyPhoneNumber` passed to `codeSent` with this resolver's session,
  /// and the code of the SMS). Throws `argument-error` for another assertion.
  @override
  Future<UserCredentialPlatform> resolveSignIn(
    MultiFactorAssertionPlatform assertion,
  ) => guard(_auth, () async {
    if (assertion is DartPhoneAssertion) {
      return _auth.resultOf(
        await _resolverOf(source).resolveSignInWithPhone(assertion.credential),
      );
    }
    if (assertion is! DartTotpSignInAssertion) {
      throw _wrongAssertion(
        assertion,
        'resolveSignIn takes an assertion of '
        'TotpMultiFactorGenerator.getAssertionForSignIn or '
        'PhoneMultiFactorGenerator.getAssertion',
      );
    }
    final dart_auth.MultiFactorResolver resolver = _resolverOf(source);
    return _auth.resultOf(
      await resolver.resolveSignInWithTotp(
        assertion.oneTimePassword,
        enrollmentId: assertion.enrollmentId,
      ),
    );
  });
}

/// `PhoneMultiFactorGenerator`: the assertion of an SMS factor, for
/// `MultiFactor.enroll` and `MultiFactorResolver.resolveSignIn`.
class DartPhoneMultiFactorGenerator extends PhoneMultiFactorGeneratorPlatform {
  /// Throws `argument-error` for a credential without a verification id or
  /// SMS code.
  @override
  MultiFactorAssertionPlatform getAssertion(PhoneAuthCredential credential) =>
      DartPhoneAssertion(clientPhoneCredentialOf(credential));
}

/// What `MultiFactor.enroll` and `MultiFactorResolver.resolveSignIn` take for
/// an SMS factor: the client's phone credential.
class DartPhoneAssertion extends MultiFactorAssertionPlatform {
  DartPhoneAssertion(this.credential);

  final dart_auth.PhoneAuthCredential credential;
}

/// `TotpMultiFactorGenerator`: secrets and assertions for an authenticator app
/// second factor.
class DartTotpMultiFactorGenerator extends TotpMultiFactorGeneratorPlatform {
  /// Starts the enrolment for the user of [session]
  /// (`v2/accounts/mfaEnrollment:start`). Throws `argument-error` for a
  /// session that `User.multiFactor.getSession()` of this package did not
  /// make.
  @override
  Future<TotpSecretPlatform> generateSecret(MultiFactorSession session) async {
    if (session is! DartMultiFactorSession) {
      throw FirebaseAuthException(
        code: 'argument-error',
        message:
            'generateSecret takes the session of '
            'User.multiFactor.getSession().',
      );
    }
    return session.multiFactor._startTotpEnrollment();
  }

  @override
  Future<MultiFactorAssertionPlatform> getAssertionForEnrollment(
    TotpSecretPlatform secret,
    String oneTimePassword,
  ) async {
    if (secret is! DartTotpSecret) {
      throw FirebaseAuthException(
        code: 'argument-error',
        message:
            'getAssertionForEnrollment takes the secret of '
            'TotpMultiFactorGenerator.generateSecret.',
      );
    }
    return DartTotpEnrollmentAssertion(secret.source, oneTimePassword);
  }

  @override
  Future<MultiFactorAssertionPlatform> getAssertionForSignIn(
    String enrollmentId,
    String oneTimePassword,
  ) async => DartTotpSignInAssertion(enrollmentId, oneTimePassword);
}

/// The secret of a TOTP enrolment: the client's [source] with the fields of
/// the interface (null where the backend gave none).
class DartTotpSecret extends TotpSecretPlatform {
  DartTotpSecret(this.source, this._defaultIssuer)
    : super(
        source.codeIntervalSeconds > 0 ? source.codeIntervalSeconds : null,
        source.codeLength > 0 ? source.codeLength : null,
        source.enrollmentCompletionDeadline,
        source.hashingAlgorithm,
        source.secretKey,
      );

  /// The secret of `firebase_auth_providers_dart`.
  final dart_auth.TotpSecret source;

  final String _defaultIssuer;

  /// The `otpauth://totp/...` URL of the secret, to show as a QR code. As in
  /// the JS SDK, [accountName] defaults to the email address of the user and
  /// [issuer] to the name of the Firebase app.
  @override
  Future<String> generateQrCodeUrl({
    String? accountName,
    String? issuer,
  }) async => source
      .otpauthUri(
        issuer: issuer == null || issuer.isEmpty ? _defaultIssuer : issuer,
        accountName: accountName,
      )
      .toString();

  /// Throws `unimplemented`: opening another app needs a URL launcher.
  @override
  Future<void> openInOtpApp(String qrCodeUrl) async => throw unimplemented(
    'TotpSecret.openInOtpApp',
    'opening an authenticator app needs a URL launcher, which this package '
        'does not depend on. Open the URL of generateQrCodeUrl with '
        'url_launcher, or show it as a QR code.',
  );
}

/// What `MultiFactor.enroll` takes for a TOTP factor.
class DartTotpEnrollmentAssertion extends MultiFactorAssertionPlatform {
  DartTotpEnrollmentAssertion(this.secret, this.oneTimePassword);

  final dart_auth.TotpSecret secret;
  final String oneTimePassword;
}

/// What `MultiFactorResolver.resolveSignIn` takes for a TOTP factor.
class DartTotpSignInAssertion extends MultiFactorAssertionPlatform {
  DartTotpSignInAssertion(this.enrollmentId, this.oneTimePassword);

  final String enrollmentId;
  final String oneTimePassword;
}

FirebaseAuthException _wrongAssertion(
  MultiFactorAssertionPlatform assertion,
  String expected,
) => FirebaseAuthException(
  code: 'argument-error',
  message: '$expected, not a ${assertion.runtimeType}.',
);

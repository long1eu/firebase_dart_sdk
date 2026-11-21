// Multi-factor authentication: the enrolled factors, the secret of an authenticator app enrolment, and the resolver
// that finishes a sign-in with a second factor. The functions at the end are for FirebaseUserAuth and are not
// exported.

import 'auth_constants.dart';
import 'auth_exception.dart';
import 'auth_user.dart';
import 'firebase_user_auth.dart';

/// A second factor enrolled on an account: an entry of [AuthUser.enrolledFactors] and of
/// [FirebaseAuthMultiFactorException.hints] (`MultiFactorInfo` of the JS SDK and of FlutterFire, with the phone
/// number of `PhoneMultiFactorInfo`).
class MultiFactorInfo {
  /// Creates the information. The package creates them; you need this only for tests.
  const MultiFactorInfo({
    required this.uid,
    required this.factorId,
    this.displayName,
    this.phoneNumber,
    this.enrollmentTime,
  });

  /// The [factorId] of an SMS second factor (`PhoneMultiFactorGenerator.FACTOR_ID` of the JS SDK). This package
  /// lists such factors and can unenrol them ([FirebaseUserAuth.unenrollMultiFactor]), but cannot enrol them or sign
  /// in with them.
  static const String phoneFactorId = FactorId.phone;

  /// The [factorId] of a time-based one-time password (authenticator app) second factor
  /// (`TotpMultiFactorGenerator.FACTOR_ID` of the JS SDK).
  static const String totpFactorId = FactorId.totp;

  /// The [factorId] of a factor this package does not know (neither `phoneInfo` nor `totpInfo` in the answer).
  static const String unknownFactorId = 'unknown';

  /// Reads one entry of the `mfaInfo` list of the Identity Toolkit API (`MfaEnrollment`), or returns null when
  /// [enrollment] is not an object with an `mfaEnrollmentId`.
  ///
  /// The factor is [phoneFactorId] when the entry has `phoneInfo`, [totpFactorId] when it has `totpInfo`, and
  /// [unknownFactorId] otherwise (the JS SDK fails with `internal-error` there). `enrolledAt` is read as an
  /// RFC 3339 timestamp (the REST API; with 0, 3, 6 or 9 fractional digits and a time zone, as the iOS SDK reads it
  /// since 2026-11) or as milliseconds since the epoch (as the JS SDK reads it); anything else gives a null
  /// [enrollmentTime].
  static MultiFactorInfo? fromResponse(Object? enrollment) {
    if (enrollment is! Map<String, Object?>) {
      return null;
    }
    final Object? id = enrollment['mfaEnrollmentId'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    final Object? displayName = enrollment['displayName'];
    final Object? phone = enrollment['phoneInfo'];
    return MultiFactorInfo(
      uid: id,
      factorId: enrollment.containsKey('phoneInfo')
          ? phoneFactorId
          : enrollment.containsKey('totpInfo')
          ? totpFactorId
          : unknownFactorId,
      displayName: displayName is String && displayName.isNotEmpty
          ? displayName
          : null,
      phoneNumber: phone is String && phone.isNotEmpty ? phone : null,
      enrollmentTime: timestampOf(enrollment['enrolledAt']),
    );
  }

  /// The id of the enrolment (`mfaEnrollmentId` of the REST API): what [FirebaseUserAuth.unenrollMultiFactor] and
  /// [MultiFactorResolver.resolveSignInWithTotp] take.
  final String uid;

  /// The kind of factor: [phoneFactorId], [totpFactorId] or [unknownFactorId].
  final String factorId;

  /// The name the user gave the factor, if any.
  final String? displayName;

  /// For a [phoneFactorId] factor, the phone number: in full in [AuthUser.enrolledFactors], masked (for example
  /// `+*******1234`) in [FirebaseAuthMultiFactorException.hints]. Null for other factors.
  final String? phoneNumber;

  /// When the factor was enrolled (UTC), or null when the backend did not say.
  final DateTime? enrollmentTime;

  @override
  bool operator ==(Object other) =>
      other is MultiFactorInfo &&
      other.uid == uid &&
      other.factorId == factorId &&
      other.displayName == displayName &&
      other.phoneNumber == phoneNumber &&
      other.enrollmentTime == enrollmentTime;

  @override
  int get hashCode =>
      Object.hash(uid, factorId, displayName, phoneNumber, enrollmentTime);

  @override
  String toString() => 'MultiFactorInfo($factorId, $uid)';
}

/// The secret of an authenticator app (TOTP) enrolment that [FirebaseUserAuth.startTotpEnrollment] started: the
/// user adds it to an authenticator app ([otpauthUri] as a QR code or a link, or [secretKey] typed in by hand), and
/// [FirebaseUserAuth.finalizeTotpEnrollment] finishes the enrolment with a code of the app.
///
/// It is a credential: do not log it or store it. [toString] leaves [secretKey] out.
///
/// ```dart
/// final TotpSecret secret = await auth.startTotpEnrollment();
/// print(secret.otpauthUri(issuer: 'My App')); // show it as a QR code
/// // ... the user scans it and types the code the app shows:
/// await auth.finalizeTotpEnrollment(secret, code: '123456', displayName: 'Phone');
/// ```
class TotpSecret {
  TotpSecret._({
    required this.secretKey,
    required this.hashingAlgorithm,
    required this.codeLength,
    required this.codeIntervalSeconds,
    required this.enrollmentCompletionDeadline,
    required String? sessionInfo,
    required String? accountName,
  }) : _sessionInfo = sessionInfo,
       _accountName = accountName;

  /// Reads the `totpSessionInfo` of an answer of `v2/accounts/mfaEnrollment:start`, or returns null when it has no
  /// `sharedSecretKey`. [accountName] is the default account name of [otpauthUri] (the email address of the user).
  static TotpSecret? fromResponse(
    Object? totpSessionInfo, {
    String? accountName,
  }) {
    if (totpSessionInfo is! Map<String, Object?>) {
      return null;
    }
    final Object? key = totpSessionInfo['sharedSecretKey'];
    if (key is! String || key.isEmpty) {
      return null;
    }
    int number(Object? value) => switch (value) {
      final num n => n.toInt(),
      final String s => int.tryParse(s) ?? 0,
      _ => 0,
    };
    final Object? algorithm = totpSessionInfo['hashingAlgorithm'];
    final Object? session = totpSessionInfo['sessionInfo'];
    return TotpSecret._(
      secretKey: key,
      hashingAlgorithm: algorithm is String && algorithm.isNotEmpty
          ? algorithm
          : null,
      codeLength: number(totpSessionInfo['verificationCodeLength']),
      codeIntervalSeconds: number(totpSessionInfo['periodSec']),
      enrollmentCompletionDeadline: timestampOf(
        totpSessionInfo['finalizeEnrollmentTime'],
      ),
      sessionInfo: session is String && session.isNotEmpty ? session : null,
      accountName: accountName,
    );
  }

  /// The shared secret, base32 encoded, for entering it into an authenticator app by hand.
  final String secretKey;

  /// The hash algorithm of the codes, for example `SHA1`, or null when the backend did not say.
  final String? hashingAlgorithm;

  /// The number of digits of a code, or 0 when the backend did not say.
  final int codeLength;

  /// How many seconds a code is valid, or 0 when the backend did not say.
  final int codeIntervalSeconds;

  /// When the enrolment must be finished (UTC), or null when the backend did not say: for a countdown.
  final DateTime? enrollmentCompletionDeadline;

  final String? _sessionInfo;
  final String? _accountName;

  /// The `otpauth://totp/...` URI of the secret (the Key URI Format of authenticator apps), to show as a QR code or
  /// to open as a link: `otpauth://totp/<issuer>:<accountName>?secret=...&issuer=...&algorithm=...&digits=...`.
  ///
  /// [issuer] is the name the app shows for the entry, usually the name of your app. [accountName] defaults to the
  /// email address of the user who started the enrolment, or `unknownuser` (the JS SDK's default). Both are
  /// percent-encoded (an `@` stays as it is). `algorithm` and `digits` are left out when the backend did not give
  /// them (apps then assume SHA1 and 6 digits), and `period` is added only when it is not 30 seconds. FlutterFire's
  /// `generateQrCodeUrl` and the JS SDK build the same string for a plain issuer and account name.
  Uri otpauthUri({required String issuer, String? accountName}) {
    String encode(String value) =>
        Uri.encodeComponent(value).replaceAll('%40', '@');
    final String account = accountName != null && accountName.isNotEmpty
        ? accountName
        : _accountName ?? 'unknownuser';
    final String? algorithm = hashingAlgorithm;
    return Uri.parse(
      'otpauth://totp/${encode(issuer)}:${encode(account)}'
      '?secret=$secretKey&issuer=${encode(issuer)}'
      '${algorithm == null ? '' : '&algorithm=${encode(algorithm)}'}'
      '${codeLength > 0 ? '&digits=$codeLength' : ''}'
      '${codeIntervalSeconds > 0 && codeIntervalSeconds != 30 ? '&period=$codeIntervalSeconds' : ''}',
    );
  }

  @override
  String toString() =>
      'TotpSecret(hashingAlgorithm: $hashingAlgorithm, codeLength: $codeLength, '
      'codeIntervalSeconds: $codeIntervalSeconds)';
}

/// Finishes a sign-in or a reauthentication that needs a second factor: the
/// [FirebaseAuthMultiFactorException.resolver] of the exception that [FirebaseUserAuth] threw (FlutterFire's and
/// the JS SDK's `MultiFactorResolver`).
///
/// It finishes with a code of an authenticator app (TOTP). An account whose only second factors are SMS cannot be
/// finished with this package: [resolveSignInWithTotp] throws `multi-factor-info-not-found` there, and the message
/// of the exception says so from the start.
///
/// ```dart
/// try {
///   await auth.signInWithEmailAndPassword(email: email, password: password);
/// } on FirebaseAuthMultiFactorException catch (e) {
///   final String code = await askForTheCodeOfTheAuthenticatorApp();
///   final UserCredential result = await e.resolver!.resolveSignInWithTotp(code);
///   print(result.user?.uid);
/// }
/// ```
class MultiFactorResolver {
  MultiFactorResolver._(this.hints, this._resolveTotp);

  /// The second factors of the account, as [FirebaseAuthMultiFactorException.hints] lists them.
  final List<MultiFactorInfo> hints;

  final Future<UserCredential> Function(String enrollmentId, String code)
  _resolveTotp;

  /// Finishes the sign-in with [code], the code an authenticator app shows for the account
  /// (`v2/accounts/mfaSignIn:finalize`), and returns what the sign-in would have returned: for a sign-in the new
  /// user is signed in (the streams emit and the session is stored as for any sign-in); for a reauthentication the
  /// signed-in user continues with the new tokens.
  ///
  /// [enrollmentId] is the [MultiFactorInfo.uid] of the factor; it can be left out when the account has a single
  /// authenticator app factor among [hints].
  ///
  /// Throws a [FirebaseAuthException] with the code `multi-factor-info-not-found` when the account has no
  /// authenticator app factor (only SMS: this package cannot finish such a sign-in) or [enrollmentId] is a factor of
  /// another kind, `argument-error` when [enrollmentId] is needed and missing, and what the backend answers: a wrong
  /// or old code, `invalid-multi-factor-session` (the pending sign-in expired after a few minutes: sign in again),
  /// `cancelled` (another sign-in or a sign-out overtook it), ...
  Future<UserCredential> resolveSignInWithTotp(
    String code, {
    String? enrollmentId,
  }) async {
    final List<MultiFactorInfo> totp = <MultiFactorInfo>[
      for (final MultiFactorInfo hint in hints)
        if (hint.factorId == MultiFactorInfo.totpFactorId) hint,
    ];
    if (enrollmentId == null) {
      if (totp.isEmpty) {
        throw FirebaseAuthException(
          code: 'multi-factor-info-not-found',
          message:
              'The account has no authenticator app (TOTP) second factor; its second factors are '
              '${_kinds(hints)}. This package cannot finish a sign-in with an SMS second factor.',
        );
      }
      if (totp.length > 1) {
        throw const FirebaseAuthException(
          code: 'argument-error',
          message:
              'The account has several authenticator app factors: pass the enrollmentId of one of them.',
        );
      }
      return _resolveTotp(totp.single.uid, code);
    }
    for (final MultiFactorInfo hint in hints) {
      if (hint.uid == enrollmentId &&
          hint.factorId != MultiFactorInfo.totpFactorId) {
        throw FirebaseAuthException(
          code: 'multi-factor-info-not-found',
          message:
              'The second factor $enrollmentId is not an authenticator app (TOTP) factor but '
              '${_kinds(<MultiFactorInfo>[hint])}; this package can finish a sign-in only with an authenticator app.',
        );
      }
    }
    return _resolveTotp(enrollmentId, code);
  }

  static String _kinds(List<MultiFactorInfo> factors) => factors.isEmpty
      ? 'not listed'
      : <String>{
          for (final MultiFactorInfo f in factors)
            f.factorId == MultiFactorInfo.phoneFactorId
                ? 'SMS (phone)'
                : f.factorId,
        }.join(', ');

  @override
  String toString() => 'MultiFactorResolver(hints: $hints)';
}

// ---- for FirebaseUserAuth, not exported ----

/// Creates the resolver of a sign-in that needs a second factor; [resolveTotp] finishes it.
MultiFactorResolver createMultiFactorResolver(
  List<MultiFactorInfo> hints,
  Future<UserCredential> Function(String enrollmentId, String code) resolveTotp,
) => MultiFactorResolver._(hints, resolveTotp);

/// The `sessionInfo` that `mfaEnrollment:finalize` takes back with the code.
String? totpSessionInfoOf(TotpSecret secret) => secret._sessionInfo;

final RegExp _rfc3339 = RegExp(
  r'^\d{4}-\d{2}-\d{2}[Tt]\d{2}:\d{2}:\d{2}(\.\d{1,9})?([Zz]|[+-]\d{2}:\d{2})$',
);

/// A timestamp of the Identity Toolkit API, in UTC: an RFC 3339 string with a time zone (the JSON form of a
/// `google.protobuf.Timestamp`), or milliseconds since the epoch as a number (what the JS SDK accepts too). Null
/// for anything else, including a date without a time or a time without a zone.
DateTime? timestampOf(Object? value) => switch (value) {
  final String text when _rfc3339.hasMatch(text) => DateTime.tryParse(
    text,
  )?.toUtc(),
  final num millis => DateTime.fromMillisecondsSinceEpoch(
    millis.toInt(),
    isUtc: true,
  ),
  _ => null,
};

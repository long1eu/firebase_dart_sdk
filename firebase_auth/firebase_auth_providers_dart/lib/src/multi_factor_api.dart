// The four calls of the Identity Toolkit API v2 that authenticator app (TOTP) multi-factor authentication makes,
// behind one seam so that another wire format can be added later. Not exported.
//
// Every call answers in the JSON shape of the REST API (`idToken`, `refreshToken`, `totpSessionInfo`, ...).
//
// All calls go as JSON: Google's published definitions (googleapis, google/cloud/identitytoolkit/v2) have no TOTP
// fields.

import 'auth_exception.dart';

/// How the calls reach the backend; `FirebaseUserAuth` provides it. [postJson] posts a JSON body to a v2 method
/// (for example `accounts/mfaEnrollment:start`) and returns the decoded answer or throws a
/// [FirebaseAuthException].
class MultiFactorTransport {
  /// Creates the transport.
  const MultiFactorTransport({required this.postJson});

  /// Posts a JSON body.
  final Future<Map<String, Object?>> Function(
    String method,
    Map<String, Object?> body,
  )
  postJson;
}

/// The calls. The tenant goes into each request when not null (`_addTidIfNecessary` of the JS SDK).
abstract class MultiFactorApi {
  /// The calls as JSON.
  factory MultiFactorApi.json(MultiFactorTransport transport) =
      _JsonMultiFactorApi;

  /// `accounts/mfaEnrollment:start` with `totpEnrollmentInfo`: the answer has `totpSessionInfo`.
  Future<Map<String, Object?>> startTotpEnrollment({
    required String idToken,
    String? tenantId,
  });

  /// `accounts/mfaEnrollment:finalize` with `totpVerificationInfo`: the answer has `idToken` and `refreshToken`.
  Future<Map<String, Object?>> finalizeTotpEnrollment({
    required String idToken,
    required String sessionInfo,
    required String code,
    String? displayName,
    String? tenantId,
  });

  /// `accounts/mfaEnrollment:withdraw`: the answer has `idToken` and `refreshToken`.
  Future<Map<String, Object?>> withdraw({
    required String idToken,
    required String enrollmentId,
    String? tenantId,
  });

  /// `accounts/mfaSignIn:finalize` with `mfaEnrollmentId` and `totpVerificationInfo`: the answer has `idToken`
  /// and `refreshToken`.
  Future<Map<String, Object?>> finalizeTotpSignIn({
    required String pendingCredential,
    required String enrollmentId,
    required String code,
    String? tenantId,
  });
}

/// The request bodies of the JS SDK (`startEnrollTotpMfa`, `finalizeEnrollTotpMfa`, `withdrawMfa`,
/// `finalizeSignInTotpMfa`) and the iOS SDK.
class _JsonMultiFactorApi implements MultiFactorApi {
  _JsonMultiFactorApi(this.transport);

  final MultiFactorTransport transport;

  @override
  Future<Map<String, Object?>> startTotpEnrollment({
    required String idToken,
    String? tenantId,
  }) => transport.postJson('accounts/mfaEnrollment:start', <String, Object?>{
    'idToken': idToken,
    'totpEnrollmentInfo': const <String, Object?>{},
    'tenantId': ?tenantId,
  });

  @override
  Future<Map<String, Object?>> finalizeTotpEnrollment({
    required String idToken,
    required String sessionInfo,
    required String code,
    String? displayName,
    String? tenantId,
  }) => transport.postJson('accounts/mfaEnrollment:finalize', <String, Object?>{
    'idToken': idToken,
    'displayName': ?displayName,
    'totpVerificationInfo': <String, Object?>{
      'sessionInfo': sessionInfo,
      'verificationCode': code,
    },
    'tenantId': ?tenantId,
  });

  @override
  Future<Map<String, Object?>> withdraw({
    required String idToken,
    required String enrollmentId,
    String? tenantId,
  }) => transport.postJson('accounts/mfaEnrollment:withdraw', <String, Object?>{
    'idToken': idToken,
    'mfaEnrollmentId': enrollmentId,
    'tenantId': ?tenantId,
  });

  @override
  Future<Map<String, Object?>> finalizeTotpSignIn({
    required String pendingCredential,
    required String enrollmentId,
    required String code,
    String? tenantId,
  }) => transport.postJson('accounts/mfaSignIn:finalize', <String, Object?>{
    'mfaPendingCredential': pendingCredential,
    'mfaEnrollmentId': enrollmentId,
    'totpVerificationInfo': <String, Object?>{'verificationCode': code},
    'tenantId': ?tenantId,
  });
}

/// The exception of an error answer of the Identity Toolkit API in JSON: `{"error": {"message": "CODE : detail"}}`,
/// or an HTTP 200 answer with an `errorMessage` (`_performFetchWithErrorHandling` of the JS SDK).
FirebaseAuthException exceptionFromJsonError(int httpStatus, Object? body) {
  final Object? error = body is Map<String, Object?> ? body['error'] : null;
  final Object? message = httpStatus == 200 && body is Map<String, Object?>
      ? body['errorMessage']
      : error is Map<String, Object?>
      ? error['message']
      : null;
  if (message is String) {
    return FirebaseAuthException.fromServer(
      message,
      httpStatus: httpStatus,
      response: body is Map<String, Object?> ? body : null,
    );
  }
  return FirebaseAuthException(
    code: 'internal-error',
    message: 'The authentication service answered with HTTP $httpStatus.',
    httpStatus: httpStatus,
  );
}

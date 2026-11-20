// The four calls of the Identity Toolkit API v2 that authenticator app (TOTP) multi-factor authentication makes,
// behind one seam with two wire formats: JSON, and protocol buffers over the same HTTP client (`$alt=proto`, no
// gRPC). Not exported.
//
// Every call answers in the JSON shape of the REST API (`idToken`, `refreshToken`, `totpSessionInfo`, ...), so the
// code above the seam does not know which format was used.
//
// Google's published definitions (googleapis, google/cloud/identitytoolkit/v2, last changed 2025-09-17) have no
// TOTP fields: StartMfaEnrollmentRequest has no `totp_enrollment_info`, StartMfaEnrollmentResponse no
// `totp_session_info`, FinalizeMfaEnrollmentRequest and FinalizeMfaSignInRequest no `totp_verification_info`, and
// FinalizeMfaSignInRequest no `mfa_enrollment_id`. Their field numbers are not published, so those three calls go
// as JSON in both formats; only `mfaEnrollment:withdraw` is fully described and goes as protobuf.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:protobuf/well_known_types/google/protobuf/any.pb.dart';

import 'auth_exception.dart';
import 'proto/google/cloud/identitytoolkit/v2/account_management_service.pb.dart'
    as v2;
import 'proto/google/rpc/error_details.pb.dart' as rpc;
import 'proto/google/rpc/status.pb.dart' as rpc;

/// The wire format of the multi-factor calls (`FirebaseUserAuth.multiFactorWireFormat`).
enum MultiFactorWireFormat {
  /// Protocol buffers where the published definitions describe the call (`mfaEnrollment:withdraw`), JSON for the
  /// rest. The default for the real service.
  protobuf,

  /// JSON for every call. The default for the Auth emulator.
  json,
}

/// How the calls reach the backend; `FirebaseUserAuth` provides both. [postJson] posts a JSON body to a v2 method
/// (for example `accounts/mfaEnrollment:start`) and returns the decoded answer or throws a
/// [FirebaseAuthException]; [postProtobuf] posts a binary body with `$alt=proto` and returns the response as it is,
/// successful or not, or throws `network-request-failed`.
class MultiFactorTransport {
  /// Creates the transport.
  const MultiFactorTransport({
    required this.postJson,
    required this.postProtobuf,
  });

  /// Posts a JSON body.
  final Future<Map<String, Object?>> Function(
    String method,
    Map<String, Object?> body,
  )
  postJson;

  /// Posts a protocol buffer body.
  final Future<http.Response> Function(String method, List<int> body)
  postProtobuf;
}

/// The calls. The tenant goes into each request when not null (`_addTidIfNecessary` of the JS SDK).
abstract class MultiFactorApi {
  /// The calls in [format].
  factory MultiFactorApi(
    MultiFactorWireFormat format,
    MultiFactorTransport transport,
  ) => switch (format) {
    MultiFactorWireFormat.json => _JsonMultiFactorApi(transport),
    MultiFactorWireFormat.protobuf => _ProtobufMultiFactorApi(transport),
  };

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

/// Protocol buffers for `mfaEnrollment:withdraw`, the one call the published definitions describe; JSON for the
/// three TOTP calls (see the top of this file).
class _ProtobufMultiFactorApi extends _JsonMultiFactorApi {
  _ProtobufMultiFactorApi(super.transport);

  @override
  Future<Map<String, Object?>> withdraw({
    required String idToken,
    required String enrollmentId,
    String? tenantId,
  }) async {
    final v2.WithdrawMfaRequest request = v2.WithdrawMfaRequest(
      idToken: idToken,
      mfaEnrollmentId: enrollmentId,
      tenantId: tenantId,
    );
    final http.Response response = await transport.postProtobuf(
      'accounts/mfaEnrollment:withdraw',
      request.writeToBuffer(),
    );
    return decodeProtobufAnswer(response, (List<int> bytes) {
      final v2.WithdrawMfaResponse answer = v2.WithdrawMfaResponse.fromBuffer(
        bytes,
      );
      return <String, Object?>{
        if (answer.idToken.isNotEmpty) 'idToken': answer.idToken,
        if (answer.refreshToken.isNotEmpty) 'refreshToken': answer.refreshToken,
      };
    });
  }
}

bool _isJson(http.Response response) =>
    (response.headers['content-type'] ?? '').contains('json');

/// The answer of a `$alt=proto` call in the JSON shape: [decode] reads a successful binary answer. A JSON answer
/// (the backend ignored `$alt`) is read as JSON. An error is thrown as a [FirebaseAuthException]: from the
/// `google.rpc.Status` of a binary error ([exceptionFromStatus]), or from a JSON error body like the JSON calls.
Map<String, Object?> decodeProtobufAnswer(
  http.Response response,
  Map<String, Object?> Function(List<int> bytes) decode,
) {
  if (_isJson(response)) {
    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      body = null;
    }
    if (response.statusCode == 200 &&
        body is Map<String, Object?> &&
        !body.containsKey('errorMessage')) {
      return body;
    }
    throw exceptionFromJsonError(response.statusCode, body);
  }
  if (response.statusCode != 200) {
    throw exceptionFromStatus(response.statusCode, response.bodyBytes);
  }
  try {
    return decode(response.bodyBytes);
  } on Object {
    throw const FirebaseAuthException(
      code: 'internal-error',
      message: 'The authentication service answered with a malformed message.',
      httpStatus: 200,
    );
  }
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

/// A code of the Identity Toolkit API in the JSON form's style (`INVALID_ID_TOKEN`, optionally followed by
/// ` : detail`).
final RegExp _serverCode = RegExp(r'^[A-Z][A-Z0-9_]+( : .*)?$', dotAll: true);

/// The names of the canonical codes of `google.rpc.Code`.
const List<String> _canonicalCodes = <String>[
  'OK',
  'CANCELLED',
  'UNKNOWN',
  'INVALID_ARGUMENT',
  'DEADLINE_EXCEEDED',
  'NOT_FOUND',
  'ALREADY_EXISTS',
  'PERMISSION_DENIED',
  'RESOURCE_EXHAUSTED',
  'FAILED_PRECONDITION',
  'ABORTED',
  'OUT_OF_RANGE',
  'UNIMPLEMENTED',
  'INTERNAL',
  'UNAVAILABLE',
  'DATA_LOSS',
  'UNAUTHENTICATED',
];

/// The exception of a binary error answer of a `$alt=proto` call: a `google.rpc.Status`.
///
/// The JSON form of the API puts the code the error map needs (`INVALID_ID_TOKEN`, `TOKEN_EXPIRED`,
/// `MFA_ENROLLMENT_NOT_FOUND`, ...) in the message; the binary form was seen with a generic message ("Request
/// contains an invalid argument."). So the code is looked for, in this order, in: the message of the status, the
/// `reason` of an `ErrorInfo` detail, the message of a `LocalizedMessage`, the detail of a `DebugInfo`, the
/// descriptions of a `BadRequest`, each taken when it has the shape of a code (`UPPER_CASE`, optionally
/// ` : detail`), and then mapped like a JSON error. When none has, the code is the canonical code of the status in
/// kebab case (`INVALID_ARGUMENT` is `invalid-argument`, with that name as [FirebaseAuthException.serverCode]) and
/// the message is the status message. A body that is not a status is `internal-error`.
FirebaseAuthException exceptionFromStatus(int httpStatus, List<int> bytes) {
  final rpc.Status status;
  try {
    status = rpc.Status.fromBuffer(bytes);
  } on Object {
    return FirebaseAuthException(
      code: 'internal-error',
      message: 'The authentication service answered with HTTP $httpStatus.',
      httpStatus: httpStatus,
    );
  }
  final List<String> candidates = <String>[status.message];
  for (final Any detail in status.details) {
    try {
      final String type = detail.typeUrl.substring(
        detail.typeUrl.lastIndexOf('/') + 1,
      );
      switch (type) {
        case 'google.rpc.ErrorInfo':
          candidates.add(rpc.ErrorInfo.fromBuffer(detail.value).reason);
        case 'google.rpc.LocalizedMessage':
          candidates.add(rpc.LocalizedMessage.fromBuffer(detail.value).message);
        case 'google.rpc.DebugInfo':
          candidates.add(rpc.DebugInfo.fromBuffer(detail.value).detail);
        case 'google.rpc.BadRequest':
          for (final rpc.BadRequest_FieldViolation violation
              in rpc.BadRequest.fromBuffer(detail.value).fieldViolations) {
            candidates.add(violation.description);
          }
      }
    } on Object {
      // A detail that does not decode is skipped.
    }
  }
  for (final String candidate in candidates) {
    if (_serverCode.hasMatch(candidate.trim())) {
      final FirebaseAuthException e = FirebaseAuthException.fromServer(
        candidate.trim(),
        httpStatus: httpStatus,
      );
      // A reason of the details carries no text of its own: the message of the status is better than the name.
      if (!candidate.contains(' : ') &&
          e.message == e.serverCode &&
          status.message.isNotEmpty) {
        return FirebaseAuthException(
          code: e.code,
          message: status.message,
          serverCode: e.serverCode,
          httpStatus: httpStatus,
        );
      }
      return e;
    }
  }
  final String name = status.code >= 0 && status.code < _canonicalCodes.length
      ? _canonicalCodes[status.code]
      : 'UNKNOWN';
  return FirebaseAuthException.fromServer(
    status.message.isEmpty ? name : '$name : ${status.message}',
    httpStatus: httpStatus,
  );
}

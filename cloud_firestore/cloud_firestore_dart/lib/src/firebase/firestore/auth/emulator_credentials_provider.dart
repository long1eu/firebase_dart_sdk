import 'dart:async';
import 'dart:convert';

import 'package:rxdart/rxdart.dart';

import 'credentials_provider.dart';
import 'token.dart';
import 'user.dart';

/// The user of a mock token that is given as a string (the user id can't be
/// read from it). Same as `User.MOCK_USER` of the JS SDK.
const User mockUser = User('mock-user');

/// A [CredentialsProvider] that always returns the same token. Used for the
/// `mockUserToken` of the emulator settings. Port of
/// `EmulatorAuthCredentialsProvider` of the JS SDK.
class EmulatorCredentialsProvider extends CredentialsProvider {
  EmulatorCredentialsProvider(this._token)
      : _onChange = BehaviorSubject<User>.seeded(_token.user);

  /// The provider for the `mockUserToken` emulator setting: [mockUserToken]
  /// is either a token string (used as is, for [mockUser]) or the claims of
  /// a Firebase ID token, which are encoded with [createMockUserToken] for
  /// [projectId].
  factory EmulatorCredentialsProvider.forMockUserToken(
      Object mockUserToken, String? projectId) {
    if (mockUserToken is String) {
      return EmulatorCredentialsProvider(Token(mockUserToken, mockUser));
    }
    final Map<String, Object?> claims = mockUserToken as Map<String, Object?>;
    final String token = createMockUserToken(claims, projectId);
    final String uid = (claims['sub'] ?? claims['user_id'])! as String;
    return EmulatorCredentialsProvider(Token(token, User(uid)));
  }

  final Token _token;

  // ignore: close_sinks
  final BehaviorSubject<User> _onChange;

  @override
  Future<String?> get token => Future<String?>.value(_token.value);

  @override
  void invalidateToken() {}

  @override
  Stream<User> get onChange => _onChange;
}

/// Encodes [token] (the claims of a Firebase ID token) as an unsigned JWT
/// that the emulators accept, for [projectId] (`demo-project` when null).
/// Port of `createMockUserToken` of the JS SDK (packages/util/src/emulator.ts):
/// the header is `{"alg":"none","type":"JWT"}`, missing claims get defaults
/// and the signature is empty.
///
/// Throws an [ArgumentError] when [token] has a `uid` claim (use `sub`) or has
/// neither `sub` nor `user_id`.
String createMockUserToken(Map<String, Object?> token, [String? projectId]) {
  if (token['uid'] != null) {
    throw ArgumentError(
        'The "uid" field is no longer supported by mockUserToken. Please use '
        '"sub" instead for Firebase Auth User ID.');
  }
  // Unsecured JWTs use "none" as the algorithm.
  const Map<String, Object?> header = <String, Object?>{
    'alg': 'none',
    'type': 'JWT',
  };

  final String project =
      projectId == null || projectId.isEmpty ? 'demo-project' : projectId;
  final Object iat = _orDefault(token['iat'], 0)!;
  final Object? sub = _orDefault(token['sub'], null) ?? token['user_id'];
  if (sub == null || sub == '') {
    throw ArgumentError("mockUserToken must contain 'sub' or 'user_id' field!");
  }
  if (sub is! String) {
    throw ArgumentError.value(
        sub, 'mockUserToken', "The 'sub' or 'user_id' field must be a String");
  }
  if (iat is! num) {
    throw ArgumentError.value(
        iat, 'mockUserToken', "The 'iat' field must be a number");
  }

  final Map<String, Object?> payload = <String, Object?>{
    // Set all required fields to decent defaults
    'iss': 'https://securetoken.google.com/$project',
    'aud': project,
    'iat': iat,
    'exp': iat + 3600,
    'auth_time': iat,
    'sub': sub,
    'user_id': sub,
    'firebase': <String, Object?>{
      'sign_in_provider': 'custom',
      'identities': <String, Object?>{},
    },
    // Override with user options
    ...token,
  };

  // Unsecured JWTs use the empty string as a signature.
  const String signature = '';
  return <String>[
    _base64UrlWithoutPadding(jsonEncode(header)),
    _base64UrlWithoutPadding(jsonEncode(payload)),
    signature,
  ].join('.');
}

/// JS `value || fallback`: falsy claims (null, 0, '' and false) use the
/// default.
Object? _orDefault(Object? value, Object? fallback) {
  if (value == null || value == 0 || value == '' || value == false) {
    return fallback;
  }
  return value;
}

String _base64UrlWithoutPadding(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');

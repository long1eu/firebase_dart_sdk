import 'dart:convert';
import 'dart:math';

const String _unreserved =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// [length] characters of the unreserved set of RFC 3986 (the code verifier alphabet of RFC 7636)
/// from a cryptographically secure source: 43 characters (the default) carry 258 bits.
String randomUnreservedString([int length = 43]) {
  final Random random = Random.secure();
  return String.fromCharCodes(
    List<int>.generate(
      length,
      (_) => _unreserved.codeUnitAt(random.nextInt(_unreserved.length)),
    ),
  );
}

/// 128 random bits, base64url without padding: a nonce for a content security policy.
String randomNonce() {
  final Random random = Random.secure();
  return base64Url
      .encode(List<int>.generate(16, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

/// Compares without an early exit, so that the time taken does not tell how much of [a] matched.
/// The length is not secret (the values compared here have a fixed length).
bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) {
    return false;
  }
  int difference = 0;
  for (int i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

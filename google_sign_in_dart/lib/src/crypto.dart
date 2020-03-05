// File created by
// Lung Razvan <long1eu>
// on 02/03/2020

part of '../google_sign_in_dart.dart';

const String _charset =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';

/// Generates a random code verifier string using the provided entropy source
/// and the specified length.
///
/// See "Proof Key for Code Exchange by OAuth Public Clients (RFC 7636)
/// <https://tools.ietf.org/html/rfc7636>"
String _generateSecureRandomString(
    [Random entropySource, int entropyBytes = 64]) {
  entropySource ??= Random.secure();
  assert(entropySource != null, 'entropySource cannot be null');
  assert(entropyBytes != null, 'entropyBytes cannot be null');

  final StringBuffer buffer = StringBuffer();
  int remainingLength = entropyBytes;
  while (remainingLength > 0) {
    final int i = entropySource.nextInt(_charset.length);
    buffer.write(_charset[i]);
    remainingLength = entropyBytes - buffer.length;
  }

  return buffer.toString();
}

/// Produces a code challenge as a Base64URL (with no padding) encoded SHA256
/// hash of the code verifier.
String _deriveCodeVerifierChallenge(String codeVerifier) {
  return base64Url
      .encode(sha256.convert(ascii.encode(codeVerifier)).bytes)
      .replaceAll('=', '');
}

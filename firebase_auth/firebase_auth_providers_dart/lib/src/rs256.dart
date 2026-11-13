import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The ASN.1 DigestInfo prefix of a SHA-256 hash (RFC 8017, section 9.2).
const List<int> _sha256DigestInfo = <int>[
  0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, //
  0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
];

/// Signs [data] with RSASSA-PKCS1-v1_5 and SHA-256 (the `RS256` algorithm of JWT).
///
/// Pure Dart, so that it also works on the web. The signature of the same data with the same key is always the
/// same (the scheme has no randomness).
///
/// The key is given by its modulus [n], its public exponent [e], its primes [p] and [q], and the values of the
/// Chinese remainder theorem ([dmp1] = d mod (p-1), [dmq1] = d mod (q-1), [coeff] = q^-1 mod p), as a PKCS#1
/// private key stores them.
///
/// No vetted RSA implementation is in the dependency tree: `googleapis_auth` (2.1 and later) has
/// `ServiceAccountCredentials.sign`, which computes the same CRT exponentiation without the two counter-measures
/// below, and `pointycastle` is not a dependency. This one adds them:
///
/// * **Blinding**: the message is multiplied by r^e for a random r ([random], by default [Random.secure]) before
///   the private exponentiation and the result by r^-1 after it, so that the time the exponentiation takes does
///   not depend on the message alone.
/// * **Verification** (against the fault attack on CRT): the signature is checked with the public key before it
///   is returned; a wrong one (a fault in one of the two halves would reveal a prime factor of [n]) throws a
///   [StateError] instead of leaving the process.
///
/// What remains: `BigInt` arithmetic in Dart is not constant time, and the key lives in ordinary memory. The data
/// signed here (a token request built by this package) is not chosen by an attacker, and the signature is only
/// sent to Google's token endpoint, so this is acceptable for its use; for keys that need a hardware or managed
/// boundary, use Application Default Credentials or the IAM `signBlob` API instead of a key file.
Uint8List signRs256(
  List<int> data, {
  required BigInt n,
  required BigInt e,
  required BigInt p,
  required BigInt q,
  required BigInt dmp1,
  required BigInt dmq1,
  required BigInt coeff,
  Random? random,
}) {
  final int length = (n.bitLength + 7) ~/ 8;
  final List<int> digest = sha256.convert(data).bytes;
  final int padding = length - _sha256DigestInfo.length - digest.length - 3;
  if (padding < 8) {
    throw ArgumentError('The RSA key is too short for an RS256 signature.');
  }
  // EMSA-PKCS1-v1_5: 0x00 0x01 0xff... 0x00 DigestInfo.
  final Uint8List encoded = Uint8List(length)
    ..[1] = 0x01
    ..fillRange(2, 2 + padding, 0xff)
    ..setRange(
      3 + padding,
      3 + padding + _sha256DigestInfo.length,
      _sha256DigestInfo,
    )
    ..setRange(length - digest.length, length, digest);

  BigInt message = BigInt.zero;
  for (final int byte in encoded) {
    message = (message << 8) | BigInt.from(byte);
  }
  // Blinding: sign m * r^e, then multiply by r^-1 (r^ed = r mod n).
  final BigInt r = _blindingFactor(n, random ?? Random.secure());
  final BigInt blinded = (message * r.modPow(e, n)) % n;
  // (m * r^e)^d mod n with the Chinese remainder theorem.
  final BigInt m1 = blinded.modPow(dmp1, p);
  final BigInt m2 = blinded.modPow(dmq1, q);
  final BigInt h = (coeff * (m1 - m2)) % p;
  BigInt signature = ((m2 + h * q) * r.modInverse(n)) % n;
  if (signature.modPow(e, n) != message) {
    throw StateError(
      'The RSA signature did not verify with the public key; it was not used.',
    );
  }

  final Uint8List result = Uint8List(length);
  final BigInt mask = BigInt.from(0xff);
  for (int i = length - 1; i >= 0; i--) {
    result[i] = (signature & mask).toInt();
    signature = signature >> 8;
  }
  return result;
}

/// A random number in [2, n - 1] that has an inverse modulo [n].
BigInt _blindingFactor(BigInt n, Random random) {
  final int length = (n.bitLength + 7) ~/ 8;
  while (true) {
    BigInt r = BigInt.zero;
    for (int i = 0; i < length + 8; i++) {
      r = (r << 8) | BigInt.from(random.nextInt(256));
    }
    r = r % n;
    if (r > BigInt.one && r.gcd(n) == BigInt.one) {
      return r;
    }
  }
}

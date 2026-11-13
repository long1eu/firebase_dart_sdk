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
/// The key is given by its modulus [n], its primes [p] and [q], and the values of the Chinese remainder theorem
/// ([dmp1] = d mod (p-1), [dmq1] = d mod (q-1), [coeff] = q^-1 mod p), as a PKCS#1 private key stores them.
Uint8List signRs256(
  List<int> data, {
  required BigInt n,
  required BigInt p,
  required BigInt q,
  required BigInt dmp1,
  required BigInt dmq1,
  required BigInt coeff,
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
        3 + padding, 3 + padding + _sha256DigestInfo.length, _sha256DigestInfo)
    ..setRange(length - digest.length, length, digest);

  BigInt message = BigInt.zero;
  for (final int byte in encoded) {
    message = (message << 8) | BigInt.from(byte);
  }
  // m^d mod n with the Chinese remainder theorem.
  final BigInt m1 = message.modPow(dmp1, p);
  final BigInt m2 = message.modPow(dmq1, q);
  final BigInt h = (coeff * (m1 - m2)) % p;
  BigInt signature = m2 + h * q;

  final Uint8List result = Uint8List(length);
  final BigInt mask = BigInt.from(0xff);
  for (int i = length - 1; i >= 0; i--) {
    result[i] = (signature & mask).toInt();
    signature = signature >> 8;
  }
  return result;
}

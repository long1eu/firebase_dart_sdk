// An RFC 6238 one-time password generator, for the tests only: it plays the authenticator app against the fake
// backend of test/multi_factor_test.dart. The package itself never computes codes.

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Decodes RFC 4648 base32 (upper or lower case, `=` padding optional), the encoding of a TOTP secret.
Uint8List base32Decode(String input) {
  const String alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final String text = input.toUpperCase().replaceAll('=', '');
  final BytesBuilder out = BytesBuilder();
  int buffer = 0;
  int bits = 0;
  for (final int unit in text.codeUnits) {
    final int value = alphabet.indexOf(String.fromCharCode(unit));
    if (value < 0) {
      throw FormatException('Not base32', input);
    }
    buffer = ((buffer << 5) | value) & 0xfff;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.addByte((buffer >> bits) & 0xff);
    }
  }
  return out.toBytes();
}

/// Encodes [bytes] as RFC 4648 base32 without padding.
String base32Encode(List<int> bytes) {
  const String alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final StringBuffer out = StringBuffer();
  int buffer = 0;
  int bits = 0;
  for (final int byte in bytes) {
    buffer = ((buffer << 8) | byte) & 0xfff;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(alphabet[(buffer >> bits) & 31]);
    }
  }
  if (bits > 0) {
    out.write(alphabet[(buffer << (5 - bits)) & 31]);
  }
  return out.toString();
}

/// The TOTP code of [key] at [time] (RFC 6238 over RFC 4226 HOTP).
String totpCode(
  List<int> key,
  DateTime time, {
  int digits = 6,
  int period = 30,
  String algorithm = 'SHA1',
}) {
  final int counter = time.millisecondsSinceEpoch ~/ 1000 ~/ period;
  final Uint8List message = Uint8List(8);
  int c = counter;
  for (int i = 7; i >= 0; i--) {
    message[i] = c & 0xff;
    c >>= 8;
  }
  final Hash hash = switch (algorithm) {
    'SHA1' => sha1,
    'SHA256' => sha256,
    'SHA512' => sha512,
    _ => throw ArgumentError.value(algorithm, 'algorithm'),
  };
  final List<int> mac = Hmac(hash, key).convert(message).bytes;
  final int offset = mac.last & 0x0f;
  final int binary =
      ((mac[offset] & 0x7f) << 24) |
      (mac[offset + 1] << 16) |
      (mac[offset + 2] << 8) |
      mac[offset + 3];
  int modulus = 1;
  for (int i = 0; i < digits; i++) {
    modulus *= 10;
  }
  return (binary % modulus).toString().padLeft(digits, '0');
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The ASN.1 DigestInfo prefix of a SHA-256 hash (RFC 8017, section 9.2).
const List<int> _sha256DigestInfo = <int>[
  0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, //
  0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
];

/// The object identifier `rsaEncryption` (1.2.840.113549.1.1.1), DER content bytes.
const List<int> _rsaEncryption = <int>[
  0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, //
];

/// An RSA public key that checks RS256 signatures (RSASSA-PKCS1-v1_5 with SHA-256).
///
/// Only what ID token verification needs: the key comes from an X.509 certificate (PEM or DER), the signature
/// check is the textbook one (s^e mod n, then a byte-for-byte comparison with the expected encoding). Nothing
/// secret is involved, so timing does not matter here.
final class RsaPublicKey {
  /// A key with [modulus] n and [exponent] e.
  RsaPublicKey(this.modulus, this.exponent) {
    if (modulus <= BigInt.one || exponent <= BigInt.one) {
      throw const FormatException('Not an RSA public key');
    }
  }

  /// The public key of the certificate [pem] (`-----BEGIN CERTIFICATE-----` ...). Throws a [FormatException] if
  /// it is not an X.509 certificate with an RSA key.
  factory RsaPublicKey.fromCertificatePem(String pem) {
    final List<String> lines = const LineSplitter()
        .convert(pem)
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList();
    final int begin = lines.indexOf('-----BEGIN CERTIFICATE-----');
    final int end = lines.indexOf('-----END CERTIFICATE-----');
    if (begin < 0 || end <= begin + 1) {
      throw const FormatException('Not a PEM certificate');
    }
    return RsaPublicKey.fromCertificateDer(
      base64.decode(lines.sublist(begin + 1, end).join()),
    );
  }

  /// The public key of the DER encoded X.509 certificate [der]. Only the path to the subject public key is
  /// read: the signature, the validity and the names of the certificate are not checked (the Firebase Admin SDKs
  /// do not check them either; the keys are trusted for coming from Google's endpoint over HTTPS).
  factory RsaPublicKey.fromCertificateDer(List<int> der) {
    final Uint8List bytes = Uint8List.fromList(der);
    final _Element certificate = _Element.read(bytes, 0, bytes.length);
    if (certificate.tag != 0x30 || certificate.end != bytes.length) {
      throw const FormatException('Not a DER certificate');
    }
    final List<_Element> parts = certificate.children(bytes);
    if (parts.length != 3 || parts[0].tag != 0x30) {
      throw const FormatException('Not an X.509 certificate');
    }
    final List<_Element> tbs = parts[0].children(bytes);
    // version [0] is optional; then serial, signature, issuer, validity, subject, subjectPublicKeyInfo.
    final int first = tbs.isNotEmpty && tbs[0].tag == 0xa0 ? 1 : 0;
    if (tbs.length < first + 6) {
      throw const FormatException('Not an X.509 certificate');
    }
    return RsaPublicKey._fromSubjectPublicKeyInfo(bytes, tbs[first + 5]);
  }

  factory RsaPublicKey._fromSubjectPublicKeyInfo(
    Uint8List bytes,
    _Element info,
  ) {
    if (info.tag != 0x30) {
      throw const FormatException('Not a SubjectPublicKeyInfo');
    }
    final List<_Element> parts = info.children(bytes);
    if (parts.length != 2 || parts[0].tag != 0x30 || parts[1].tag != 0x03) {
      throw const FormatException('Not a SubjectPublicKeyInfo');
    }
    final List<_Element> algorithm = parts[0].children(bytes);
    if (algorithm.isEmpty ||
        algorithm[0].tag != 0x06 ||
        !_equal(algorithm[0].content(bytes), _rsaEncryption)) {
      throw const FormatException('Not an RSA key');
    }
    final _Element bitString = parts[1];
    if (bitString.end - bitString.start < 1 || bytes[bitString.start] != 0) {
      throw const FormatException('Bad public key bit string');
    }
    final _Element key = _Element.read(
      bytes,
      bitString.start + 1,
      bitString.end,
    );
    if (key.tag != 0x30 || key.end != bitString.end) {
      throw const FormatException('Not an RSAPublicKey');
    }
    final List<_Element> numbers = key.children(bytes);
    if (numbers.length != 2) {
      throw const FormatException('Not an RSAPublicKey');
    }
    return RsaPublicKey(
      numbers[0].positiveInteger(bytes),
      numbers[1].positiveInteger(bytes),
    );
  }

  /// The modulus n.
  final BigInt modulus;

  /// The public exponent e.
  final BigInt exponent;

  /// Whether [signature] is the RS256 signature of [data] by the private half of this key.
  bool verifyRs256(List<int> data, List<int> signature) {
    final int length = (modulus.bitLength + 7) ~/ 8;
    if (signature.length != length) {
      return false;
    }
    final BigInt s = _toBigInt(signature);
    if (s >= modulus) {
      return false;
    }
    final List<int> digest = sha256.convert(data).bytes;
    final int padding = length - _sha256DigestInfo.length - digest.length - 3;
    if (padding < 8) {
      return false;
    }
    final Uint8List expected = Uint8List(length)
      ..[1] = 0x01
      ..fillRange(2, 2 + padding, 0xff)
      ..setRange(
        3 + padding,
        3 + padding + _sha256DigestInfo.length,
        _sha256DigestInfo,
      )
      ..setRange(length - digest.length, length, digest);
    BigInt m = s.modPow(exponent, modulus);
    final Uint8List actual = Uint8List(length);
    final BigInt mask = BigInt.from(0xff);
    for (int i = length - 1; i >= 0; i--) {
      actual[i] = (m & mask).toInt();
      m = m >> 8;
    }
    return _equal(actual, expected);
  }
}

BigInt _toBigInt(List<int> bytes) {
  BigInt value = BigInt.zero;
  for (final int byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// One DER element: its tag and where its content is.
class _Element {
  _Element(this.tag, this.start, this.end);

  /// Reads the element that starts at [offset] and must end at or before [limit].
  factory _Element.read(Uint8List bytes, int offset, int limit) {
    if (offset + 2 > limit) {
      throw const FormatException('Truncated DER');
    }
    final int tag = bytes[offset];
    if (tag & 0x1f == 0x1f) {
      throw const FormatException('Unsupported DER tag');
    }
    int length = bytes[offset + 1];
    int start = offset + 2;
    if (length & 0x80 != 0) {
      final int count = length & 0x7f;
      if (count == 0 || count > 4 || start + count > limit) {
        throw const FormatException('Bad DER length');
      }
      length = 0;
      for (int i = 0; i < count; i++) {
        length = (length << 8) | bytes[start + i];
      }
      start += count;
    }
    if (length < 0 || start + length > limit) {
      throw const FormatException('Truncated DER');
    }
    return _Element(tag, start, start + length);
  }

  final int tag;
  final int start;
  final int end;

  Uint8List content(Uint8List bytes) =>
      Uint8List.sublistView(bytes, start, end);

  List<_Element> children(Uint8List bytes) {
    final List<_Element> result = <_Element>[];
    int offset = start;
    while (offset < end) {
      final _Element child = _Element.read(bytes, offset, end);
      result.add(child);
      offset = child.end;
    }
    return result;
  }

  BigInt positiveInteger(Uint8List bytes) {
    if (tag != 0x02 || end == start || bytes[start] & 0x80 != 0) {
      throw const FormatException('Not a positive DER integer');
    }
    return _toBigInt(content(bytes));
  }
}

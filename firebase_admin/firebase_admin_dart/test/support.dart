// Test helpers: throwaway RSA keys made in Dart at run time (nothing secret is committed), their PEM and X.509
// encodings, a service account key file around them, and JWTs signed with them.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final Random _random = Random(20261116);

BigInt _randomBits(int bits) {
  BigInt value = BigInt.zero;
  for (int i = 0; i < bits ~/ 8; i++) {
    value = (value << 8) | BigInt.from(_random.nextInt(256));
  }
  return value | (BigInt.one << (bits - 1)) | BigInt.one;
}

bool _isProbablePrime(BigInt n) {
  const List<int> small = <int>[2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37];
  for (final int p in small) {
    if (n % BigInt.from(p) == BigInt.zero) {
      return n == BigInt.from(p);
    }
  }
  BigInt d = n - BigInt.one;
  int s = 0;
  while (d.isEven) {
    d >>= 1;
    s++;
  }
  for (final int a in small) {
    BigInt x = BigInt.from(a).modPow(d, n);
    if (x == BigInt.one || x == n - BigInt.one) {
      continue;
    }
    bool composite = true;
    for (int i = 1; i < s; i++) {
      x = x.modPow(BigInt.two, n);
      if (x == n - BigInt.one) {
        composite = false;
        break;
      }
    }
    if (composite) {
      return false;
    }
  }
  return true;
}

BigInt _prime(int bits, BigInt e) {
  while (true) {
    final BigInt candidate = _randomBits(bits);
    if (_isProbablePrime(candidate) &&
        (candidate - BigInt.one).gcd(e) == BigInt.one) {
      return candidate;
    }
  }
}

/// A throwaway RSA key pair (1024 bits by default: fast to make, enough for tests).
class TestKey {
  TestKey([int bits = 1024]) {
    p = _prime(bits ~/ 2, e);
    do {
      q = _prime(bits ~/ 2, e);
    } while (q == p);
    n = p * q;
    d = e.modInverse((p - BigInt.one) * (q - BigInt.one));
  }

  final BigInt e = BigInt.from(65537);
  late final BigInt p;
  late final BigInt q;
  late final BigInt n;
  late final BigInt d;

  int get length => (n.bitLength + 7) ~/ 8;

  /// Textbook RS256 (no CRT, no blinding): independent of the signer under test.
  Uint8List sign(List<int> data) {
    const List<int> prefix = <int>[
      0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, //
      0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
    ];
    final List<int> digest = sha256.convert(data).bytes;
    final int padding = length - prefix.length - digest.length - 3;
    final List<int> encoded = <int>[
      0, 1, ...List<int>.filled(padding, 0xff), 0, ...prefix, ...digest, //
    ];
    return bytesOf(bigIntOf(encoded).modPow(d, n), length);
  }

  /// PKCS#1 RSAPrivateKey in PEM, as googleapis_auth reads it.
  String get privateKeyPem {
    final List<int> der = derSequence(<List<int>>[
      derInteger(BigInt.zero),
      derInteger(n),
      derInteger(e),
      derInteger(d),
      derInteger(p),
      derInteger(q),
      derInteger(d % (p - BigInt.one)),
      derInteger(d % (q - BigInt.one)),
      derInteger(q.modInverse(p)),
    ]);
    return pem('RSA PRIVATE KEY', der);
  }

  /// SubjectPublicKeyInfo DER.
  List<int> get publicKeyInfo => derSequence(<List<int>>[
    derSequence(<List<int>>[
      derOid(_rsaEncryption),
      <int>[0x05, 0x00],
    ]),
    derBitString(derSequence(<List<int>>[derInteger(n), derInteger(e)])),
  ]);

  /// PEM of the public key (for openssl).
  String get publicKeyPem => pem('PUBLIC KEY', publicKeyInfo);

  /// A minimal X.509 certificate of the public key, PEM. Its own signature is a dummy: the verifier only reads
  /// the key, as the Admin SDKs do.
  String get certificatePem {
    final List<int> algorithm = derSequence(<List<int>>[
      derOid(_sha256WithRsa),
      <int>[0x05, 0x00],
    ]);
    final List<int> tbs = derSequence(<List<int>>[
      <int>[0xa0, ...derLength(3), ...derInteger(BigInt.two)],
      derInteger(BigInt.from(1234)),
      algorithm,
      derSequence(<List<int>>[]),
      derSequence(<List<int>>[
        derTagged(0x17, ascii.encode('260101000000Z')),
        derTagged(0x17, ascii.encode('360101000000Z')),
      ]),
      derSequence(<List<int>>[]),
      publicKeyInfo,
    ]);
    return pem(
      'CERTIFICATE',
      derSequence(<List<int>>[
        tbs,
        algorithm,
        derBitString(<int>[1, 2, 3]),
      ]),
    );
  }

  /// A service account key file for this key.
  Map<String, Object?> serviceAccount({
    String email = 'admin@demo-test.iam.gserviceaccount.com',
  }) => <String, Object?>{
    'type': 'service_account',
    'project_id': 'demo-test',
    'private_key_id': 'throwaway',
    'private_key': privateKeyPem,
    'client_email': email,
    'client_id': '1234567890',
  };
}

const List<int> _rsaEncryption = <int>[
  0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, //
];
const List<int> _sha256WithRsa = <int>[
  0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, //
];

BigInt bigIntOf(List<int> bytes) =>
    bytes.fold(BigInt.zero, (BigInt v, int b) => (v << 8) | BigInt.from(b));

Uint8List bytesOf(BigInt value, int length) {
  final Uint8List result = Uint8List(length);
  for (int i = length - 1; i >= 0; i--) {
    result[i] = (value & BigInt.from(0xff)).toInt();
    value >>= 8;
  }
  return result;
}

List<int> derLength(int length) {
  if (length < 0x80) {
    return <int>[length];
  }
  final List<int> bytes = <int>[];
  while (length > 0) {
    bytes.insert(0, length & 0xff);
    length >>= 8;
  }
  return <int>[0x80 | bytes.length, ...bytes];
}

List<int> derTagged(int tag, List<int> content) => <int>[
  tag,
  ...derLength(content.length),
  ...content,
];

List<int> derSequence(List<List<int>> parts) =>
    derTagged(0x30, <int>[for (final List<int> part in parts) ...part]);

List<int> derOid(List<int> content) => derTagged(0x06, content);

List<int> derBitString(List<int> content) =>
    derTagged(0x03, <int>[0, ...content]);

List<int> derInteger(BigInt value) {
  List<int> bytes = value == BigInt.zero
      ? <int>[0]
      : bytesOf(value, (value.bitLength + 7) ~/ 8);
  if (bytes.first & 0x80 != 0) {
    bytes = <int>[0, ...bytes];
  }
  return derTagged(0x02, bytes);
}

String pem(String label, List<int> der) {
  final String body = base64.encode(der);
  final StringBuffer buffer = StringBuffer('-----BEGIN $label-----\n');
  for (int i = 0; i < body.length; i += 64) {
    buffer.writeln(body.substring(i, min(i + 64, body.length)));
  }
  buffer.write('-----END $label-----\n');
  return buffer.toString();
}

String b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

String segment(Map<String, Object?> json) =>
    b64url(utf8.encode(jsonEncode(json)));

Map<String, Object?> decodeJson(String part) =>
    jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(part))))
        as Map<String, Object?>;

/// A JWT signed by [key] (unsigned when [key] is null) with [header] and [payload].
String jwt(
  Map<String, Object?> header,
  Map<String, Object?> payload,
  TestKey? key,
) {
  final String input = '${segment(header)}.${segment(payload)}';
  return key == null
      ? '$input.'
      : '$input.${b64url(key.sign(ascii.encode(input)))}';
}

/// The claims of a Firebase ID token for [projectId], issued [at].
Map<String, Object?> idTokenClaims(
  DateTime at, {
  String projectId = 'demo-test',
  String uid = 'user-1',
  Map<String, Object?> extra = const <String, Object?>{},
}) {
  final int now = at.millisecondsSinceEpoch ~/ 1000;
  return <String, Object?>{
    'iss': 'https://securetoken.google.com/$projectId',
    'aud': projectId,
    'auth_time': now,
    'user_id': uid,
    'sub': uid,
    'iat': now,
    'exp': now + 3600,
    'firebase': <String, Object?>{
      'identities': <String, Object?>{},
      'sign_in_provider': 'custom',
    },
    ...extra,
  };
}

/// Why openssl tests are skipped, or null when openssl runs.
String? opensslSkip() {
  try {
    return Process.runSync('openssl', <String>['version']).exitCode == 0
        ? null
        : '`openssl version` failed';
  } on ProcessException {
    return 'openssl is not installed';
  }
}

class FakeClock {
  FakeClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

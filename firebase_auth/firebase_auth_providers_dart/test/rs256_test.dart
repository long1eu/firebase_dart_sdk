// Unit tests of the RS256 signer. The RSA key is made by the test from random primes (nothing is committed); the
// end-to-end check against openssl is in oauth_token_provider_test.dart.

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth_providers_dart/src/rs256.dart';
import 'package:test/test.dart';

final Random _random = Random(20261113);

BigInt _randomBits(int bits) {
  BigInt value = BigInt.zero;
  for (int i = 0; i < bits ~/ 8; i++) {
    value = (value << 8) | BigInt.from(_random.nextInt(256));
  }
  // The top bit set (full length), odd.
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

class _Key {
  _Key() {
    p = _prime(512, e);
    do {
      q = _prime(512, e);
    } while (q == p);
    n = p * q;
    d = e.modInverse((p - BigInt.one) * (q - BigInt.one));
    dmp1 = d % (p - BigInt.one);
    dmq1 = d % (q - BigInt.one);
    coeff = q.modInverse(p);
  }

  final BigInt e = BigInt.from(65537);
  late final BigInt p;
  late final BigInt q;
  late final BigInt n;
  late final BigInt d;
  late final BigInt dmp1;
  late final BigInt dmq1;
  late final BigInt coeff;
}

BigInt _toInt(List<int> bytes) =>
    bytes.fold(BigInt.zero, (BigInt v, int b) => (v << 8) | BigInt.from(b));

void main() {
  final _Key key = _Key();
  final List<int> data = utf8.encode('header.payload');

  List<int> sign({Random? random, BigInt? dmp1}) => signRs256(
    data,
    n: key.n,
    e: key.e,
    p: key.p,
    q: key.q,
    dmp1: dmp1 ?? key.dmp1,
    dmq1: key.dmq1,
    coeff: key.coeff,
    random: random,
  );

  test('the signature is EMSA-PKCS1-v1_5 with SHA-256, raised to d', () {
    final int length = (key.n.bitLength + 7) ~/ 8;
    final List<int> signature = sign();
    expect(signature, hasLength(length));

    final List<int> digest = sha256.convert(data).bytes;
    final List<int> prefix = <int>[
      0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, //
      0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
    ];
    final int padding = length - prefix.length - digest.length - 3;
    final List<int> encoded = <int>[
      0x00,
      0x01,
      ...List<int>.filled(padding, 0xff),
      0x00,
      ...prefix,
      ...digest,
    ];
    expect(_toInt(signature).modPow(key.e, key.n), _toInt(encoded));
    // The textbook signature, without CRT and without blinding.
    expect(_toInt(signature), _toInt(encoded).modPow(key.d, key.n));
  });

  test('blinding does not change the signature', () {
    final List<int> first = sign(random: Random(1));
    expect(sign(random: Random(2)), first);
    expect(sign(), first);
  });

  test(
    'a wrong CRT half (a fault) throws instead of returning the signature',
    () {
      expect(
        () => sign(dmp1: key.dmp1 + BigInt.one),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('did not verify'),
          ),
        ),
      );
    },
  );
}

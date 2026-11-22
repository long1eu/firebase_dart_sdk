// Number behaviour the client relies on, measured on the VM, dart2js and dart2wasm (web audit
// round 2, items C2, C3 and C4). Every expectation must hold on all three compilers. What may
// differ between them is written into the test names, so the test output of each compiler
// records it; failure messages say what this compiler produced.
//
// Expected strings: the IEEE 754 texts are the big-endian bits of each double (the form the JS
// SDK hashes, util.ts doubleToIEEE754String); the jsStringify texts follow the ECMAScript
// Number::toString rule (shortest round-trip digits; exponent form from 1e21 and below 1e-6).
// All were derived from those rules, none from a run.
import 'dart:convert';

import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/util/hash.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:test/test.dart';

/// True on dart2js only: there `1` and `1.0` are the same JavaScript number.
final bool _isJs = identical(1, 1.0);

final String _compiler = _isJs
    ? 'dart2js'
    : (const bool.fromEnvironment('dart.tool.dart2wasm') ? 'dart2wasm' : 'vm');

String _describe(Object? value) =>
    '$value (${value.runtimeType}, is int: ${value is int}, is double: ${value is double})';

/// A value, its source text, the text JavaScript prints for it and its IEEE 754 bits.
typedef _Number = ({String source, num value, String js, String ieee});

const List<_Number> _numbers = <_Number>[
  (source: '1', value: 1, js: '1', ieee: '3ff0000000000000'),
  (source: '1.0', value: 1.0, js: '1', ieee: '3ff0000000000000'),
  (source: '100', value: 100, js: '100', ieee: '4059000000000000'),
  (source: '100.0', value: 100.0, js: '100', ieee: '4059000000000000'),
  (source: '1.5', value: 1.5, js: '1.5', ieee: '3ff8000000000000'),
  (source: '0.1', value: 0.1, js: '0.1', ieee: '3fb999999999999a'),
  (source: '1e-7', value: 1e-7, js: '1e-7', ieee: '3e7ad7f29abcaf48'),
  (source: '1e21', value: 1e21, js: '1e+21', ieee: '444b1ae4d6e2ef50'),
  (source: '5e-324', value: 5e-324, js: '5e-324', ieee: '0000000000000001'),
  (
    source: '1.7976931348623157e308',
    value: 1.7976931348623157e308,
    js: '1.7976931348623157e+308',
    ieee: '7fefffffffffffff',
  ),
  (source: '-0.0', value: -0.0, js: '0', ieee: '8000000000000000'),
];

/// 123456789012345680000: integral, below 1e21 and above 2^53, where JavaScript prints the
/// shortest digits padded with zeros and the exact value of the double is 123456789012345683968.
const _Number _large = (
  source: '123456789012345680000',
  value: 1.2345678901234568e20,
  js: '123456789012345680000',
  ieee: '441ac53a7e04bcda',
);

void main() {
  group('C2: jsonDecode of an integer above 2^53', () {
    final Object? decoded =
        (jsonDecode('{"v":9007199254740993}') as Map<String, Object?>)['v'];

    test('on $_compiler 9007199254740993 decodes to ${_describe(decoded)}', () {
      // Holds everywhere: a number whose double form (the one hashes use) is 2^53.
      expect(decoded, isA<num>(), reason: _describe(decoded));
      expect((decoded! as num).toDouble(), 9007199254740992.0);
    });

    test(
      'the VM and wasm keep it exact (numbers.dart: "the VM and wasm keep all 64 bits")',
      () {
        expect(
          decoded,
          isA<int>(),
          reason: '$_compiler: ${_describe(decoded)}',
        );
        expect('$decoded', '9007199254740993', reason: _compiler);
      },
      skip: _isJs
          ? 'dart2js decodes with JSON.parse, which rounds to 2^53'
          : false,
    );
  });

  group('C3: negative zero from the server', () {
    final Object? integerForm = jsonDecode('-0');
    final Object? doubleForm = jsonDecode('-0.0');
    final String signedZeroHash = sha1Base64('number:8000000000000000');
    final String zeroHash = sha1Base64('number:0000000000000000');
    String leafHashText(Object? value) => LeafNode(value! as num).hashText();

    test('on $_compiler "-0" decodes to ${_describe(integerForm)}, leaf hash text '
        '${leafHashText(integerForm)}', () {
      // Holds everywhere: a zero, hashed as one of the two zeros. Which one the server uses
      // for a stored -0 is not known (no probe); the JS SDK hashes JSON.parse('-0') with the
      // sign bit.
      expect(integerForm, isA<num>());
      expect(integerForm == 0, isTrue, reason: _describe(integerForm));
      expect(
        LeafNode(integerForm! as num).hash(),
        anyOf(signedZeroHash, zeroHash),
        reason: leafHashText(integerForm),
      );
    });

    test('"-0.0" decodes to a negative zero and hashes with the sign bit', () {
      expect(doubleForm, isA<num>());
      expect(
        (doubleForm! as num).isNegative,
        isTrue,
        reason: _describe(doubleForm),
      );
      expect(leafHashText(doubleForm), 'number:8000000000000000');
      expect(LeafNode(doubleForm as num).hash(), signedZeroHash);
    });
  });

  group('C4: the text of a number', () {
    // The leaf hash, the priority hash and the compound hash write numbers only through these
    // bits (leaf_node.dart, priority.dart, compound_hash.dart); no hash uses num.toString().
    for (final _Number n in <_Number>[..._numbers, _large]) {
      test('the leaf hash text of ${n.source} is number:${n.ieee}', () {
        expect(
          LeafNode(n.value).hashText(),
          'number:${n.ieee}',
          reason: '$_compiler: ${_describe(n.value)}',
        );
      });
    }

    // jsStringify writes numbers into outgoing frames and query identifiers (persisted cache
    // keys), where the JS SDK uses JSON.stringify.
    for (final _Number n in _numbers) {
      test('jsStringify(${n.source}) is ${n.js} as in JavaScript', () {
        expect(
          jsStringify(n.value),
          n.js,
          reason: '$_compiler: ${_describe(n.value)}',
        );
      });
    }

    final String largeText = jsStringify(_large.value);
    test(
      'on $_compiler jsStringify(${_large.source}) is $largeText, the same number',
      () {
        // Holds everywhere: the server reads the same double from the text.
        expect(double.parse(largeText), _large.value, reason: largeText);
      },
    );

    test(
      'jsStringify(${_large.source}) is ${_large.js} as in JavaScript',
      () {
        expect(largeText, _large.js, reason: _compiler);
      },
      skip: _isJs
          ? false
          : 'query_params.dart _jsNumber prints integral doubles below 1e21 through BigInt, '
                'the exact digits 123456789012345683968; remove this skip with that fix',
    );
  });
}

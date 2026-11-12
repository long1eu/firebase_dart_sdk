// Copyright 2024 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Ported from upstream UtilTest.compareUtf8StringsShouldReturnCorrectValue
// (main): compares compareUtf8Strings() with a byte-wise comparison of the
// UTF-8 encodings over a million random string pairs.

import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore_vm/src/firebase/firestore/util/util.dart';
import 'package:test/test.dart';

/// Lexicographic comparison of unsigned bytes (ByteString.compare semantics).
int compareByteStrings(List<int> a, List<int> b) {
  final int n = min(a.length, b.length);
  for (int i = 0; i < n; i++) {
    final int c = a[i].compareTo(b[i]);
    if (c != 0) {
      return c;
    }
  }
  return a.length.compareTo(b.length);
}

String signName(int value) {
  if (value < 0) {
    return 'a negative value';
  } else if (value > 0) {
    return 'a positive value';
  } else {
    return '0';
  }
}

class StringGenerator {
  StringGenerator(int seed,
      {this.surrogatePairProbability = 0.33, this.maxLength = 20})
      : rnd = Random(seed);

  static const int minHighSurrogate = 0xD800;
  static const int maxHighSurrogate = 0xDBFF;
  static const int minLowSurrogate = 0xDC00;
  static const int maxLowSurrogate = 0xDFFF;

  final Random rnd;
  final double surrogatePairProbability;
  final int maxLength;

  String next() {
    final int length = rnd.nextInt(maxLength + 1);
    final StringBuffer sb = StringBuffer();
    int written = 0; // UTF-16 code units, like StringBuilder.length() in Java
    while (written < length) {
      final int codePoint = _nextCodePoint();
      final String s = String.fromCharCode(codePoint);
      sb.write(s);
      written += s.length;
    }
    return sb.toString();
  }

  bool _isNextSurrogatePair() {
    if (surrogatePairProbability == 0.0) {
      return false;
    } else if (surrogatePairProbability == 1.0) {
      return true;
    }
    return rnd.nextDouble() < surrogatePairProbability;
  }

  int _nextCodePoint() {
    return _isNextSurrogatePair()
        ? _nextSurrogateCodePoint()
        : _nextNonSurrogateCodePoint();
  }

  int _nextSurrogateCodePoint() {
    final int high =
        rnd.nextInt(maxHighSurrogate - minHighSurrogate + 1) + minHighSurrogate;
    final int low =
        rnd.nextInt(maxLowSurrogate - minLowSurrogate + 1) + minLowSurrogate;
    return 0x10000 + ((high - minHighSurrogate) << 10) + (low - minLowSurrogate);
  }

  int _nextNonSurrogateCodePoint() {
    int codePoint;
    do {
      codePoint = rnd.nextInt(0x10000); // BMP range
    } while (codePoint >= minHighSurrogate && codePoint <= maxLowSurrogate);
    return codePoint;
  }
}

void main() {
  test('compareUtf8StringsShouldReturnCorrectValue', () {
    final List<String> errors = <String>[];
    final int seed = Random().nextInt(0x7fffffff);
    int passCount = 0;
    final StringGenerator stringGenerator = StringGenerator(29750468);
    for (int i = 0; i < 1000000 && errors.length < 10; i++) {
      final String prefix = stringGenerator.next();
      final String s1 = prefix + stringGenerator.next();
      final String s2 = prefix + stringGenerator.next();

      final int actual = compareUtf8Strings(s1, s2);
      final int expected =
          compareByteStrings(utf8.encode(s1), utf8.encode(s2));

      if (actual.sign == expected.sign) {
        passCount++;
      } else {
        errors.add('compareUtf8Strings(s1="$s1", s2="$s2") returned '
            '${signName(actual)} ($actual), but expected '
            '${signName(expected)} (i=$i, s1.length=${s1.length}, '
            's2.length=${s2.length})');
      }
    }

    if (errors.isNotEmpty) {
      final StringBuffer sb = StringBuffer();
      sb.write('${errors.length} test cases failed, ');
      sb.write('$passCount test cases passed, ');
      sb.write('seed=$seed;');
      for (int i = 0; i < errors.length; i++) {
        sb.write('\nerrors[$i]: ${errors[i]}');
      }
      fail(sb.toString());
    }
  });

  // The remaining main UtilTest cases test Util.diffCollections and
  // Util.firstNEntries, which the port does not have.
  for (final String name in <String>[
    'testDiffCollectionsWithMissingElement',
    'testDiffCollectionsWithAddedElement',
    'testDiffCollectionsWithoutOrdering',
    'testDiffCollectionsWithEmptyLists',
  ]) {
    test(name,
        skip: 'Util.diffCollections is not implemented in the port', () {});
  }
  test('testFirstNEntries',
      skip: 'Util.firstNEntries is not implemented in the port', () {});
}

// NOTICE: the cases of this file are taken from the appsup firebase_dart package
// (packages/firebase_dart/test/database/hash_test.dart and treestructureddata_test.dart,
// appsup-firebase_dart 912beb1), which is distributed under this license:
//
//   Copyright (c) 2015, Rik Bellens.
//   All rights reserved.
//
//   Redistribution and use in source and binary forms, with or without modification, are permitted
//   provided that the following conditions are met:
//       * Redistributions of source code must retain the above copyright notice, this list of
//         conditions and the following disclaimer.
//       * Redistributions in binary form must reproduce the above copyright notice, this list of
//         conditions and the following disclaimer in the documentation and/or other materials
//         provided with the distribution.
//       * Neither the name of the <organization> nor the names of its contributors may be used to
//         endorse or promote products derived from this software without specific prior written
//         permission.
//
//   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
//   IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
//   FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE
//   FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
//   BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
//   OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
//   STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// Cases taken: 'Hash for string', 'Hash for string with special chars', 'Hash for bool' (hash_test),
// and 'TreeStructuredData.toJson' (treestructureddata_test: export form, plain form, array
// conversion). Not taken: the IndexedTreeStructuredData tests (appsup-specific classes), the
// performance test.
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('hash', () {
    test('Hash for string', () {
      expect(n('nl').hash(), 'lzXmvmvvpskRQUDqDuTMvZE2AQI=');
      expect(n('default config').hash(), 'wvI1cAKcFCSEHyb527WMjwKCR/o=');
    });
    test('Hash for string with special chars', () {
      expect(n('à').hash(), '31pfWlkApe+5G1/vDg375CZ+I2M=');
    });
    test('Hash for bool', () {
      expect(n(true).hash(), 'E5z61QM0lN/U2WsOnusszCTkR8M=');
      expect(n(false).hash(), 'aSSNoqcS4oQwJ2xxH20rvpp3zP0=');
    });
  });

  group('toJson', () {
    final v = {
      '.priority': '1',
      'hello': 'world',
      'object': {'.priority': 2, 'test': 1},
      'number': {'.priority': 3, '.value': 1},
    };

    test('export form keeps priorities', () {
      expect(nodeFromJson(v).toJson(exportFormat: true), v);
    });

    test('plain form drops priorities', () {
      expect(nodeFromJson(v).toJson(), {
        'hello': 'world',
        'object': {'test': 1},
        'number': 1,
      });
    });

    test('lists round trip as lists', () {
      final x = {
        'hello': 'world',
        'object': ['test', 'test2'],
      };
      expect(nodeFromJson(x).toJson(), x);
    });

    test('lists with null holes round trip as lists', () {
      final z = {
        'hello': 'world',
        'object': [null, 'test', null, 'test2'],
      };
      expect(nodeFromJson(z).toJson(), z);
    });

    test('integer keys of a dense enough object come out as a list', () {
      final y = {
        'hello': 'world',
        'object': {'1': 'test', '3': 'test2'},
      };
      expect(nodeFromJson(y).toJson(), {
        'hello': 'world',
        'object': [null, 'test', null, 'test2'],
      });
    });

    test('integer keys of a sparse object stay an object', () {
      final z2 = {
        'hello': 'world',
        'object': [null, 'test', null, null, 'test2'],
      };
      final y2 = {
        'hello': 'world',
        'object': {'1': 'test', '4': 'test2'},
      };
      expect(nodeFromJson(z2).toJson(), y2);
      expect(nodeFromJson(y2).toJson(), y2);
    });
  });
}

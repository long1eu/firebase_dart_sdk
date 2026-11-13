// Copyright 2026 Google LLC
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

// Ported from the JS SDK's test/unit/model/path.test.ts.

import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

ResourcePath _path(List<String> segments) =>
    ResourcePath.fromSegments(segments);

void expectEqual(List<String> s1, List<String> s2) {
  expect(_path(s1).compareTo(_path(s2)), 0);
}

void expectLess(List<String> s1, List<String> s2) {
  expect(_path(s1).compareTo(_path(s2)), -1);
  expect(_path(s2).compareTo(_path(s1)), 1);
}

void main() {
  test('can be constructed', () {
    _path(<String>['rooms', 'Eros', 'messages']);
  });

  test('can index into itself', () {
    final ResourcePath path = _path(<String>['rooms', 'Eros', 'messages']);
    expect(path.getSegment(0), 'rooms');
    expect(path.getSegment(1), 'Eros');
    expect(path.getSegment(2), 'messages');
  });

  test(
    'can be constructed with offsets',
    skip:
        'the port has no offset constructor; popFirst(n) is covered by '
        '"can pop front repeatedly"',
    () {},
  );

  test('can pop front repeatedly', () {
    final ResourcePath path = _path(<String>['rooms', 'Eros', 'messages']);

    expect(path.popFirst(), _path(<String>['Eros', 'messages']));
    expect(path.popFirst().popFirst(), _path(<String>['messages']));
    expect(path.popFirst().popFirst().popFirst(), _path(<String>[]));
    expect(path.popFirst(0), _path(<String>['rooms', 'Eros', 'messages']));
    expect(path.popFirst(1), _path(<String>['Eros', 'messages']));
    expect(path.popFirst(2), _path(<String>['messages']));
    expect(path.popFirst(3), _path(<String>[]));
    // unmodified original
    expect(path, _path(<String>['rooms', 'Eros', 'messages']));
  });

  test('can yield the last segment', () {
    final ResourcePath path = _path(<String>['rooms', 'Eros', 'messages']);

    expect(path.getLastSegment(), 'messages');
    expect(path.popLast().getLastSegment(), 'Eros');
    expect(path.popLast().popLast().getLastSegment(), 'rooms');
  });

  test('can create child path', () {
    final ResourcePath p = path('rooms');

    expect(p.appendSegment('eros'), path('rooms/eros'));
    expect(p.appendSegment('eros').appendSegment('1'), path('rooms/eros/1'));
    // unmodified original
    expect(p, path('rooms'));
  });

  test('can pop last repeatedly', () {
    final ResourcePath path = _path(<String>['rooms', 'Eros', 'messages']);

    expect(path.popLast(), _path(<String>['rooms', 'Eros']));
    expect(path.popLast().popLast(), _path(<String>['rooms']));
    expect(path.popLast().popLast().popLast(), _path(<String>[]));

    // original remains unmodified
    expect(path, _path(<String>['rooms', 'Eros', 'messages']));
  });

  test('compares correctly', () {
    expectEqual(<String>[], <String>[]);
    expectEqual(<String>['a'], <String>['a']);
    expectEqual(<String>['a', 'b', 'c'], <String>['a', 'b', 'c']);

    expectLess(<String>[], <String>['a']);
    expectLess(<String>['a'], <String>['b']);
    expectLess(<String>['a'], <String>['a', 'b']);
  });

  test('determines prefix correctly', () {
    final ResourcePath empty = _path(<String>[]);
    final ResourcePath a = _path(<String>['a']);
    final ResourcePath ab = _path(<String>['a', 'b']);
    final ResourcePath abc = _path(<String>['a', 'b', 'c']);
    final ResourcePath b = _path(<String>['b']);
    final ResourcePath ba = _path(<String>['b', 'a']);

    expect(empty.isPrefixOf(a), isTrue);
    expect(empty.isPrefixOf(ab), isTrue);
    expect(empty.isPrefixOf(abc), isTrue);
    expect(empty.isPrefixOf(empty), isTrue);
    expect(empty.isPrefixOf(b), isTrue);
    expect(empty.isPrefixOf(ba), isTrue);

    expect(a.isPrefixOf(a), isTrue);
    expect(a.isPrefixOf(ab), isTrue);
    expect(a.isPrefixOf(abc), isTrue);
    expect(a.isPrefixOf(empty), isFalse);
    expect(a.isPrefixOf(b), isFalse);
    expect(a.isPrefixOf(ba), isFalse);

    expect(ab.isPrefixOf(a), isFalse);
    expect(ab.isPrefixOf(ab), isTrue);
    expect(ab.isPrefixOf(abc), isTrue);
    expect(ab.isPrefixOf(empty), isFalse);
    expect(ab.isPrefixOf(b), isFalse);
    expect(ab.isPrefixOf(ba), isFalse);

    expect(abc.isPrefixOf(a), isFalse);
    expect(abc.isPrefixOf(ab), isFalse);
    expect(abc.isPrefixOf(abc), isTrue);
    expect(abc.isPrefixOf(empty), isFalse);
    expect(abc.isPrefixOf(b), isFalse);
    expect(abc.isPrefixOf(ba), isFalse);
  });

  test('escapes FieldPath with segments', () {
    final FieldPath path = FieldPath.fromSegments(<String>['\\foo\\.`bar`']);
    expect(path.canonicalString, '`\\\\foo\\\\.\\`bar\\``');
  });

  test('can be constructed from field path.', () {
    final FieldPath path = FieldPath.fromServerFormat('foo\\..bar\\\\.baz');
    expect(path.segments, <String>['foo.', 'bar\\', 'baz']);
  });

  group('fails to construct from invalid field path', () {
    for (final String bad in <String>[
      '',
      'foo\\',
      'foo\\x',
      'foo.',
      '.foo',
      'foo..bar',
    ]) {
      test(
        '"$bad"',
        skip: bad == 'foo\\x'
            ? 'like the Android SDK, the port accepts any escaped character '
                  'in a server-format path; the JS SDK only accepts \\\\, \\. '
                  'and \\`'
            : null,
        () {
          expect(() => FieldPath.fromServerFormat(bad), throwsArgumentError);
        },
      );
    }
  });
}

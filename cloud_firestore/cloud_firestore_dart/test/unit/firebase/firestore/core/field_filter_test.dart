// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

/// Unit tests for the [FieldFilter] family (equality, matching and operator
/// dispatch), including the operators the port gained after the sync point
/// (not-equal, not-in). Modelled on upstream QueryTest/FilterTest.
void main() {
  Document d(String path, [Object? a, bool hasA = true]) =>
      doc(path, 0, hasA ? map<Object?>(<Object?>['a', a]) : map());

  group('factory dispatch', () {
    test('picks the specialised filter classes', () {
      expect(filter('a', '==', 1), isA<FieldFilter>());
      expect(filter('a', 'array-contains', 1), isA<ArrayContainsFilter>());
      expect(filter('a', 'in', <int>[1]), isA<InFilter>());
      expect(filter('a', 'not-in', <int>[1]), isA<NotInFilter>());
      expect(filter('a', 'array-contains-any', <int>[1]),
          isA<ArrayContainsAnyFilter>());
      expect(filter('__name__', '==', ref('c/1')), isA<KeyFieldFilter>());
      expect(filter('__name__', 'in', <Object>[ref('c/1')]),
          isA<KeyFieldInFilter>());
      expect(filter('__name__', 'not-in', <Object>[ref('c/1')]),
          isA<KeyFieldNotInFilter>());
    });

    test('isInequality', () {
      for (final String op in <String>['<', '<=', '>', '>=', '!=']) {
        expect(filter('a', op, 1).isInequality, isTrue,
            reason: op);
      }
      expect(filter('a', 'not-in', <int>[1]).isInequality,
          isTrue);
      for (final String op in <String>['==', 'array-contains']) {
        expect(filter('a', op, 1).isInequality, isFalse,
            reason: op);
      }
      expect(
          filter('a', 'in', <int>[1]).isInequality, isFalse);
      expect(
          filter('a', 'array-contains-any', <int>[1])
              .isInequality,
          isFalse);
    });
  });

  group('matches', () {
    test('comparison operators only compare values of the same type', () {
      final Document n = d('c/n', 5);
      final Document dbl = d('c/dbl', 5.5);
      final Document s = d('c/s', 'x');
      final Document nl = d('c/nl', null);
      final Document missing = d('c/m', null, false);

      expect(filter('a', '<', 6).matches(n), isTrue);
      expect(filter('a', '<', 5).matches(n), isFalse);
      expect(filter('a', '<=', 5).matches(n), isTrue);
      expect(filter('a', '>', 5).matches(dbl), isTrue);
      expect(filter('a', '>=', 5.5).matches(dbl), isTrue);
      expect(filter('a', '==', 5.0).matches(n), isTrue);
      // Type mismatches never match a range comparison.
      expect(filter('a', '>', 1).matches(s), isFalse);
      expect(filter('a', '<', 1).matches(s), isFalse);
      expect(filter('a', '>', 1).matches(nl), isFalse);
      expect(filter('a', '==', 1).matches(missing), isFalse);
    });

    test('not-equal matches other types but not null or missing fields', () {
      final FieldFilter f = filter('a', '!=', 5);
      expect(f.matches(d('c/1', 4)), isTrue);
      expect(f.matches(d('c/2', 5)), isFalse);
      expect(f.matches(d('c/3', 'str')), isTrue);
      expect(f.matches(d('c/4', true)), isTrue);
      expect(f.matches(d('c/5', null)), isFalse);
      expect(f.matches(d('c/6', null, false)), isFalse);
    });

    test('in matches any listed value', () {
      final Filter f = filter('a', 'in', <Object>[1, 'x']);
      expect(f.matches(d('c/1', 1)), isTrue);
      expect(f.matches(d('c/2', 'x')), isTrue);
      expect(f.matches(d('c/3', 2)), isFalse);
      expect(f.matches(d('c/4', null, false)), isFalse);
    });

    test('not-in excludes listed values, null and missing fields', () {
      final Filter f = filter('a', 'not-in', <Object>[1, 'x']);
      expect(f.matches(d('c/1', 1)), isFalse);
      expect(f.matches(d('c/2', 'x')), isFalse);
      expect(f.matches(d('c/3', 2)), isTrue);
      expect(f.matches(d('c/4', true)), isTrue);
      expect(f.matches(d('c/5', null)), isFalse);
      expect(f.matches(d('c/6', null, false)), isFalse);
    });

    test('not-in with null in the list matches nothing', () {
      final Filter f = filter('a', 'not-in', <Object?>[1, null]);
      expect(f.matches(d('c/1', 2)), isFalse);
      expect(f.matches(d('c/2', 'x')), isFalse);
      expect(f.matches(d('c/3', null)), isFalse);
    });

    test('array-contains and array-contains-any', () {
      final Filter any = filter('a', 'array-contains-any', <Object>[1, 'x']);
      final Filter one = filter('a', 'array-contains', 2);
      expect(one.matches(d('c/1', <int>[1, 2])), isTrue);
      expect(one.matches(d('c/2', <int>[1])), isFalse);
      expect(one.matches(d('c/3', 2)), isFalse);
      expect(any.matches(d('c/1', <Object>[0, 'x'])), isTrue);
      expect(any.matches(d('c/2', <Object>[0, 3])), isFalse);
      expect(any.matches(d('c/3', 'x')), isFalse);
      expect(any.matches(d('c/4', null, false)), isFalse);
    });

    test('key field filters compare document keys', () {
      final Filter eq = filter('__name__', '==', ref('c/2'));
      final Filter lt = filter('__name__', '<', ref('c/2'));
      final Filter gt = filter('__name__', '>=', ref('c/2'));
      final Filter ne = filter('__name__', '!=', ref('c/2'));
      expect(eq.matches(d('c/2')), isTrue);
      expect(eq.matches(d('c/1')), isFalse);
      expect(lt.matches(d('c/1')), isTrue);
      expect(lt.matches(d('c/2')), isFalse);
      expect(gt.matches(d('c/2')), isTrue);
      expect(gt.matches(d('c/3')), isTrue);
      expect(gt.matches(d('c/1')), isFalse);
      expect(ne.matches(d('c/1')), isTrue);
      expect(ne.matches(d('c/2')), isFalse);
    });

    test('key field in / not-in', () {
      final Filter inF =
          filter('__name__', 'in', <Object>[ref('c/1'), ref('c/3')]);
      final Filter notIn =
          filter('__name__', 'not-in', <Object>[ref('c/1'), ref('c/3')]);
      expect(inF.matches(d('c/1')), isTrue);
      expect(inF.matches(d('c/2')), isFalse);
      expect(inF.matches(d('c/3')), isTrue);
      expect(notIn.matches(d('c/1')), isFalse);
      expect(notIn.matches(d('c/2')), isTrue);
      expect(notIn.matches(d('c/3')), isFalse);
    });
  });

  group('equality', () {
    test('filters are equal when field, operator and value are', () {
      expect(filter('a', '==', 1), filter('a', '==', 1));
      expect(filter('a', '==', 1).hashCode, filter('a', '==', 1).hashCode);
      expect(filter('a', '==', 1), isNot(filter('b', '==', 1)));
      expect(filter('a', '==', 1), isNot(filter('a', '!=', 1)));
      expect(filter('a', '==', 1), isNot(filter('a', '==', 2)));
      expect(filter('a', 'in', <int>[1]), filter('a', 'in', <int>[1]));
      expect(
          filter('a', 'in', <int>[1]), isNot(filter('a', 'not-in', <int>[1])));
    });

    test('canonicalId contains field, operator and value', () {
      final String id = filter('a.b', '>=', 3).canonicalId;
      expect(id, contains('a.b'));
      expect(id, contains('>='));
      expect(id, contains('3'));
      expect(filter('a', '<', 3).canonicalId,
          isNot(filter('a', '<=', 3).canonicalId));
    });

    test('FilterOperator toString is the wire name', () {
      expect(FilterOperator.lessThan.toString(), '<');
      expect(FilterOperator.notEqual.toString(), '!=');
      expect(FilterOperator.arrayContainsAny.toString(), 'array-contains-any');
      expect(FilterOperator.NOT_IN.toString(), 'not-in');
    });
  });
}

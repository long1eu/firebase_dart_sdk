// Copyright 2026 Google LLC
//
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
// Guards the mapping from the Dart helpers to the server function names (the
// names of the JS SDK's lite-api/expressions.ts).

import 'dart:typed_data';

import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:test/test.dart';

import 'pipeline_test_util.dart';

void main() {
  final Field a = field('a');
  final pb.Value fa = fieldRef('a');
  final BooleanExpression c1 = field('x').exists();
  final BooleanExpression c2 = field('y').exists();
  final BooleanExpression c3 = field('z').exists();
  final pb.Value p1 = fn('exists', <pb.Value>[fieldRef('x')]);
  final pb.Value p2 = fn('exists', <pb.Value>[fieldRef('y')]);
  final pb.Value p3 = fn('exists', <pb.Value>[fieldRef('z')]);

  group('fields and constants', () {
    test('field', () {
      expect(encode(field('a.b')), fieldRef('a.b'));
      expect(encode(field(FieldPath.of(<String>['a', 'b.c']))),
          fieldRef('a.`b.c`'));
      expect(encode(field('__name__')), fieldRef('__name__'));
      expect(field('a.b').fieldName, 'a.b');
      expect(field('a'), field('a'));
      expect(() => field(1), throwsArgumentError);
      expect(() => field('a..b'), throwsArgumentError);
    });

    test('constants', () {
      expect(
          encode(constant(null)), pb.Value()..nullValue = pb.Value().nullValue);
      expect(encode(constant(true)), boolean(true));
      expect(encode(constant(1)), integer(1));
      expect(encode(constant(1.5)), dbl(1.5));
      expect(encode(constant('s')), str('s'));
      expect(encode(constant(const Timestamp(1, 2000))).hasTimestampValue(),
          isTrue);
      expect(encode(constant(const GeoPoint(1, 2))).hasGeoPointValue(), isTrue);
      expect(
          encode(constant(Blob(Uint8List.fromList(<int>[1])))).hasBytesValue(),
          isTrue);
      expect(encode(constant(<Object?>[1, 'a'])),
          arrayValue(<pb.Value>[integer(1), str('a')]));
      expect(encode(constant(<String, Object?>{'k': 1})),
          mapValue(<String, pb.Value>{'k': integer(1)}));
      expect(
          encode(constant(DocumentReference<Map<String, Object?>>(
              DocumentKey.fromPathString('c/d'), fakeFirestore))),
          ref('projects/new-project/databases/(default)/documents/c/d'));
    });

    test('plain operands are constants, lists and maps are functions', () {
      expect(encode(a.equal(1)), fn('equal', <pb.Value>[fa, integer(1)]));
      expect(
          encode(a.equal(<Object?>[1, field('b')])),
          fn('equal', <pb.Value>[
            fa,
            fn('array', <pb.Value>[integer(1), fieldRef('b')])
          ]));
      expect(
          encode(a.equal(<String, Object?>{'k': field('b')})),
          fn('equal', <pb.Value>[
            fa,
            fn('map', <pb.Value>[str('k'), fieldRef('b')])
          ]));
    });
  });

  test('binary and unary functions use the server names', () {
    final Map<String, Expression> binary = <String, Expression>{
      'equal': a.equal(1),
      'not_equal': a.notEqual(1),
      'less_than': a.lessThan(1),
      'less_than_or_equal': a.lessThanOrEqual(1),
      'greater_than': a.greaterThan(1),
      'greater_than_or_equal': a.greaterThanOrEqual(1),
      'add': a.add(1),
      'subtract': a.subtract(1),
      'multiply': a.multiply(1),
      'divide': a.divide(1),
      'mod': a.mod(1),
      'array_contains': a.arrayContains(1),
    };
    for (final MapEntry<String, Expression> entry in binary.entries) {
      final String name = entry.key;
      final Expression expression = entry.value;
      expect(encode(expression), fn(name, <pb.Value>[fa, integer(1)]),
          reason: name);
    }

    final Map<String, Expression> withString = <String, Expression>{
      'starts_with': a.startsWith('s'),
      'ends_with': a.endsWith('s'),
      'string_contains': a.stringContains('s'),
      'like': a.like('s'),
      'regex_match': a.regexMatch('s'),
      'regex_contains': a.regexContains('s'),
      'map_get': a.mapGet('s'),
    };
    for (final MapEntry<String, Expression> entry in withString.entries) {
      final String name = entry.key;
      final Expression expression = entry.value;
      expect(encode(expression), fn(name, <pb.Value>[fa, str('s')]),
          reason: name);
    }

    final Map<String, Expression> unary = <String, Expression>{
      'exists': a.exists(),
      'is_absent': a.isAbsent(),
      'is_error': a.isError(),
      'array_length': a.arrayLength(),
      'to_lower': a.toLower(),
      'to_upper': a.toUpper(),
      'trim': a.trim(),
      'char_length': a.charLength(),
      'document_id': a.documentId(),
    };
    for (final MapEntry<String, Expression> entry in unary.entries) {
      final String name = entry.key;
      final Expression expression = entry.value;
      expect(encode(expression), fn(name, <pb.Value>[fa]), reason: name);
    }
  });

  test('list operands are encoded as arrays', () {
    final Map<String, Expression> lists = <String, Expression>{
      'equal_any': a.equalAny(<Object?>[1, field('b')]),
      'not_equal_any': a.notEqualAny(<Object?>[1, field('b')]),
      'array_contains_any': a.arrayContainsAny(<Object?>[1, field('b')]),
      'array_contains_all': a.arrayContainsAll(<Object?>[1, field('b')]),
    };
    for (final MapEntry<String, Expression> entry in lists.entries) {
      final String name = entry.key;
      final Expression expression = entry.value;
      expect(
          encode(expression),
          fn(name, <pb.Value>[
            fa,
            arrayValue(<pb.Value>[integer(1), fieldRef('b')])
          ]),
          reason: name);
    }
    expect(encode(a.equalAny(field('list'))),
        fn('equal_any', <pb.Value>[fa, fieldRef('list')]));
    expect(() => a.equalAny(1), throwsArgumentError);
  });

  test('stringConcat', () {
    expect(encode(a.stringConcat(<Object?>['-', field('b')])),
        fn('string_concat', <pb.Value>[fa, str('-'), fieldRef('b')]));
  });

  test('logical functions', () {
    expect(encode(c1.and(c2)), fn('and', <pb.Value>[p1, p2]));
    expect(encode(and(c1, c2, <BooleanExpression>[c3])),
        fn('and', <pb.Value>[p1, p2, p3]));
    expect(encode(or(c1, c2)), fn('or', <pb.Value>[p1, p2]));
    expect(encode(c1.or(c2, <BooleanExpression>[c3])),
        fn('or', <pb.Value>[p1, p2, p3]));
    expect(encode(xor(c1, c2)), fn('xor', <pb.Value>[p1, p2]));
    expect(encode(not(c1)), fn('not', <pb.Value>[p1]));
    expect(encode(c1.not()), fn('not', <pb.Value>[p1]));
    expect(encode(conditional(c1, 'yes', field('b'))),
        fn('conditional', <pb.Value>[p1, str('yes'), fieldRef('b')]));
    expect(encode(field('flag').asBoolean()), fieldRef('flag'));
    expect(encode(field('flag').asBoolean().not()),
        fn('not', <pb.Value>[fieldRef('flag')]));
  });

  test('aggregates', () {
    pb.Value agg(AggregateFunction function) => function.toProto(encoder());

    expect(agg(countAll()), fn('count'));
    expect(agg(a.count()), fn('count', <pb.Value>[fa]));
    expect(agg(a.countDistinct()), fn('count_distinct', <pb.Value>[fa]));
    expect(agg(a.sum()), fn('sum', <pb.Value>[fa]));
    expect(agg(a.average()), fn('average', <pb.Value>[fa]));
    expect(agg(a.minimum()), fn('minimum', <pb.Value>[fa]));
    expect(agg(a.maximum()), fn('maximum', <pb.Value>[fa]));
    expect(agg(c1.countIf()), fn('count_if', <pb.Value>[p1]));
    expect(agg(countIf(c1)), fn('count_if', <pb.Value>[p1]));
    expect(agg(AggregateFunction('array_agg', <Object?>[a])),
        fn('array_agg', <pb.Value>[fa]));
    expect(a.sum().as('total').alias, 'total');
  });

  test('raw function expressions', () {
    expect(encode(FunctionExpression('timestamp_add', <Object?>[a, 'day', 1])),
        fn('timestamp_add', <pb.Value>[fa, str('day'), integer(1)]));
  });

  group('tier 2 functions', () {
    void check(Map<String, Expression> cases, List<pb.Value> rest) {
      for (final MapEntry<String, Expression> entry in cases.entries) {
        expect(encode(entry.value), fn(entry.key, <pb.Value>[fa, ...rest]),
            reason: entry.key);
      }
    }

    test('unary', () {
      check(<String, Expression>{
        'abs': a.abs(),
        'ceil': a.ceil(),
        'floor': a.floor(),
        'round': a.round(),
        'trunc': a.trunc(),
        'sqrt': a.sqrt(),
        'exp': a.exp(),
        'ln': a.ln(),
        'timestamp_to_unix_micros': a.timestampToUnixMicros(),
        'timestamp_to_unix_millis': a.timestampToUnixMillis(),
        'timestamp_to_unix_seconds': a.timestampToUnixSeconds(),
        'unix_micros_to_timestamp': a.unixMicrosToTimestamp(),
        'unix_millis_to_timestamp': a.unixMillisToTimestamp(),
        'unix_seconds_to_timestamp': a.unixSecondsToTimestamp(),
        'vector_length': a.vectorLength(),
        'array_reverse': a.arrayReverse(),
        'array_first': a.arrayFirst(),
        'array_last': a.arrayLast(),
        'map_keys': a.mapKeys(),
        'map_values': a.mapValues(),
        'map_entries': a.mapEntries(),
        'type': a.type(),
        'collection_id': a.collectionId(),
        'parent': a.parent(),
        'trim': a.trim(),
        'ltrim': a.ltrim(),
        'rtrim': a.rtrim(),
        'byte_length': a.byteLength(),
        'length': a.length(),
        'string_reverse': a.stringReverse(),
        'reverse': a.reverse(),
      }, <pb.Value>[]);
    });

    test('with one number', () {
      check(<String, Expression>{
        'round': a.round(2),
        'trunc': a.trunc(2),
        'pow': a.pow(2),
        'log': a.log(2),
        'array_get': a.arrayGet(2),
        'array_slice': a.arraySlice(2),
        'array_first_n': a.arrayFirstN(2),
        'array_last_n': a.arrayLastN(2),
        'array_index_of_all': a.arrayIndexOfAll(2),
        'string_repeat': a.stringRepeat(2),
        'substring': a.substring(2),
        'if_absent': a.ifAbsent(2),
        'if_error': a.ifError(2),
        'if_null': a.ifNull(2),
        'coalesce': a.coalesce(2),
        'maximum': a.logicalMaximum(<Object?>[2]),
        'minimum': a.logicalMinimum(<Object?>[2]),
      }, <pb.Value>[
        integer(2)
      ]);
    });

    test('with one string', () {
      check(<String, Expression>{
        'trim': a.trim('s'),
        'ltrim': a.ltrim('s'),
        'rtrim': a.rtrim('s'),
        'split': a.split('s'),
        'join': a.join('s'),
        'string_index_of': a.stringIndexOf('s'),
        'regex_find': a.regexFind('s'),
        'regex_find_all': a.regexFindAll('s'),
        'map_remove': a.mapRemove('s'),
        'is_type': a.isType('s'),
        'timestamp_trunc': a.timestampTruncate('s'),
        'timestamp_extract': a.timestampExtract('s'),
        'concat': a.concat(<Object?>['s']),
      }, <pb.Value>[
        str('s')
      ]);
    });

    test('with two arguments', () {
      check(<String, Expression>{
        'timestamp_add': a.timestampAdd('day', 1),
        'timestamp_subtract': a.timestampSubtract('day', 1),
        'map_set': a.mapSet('day', 1),
      }, <pb.Value>[
        str('day'),
        integer(1)
      ]);
      check(<String, Expression>{
        'string_replace_all': a.stringReplaceAll('x', 'y'),
        'string_replace_one': a.stringReplaceOne('x', 'y'),
        'timestamp_trunc': a.timestampTruncate('x', 'y'),
        'timestamp_extract': a.timestampExtract('x', 'y'),
      }, <pb.Value>[
        str('x'),
        str('y')
      ]);
      check(<String, Expression>{
        'substring': a.substring(1, 2),
        'array_slice': a.arraySlice(1, 2),
        'coalesce': a.coalesce(1, <Object?>[2]),
      }, <pb.Value>[
        integer(1),
        integer(2)
      ]);
      expect(encode(a.arrayIndexOf(1)),
          fn('array_index_of', <pb.Value>[fa, integer(1), str('first')]));
      expect(encode(a.arrayLastIndexOf(1)),
          fn('array_index_of', <pb.Value>[fa, integer(1), str('last')]));
    });

    test('timestampDiff reads a string start as a field', () {
      expect(encode(a.timestampDiff('start', 'day')),
          fn('timestamp_diff', <pb.Value>[fa, fieldRef('start'), str('day')]));
      expect(encode(a.timestampDiff(constant(1), 'day')),
          fn('timestamp_diff', <pb.Value>[fa, integer(1), str('day')]));
    });

    test('vectors', () {
      final pb.Value vector = mapValue(<String, pb.Value>{
        '__type__': str('__vector__'),
        'value': arrayValue(<pb.Value>[dbl(1), dbl(2)]),
      });
      check(<String, Expression>{
        'cosine_distance': a.cosineDistance(<double>[1, 2]),
        'dot_product': a.dotProduct(VectorValue(<double>[1, 2])),
        'euclidean_distance': a.euclideanDistance(<double>[1, 2]),
      }, <pb.Value>[
        vector
      ]);
      expect(encode(a.cosineDistance(field('b'))),
          fn('cosine_distance', <pb.Value>[fa, fieldRef('b')]));
      expect(() => a.cosineDistance('b'), throwsArgumentError);
    });

    test('arrays, maps and locations', () {
      expect(
          encode(a.arrayConcat(<Object?>[
            field('b'),
            <int>[1]
          ])),
          fn('array_concat', <pb.Value>[
            fa,
            fieldRef('b'),
            fn('array', <pb.Value>[integer(1)])
          ]));
      expect(
          encode(a.mapMerge(field('b'), <Object>[
            <String, Object?>{'k': 1}
          ])),
          fn('map_merge', <pb.Value>[
            fa,
            fieldRef('b'),
            fn('map', <pb.Value>[str('k'), integer(1)])
          ]));
      expect(encode(a.geoDistance(const GeoPoint(1, 2))).functionValue.name,
          'geo_distance');
    });

    test('top-level helpers', () {
      expect(encode(array(<Object?>[1, a])),
          fn('array', <pb.Value>[integer(1), fa]));
      expect(encode(map(<String, Object?>{'k': a})),
          fn('map', <pb.Value>[str('k'), fa]));
      expect(encode(currentTimestamp()), fn('current_timestamp'));
      expect(encode(rand()), fn('rand'));
    });

    test('aggregates', () {
      pb.Value agg(AggregateFunction function) => function.toProto(encoder());
      expect(agg(a.first()), fn('first', <pb.Value>[fa]));
      expect(agg(a.last()), fn('last', <pb.Value>[fa]));
      expect(agg(a.arrayAgg()), fn('array_agg', <pb.Value>[fa]));
      expect(
          agg(a.arrayAggDistinct()), fn('array_agg_distinct', <pb.Value>[fa]));
    });
  });

  test('aliases and orderings', () {
    final AliasedExpression aliased = a.add(1).as('b');
    expect(aliased.alias, 'b');
    expect(encode(aliased.expression), fn('add', <pb.Value>[fa, integer(1)]));
    expect(a.alias, 'a');
    expect(a.ascending().direction, OrderingDirection.ascending);
    expect(a.descending().direction, OrderingDirection.descending);
  });
}

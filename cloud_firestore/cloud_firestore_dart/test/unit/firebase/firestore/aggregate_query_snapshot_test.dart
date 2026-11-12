// Copyright 2022 Google LLC
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

// Ported from upstream AggregateQuerySnapshotTest and AggregateQueryTest.

import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import 'test_util.dart';

void main() {
  test('createWithCountShouldReturnInstanceWithTheGivenQueryAndCount', () {
    final AggregateQuery query = collectionReference('foo/bar/baz').count();
    final AggregateQuerySnapshot snapshot =
        AggregateQuerySnapshot(query, <String, FieldValue>{
      AggregateField.count().alias: IntegerValue.valueOf(42),
    });
    expect(snapshot.query, same(query));
    expect(snapshot.getCount(), 42);
  });

  test('testSourceMustNotBeNull',
      skip: 'AggregateQuery.get takes a non-nullable AggregateSource in Dart; '
          'a null source is rejected by the compiler',
      () {});

  test('data returns every result keyed by alias', () {
    final AggregateQuery query =
        collectionReference('coll').aggregate(<AggregateField>[
      AggregateField.count(),
      AggregateField.sum('pages'),
      AggregateField.average('rating'),
    ]);
    final AggregateQuerySnapshot snapshot =
        AggregateQuerySnapshot(query, <String, FieldValue>{
      AggregateField.count().alias: IntegerValue.valueOf(3),
      AggregateField.sum('pages').alias: IntegerValue.valueOf(150),
      AggregateField.average('rating').alias: NullValue.nullValue(),
    });
    final Map<String, Object?> data = snapshot.data();
    expect(data, <String, Object?>{
      'count': 3,
      'sum_pages': 150,
      'average_rating': null,
    });
    expect(data[AggregateField.sum('pages').alias],
        snapshot.get(AggregateField.sum('pages')));
    expect(() => data['count'] = 4, throwsUnsupportedError);
  });

  test('data converts double results', () {
    final AggregateQuery query = collectionReference('coll')
        .aggregate(<AggregateField>[AggregateField.average('rating')]);
    final AggregateQuerySnapshot snapshot =
        AggregateQuerySnapshot(query, <String, FieldValue>{
      AggregateField.average('rating').alias: DoubleValue.valueOf(4.5),
    });
    expect(snapshot.data(), <String, Object?>{'average_rating': 4.5});
  });

  test('aggregateWithAliases keys data by the user aliases', () {
    final Map<String, AggregateField> spec = <String, AggregateField>{
      'total': AggregateField.sum('pages'),
      'n': AggregateField.count(),
      'again `with` \\ odd chars.': AggregateField.sum('pages'),
      'avg': AggregateField.average('rating'),
    };
    final AggregateQuery query =
        collectionReference('coll').aggregateWithAliases(spec);
    expect(query.aliases, spec);
    // The same aggregation under two aliases is sent once.
    expect(query.aggregateFields, <AggregateField>[
      AggregateField.sum('pages'),
      AggregateField.count(),
      AggregateField.average('rating'),
    ]);

    final AggregateQuerySnapshot snapshot =
        AggregateQuerySnapshot(query, <String, FieldValue>{
      AggregateField.count().alias: IntegerValue.valueOf(3),
      AggregateField.sum('pages').alias: IntegerValue.valueOf(150),
      AggregateField.average('rating').alias: NullValue.nullValue(),
    });
    final Map<String, Object?> data = snapshot.data();
    expect(data, <String, Object?>{
      'total': 150,
      'n': 3,
      'again `with` \\ odd chars.': 150,
      'avg': null,
    });
    expect(data.keys.toList(), spec.keys.toList());
    expect(() => data['n'] = 4, throwsUnsupportedError);
    // Typed access by field keeps working.
    expect(snapshot.getCount(), 3);
    expect(snapshot.get(AggregateField.sum('pages')), 150);
  });

  test('aggregateWithAliases validation and equality', () {
    expect(
        () => collectionReference('coll')
            .aggregateWithAliases(<String, AggregateField>{}),
        throwsArgumentError);

    AggregateQuery build(String alias) => collectionReference('coll')
        .aggregateWithAliases(
            <String, AggregateField>{alias: AggregateField.count()});
    expect(build('n'), build('n'));
    expect(build('n').hashCode, build('n').hashCode);
    expect(build('n'), isNot(build('m')));
    expect(build('n'), isNot(collectionReference('coll').count()));

    // The spec is copied.
    final Map<String, AggregateField> spec = <String, AggregateField>{
      'n': AggregateField.count()
    };
    final AggregateQuery query =
        collectionReference('coll').aggregateWithAliases(spec);
    spec['m'] = AggregateField.sum('x');
    expect(query.aliases!.keys, <String>['n']);
  });
}

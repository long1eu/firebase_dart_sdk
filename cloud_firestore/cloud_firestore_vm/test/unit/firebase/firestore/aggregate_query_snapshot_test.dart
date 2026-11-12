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

import 'package:cloud_firestore_vm/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/aggregate_query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/aggregate_query_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
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
}

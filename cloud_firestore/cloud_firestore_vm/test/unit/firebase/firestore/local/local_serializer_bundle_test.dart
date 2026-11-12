// Copyright 2021 Google LLC
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

import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_vm/src/proto/index.dart' as proto;
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

// Port of the bundled query tests of the Android LocalSerializerTest.
void main() {
  final LocalSerializer serializer =
      LocalSerializer(RemoteSerializer(DatabaseId.forProject('p')));

  BundledQuery roundTrip(BundledQuery bundledQuery) {
    final proto.BundledQuery encoded =
        serializer.encodeBundledQuery(bundledQuery);
    // Through the wire format, like the SQLite bundle cache does.
    return serializer.decodeBundledQuery(
        proto.BundledQuery.fromBuffer(encoded.writeToBuffer()));
  }

  test('testEncodesBundledQuery', () {
    final BundledQuery bundledQuery =
        BundledQuery(Query(path('room')), BundledQueryLimitType.first);
    final proto.BundledQuery encoded =
        serializer.encodeBundledQuery(bundledQuery);

    expect(encoded.parent, 'projects/p/databases/(default)/documents');
    expect(encoded.structuredQuery.from.single.collectionId, 'room');
    expect(encoded.limitType, proto.BundledQuery_LimitType.FIRST);
    expect(serializer.decodeBundledQuery(encoded), bundledQuery);
    expect(roundTrip(bundledQuery), bundledQuery);
  });

  test('testEncodesLimitToLastQuery', () {
    final BundledQuery bundledQuery = BundledQuery(
        Query(path('room'), limit: 42), BundledQueryLimitType.last);
    final proto.BundledQuery encoded =
        serializer.encodeBundledQuery(bundledQuery);

    expect(encoded.limitType, proto.BundledQuery_LimitType.LAST);
    expect(encoded.structuredQuery.limit.value, 42);
    expect(roundTrip(bundledQuery), bundledQuery);
  });

  test('testEncodesCollectionGroupQuery', () {
    // The decoding of collection group targets is part of the bundles work: it used to resolve them to the
    // collection with the group's id at the root.
    final BundledQuery bundledQuery = BundledQuery(
        Query(ResourcePath.empty, collectionGroup: 'rooms', limit: 1),
        BundledQueryLimitType.first);
    final proto.BundledQuery encoded =
        serializer.encodeBundledQuery(bundledQuery);

    expect(encoded.structuredQuery.from.single.allDescendants, isTrue);
    expect(roundTrip(bundledQuery), bundledQuery);
    expect(roundTrip(bundledQuery).query.collectionGroup, 'rooms');
  });
}

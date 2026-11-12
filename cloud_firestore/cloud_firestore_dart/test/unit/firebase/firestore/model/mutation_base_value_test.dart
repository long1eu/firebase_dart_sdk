// Copyright 2019 Google LLC
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

// Ported from upstream MutationTest.testNonTransformMutationBaseValue.

import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  test('testNonTransformMutationBaseValue', () {
    final Map<String, Object> data = map(<dynamic>['foo', 'foo']);
    final Document baseDoc = doc('collection/key', 0, data);

    final Mutation set =
        setMutation('collection/key', map(<dynamic>['foo', 'bar']));
    expect(set.extractTransformBaseValue(baseDoc), isNull);

    final Mutation patch =
        patchMutation('collection/key', map(<dynamic>['foo', 'bar']));
    expect(patch.extractTransformBaseValue(baseDoc), isNull);

    final Mutation delete = deleteMutation('collection/key');
    expect(delete.extractTransformBaseValue(baseDoc), isNull);
  });
}

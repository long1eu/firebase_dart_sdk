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

import 'package:cloud_firestore_vm/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/index.dart'
    as proto_;
import 'package:cloud_firestore_vm/src/proto/index.dart' as proto;
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

/// RemoteSerializerTest cases from upstream `main` that the Dart
/// remote_serializer_test.dart does not have yet: testNotInWithNullSerialization.
void main() {
  late RemoteSerializer serializer;

  setUp(() => serializer = RemoteSerializer(DatabaseId.forDatabase('p', 'd')));

  test('testNotInWithNullSerialization', () {
    final FieldFilter inputFilter =
        filter('field', 'not-in', <Object?>[null]);
    final proto.StructuredQuery_Filter apiFilter =
        serializer.encodeUnaryOrFieldFilter(inputFilter);

    final proto.ArrayValue notInFilterValue = proto.ArrayValue()
      ..values.add(proto_.Value()..nullValue = proto.NullValue.NULL_VALUE);

    final proto.StructuredQuery_Filter expectedFilter =
        proto.StructuredQuery_Filter()
          ..fieldFilter = (proto.StructuredQuery_FieldFilter()
            ..field_1 =
                (proto.StructuredQuery_FieldReference()..fieldPath = 'field')
            ..op = proto.StructuredQuery_FieldFilter_Operator.NOT_IN
            ..value = (proto_.Value()..arrayValue = notInFilterValue));

    expect(apiFilter, expectedFilter);
    final FieldFilter roundTripped =
        serializer.decodeFieldFilter(apiFilter.fieldFilter);
    expect(roundTripped, inputFilter);
    expect(roundTripped, isA<NotInFilter>());
  });
}

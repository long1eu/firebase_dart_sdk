// Copyright 2024 Google LLC
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

import 'package:cloud_firestore_vm/cloud_firestore_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/index.dart'
    as proto_;
import 'package:test/test.dart';

void main() {
  final DatabaseId databaseId = DatabaseId.forDatabase('p', 'd');
  final UserDataConverter converter = UserDataConverter(databaseId);
  final RemoteSerializer serializer = RemoteSerializer(databaseId);

  model.FieldValue wrap(Object? v) =>
      converter.parseQueryValue(v, allowArrays: true);

  group('VectorValue', () {
    test('copies its input and exposes length / toArray', () {
      final List<double> input = <double>[1.0, 2.0, 3.0];
      final VectorValue v = FieldValue.vector(input);
      input[0] = 99.0;
      expect(v.toArray(), <double>[1.0, 2.0, 3.0]);
      expect(v.length, 3);
      v.toArray()[1] = 42.0;
      expect(v.toArray(), <double>[1.0, 2.0, 3.0]);
    });

    test('equality and hashCode', () {
      expect(FieldValue.vector(<double>[1.0, 2.0]),
          FieldValue.vector(<double>[1.0, 2.0]));
      expect(FieldValue.vector(<double>[1.0, 2.0]).hashCode,
          FieldValue.vector(<double>[1.0, 2.0]).hashCode);
      expect(FieldValue.vector(<double>[1.0, 2.0]),
          isNot(FieldValue.vector(<double>[1.0, 3.0])));
      expect(FieldValue.vector(<double>[1.0]),
          isNot(FieldValue.vector(<double>[1.0, 0.0])));
      expect(FieldValue.vector(<double>[]), FieldValue.vector(<double>[]));
    });
  });

  group('model ordering', () {
    test('type order is between arrays and maps', () {
      final model.FieldValue array = wrap(<Object>[1]);
      final model.FieldValue vector = wrap(FieldValue.vector(<double>[1.0]));
      final model.FieldValue map = wrap(<String, Object>{'a': 1});
      expect(vector, isA<model.VectorFieldValue>());
      expect(array.compareTo(vector), lessThan(0));
      expect(vector.compareTo(array), greaterThan(0));
      expect(vector.compareTo(map), lessThan(0));
      expect(map.compareTo(vector), greaterThan(0));
    });

    test('vectors compare by length first, then by values', () {
      final List<model.FieldValue> ordered = <model.FieldValue>[
        wrap(FieldValue.vector(<double>[])),
        wrap(FieldValue.vector(<double>[100.0])),
        wrap(FieldValue.vector(<double>[1.0, 2.0])),
        wrap(FieldValue.vector(<double>[1.0, 3.0])),
        wrap(FieldValue.vector(<double>[2.0, 0.0])),
        wrap(FieldValue.vector(<double>[1.0, 2.0, 0.0])),
      ];
      for (int i = 0; i < ordered.length; i++) {
        for (int j = 0; j < ordered.length; j++) {
          expect(ordered[i].compareTo(ordered[j]).sign, i.compareTo(j).sign,
              reason: 'comparing $i with $j');
        }
      }
      expect(wrap(FieldValue.vector(<double>[1.0])),
          wrap(FieldValue.vector(<double>[1.0])));
    });
  });

  group('serializer', () {
    test('encodes a vector as a reserved-key map', () {
      final proto_.Value encoded =
          serializer.encodeValue(wrap(FieldValue.vector(<double>[1.0, 2.5])));
      expect(encoded.hasMapValue(), isTrue);
      final Map<String, proto_.Value> fields = encoded.mapValue.fields;
      expect(fields.keys, unorderedEquals(<String>['__type__', 'value']));
      expect(fields['__type__']!.stringValue, '__vector__');
      expect(
          fields['value']!
              .arrayValue
              .values
              .map((proto_.Value v) => v.doubleValue),
          <double>[1.0, 2.5]);
    });

    test('round trips', () {
      final model.FieldValue v = wrap(FieldValue.vector(<double>[1.0, -2.5]));
      expect(serializer.decodeValue(serializer.encodeValue(v)), v);
    });

    test('a map with a different type marker stays a map', () {
      final proto_.Value value = proto_.Value.create()
        ..mapValue = (proto_.MapValue.create()
          ..fields['__type__'] = (proto_.Value.create()..stringValue = 'other')
          ..fields['value'] =
              (proto_.Value.create()..arrayValue = proto_.ArrayValue.create()));
      expect(serializer.decodeValue(value), isA<model.ObjectValue>());
    });

    test('vectors nested in documents round trip', () {
      final model.FieldValue doc = wrap(<String, Object>{
        'embedding': FieldValue.vector(<double>[0.5, 1.5]),
      });
      final model.FieldValue decoded =
          serializer.decodeValue(serializer.encodeValue(doc));
      expect(decoded, doc);
      expect((decoded as model.ObjectValue).value['embedding'],
          FieldValue.vector(<double>[0.5, 1.5]));
    });
  });
}

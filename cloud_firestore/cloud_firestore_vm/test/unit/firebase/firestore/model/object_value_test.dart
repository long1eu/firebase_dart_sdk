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

// Ported from upstream ObjectValueTest (main). The upstream ObjectValue is
// mutable; the port's is immutable (set/delete return a new value), so each
// step is applied to the returned value. Cases that already exist in
// field_value_test.dart (extracts fields, field mask, overwrites existing
// fields, adds new fields, implicitly creates objects, overwrites primitives
// with objects, adds to nested objects, deletes key / missing keys / nested
// keys) are not repeated here.

import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  const String fooString = 'foo';
  const String barString = 'bar';
  final FieldValue fooValue = wrap(fooString);
  final FieldValue barValue = wrap(barString);

  ObjectValue obj(List<dynamic> entries) => wrapList(entries);

  test('testSupportsEmptyObjectValues', () {
    expect(ObjectValue.empty, ObjectValue.empty);
    expect(obj(<dynamic>[]), ObjectValue.empty);
  });

  test('testOverwritesNestedFields', () {
    ObjectValue objectValue = obj(<dynamic>[
      'a',
      map<dynamic>(<dynamic>[
        'b',
        fooString,
        'c',
        map<dynamic>(<dynamic>['d', fooString])
      ])
    ]);
    objectValue = objectValue.set(field('a.b'), barValue);
    objectValue = objectValue.set(field('a.c.d'), barValue);
    expect(
        objectValue,
        obj(<dynamic>[
          'a',
          map<dynamic>(<dynamic>[
            'b',
            barString,
            'c',
            map<dynamic>(<dynamic>['d', barString])
          ])
        ]));
  });

  test('testOverwritesDeeplyNestedField', () {
    ObjectValue objectValue = obj(<dynamic>[
      'a',
      map<dynamic>(<dynamic>['b', fooString])
    ]);
    objectValue = objectValue.set(field('a.b.c'), barValue);
    expect(
        objectValue,
        obj(<dynamic>[
          'a',
          map<dynamic>(<dynamic>[
            'b',
            map<dynamic>(<dynamic>['c', barString])
          ])
        ]));
  });

  test('testOverwritesNestedObject', () {
    ObjectValue objectValue = obj(<dynamic>[
      'a',
      map<dynamic>(<dynamic>[
        'b',
        map<dynamic>(<dynamic>['c', fooString, 'd', fooString])
      ])
    ]);
    objectValue = objectValue.set(field('a.b'), barValue);
    expect(
        objectValue,
        obj(<dynamic>[
          'a',
          map<dynamic>(<dynamic>['b', 'bar'])
        ]));
  });

  test('testReplacesNestedObject', () {
    final ObjectValue singleValueObject = obj(<dynamic>['c', barString]);
    ObjectValue objectValue = obj(<dynamic>[
      'a',
      map<dynamic>(<dynamic>['b', fooString])
    ]);
    objectValue = objectValue.set(field('a'), singleValueObject);
    expect(
        objectValue,
        obj(<dynamic>[
          'a',
          map<dynamic>(<dynamic>['c', barString])
        ]));
  });

  test('testAddsMultipleNewFields', () {
    ObjectValue object = ObjectValue.empty;
    object = object.set(field('a'), wrap('a'));
    object = object.set(field('b'), wrap('b'));
    object = object.set(field('c'), wrap('c'));

    expect(object, obj(<dynamic>['a', 'a', 'b', 'b', 'c', 'c']));
  });

  test('testAddsNestedField', () {
    ObjectValue objectValue = ObjectValue.empty;
    objectValue = objectValue.set(field('a.b'), fooValue);
    objectValue = objectValue.set(field('c.d.e'), fooValue);
    expect(
        objectValue,
        obj(<dynamic>[
          'a',
          map<dynamic>(<dynamic>['b', fooString]),
          'c',
          map<dynamic>(<dynamic>[
            'd',
            map<dynamic>(<dynamic>['e', fooString])
          ])
        ]));
  });

  test('testAddsFieldInNestedObject', () {
    ObjectValue objectValue = ObjectValue.empty;
    objectValue = objectValue.set(field('a'), obj(<dynamic>['b', fooString]));
    objectValue = objectValue.set(field('a.c'), fooValue);
    expect(
        objectValue,
        obj(<dynamic>[
          'a',
          map<dynamic>(<dynamic>['b', fooString, 'c', fooString])
        ]));
  });

  test('testAddsTwoFieldsInNestedObject', () {
    ObjectValue objectValue = ObjectValue.empty;
    objectValue = objectValue.set(field('a.b'), fooValue);
    objectValue = objectValue.set(field('a.c'), fooValue);
    expect(
        objectValue,
        obj(<dynamic>[
          'a',
          map<dynamic>(<dynamic>['b', fooString, 'c', fooString])
        ]));
  });

  test('testAddDeeplyNestedFieldInNestedObject', () {
    ObjectValue objectValue = ObjectValue.empty;
    objectValue = objectValue.set(field('a.b.c.d.e.f'), fooValue);
    expect(
        objectValue,
        obj(<dynamic>[
          'a',
          map<dynamic>(<dynamic>[
            'b',
            map<dynamic>(<dynamic>[
              'c',
              map<dynamic>(<dynamic>[
                'd',
                map<dynamic>(<dynamic>[
                  'e',
                  map<dynamic>(<dynamic>['f', fooString])
                ])
              ])
            ])
          ])
        ]));
  });

  test('testAddsSingleFieldInExistingObject', () {
    ObjectValue objectValue = obj(<dynamic>['a', fooString]);
    objectValue = objectValue.set(field('b'), fooValue);
    expect(objectValue, obj(<dynamic>['a', fooString, 'b', fooString]));
  });

  test('testSetsNestedFieldMultipleTimes', () {
    ObjectValue objectValue = ObjectValue.empty;
    objectValue = objectValue.set(field('a.c'), fooValue);
    objectValue = objectValue.set(field('a'), obj(<dynamic>['b', fooString]));
    expect(
        objectValue,
        obj(<dynamic>[
          'a',
          map<dynamic>(<dynamic>['b', fooString])
        ]));
  });

  test('testDeletesNestedObject', () {
    ObjectValue objectValue = obj(<dynamic>[
      'a',
      map<dynamic>(<dynamic>[
        'b',
        map<dynamic>(<dynamic>['c', fooString, 'd', fooString]),
        'f',
        fooString
      ])
    ]);
    objectValue = objectValue.delete(field('a.b'));
    expect(
        objectValue,
        obj(<dynamic>[
          'a',
          map<dynamic>(<dynamic>['f', fooString])
        ]));
  });

  test('testAddsAndDeletesField', () {
    ObjectValue objectValue = ObjectValue.empty;
    objectValue = objectValue.set(field(fooString), fooValue);
    objectValue = objectValue.delete(field(fooString));
    expect(objectValue, obj(<dynamic>[]));
  });

  test('testAddsAndDeletesNestedField', () {
    ObjectValue objectValue = ObjectValue.empty;
    objectValue = objectValue.set(field('a.b.c'), fooValue);
    objectValue = objectValue.set(field('a.b.d'), fooValue);
    objectValue = objectValue.set(field('f.g'), fooValue);
    objectValue = objectValue.set(field('h'), fooValue);
    objectValue = objectValue.delete(field('a.b.c'));
    objectValue = objectValue.delete(field('h'));
    expect(
        objectValue,
        obj(<dynamic>[
          'a',
          map<dynamic>(<dynamic>[
            'b',
            map<dynamic>(<dynamic>['d', fooString])
          ]),
          'f',
          map<dynamic>(<dynamic>['g', fooString])
        ]));
  });

  test('testMergesExistingObject', () {
    ObjectValue objectValue = obj(<dynamic>[
      'a',
      map<dynamic>(<dynamic>['b', fooString])
    ]);
    objectValue = objectValue.set(field('a.c'), fooValue);
    expect(
        objectValue,
        obj(<dynamic>[
          'a',
          map<dynamic>(<dynamic>['b', fooString, 'c', fooString])
        ]));
  });
}

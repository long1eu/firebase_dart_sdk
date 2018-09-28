// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'package:firebase_firestore/src/firebase/firestore/field_value.dart'
    as firestore;
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/array_transform_operation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/transform_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/server_timestamp_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/string_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/timestamp_value.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart';

void main() {
  void _verifyTransform(Map<String, Object> baseData,
      Map<String, Object> transformData, Map<String, Object> expectedData) {
    final Document baseDoc = doc('collection/key', 0, baseData);
    final TransformMutation transform =
        transformMutation('collection/key', transformData);
    final MaybeDocument transformedDoc =
        transform.applyToLocalView(baseDoc, baseDoc, Timestamp.now());

    final Document expectedDoc =
        doc('collection/key', 0, expectedData, /*hasLocalMutations:*/ true);
    expect(expectedDoc, transformedDoc);
  }

  test('testAppliesSetsToDocuments', () {
    final Map<String, Object> data =
        map(<String>['foo', 'foo-value', 'baz', 'baz-value']);
    final Document baseDoc = doc('collection/key', 0, data, false);

    final Mutation set =
        setMutation('collection/key', map(<String>['bar', 'bar-value']));
    final MaybeDocument setDoc =
        set.applyToLocalView(baseDoc, baseDoc, Timestamp.now());
    expect(setDoc,
        doc('collection/key', 0, map(<String>['bar', 'bar-value']), true));
  });

  test('testAppliesPatchToDocuments', () {
    final Map<String, Object> data = map(<dynamic>[
      'foo',
      map<String>(<String>['bar', 'bar-value']),
      'baz',
      'baz-value'
    ]);
    final Document baseDoc = doc('collection/key', 0, data, false);

    final Mutation patch = patchMutation(
        'collection/key', map(<String>['foo.bar', 'new-bar-value']));
    print(patch);

    final MaybeDocument local =
        patch.applyToLocalView(baseDoc, baseDoc, Timestamp.now());
    print(local);

    final Map<String, Object> expectedData = map(<dynamic>[
      'foo',
      map<String>(<String>['bar', 'new-bar-value']),
      'baz',
      'baz-value'
    ]);
    expect(local, doc('collection/key', 0, expectedData, true));
  });

  test('testAppliesPatchWithMergeToDocuments', () {
    final MaybeDocument baseDoc = deletedDoc('collection/key', 0);
    final Mutation upsert = patchMutation(
        'collection/key',
        map(<String>['foo.bar', 'new-bar-value']),
        <FieldPath>[field('foo.bar')]);
    final MaybeDocument newDoc =
        upsert.applyToLocalView(baseDoc, baseDoc, Timestamp.now());
    final Map<String, Object> expectedData = map(<dynamic>[
      'foo',
      map<String>(<String>['bar', 'new-bar-value'])
    ]);
    expect(newDoc, doc('collection/key', 0, expectedData, true));
  });

  test('testAppliesPatchToNullDocWithMergeToDocuments', () {
    MaybeDocument baseDoc;
    final Mutation upsert = patchMutation(
        'collection/key',
        map(<String>['foo.bar', 'new-bar-value']),
        <FieldPath>[field('foo.bar')]);
    final MaybeDocument newDoc =
        upsert.applyToLocalView(baseDoc, baseDoc, Timestamp.now());
    final Map<String, Object> expectedData = map(<dynamic>[
      'foo',
      map<String>(<String>['bar', 'new-bar-value'])
    ]);
    expect(newDoc, doc('collection/key', 0, expectedData, true));
  });

  test('testDeletesValuesFromTheFieldMask', () {
    final Map<String, Object> data = map(<dynamic>[
      'foo',
      map<String>(<String>['bar', 'bar-value', 'baz', 'baz-value'])
    ]);
    final Document baseDoc = doc('collection/key', 0, data, false);

    final DocumentKey key = TestUtil.key('collection/key');
    final FieldMask mask = FieldMask(<FieldPath>[field('foo.bar')]);
    final Mutation patch =
        PatchMutation(key, ObjectValue.empty, mask, Precondition.none);

    final MaybeDocument patchDoc =
        patch.applyToLocalView(baseDoc, baseDoc, Timestamp.now());
    final Map<String, Object> expectedData = map(<dynamic>[
      'foo',
      map<String>(<String>['baz', 'baz-value'])
    ]);
    expect(patchDoc, doc('collection/key', 0, expectedData, true));
  });

  test('testPatchesPrimitiveValue', () {
    final Map<String, Object> data =
        map(<String>['foo', 'foo-value', 'baz', 'baz-value']);
    final Document baseDoc = doc('collection/key', 0, data, false);

    final Mutation patch = patchMutation(
        'collection/key', map(<String>['foo.bar', 'new-bar-value']));
    final MaybeDocument patchedDoc =
        patch.applyToLocalView(baseDoc, baseDoc, Timestamp.now());
    final Map<String, Object> expectedData = map(<dynamic>[
      'foo',
      map<String>(<String>['bar', 'new-bar-value']),
      'baz',
      'baz-value'
    ]);
    expect(patchedDoc, doc('collection/key', 0, expectedData, true));
  });

  test('testPatchingDeletedDocumentsDoesNothing', () {
    final MaybeDocument baseDoc = deletedDoc('collection/key', 0);
    final Mutation patch =
        patchMutation('collection/key', map(<String>['foo', 'bar']));
    final MaybeDocument patchedDoc =
        patch.applyToLocalView(baseDoc, baseDoc, Timestamp.now());
    expect(patchedDoc, baseDoc);
  });

  test('testAppliesLocalServerTimestampTransformsToDocuments', () {
    final Map<String, Object> data = map(<dynamic>[
      'foo',
      map<String>(<String>['bar', 'bar-value']),
      'baz',
      'baz-value'
    ]);
    final Document baseDoc = doc('collection/key', 0, data, false);

    final Timestamp timestamp = Timestamp.now();
    final Mutation transform = transformMutation('collection/key',
        map(<dynamic>['foo.bar', firestore.FieldValue.serverTimestamp]));
    final MaybeDocument transformedDoc =
        transform.applyToLocalView(baseDoc, baseDoc, timestamp);

    // Server timestamps aren't parsed, so we manually insert it.
    ObjectValue expectedData = wrapObject(map(<dynamic>[
      'foo',
      map<String>(<String>['bar', '<server-timestamp>']),
      'baz',
      'baz-value'
    ]));
    expectedData = expectedData.set(field('foo.bar'),
        ServerTimestampValue(timestamp, StringValue.valueOf('bar-value')));

    final Document expectedDoc = Document(
        key('collection/key'),
        version(0),
        expectedData,
        /*hasLocalMutations:*/
        true);
    expect(transformedDoc, expectedDoc);
  });

  // NOTE: This is more a test of UserDataConverter code than Mutation code but
  // we don't have unit tests for it currently. We could consider removing this
  // test once we have integration tests.
  test('testCreateArrayUnionTransform', () {
    final TransformMutation transform = transformMutation(
        'collection/key',
        map(<dynamic>[
          'a',
          firestore.FieldValue.arrayUnion(<String>['tag']),
          'bar.baz',
          firestore.FieldValue.arrayUnion(<dynamic>[
            true,
            map<dynamic>(<dynamic>[
              'nested',
              map<dynamic>(<dynamic>[
                'a',
                <int>[1, 2]
              ])
            ])
          ])
        ]));
    expect(transform.fieldTransforms.length, 2);

    final FieldTransform first = transform.fieldTransforms.first;
    expect(first.fieldPath, field('a'));
    expect(first.operation,
        ArrayTransformOperationUnion(<FieldValue>[wrap('tag')]));

    final FieldTransform second = transform.fieldTransforms[1];
    expect(second.fieldPath, field('bar.baz'));
    expect(
        second.operation,
        ArrayTransformOperationUnion(<FieldValue>[
          wrap(true),
          wrapObject(map(<dynamic>[
            'nested',
            map<dynamic>(<dynamic>[
              'a',
              <int>[1, 2]
            ])
          ]))
        ]));
  });

  // NOTE: This is more a test of UserDataConverter code than Mutation code but
  // we don't have unit tests for it currently. We could consider removing this
  // test once we have integration tests.
  test('testCreateArrayRemoveTransform', () {
    final TransformMutation transform = transformMutation(
        'collection/key',
        map(<dynamic>[
          'foo',
          firestore.FieldValue.arrayRemove(<String>['tag'])
        ]));
    expect(transform.fieldTransforms.length, 1);

    final FieldTransform first = transform.fieldTransforms.first;
    expect(first.fieldPath, field('foo'));
    expect(first.operation,
        ArrayTransformOperationRemove(<FieldValue>[wrap('tag')]));
  });

  test('testAppliesLocalArrayUnionTransformToMissingField', () {
    final Map<String, Object> baseDoc = map();
    final Map<String, Object> transform = map(<dynamic>[
      'missing',
      firestore.FieldValue.arrayUnion(<int>[1, 2])
    ]);
    final Map<String, Object> expected = map(<dynamic>[
      'missing',
      <int>[1, 2]
    ]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesLocalArrayUnionTransformToNonArrayField', () {
    final Map<String, Object> baseDoc = map(<dynamic>['nonArray', 42]);
    final Map<String, Object> transform = map(<dynamic>[
      'nonArray',
      firestore.FieldValue.arrayUnion(<int>[1, 2])
    ]);
    final Map<String, Object> expected = map(<dynamic>[
      'nonArray',
      <int>[1, 2]
    ]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesLocalArrayUnionTransformWithNonExistingElements', () {
    final Map<String, Object> baseDoc = map(<dynamic>[
      'array',
      <int>[1, 3]
    ]);
    final Map<String, Object> transform = map(<dynamic>[
      'array',
      firestore.FieldValue.arrayUnion(<int>[2, 4])
    ]);
    final Map<String, Object> expected = map(<dynamic>[
      'array',
      <int>[1, 3, 2, 4]
    ]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesLocalArrayUnionTransformWithExistingElements', () {
    final Map<String, Object> baseDoc = map(<dynamic>[
      'array',
      <int>[1, 3]
    ]);
    final Map<String, Object> transform = map(<dynamic>[
      'array',
      firestore.FieldValue.arrayUnion(<int>[1, 3])
    ]);
    final Map<String, Object> expected = map(<dynamic>[
      'array',
      <int>[1, 3]
    ]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesLocalArrayUnionTransformWithDuplicateExistingElements', () {
    // Duplicate entries in your existing array should be preserved.
    final Map<String, Object> baseDoc = map(<dynamic>[
      'array',
      <int>[1, 2, 2, 3]
    ]);
    final Map<String, Object> transform =
        map(<dynamic>['array', firestore.FieldValue.arrayUnion(<int>[])]);
    final Map<String, Object> expected = map(<dynamic>[
      'array',
      <int>[1, 2, 2, 3]
    ]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesLocalArrayUnionTransformWithDuplicateUnionElements', () {
    // Duplicate entries in your union array should only be added once.
    final Map<String, Object> baseDoc = map(<dynamic>[
      'array',
      <int>[1, 3]
    ]);
    final Map<String, Object> transform = map(<dynamic>[
      'array',
      firestore.FieldValue.arrayUnion(<int>[2, 2])
    ]);
    final Map<String, Object> expected = map(<dynamic>[
      'array',
      <int>[1, 3, 2]
    ]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesLocalArrayUnionTransformWithNonPrimitiveElements', () {
    // Union nested object values (one existing, one not).
    final Map<String, Object> baseDoc = map(<dynamic>[
      'array',
      <dynamic>[
        1,
        map<String>(<String>['a', 'b'])
      ]
    ]);
    final Map<String, Object> transform = map(<dynamic>[
      'array',
      firestore.FieldValue.arrayUnion(<Map<String, String>>[
        map<String>(<String>['a', 'b']),
        map<String>(<String>['c', 'd'])
      ])
    ]);
    final Map<String, Object> expected = map(<dynamic>[
      'array',
      <dynamic>[
        1,
        map<String>(<String>['a', 'b']),
        map<String>(<String>['c', 'd'])
      ]
    ]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesLocalArrayUnionTransformWithPartiallyOverlappingElements',
      () {
    // Union objects that partially overlap an existing object.
    final Map<String, Object> baseDoc = map(<dynamic>[
      'array',
      <dynamic>[
        1,
        map<String>(<String>['a', 'b', 'c', 'd'])
      ]
    ]);
    final Map<String, Object> transform = map(<dynamic>[
      'array',
      firestore.FieldValue.arrayUnion(<Map<String, String>>[
        map<String>(<String>['a', 'b']),
        map<String>(<String>['c', 'd'])
      ])
    ]);
    final Map<String, Object> expected = map(<dynamic>[
      'array',
      <dynamic>[
        1,
        map<String>(<String>['a', 'b', 'c', 'd']),
        map<String>(<String>['a', 'b']),
        map<String>(<String>['c', 'd'])
      ]
    ]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesLocalArrayRemoveTransformToMissingField', () {
    final Map<String, Object> baseDoc = map();
    final Map<String, Object> transform = map(<dynamic>[
      'missing',
      firestore.FieldValue.arrayRemove(<int>[1, 2])
    ]);
    final Map<String, Object> expected = map(<dynamic>['missing', <int>[]]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesLocalArrayRemoveTransformToNonArrayField', () {
    final Map<String, Object> baseDoc = map(<dynamic>['nonArray', 42]);
    final Map<String, Object> transform = map(<dynamic>[
      'nonArray',
      firestore.FieldValue.arrayRemove(<int>[1, 2])
    ]);
    final Map<String, Object> expected = map(<dynamic>['nonArray', <int>[]]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesLocalArrayRemoveTransformWithNonExistingElements', () {
    final Map<String, Object> baseDoc = map(<dynamic>[
      'array',
      <int>[1, 3]
    ]);
    final Map<String, Object> transform = map(<dynamic>[
      'array',
      firestore.FieldValue.arrayRemove(<int>[2, 4])
    ]);
    final Map<String, Object> expected = map(<dynamic>[
      'array',
      <int>[1, 3]
    ]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesLocalArrayRemoveTransformWithExistingElements', () {
    final Map<String, Object> baseDoc = map(<dynamic>[
      'array',
      <int>[1, 2, 3, 4]
    ]);
    final Map<String, Object> transform = map(<dynamic>[
      'array',
      firestore.FieldValue.arrayRemove(<int>[1, 3])
    ]);
    final Map<String, Object> expected = map(<dynamic>[
      'array',
      <int>[2, 4]
    ]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesLocalArrayRemoveTransformWithNonPrimitiveElements', () {
    // Remove nested object values (one existing, one not).
    final Map<String, Object> baseDoc = map(<dynamic>[
      'array',
      <dynamic>[
        1,
        map<String>(<String>['a', 'b'])
      ]
    ]);
    final Map<String, Object> transform = map(<dynamic>[
      'array',
      firestore.FieldValue.arrayRemove(<Map<String, String>>[
        map(<String>['a', 'b']),
        map(<String>['c', 'd'])
      ])
    ]);
    final Map<String, Object> expected = map(<dynamic>[
      'array',
      <int>[1]
    ]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesServerAckedServerTimestampTransformsToDocuments', () {
    final Map<String, Object> data = map(<dynamic>[
      'foo',
      map<String>(<String>['bar', 'bar-value']),
      'baz',
      'baz-value'
    ]);
    final Document baseDoc = doc('collection/key', 0, data, false);

    final Mutation transform = transformMutation('collection/key',
        map(<dynamic>['foo.bar', firestore.FieldValue.serverTimestamp]));

    final Timestamp serverTimestamp = Timestamp(2, 0);

    final MutationResult mutationResult = MutationResult(
        version(1), <TimestampValue>[TimestampValue.valueOf(serverTimestamp)]);

    final MaybeDocument transformedDoc =
        transform.applyToRemoteDocument(baseDoc, mutationResult);

    final Map<String, Object> expectedData = map(<dynamic>[
      'foo',
      map<dynamic>(<dynamic>['bar', serverTimestamp.toDate()]),
      'baz',
      'baz-value'
    ]);
    expect(transformedDoc, doc('collection/key', 0, expectedData, false));
  });

  test('testAppliesServerAckedArrayTransformsToDocuments', () {
    final Map<String, Object> data = map(<dynamic>[
      'array1',
      <int>[1, 2],
      'array2',
      <String>['a', 'b']
    ]);
    final Document baseDoc = doc('collection/key', 0, data, false);
    final Mutation transform = transformMutation(
        'collection/key',
        map(<dynamic>[
          'array1',
          firestore.FieldValue.arrayUnion(<int>[2, 3]),
          'array2',
          firestore.FieldValue.arrayRemove(<String>['a', 'c'])
        ]));

    // Server just sends null transform results for array operations.
    final MutationResult mutationResult =
        MutationResult(version(1), <FieldValue>[wrap(null), wrap(null)]);
    final MaybeDocument transformedDoc =
        transform.applyToRemoteDocument(baseDoc, mutationResult);

    final Map<String, Object> expectedData = map(<dynamic>[
      'array1',
      <int>[1, 2, 3],
      'array2',
      <String>['b']
    ]);
    expect(transformedDoc, doc('collection/key', 0, expectedData, false));
  });

  test('testDeleteDeletes', () {
    final Map<String, Object> data = map(<String>['foo', 'bar']);
    final Document baseDoc = doc('collection/key', 0, data, false);

    final Mutation delete = deleteMutation('collection/key');
    final MaybeDocument deletedDoc =
        delete.applyToLocalView(baseDoc, baseDoc, Timestamp.now());
    expect(deletedDoc, TestUtil.deletedDoc('collection/key', 0));
  });

  test('testSetWithMutationResult', () {
    final Map<String, Object> data = map(<String>['foo', 'bar']);
    final Document baseDoc = doc('collection/key', 0, data, false);

    final Mutation set =
        setMutation('collection/key', map(<String>['foo', 'new-bar']));
    final MaybeDocument setDoc =
        set.applyToRemoteDocument(baseDoc, mutationResult(4));

    expect(setDoc,
        doc('collection/key', 0, map(<String>['foo', 'new-bar']), false));
  });

  test('testPatchWithMutationResult', () {
    final Map<String, Object> data = map(<String>['foo', 'bar']);
    final Document baseDoc = doc('collection/key', 0, data, false);

    final Mutation patch =
        patchMutation('collection/key', map(<String>['foo', 'new-bar']));
    final MaybeDocument patchDoc =
        patch.applyToRemoteDocument(baseDoc, mutationResult(4));

    expect(doc('collection/key', 0, map(<String>['foo', 'new-bar']), false),
        patchDoc);
  });

  void _assertVersionTransitions(Mutation mutation, MaybeDocument base,
      MutationResult mutationResult, MaybeDocument expected) {
    final MaybeDocument actual =
        mutation.applyToRemoteDocument(base, mutationResult);
    expect(actual, expected);
  }

  test('testTransitions', () {
    final Document docV0 = doc('collection/key', 0, map(), false);
    final NoDocument deletedV0 = deletedDoc('collection/key', 0);

    final Document docV3 = doc('collection/key', 3, map(), false);
    final NoDocument deletedV3 = deletedDoc('collection/key', 3);

    final Mutation set = setMutation('collection/key', map());
    final Mutation patch = patchMutation('collection/key', map());
    final Mutation transform = transformMutation('collection/key', map());
    final Mutation delete = deleteMutation('collection/key');

    final MutationResult mutationResult =
        MutationResult(version(7), /*transformResults:*/ null);
    final MutationResult transformResult =
        MutationResult(version(7), <FieldValue>[]);

    _assertVersionTransitions(set, docV3, mutationResult, docV3);
    _assertVersionTransitions(set, deletedV3, mutationResult, docV0);
    _assertVersionTransitions(set, null, mutationResult, docV0);

    _assertVersionTransitions(patch, docV3, mutationResult, docV3);
    _assertVersionTransitions(patch, deletedV3, mutationResult, deletedV3);
    _assertVersionTransitions(patch, null, mutationResult, null);

    _assertVersionTransitions(transform, docV3, transformResult, docV3);
    _assertVersionTransitions(transform, deletedV3, transformResult, deletedV3);
    _assertVersionTransitions(transform, null, transformResult, null);

    _assertVersionTransitions(delete, docV3, mutationResult, deletedV0);
    _assertVersionTransitions(delete, deletedV3, mutationResult, deletedV0);
    _assertVersionTransitions(delete, null, mutationResult, deletedV0);
  });
}

// ignore: always_specify_types
const wrap = TestUtil.wrap;
// ignore: always_specify_types
const doc = TestUtil.doc;
// ignore: always_specify_types
const deletedDoc = TestUtil.deletedDoc;
// ignore: always_specify_types
const version = TestUtil.version;
// ignore: always_specify_types
const field = TestUtil.field;
// ignore: always_specify_types
const setMutation = TestUtil.setMutation;
// ignore: always_specify_types
const patchMutation = TestUtil.patchMutation;
// ignore: always_specify_types
const deleteMutation = TestUtil.deleteMutation;
// ignore: always_specify_types
const transformMutation = TestUtil.transformMutation;
// ignore: always_specify_types
const map = TestUtil.map;
// ignore: always_specify_types
const wrapObject = TestUtil.wrapMap;
// ignore: always_specify_types
const key = TestUtil.key;
// ignore: always_specify_types
const mutationResult = TestUtil.mutationResult;

// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart'
    as firestore;
import 'package:cloud_firestore_dart/src/firebase/firestore/int32_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/array_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_extremum_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_increment_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/server_timestamp_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/unknown_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  void _verifyTransformAsList(
    Map<String, Object> baseData,
    List<Map<String, Object>> transforms,
    Map<String, Object> expectedData,
  ) {
    MaybeDocument? currentDoc = doc('collection/key', 0, baseData);

    for (Map<String, Object> transformData in transforms) {
      final Mutation transform =
          transformMutation('collection/key', transformData);
      currentDoc =
          transform.applyToLocalView(currentDoc, currentDoc, Timestamp.now());
    }

    final Document expectedDoc =
        doc('collection/key', 0, expectedData, DocumentState.localMutations);
    expect(currentDoc, expectedDoc);
  }

  void _verifyTransform(
    Map<String, Object> baseData,
    Map<String, Object> transformData,
    Map<String, Object> expectedData,
  ) {
    _verifyTransformAsList(
        baseData, <Map<String, Object>>[transformData], expectedData);
  }

  void _verifyDocTransform(
    Object? baseVal,
    firestore.FieldValue transformOp,
    Object expectedVal,
  ) {
    if (baseVal == null) {
      _verifyTransform(
        map(),
        map(<dynamic>['val', transformOp]),
        map(<dynamic>['val', expectedVal]),
      );
    } else {
      _verifyTransform(
        map(<dynamic>['val', baseVal]),
        map(<dynamic>['val', transformOp]),
        map(<dynamic>['val', expectedVal]),
      );
    }
  }

  void _verifyModelTransform(
    TransformOperation op,
    Object? baseVal,
    Object expectedVal,
  ) {
    final FieldValue? baseProto = baseVal != null ? wrap(baseVal) : null;
    final FieldValue expectedProto = wrap(expectedVal);
    final FieldValue result = op.applyToLocalView(baseProto, Timestamp.now());
    expect(result, expectedProto);
  }

  test('testLocalMutationsCarryNoServerVersion', () {
    final Document base = doc('collection/key', 5, map(<String>['a', 'b']));

    final MaybeDocument? set = SetMutation(key('collection/key'),
            wrapMap(map(<String>['c', 'd'])), Precondition.none)
        .applyToLocalView(base, null, Timestamp.now());
    expect(set!.version, SnapshotVersion.none);
    expect((set as Document).hasLocalMutations, isTrue);

    final MaybeDocument? patch = PatchMutation(
            key('collection/key'),
            wrapMap(map(<String>['c', 'd'])),
            FieldMask(<FieldPath>{field('c')}),
            Precondition.none)
        .applyToLocalView(base, null, Timestamp.now());
    expect(patch!.version, SnapshotVersion.none);
    expect((patch as Document).hasLocalMutations, isTrue);

    final MaybeDocument? delete = DeleteMutation(
            key('collection/key'), Precondition.none)
        .applyToLocalView(base, null, Timestamp.now());
    expect(delete, isA<NoDocument>());
    expect(delete!.version, SnapshotVersion.none);
  });

  test('testAppliesSetsToDocuments', () {
    final Map<String, Object> data =
        map(<String>['foo', 'foo-value', 'baz', 'baz-value']);
    final Document baseDoc = doc('collection/key', 0, data);

    final Mutation set =
        setMutation('collection/key', map(<String>['bar', 'bar-value']));
    final MaybeDocument? setDoc =
        set.applyToLocalView(baseDoc, baseDoc, Timestamp.now());
    expect(
        setDoc,
        doc('collection/key', 0, map(<String>['bar', 'bar-value']),
            DocumentState.localMutations));
  });

  group('set and patch with transforms', () {
    final List<FieldTransform> serverTs = <FieldTransform>[
      FieldTransform(field('ts'), ServerTimestampOperation()),
    ];
    final List<FieldTransform> arrUnion = <FieldTransform>[
      FieldTransform(
          field('arr'), ArrayTransformOperationUnion(<FieldValue>[wrap(2)])),
    ];

    test('testSetWithTransformAppliesTransformOnTopOfNewData', () {
      // The set replaces the whole document, so the transform is evaluated on
      // top of the written data and not on the old value of the field (no
      // base document is given here; see the local store tests for the
      // base-document fallback).
      final Document baseDoc = doc(
          'collection/key',
          3,
          map(<dynamic>[
            'arr',
            <int>[9],
            'other',
            1
          ]));
      final Mutation set = SetMutation(key('collection/key'),
          wrapMap(map(<String>['foo', 'bar'])), Precondition.none, arrUnion);
      final Document local =
          set.applyToLocalView(baseDoc, null, Timestamp.now())! as Document;
      expect(
          local.data,
          wrapMap(map(<dynamic>[
            'foo',
            'bar',
            'arr',
            <int>[2]
          ])));
      // Locally mutated documents carry no server version.
      expect(local.version, version(0));
      expect(local.hasLocalMutations, isTrue);
    });

    test('testPatchWithTransformKeepsUnmaskedFields', () {
      final Document baseDoc = doc(
          'collection/key',
          3,
          map(<dynamic>[
            'arr',
            <int>[1],
            'a',
            1,
            'b',
            2
          ]));
      final Mutation patch = PatchMutation(
          key('collection/key'),
          wrapMap(map(<dynamic>['a', 10])),
          fieldMask(<String>['a']),
          Precondition(exists: true),
          arrUnion);
      final Document local = patch.applyToLocalView(
          baseDoc, baseDoc, Timestamp.now())! as Document;
      expect(
          local.data,
          wrapMap(map(<dynamic>[
            'arr',
            <int>[1, 2],
            'a',
            10,
            'b',
            2
          ])));
    });

    test(
        'testPatchWithTransformDoesNotCreateMissingDocumentWithExistsPrecondition',
        () {
      final Mutation patch = PatchMutation(
          key('collection/key'),
          ObjectValue.empty,
          const FieldMask(<FieldPath>{}),
          Precondition(exists: true),
          serverTs);
      expect(patch.applyToLocalView(null, null, Timestamp.now()), isNull);
    });

    test('testSetWithTransformUsesServerResultsWhenAcknowledged', () {
      final Mutation set = SetMutation(
          key('collection/key'),
          wrapMap(map(<String>['foo', 'bar'])),
          Precondition.none, <FieldTransform>[
        FieldTransform(field('inc'),
            NumericIncrementTransformOperation(wrap(1) as NumberValue)),
        FieldTransform(field('ts'), ServerTimestampOperation()),
      ]);
      const Timestamp serverTime = Timestamp(100, 0);
      final MaybeDocument result = set.applyToRemoteDocument(
          null,
          MutationResult(version(7), <FieldValue>[
            wrap(5),
            wrap(serverTime),
          ]));
      expect(
          result,
          doc(
              'collection/key',
              7,
              map(<dynamic>['foo', 'bar', 'inc', 5, 'ts', serverTime]),
              DocumentState.committedMutations));
    });

    test('testPatchWithTransformUsesServerResultsWhenAcknowledged', () {
      final Document baseDoc = doc(
          'collection/key',
          3,
          map(<dynamic>[
            'a',
            1,
            'b',
            2,
            'arr',
            <int>[7]
          ]));
      final Mutation patch = PatchMutation(
          key('collection/key'),
          wrapMap(map(<dynamic>['a', 10])),
          fieldMask(<String>['a']),
          Precondition(exists: true),
          arrUnion);
      final MaybeDocument result = patch.applyToRemoteDocument(
          baseDoc,
          MutationResult(version(7), <FieldValue>[
            wrap(<int>[7, 2])
          ]));
      expect(
          result,
          doc(
              'collection/key',
              7,
              map(<dynamic>[
                'a',
                10,
                'b',
                2,
                'arr',
                <int>[7, 2]
              ]),
              DocumentState.committedMutations));
    });

    test('testMutationsWithDifferentTransformsAreNotEqual', () {
      final Mutation plain = setMutation('collection/key', map());
      final Mutation withTransform = SetMutation(key('collection/key'),
          ObjectValue.empty, Precondition.none, serverTs);
      expect(plain, isNot(withTransform));
      expect(
          withTransform,
          SetMutation(key('collection/key'), ObjectValue.empty,
              Precondition.none, serverTs));
      expect(
          withTransform.hashCode,
          SetMutation(key('collection/key'), ObjectValue.empty,
                  Precondition.none, serverTs)
              .hashCode);
    });

    test('testTransformBaseValueExtractedFromSetAndPatch', () {
      final Document baseDoc = doc('collection/key', 3, map(<dynamic>['n', 4]));
      final List<FieldTransform> inc = <FieldTransform>[
        FieldTransform(field('n'),
            NumericIncrementTransformOperation(wrap(1) as NumberValue)),
      ];
      final Mutation set = SetMutation(
          key('collection/key'), ObjectValue.empty, Precondition.none, inc);
      expect(set.extractTransformBaseValue(baseDoc),
          wrapMap(map(<dynamic>['n', 4])));
      expect(
          setMutation('collection/key', map())
              .extractTransformBaseValue(baseDoc),
          isNull);
    });
  });

  test('testAppliesPatchToDocuments', () {
    final Map<String, Object> data = map(<dynamic>[
      'foo',
      map<String>(<String>['bar', 'bar-value']),
      'baz',
      'baz-value'
    ]);
    final Document baseDoc = doc('collection/key', 0, data);

    final Mutation patch = patchMutation(
        'collection/key', map(<String>['foo.bar', 'new-bar-value']));

    final MaybeDocument? local =
        patch.applyToLocalView(baseDoc, baseDoc, Timestamp.now());

    final Map<String, Object> expectedData = map(<dynamic>[
      'foo',
      map<String>(<String>['bar', 'new-bar-value']),
      'baz',
      'baz-value'
    ]);
    expect(local,
        doc('collection/key', 0, expectedData, DocumentState.localMutations));
  });

  test('testAppliesPatchWithMergeToDocuments', () {
    final MaybeDocument baseDoc = deletedDoc('collection/key', 0);
    final Mutation upsert = patchMutation(
        'collection/key',
        map(<String>['foo.bar', 'new-bar-value']),
        <FieldPath>[field('foo.bar')]);
    final MaybeDocument? newDoc =
        upsert.applyToLocalView(baseDoc, baseDoc, Timestamp.now());
    final Map<String, Object> expectedData = map(<dynamic>[
      'foo',
      map<String>(<String>['bar', 'new-bar-value'])
    ]);
    expect(newDoc,
        doc('collection/key', 0, expectedData, DocumentState.localMutations));
  });

  test('testAppliesPatchToNullDocWithMergeToDocuments', () {
    MaybeDocument? baseDoc;
    final Mutation upsert = patchMutation(
        'collection/key',
        map(<String>['foo.bar', 'new-bar-value']),
        <FieldPath>[field('foo.bar')]);
    final MaybeDocument? newDoc =
        upsert.applyToLocalView(baseDoc, baseDoc, Timestamp.now());
    final Map<String, Object> expectedData = map(<dynamic>[
      'foo',
      map<String>(<String>['bar', 'new-bar-value'])
    ]);
    expect(newDoc,
        doc('collection/key', 0, expectedData, DocumentState.localMutations));
  });

  test('testDeletesValuesFromTheFieldMask', () {
    final Map<String, Object> data = map(<dynamic>[
      'foo',
      map<String>(<String>['bar', 'bar-value', 'baz', 'baz-value'])
    ]);
    final Document baseDoc = doc('collection/key', 0, data);

    final DocumentKey _key = key('collection/key');
    final FieldMask mask = fieldMask(<String>['foo.bar']);
    final Mutation patch =
        PatchMutation(_key, ObjectValue.empty, mask, Precondition.none);

    final MaybeDocument? patchDoc =
        patch.applyToLocalView(baseDoc, baseDoc, Timestamp.now());
    final Map<String, Object> expectedData = map(<dynamic>[
      'foo',
      map<String>(<String>['baz', 'baz-value'])
    ]);
    expect(patchDoc,
        doc('collection/key', 0, expectedData, DocumentState.localMutations));
  });

  test('testPatchesPrimitiveValue', () {
    final Map<String, Object> data =
        map(<String>['foo', 'foo-value', 'baz', 'baz-value']);
    final Document baseDoc = doc('collection/key', 0, data);

    final Mutation patch = patchMutation(
        'collection/key', map(<String>['foo.bar', 'new-bar-value']));
    final MaybeDocument? patchedDoc =
        patch.applyToLocalView(baseDoc, baseDoc, Timestamp.now());
    final Map<String, Object> expectedData = map(<dynamic>[
      'foo',
      map<String>(<String>['bar', 'new-bar-value']),
      'baz',
      'baz-value'
    ]);
    expect(patchedDoc,
        doc('collection/key', 0, expectedData, DocumentState.localMutations));
  });

  test('testPatchingDeletedDocumentsDoesNothing', () {
    final MaybeDocument baseDoc = deletedDoc('collection/key', 0);
    final Mutation patch =
        patchMutation('collection/key', map(<String>['foo', 'bar']));
    final MaybeDocument? patchedDoc =
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
    final Document baseDoc = doc('collection/key', 0, data);

    final Timestamp timestamp = Timestamp.now();
    final Mutation transform = transformMutation('collection/key',
        map(<dynamic>['foo.bar', firestore.FieldValue.serverTimestamp()]));
    final MaybeDocument? transformedDoc =
        transform.applyToLocalView(baseDoc, baseDoc, timestamp);

    // Server timestamps aren't parsed, so we manually insert it.
    ObjectValue expectedData = wrapMap(map(<dynamic>[
      'foo',
      map<String>(<String>['bar', '<server-timestamp>']),
      'baz',
      'baz-value'
    ]));
    expectedData = expectedData.set(field('foo.bar'),
        ServerTimestampValue(timestamp, StringValue.valueOf('bar-value')));

    final Document expectedDoc = Document(key('collection/key'), version(0),
        DocumentState.localMutations, expectedData);
    expect(transformedDoc, expectedDoc);
  });

  test('testAppliesIncrementTransformToDocument', () async {
    final Map<String, Object> baseDoc = map(<dynamic>[
      'longPlusLong',
      1,
      'longPlusDouble',
      2,
      'doublePlusLong',
      3.3,
      'doublePlusDouble',
      4.0,
      'longPlusNan',
      5,
      'doublePlusNan',
      6.6,
      'longPlusInfinity',
      7,
      'doublePlusInfinity',
      8.8
    ]);
    final Map<String, Object> transform = map(<dynamic>[
      'longPlusLong',
      firestore.FieldValue.increment(1),
      'longPlusDouble',
      firestore.FieldValue.increment(2.2),
      'doublePlusLong',
      firestore.FieldValue.increment(3),
      'doublePlusDouble',
      firestore.FieldValue.increment(4.4),
      'longPlusNan',
      firestore.FieldValue.increment(double.nan),
      'doublePlusNan',
      firestore.FieldValue.increment(double.nan),
      'longPlusInfinity',
      firestore.FieldValue.increment(double.infinity),
      'doublePlusInfinity',
      firestore.FieldValue.increment(double.infinity)
    ]);
    final Map<String, Object> expected = map(<dynamic>[
      'longPlusLong',
      2,
      'longPlusDouble',
      4.2,
      'doublePlusLong',
      6.3,
      'doublePlusDouble',
      8.4,
      'longPlusNan',
      double.nan,
      'doublePlusNan',
      double.nan,
      'longPlusInfinity',
      double.infinity,
      'doublePlusInfinity',
      double.infinity
    ]);

    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesIncrementTransformToUnexpectedType', () async {
    final Map<String, Object> baseDoc = map(<dynamic>['string', 'zero']);
    final Map<String, Object> transform =
        map(<dynamic>['string', firestore.FieldValue.increment(1)]);
    final Map<String, Object> expected = map(<dynamic>['string', 1]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesIncrementTransformToMissingField', () async {
    final Map<String, Object> baseDoc = map();
    final Map<String, Object> transform =
        map(<dynamic>['missing', firestore.FieldValue.increment(1)]);
    final Map<String, Object> expected = map(<dynamic>['missing', 1]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesIncrementTransformsConsecutively', () async {
    final Map<String, Object> baseDoc = map(<dynamic>['number', 1]);
    final Map<String, Object> transform1 =
        map(<dynamic>['number', firestore.FieldValue.increment(2)]);
    final Map<String, Object> transform2 =
        map(<dynamic>['number', firestore.FieldValue.increment(3)]);
    final Map<String, Object> transform3 =
        map(<dynamic>['number', firestore.FieldValue.increment(4)]);
    final Map<String, Object> expected = map(<dynamic>['number', 10]);
    _verifyTransformAsList(baseDoc,
        <Map<String, Object>>[transform1, transform2, transform3], expected);
  });

  test('testAppliesIncrementWithoutOverflow', () async {
    final Map<String, Object> baseDoc = map(<dynamic>[
      'a',
      IntegerValue.max - 1,
      'b',
      IntegerValue.max - 1,
      'c',
      IntegerValue.max,
      'd',
      IntegerValue.max
    ]);
    final Map<String, Object> transform = map(<dynamic>[
      'a',
      firestore.FieldValue.increment(1),
      'b',
      firestore.FieldValue.increment(IntegerValue.max),
      'c',
      firestore.FieldValue.increment(1),
      'd',
      firestore.FieldValue.increment(IntegerValue.max)
    ]);
    final Map<String, Object> expected = map(<dynamic>[
      'a',
      IntegerValue.max,
      'b',
      IntegerValue.max,
      'c',
      IntegerValue.max,
      'd',
      IntegerValue.max
    ]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesIncrementWithoutUnderflow', () async {
    final Map<String, Object> baseDoc = map(<dynamic>[
      'a',
      IntegerValue.min + 1,
      'b',
      IntegerValue.min + 1,
      'c',
      IntegerValue.min,
      'd',
      IntegerValue.min
    ]);
    final Map<String, Object> transform = map(<dynamic>[
      'a',
      firestore.FieldValue.increment(-1),
      'b',
      firestore.FieldValue.increment(IntegerValue.min),
      'c',
      firestore.FieldValue.increment(-1),
      'd',
      firestore.FieldValue.increment(IntegerValue.min)
    ]);
    final Map<String, Object> expected = map(<dynamic>[
      'a',
      IntegerValue.min,
      'b',
      IntegerValue.min,
      'c',
      IntegerValue.min,
      'd',
      IntegerValue.min
    ]);
    _verifyTransform(baseDoc, transform, expected);
  });

  // NOTE: This is more a test of UserDataConverter code than Mutation code but we don't have unit tests for it
  // currently. We could consider removing this test once we have integration tests.
  test('testCreateArrayUnionTransform', () {
    final Mutation transform = transformMutation(
        'collection/key',
        map(<dynamic>[
          'a',
          firestore.FieldValue.arrayUnion(<String>['tag']),
          'bar.baz',
          firestore.FieldValue.arrayUnion(<Object>[
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
          wrapMap(map(<dynamic>[
            'nested',
            map<dynamic>(<dynamic>[
              'a',
              <int>[1, 2]
            ])
          ]))
        ]));
  });

  // NOTE: This is more a test of UserDataConverter code than Mutation code but we don't have unit tests for it
  // currently. We could consider removing this test once we have integration tests.
  test('testCreateArrayRemoveTransform', () {
    final Mutation transform = transformMutation(
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

  test('testAppliesServerAckedIncrementTransformToDocuments', () async {
    final Map<String, Object> data = map(<dynamic>['sum', 1]);
    final Document baseDoc = doc('collection/key', 0, data);

    final Mutation transform = transformMutation('collection/key',
        map(<dynamic>['sum', firestore.FieldValue.increment(2)]));
    final MutationResult mutationResult =
        MutationResult(version(1), <IntegerValue>[IntegerValue.valueOf(3)]);

    final MaybeDocument transformedDoc =
        transform.applyToRemoteDocument(baseDoc, mutationResult);

    final Map<String, Object> expectedData = map(<dynamic>['sum', 3]);
    expect(
        transformedDoc,
        doc('collection/key', 1, expectedData,
            DocumentState.committedMutations));
  });

  test('testAppliesServerAckedServerTimestampTransformsToDocuments', () {
    final Map<String, Object> data = map(<dynamic>[
      'foo',
      map<String>(<String>['bar', 'bar-value']),
      'baz',
      'baz-value'
    ]);
    final Document baseDoc = doc('collection/key', 0, data);

    final Mutation transform = transformMutation('collection/key',
        map(<dynamic>['foo.bar', firestore.FieldValue.serverTimestamp()]));

    const Timestamp serverTimestamp = Timestamp(2, 0);

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
    expect(
        transformedDoc,
        doc('collection/key', 1, expectedData,
            DocumentState.committedMutations));
  });

  test('testAppliesServerAckedArrayTransformsToDocuments', () {
    final Map<String, Object> data = map(<dynamic>[
      'array1',
      <int>[1, 2],
      'array2',
      <String>['a', 'b']
    ]);
    final Document baseDoc = doc('collection/key', 0, data);
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
    expect(
        transformedDoc,
        doc('collection/key', 1, expectedData,
            DocumentState.committedMutations));
  });

  test('testDeleteDeletes', () {
    final Map<String, Object> data = map(<String>['foo', 'bar']);
    final Document baseDoc = doc('collection/key', 0, data);

    final Mutation delete = deleteMutation('collection/key');
    final MaybeDocument? deletedDocument =
        delete.applyToLocalView(baseDoc, baseDoc, Timestamp.now());
    expect(deletedDocument, deletedDoc('collection/key', 0));
  });

  test('testSetWithMutationResult', () {
    final Map<String, Object> data = map(<String>['foo', 'bar']);
    final Document baseDoc = doc('collection/key', 0, data);

    final Mutation set =
        setMutation('collection/key', map(<String>['foo', 'new-bar']));
    final MaybeDocument setDoc =
        set.applyToRemoteDocument(baseDoc, mutationResult(4));

    expect(
        setDoc,
        doc('collection/key', 4, map(<String>['foo', 'new-bar']),
            DocumentState.committedMutations));
  });

  test('testPatchWithMutationResult', () {
    final Map<String, Object> data = map(<String>['foo', 'bar']);
    final Document baseDoc = doc('collection/key', 0, data);

    final Mutation patch =
        patchMutation('collection/key', map(<String>['foo', 'new-bar']));
    final MaybeDocument patchDoc =
        patch.applyToRemoteDocument(baseDoc, mutationResult(4));

    expect(
        patchDoc,
        doc('collection/key', 4, map(<String>['foo', 'new-bar']),
            DocumentState.committedMutations));
  });

  void _assertVersionTransitions(Mutation mutation, MaybeDocument? base,
      MutationResult mutationResult, MaybeDocument expected) {
    final MaybeDocument actual =
        mutation.applyToRemoteDocument(base, mutationResult);
    expect(actual, expected);
  }

  test('testTransitions', () {
    final Document docV3 = doc('collection/key', 3, map());
    final NoDocument deletedV3 = deletedDoc('collection/key', 3);

    final Mutation set = setMutation('collection/key', map());
    final Mutation patch = patchMutation('collection/key', map());
    final Mutation transform = transformMutation('collection/key', map());
    final Mutation delete = deleteMutation('collection/key');

    final NoDocument docV7Deleted =
        deletedDoc('collection/key', 7, hasCommittedMutations: true);
    final Document docV7Committed =
        doc('collection/key', 7, map(), DocumentState.committedMutations);
    final UnknownDocument docV7Unknown = unknownDoc('collection/key', 7);

    final MutationResult mutationResult = MutationResult(version(7));
    final MutationResult transformResult =
        MutationResult(version(7), <FieldValue>[]);

    _assertVersionTransitions(set, docV3, mutationResult, docV7Committed);
    _assertVersionTransitions(set, deletedV3, mutationResult, docV7Committed);
    _assertVersionTransitions(set, null, mutationResult, docV7Committed);

    _assertVersionTransitions(patch, docV3, mutationResult, docV7Committed);
    _assertVersionTransitions(patch, deletedV3, mutationResult, docV7Unknown);
    _assertVersionTransitions(patch, null, mutationResult, docV7Unknown);

    _assertVersionTransitions(
        transform, docV3, transformResult, docV7Committed);
    _assertVersionTransitions(
        transform, deletedV3, transformResult, docV7Unknown);
    _assertVersionTransitions(transform, null, transformResult, docV7Unknown);

    _assertVersionTransitions(delete, docV3, mutationResult, docV7Deleted);
    _assertVersionTransitions(delete, deletedV3, mutationResult, docV7Deleted);
    _assertVersionTransitions(delete, null, mutationResult, docV7Deleted);
  });

  test('testServerTimestampBaseValue', () {
    final Map<String, Object> allValues = map(<dynamic>['time', 'foo']);
    final Document baseDoc =
        doc('collection/key', 0, <String, Object>{'nested': allValues});

    final Map<String, Object> allTransforms =
        map(<dynamic>['time', firestore.FieldValue.serverTimestamp()]);

    // Server timestamps are idempotent and don't have base values.
    final Mutation _transformMutation = transformMutation(
        'collection/key', <String, Object>{'nested': allTransforms});
    expect(_transformMutation.extractTransformBaseValue(baseDoc), isNull);
  });

  test('testNumericIncrementBaseValue', () {
    final Map<String, Object> allValues = map<Object>(<dynamic>[
      'ignore',
      'foo',
      'double',
      42.0,
      'long',
      42,
      'string',
      'foo',
      'map',
      map<dynamic>(<dynamic>[])
    ]);
    allValues['nested'] = Map<String, Object>.from(allValues);
    final Document baseDoc = doc('collection/key', 0, allValues);

    final Map<String, Object> allTransforms = map<Object>(<dynamic>[
      'double',
      firestore.FieldValue.increment(1),
      'long',
      firestore.FieldValue.increment(1),
      'string',
      firestore.FieldValue.increment(1),
      'map',
      firestore.FieldValue.increment(1),
      'missing',
      firestore.FieldValue.increment(1)
    ]);
    allTransforms['nested'] = Map<String, Object>.from(allTransforms);

    final ObjectValue baseValue = transformMutation(
      'collection/key',
      allTransforms,
    ).extractTransformBaseValue(baseDoc)!;

    final FieldValue expected = wrapMap(map<dynamic>(<dynamic>[
      'double',
      42.0,
      'long',
      42,
      'string',
      0,
      'map',
      0,
      'missing',
      0,
      'nested',
      map<dynamic>(<dynamic>[
        'double',
        42.0,
        'long',
        42,
        'string',
        0,
        'map',
        0,
        'missing',
        0
      ])
    ]));
    expect(baseValue, expected);
  });

  test('testIncrementTwice', () {
    final Document baseDoc =
        doc('collection/key', 0, map(<dynamic>['sum', '0']));

    final Map<String, Object> increment =
        map(<dynamic>['sum', firestore.FieldValue.increment(1)]);
    final Mutation _transformMutation =
        transformMutation('collection/key', increment);

    MaybeDocument? mutatedDoc =
        _transformMutation.applyToLocalView(baseDoc, baseDoc, Timestamp.now());
    mutatedDoc = _transformMutation.applyToLocalView(
        mutatedDoc, baseDoc, Timestamp.now());

    final Document _mutatedDoc = mutatedDoc! as Document;
    expect(_mutatedDoc.getField(field('sum')), wrap(2));
  });

  test('testAppliesMinimumTransformToDocument', () async {
    final Map<String, Object> baseDoc = map(<dynamic>[
      'longMinLong', 5,
      'longMinDouble', 5,
      'doubleMinLong', 5.5,
      'doubleMinDouble', 5.5,
      'longMinNan', 5,
      'doubleMinNan', 5.5,
    ]);
    final Map<String, Object> transform = map(<dynamic>[
      'longMinLong', firestore.FieldValue.minimum(2),
      'longMinDouble', firestore.FieldValue.minimum(2.2),
      'doubleMinLong', firestore.FieldValue.minimum(2),
      'doubleMinDouble', firestore.FieldValue.minimum(2.2),
      'longMinNan', firestore.FieldValue.minimum(double.nan),
      'doubleMinNan', firestore.FieldValue.minimum(double.nan),
    ]);
    final Map<String, Object> expected = map(<dynamic>[
      'longMinLong', 2,
      'longMinDouble', 2.2,
      'doubleMinLong', 2,
      'doubleMinDouble', 2.2,
      'longMinNan', double.nan,
      'doubleMinNan', double.nan,
    ]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testAppliesMaximumTransformToDocument', () async {
    final Map<String, Object> baseDoc = map(<dynamic>[
      'longMaxLong', 5,
      'longMaxDouble', 5,
      'doubleMaxLong', 5.5,
      'doubleMaxDouble', 5.5,
      'longMaxNan', 5,
      'doubleMaxNan', 5.5,
    ]);
    final Map<String, Object> transform = map(<dynamic>[
      'longMaxLong', firestore.FieldValue.maximum(8),
      'longMaxDouble', firestore.FieldValue.maximum(8.8),
      'doubleMaxLong', firestore.FieldValue.maximum(8),
      'doubleMaxDouble', firestore.FieldValue.maximum(8.8),
      'longMaxNan', firestore.FieldValue.maximum(double.nan),
      'doubleMaxNan', firestore.FieldValue.maximum(double.nan),
    ]);
    final Map<String, Object> expected = map(<dynamic>[
      'longMaxLong', 8,
      'longMaxDouble', 8.8,
      'doubleMaxLong', 8,
      'doubleMaxDouble', 8.8,
      'longMaxNan', double.nan,
      'doubleMaxNan', double.nan,
    ]);
    _verifyTransform(baseDoc, transform, expected);
  });

  test('testMinimumAndMaximumKeepPreviousValueWhenPreviousWins', () async {
    // The previous value is already the winner: it keeps its own type.
    _verifyTransform(
        map(<dynamic>['a', 1, 'b', 1.5, 'c', 10, 'd', 10.5]),
        map(<dynamic>[
          'a', firestore.FieldValue.minimum(5.5),
          'b', firestore.FieldValue.minimum(5),
          'c', firestore.FieldValue.maximum(5.5),
          'd', firestore.FieldValue.maximum(5),
        ]),
        map(<dynamic>['a', 1, 'b', 1.5, 'c', 10, 'd', 10.5]));
  });

  test('testMinimumAndMaximumEquivalentValuesKeepPreviousType', () async {
    _verifyTransform(
        map(<dynamic>['a', 3, 'b', 3.0, 'c', 3, 'd', 3.0]),
        map(<dynamic>[
          'a', firestore.FieldValue.minimum(3.0),
          'b', firestore.FieldValue.minimum(3),
          'c', firestore.FieldValue.maximum(3.0),
          'd', firestore.FieldValue.maximum(3),
        ]),
        map(<dynamic>['a', 3, 'b', 3.0, 'c', 3, 'd', 3.0]));
  });

  test('testMinimumAndMaximumWithNaNPreviousValue', () async {
    _verifyTransform(
        map(<dynamic>['a', double.nan, 'b', double.nan]),
        map(<dynamic>[
          'a', firestore.FieldValue.minimum(5),
          'b', firestore.FieldValue.maximum(5),
        ]),
        map(<dynamic>['a', double.nan, 'b', double.nan]));
  });

  test('testAppliesMinimumTransformToUnexpectedType', () async {
    _verifyTransform(map(<dynamic>['string', 'value']),
        map(<dynamic>['string', firestore.FieldValue.minimum(1)]),
        map(<dynamic>['string', 1]));
  });

  test('testAppliesMaximumTransformToUnexpectedType', () async {
    _verifyTransform(map(<dynamic>['string', 'value']),
        map(<dynamic>['string', firestore.FieldValue.maximum(1)]),
        map(<dynamic>['string', 1]));
  });

  test('testAppliesMinimumTransformToMissingField', () async {
    _verifyTransform(map(),
        map(<dynamic>['missing', firestore.FieldValue.minimum(1)]),
        map(<dynamic>['missing', 1]));
  });

  test('testAppliesMaximumTransformToMissingField', () async {
    _verifyTransform(map(),
        map(<dynamic>['missing', firestore.FieldValue.maximum(1)]),
        map(<dynamic>['missing', 1]));
  });

  test('testAppliesServerAckedMinimumAndMaximumTransformToDocuments',
      () async {
    final Document baseDoc =
        doc('collection/key', 0, map(<dynamic>['min', 10, 'max', 10]));

    final Mutation transform = transformMutation(
        'collection/key',
        map(<dynamic>[
          'min', firestore.FieldValue.minimum(2),
          'max', firestore.FieldValue.maximum(20),
        ]));
    final MutationResult mutationResult = MutationResult(version(1),
        <FieldValue>[IntegerValue.valueOf(20), IntegerValue.valueOf(2)]);

    final MaybeDocument transformedDoc =
        transform.applyToRemoteDocument(baseDoc, mutationResult);

    expect(
        transformedDoc,
        doc('collection/key', 1, map(<dynamic>['min', 2, 'max', 20]),
            DocumentState.committedMutations));
  });

  test('testNumericMinimumBaseValue', () {
    _expectNoBaseValue(firestore.FieldValue.minimum(1));
  });

  test('testNumericMaximumBaseValue', () {
    _expectNoBaseValue(firestore.FieldValue.maximum(1));
  });

  // Model-level increment evaluation

  test('testModelIncrementInt32AndInt32', () {
    _verifyModelTransform(
      NumericIncrementTransformOperation(wrap(Int32Value(5)) as NumberValue),
      Int32Value(10),
      Int32Value(15),
    );
  });

  test('testModelIncrementIntAndInt32', () {
    _verifyModelTransform(
      NumericIncrementTransformOperation(wrap(Int32Value(5)) as NumberValue),
      10,
      15,
    );
  });

  test('testModelIncrementDecimal128AndInt', () {
    _verifyModelTransform(
      NumericIncrementTransformOperation(wrap(5) as NumberValue),
      Decimal128Value('10'),
      Decimal128Value('15'),
    );
  });

  test('testModelIncrementIntAndDecimal128', () {
    _verifyModelTransform(
      NumericIncrementTransformOperation(
        wrap(Decimal128Value('5')) as NumberValue,
      ),
      10,
      Decimal128Value('15'),
    );
  });

  test('testModelIncrementInt32AndDecimal128', () {
    _verifyModelTransform(
      NumericIncrementTransformOperation(
        wrap(Decimal128Value('5')) as NumberValue,
      ),
      Int32Value(10),
      Decimal128Value('15'),
    );
  });

  test('testModelIncrementDoubleAndInt32', () {
    _verifyModelTransform(
      NumericIncrementTransformOperation(wrap(Int32Value(5)) as NumberValue),
      10.5,
      15.5,
    );
  });

  test('testModelIncrementDecimal128AndDecimal128', () {
    _verifyModelTransform(
      NumericIncrementTransformOperation(
        wrap(Decimal128Value('5')) as NumberValue,
      ),
      Decimal128Value('10'),
      Decimal128Value('15'),
    );
  });

  test('testModelIncrementDoubleAndDecimal128', () {
    _verifyModelTransform(
      NumericIncrementTransformOperation(
        wrap(Decimal128Value('5')) as NumberValue,
      ),
      10.5,
      Decimal128Value('15.5'),
    );
  });

  // Standalone document-level increment tests
  test('testAppliesIncrementWithIntegerToInt32Base', () {
    _verifyTransform(
      map(<dynamic>['val', Int32Value(10)]),
      map(<dynamic>['val', firestore.FieldValue.increment(5)]),
      map(<dynamic>['val', 15]),
    );
  });

  test('testAppliesIncrementWithDoubleToInt32Base', () {
    _verifyTransform(
      map(<dynamic>['val', Int32Value(10)]),
      map(<dynamic>['val', firestore.FieldValue.increment(1.5)]),
      map(<dynamic>['val', 11.5]),
    );
  });

  test('testAppliesIncrementWithIntegerToDecimal128Base', () {
    _verifyTransform(
      map(<dynamic>['val', Decimal128Value('10.5')]),
      map(<dynamic>['val', firestore.FieldValue.increment(5)]),
      map(<dynamic>['val', Decimal128Value('15.5')]),
    );
  });

  // Model-level minimum and maximum evaluation

  test('testModelMinimumInt32AndInt32_Smaller', () {
    _verifyModelTransform(
      NumericMinimumTransformOperation(wrap(Int32Value(5)) as NumberValue),
      Int32Value(10),
      Int32Value(5),
    );
  });

  test('testModelMinimumInt32AndInt32_Larger', () {
    _verifyModelTransform(
      NumericMinimumTransformOperation(wrap(Int32Value(15)) as NumberValue),
      Int32Value(10),
      Int32Value(10),
    );
  });

  test('testModelMinimumIntAndInt32', () {
    _verifyModelTransform(
      NumericMinimumTransformOperation(wrap(Int32Value(5)) as NumberValue),
      10,
      Int32Value(5),
    );
  });

  test('testModelMinimumInt32AndInt', () {
    _verifyModelTransform(
      NumericMinimumTransformOperation(wrap(5) as NumberValue),
      Int32Value(10),
      5,
    );
  });

  test('testModelMinimumDecimal128AndInt', () {
    _verifyModelTransform(
      NumericMinimumTransformOperation(wrap(5) as NumberValue),
      Decimal128Value('10'),
      5,
    );
  });

  test('testModelMinimumIntAndDecimal128', () {
    _verifyModelTransform(
      NumericMinimumTransformOperation(
        wrap(Decimal128Value('5')) as NumberValue,
      ),
      10,
      Decimal128Value('5'),
    );
  });

  test('testModelMinimumInt32AndDecimal128', () {
    _verifyModelTransform(
      NumericMinimumTransformOperation(
        wrap(Decimal128Value('5')) as NumberValue,
      ),
      Int32Value(10),
      Decimal128Value('5'),
    );
  });

  test('testModelMinimumDoubleAndInt32', () {
    _verifyModelTransform(
      NumericMinimumTransformOperation(wrap(Int32Value(5)) as NumberValue),
      10.5,
      Int32Value(5),
    );
  });

  test('testModelMinimumDecimal128AndDecimal128', () {
    _verifyModelTransform(
      NumericMinimumTransformOperation(
        wrap(Decimal128Value('5')) as NumberValue,
      ),
      Decimal128Value('10'),
      Decimal128Value('5'),
    );
  });

  test('testModelMinimumDoubleAndDecimal128', () {
    _verifyModelTransform(
      NumericMinimumTransformOperation(
        wrap(Decimal128Value('5')) as NumberValue,
      ),
      10.5,
      Decimal128Value('5'),
    );
  });

  test('testModelMinimumNonNumericBaseSelectsOperand', () {
    _verifyModelTransform(
      NumericMinimumTransformOperation(wrap(Int32Value(5)) as NumberValue),
      'hello',
      Int32Value(5),
    );
  });

  test('testModelMinimumNullBaseSelectsOperand', () {
    _verifyModelTransform(
      NumericMinimumTransformOperation(wrap(Int32Value(5)) as NumberValue),
      null,
      Int32Value(5),
    );
  });

  test('testModelMaximumInt32AndInt32_Smaller', () {
    _verifyModelTransform(
      NumericMaximumTransformOperation(wrap(Int32Value(5)) as NumberValue),
      Int32Value(10),
      Int32Value(10),
    );
  });

  test('testModelMaximumInt32AndInt32_Larger', () {
    _verifyModelTransform(
      NumericMaximumTransformOperation(wrap(Int32Value(15)) as NumberValue),
      Int32Value(10),
      Int32Value(15),
    );
  });

  test('testModelMaximumIntAndInt32', () {
    _verifyModelTransform(
      NumericMaximumTransformOperation(wrap(Int32Value(15)) as NumberValue),
      10,
      Int32Value(15),
    );
  });

  test('testModelMaximumInt32AndInt', () {
    _verifyModelTransform(
      NumericMaximumTransformOperation(wrap(15) as NumberValue),
      Int32Value(10),
      15,
    );
  });

  test('testModelMaximumDecimal128AndInt', () {
    _verifyModelTransform(
      NumericMaximumTransformOperation(wrap(15) as NumberValue),
      Decimal128Value('10'),
      15,
    );
  });

  test('testModelMaximumIntAndDecimal128', () {
    _verifyModelTransform(
      NumericMaximumTransformOperation(
        wrap(Decimal128Value('15')) as NumberValue,
      ),
      10,
      Decimal128Value('15'),
    );
  });

  test('testModelMaximumInt32AndDecimal128', () {
    _verifyModelTransform(
      NumericMaximumTransformOperation(
        wrap(Decimal128Value('15')) as NumberValue,
      ),
      Int32Value(10),
      Decimal128Value('15'),
    );
  });

  test('testModelMaximumDoubleAndInt32', () {
    _verifyModelTransform(
      NumericMaximumTransformOperation(wrap(Int32Value(15)) as NumberValue),
      10.5,
      Int32Value(15),
    );
  });

  test('testModelMaximumDecimal128AndDecimal128', () {
    _verifyModelTransform(
      NumericMaximumTransformOperation(
        wrap(Decimal128Value('15')) as NumberValue,
      ),
      Decimal128Value('10'),
      Decimal128Value('15'),
    );
  });

  test('testModelMaximumDoubleAndDecimal128', () {
    _verifyModelTransform(
      NumericMaximumTransformOperation(
        wrap(Decimal128Value('15')) as NumberValue,
      ),
      10.5,
      Decimal128Value('15'),
    );
  });

  test('testModelMaximumNonNumericBaseSelectsOperand', () {
    _verifyModelTransform(
      NumericMaximumTransformOperation(
        wrap(Decimal128Value('10.5')) as NumberValue,
      ),
      'hello',
      Decimal128Value('10.5'),
    );
  });

  test('testModelMaximumNullBaseSelectsOperand', () {
    _verifyModelTransform(
      NumericMaximumTransformOperation(
        wrap(Decimal128Value('10.5')) as NumberValue,
      ),
      null,
      Decimal128Value('10.5'),
    );
  });

  // Ported from the JS SDK's mutation.test.ts: the high-precision cases.
  test(
    'minimum with high-precision Decimal128Value selects smaller operand (operand smaller)',
    () {
      _verifyModelTransform(
        NumericMinimumTransformOperation(
          wrap(Decimal128Value('1.000000000000000000000000000000001'))
              as NumberValue,
        ),
        Decimal128Value('1.000000000000000000000000000000002'),
        Decimal128Value('1.000000000000000000000000000000001'),
      );
    },
  );

  test(
    'minimum with high-precision Decimal128Value retains base when base is smaller',
    () {
      _verifyModelTransform(
        NumericMinimumTransformOperation(
          wrap(Decimal128Value('1.000000000000000000000000000000002'))
              as NumberValue,
        ),
        Decimal128Value('1.000000000000000000000000000000001'),
        Decimal128Value('1.000000000000000000000000000000001'),
      );
    },
  );

  test(
    'maximum with high-precision Decimal128Value selects larger operand (operand larger)',
    () {
      _verifyModelTransform(
        NumericMaximumTransformOperation(
          wrap(Decimal128Value('1.000000000000000000000000000000002'))
              as NumberValue,
        ),
        Decimal128Value('1.000000000000000000000000000000001'),
        Decimal128Value('1.000000000000000000000000000000002'),
      );
    },
  );

  test(
    'maximum with high-precision Decimal128Value retains base when base is larger',
    () {
      _verifyModelTransform(
        NumericMaximumTransformOperation(
          wrap(Decimal128Value('1.000000000000000000000000000000001'))
              as NumberValue,
        ),
        Decimal128Value('1.000000000000000000000000000000002'),
        Decimal128Value('1.000000000000000000000000000000002'),
      );
    },
  );

  // Document-level numeric transform evaluation
  test('testAppliesNumericTransformsToInt32Fields', () {
    final Int32Value base = Int32Value(10);
    _verifyDocTransform(base, firestore.FieldValue.increment(5), 15);
    _verifyDocTransform(base, firestore.FieldValue.increment(1.5), 11.5);
    _verifyDocTransform(base, firestore.FieldValue.minimum(5), 5);
    _verifyDocTransform(base, firestore.FieldValue.minimum(15), Int32Value(10));
    _verifyDocTransform(base, firestore.FieldValue.minimum(5.5), 5.5);
    _verifyDocTransform(base, firestore.FieldValue.minimum(-5), -5);
    _verifyDocTransform(base, firestore.FieldValue.maximum(5), Int32Value(10));
    _verifyDocTransform(base, firestore.FieldValue.maximum(15), 15);
    _verifyDocTransform(
      base,
      firestore.FieldValue.maximum(5.5),
      Int32Value(10),
    );
    _verifyDocTransform(base, firestore.FieldValue.maximum(-5), Int32Value(10));
  });

  test('testAppliesNumericTransformsToDecimal128Fields', () {
    final Decimal128Value base = Decimal128Value('10.5');
    _verifyDocTransform(
      base,
      firestore.FieldValue.increment(5),
      Decimal128Value('15.5'),
    );
    _verifyDocTransform(base, firestore.FieldValue.minimum(5), 5);
    _verifyDocTransform(
      base,
      firestore.FieldValue.minimum(15),
      Decimal128Value('10.5'),
    );
    _verifyDocTransform(base, firestore.FieldValue.minimum(5.5), 5.5);
    _verifyDocTransform(base, firestore.FieldValue.minimum(-5), -5);
    _verifyDocTransform(
      base,
      firestore.FieldValue.maximum(5),
      Decimal128Value('10.5'),
    );
    _verifyDocTransform(base, firestore.FieldValue.maximum(15), 15);
    _verifyDocTransform(
      base,
      firestore.FieldValue.maximum(5.5),
      Decimal128Value('10.5'),
    );
    _verifyDocTransform(
      base,
      firestore.FieldValue.maximum(-5),
      Decimal128Value('10.5'),
    );
  });

  test('testAppliesNumericTransformsToStandardIntegerAndDoubleFields', () {
    const int intBase = 10;
    _verifyDocTransform(intBase, firestore.FieldValue.minimum(5), 5);
    _verifyDocTransform(intBase, firestore.FieldValue.minimum(5.5), 5.5);
    _verifyDocTransform(intBase, firestore.FieldValue.maximum(15), 15);
    _verifyDocTransform(intBase, firestore.FieldValue.maximum(15.5), 15.5);

    // PORTING NOTE: Android expects 5.0 and 15.0 here, which only pass there
    // because its document equality treats 5L and 5.0 as equal. The result is
    // the integer operand in both SDKs; the expectations follow the JS SDK.
    const double doubleBase = 10.5;
    _verifyDocTransform(doubleBase, firestore.FieldValue.minimum(5), 5);
    _verifyDocTransform(doubleBase, firestore.FieldValue.minimum(5.5), 5.5);
    _verifyDocTransform(doubleBase, firestore.FieldValue.maximum(15), 15);
    _verifyDocTransform(doubleBase, firestore.FieldValue.maximum(15.5), 15.5);
  });

  test('testAppliesNumericTransformsToMissingAndNonNumericFields', () {
    _verifyDocTransform(null, firestore.FieldValue.increment(1), 1);
    _verifyDocTransform(null, firestore.FieldValue.minimum(10), 10);
    _verifyDocTransform(null, firestore.FieldValue.maximum(10.5), 10.5);

    const String stringBase = 'hello';
    _verifyDocTransform(stringBase, firestore.FieldValue.minimum(5), 5);
    _verifyDocTransform(stringBase, firestore.FieldValue.maximum(15), 15);
  });

  test('testAppliesConsecutiveNumericTransformsOnDocument', () {
    final Map<String, Object> baseDoc = map(<dynamic>['val', Int32Value(10)]);
    final Map<String, Object> t1 = map(<dynamic>[
      'val',
      firestore.FieldValue.minimum(15),
    ]);
    final Map<String, Object> t2 = map(<dynamic>[
      'val',
      firestore.FieldValue.minimum(5),
    ]);
    final Map<String, Object> t3 = map(<dynamic>[
      'val',
      firestore.FieldValue.maximum(20),
    ]);
    _verifyTransformAsList(baseDoc, <Map<String, Object>>[
      t1,
      t2,
      t3,
    ], map(<dynamic>['val', 20]));

    final Map<String, Object> numDoc = map(<dynamic>['numberVal', 1]);
    _verifyTransformAsList(numDoc, <Map<String, Object>>[
      map(<dynamic>['numberVal', firestore.FieldValue.increment(2)]),
      map(<dynamic>['numberVal', firestore.FieldValue.increment(3)]),
      map(<dynamic>['numberVal', firestore.FieldValue.increment(4)]),
    ], map(<dynamic>['numberVal', 10]));
  });

  test('testNumericTransformOperationEquality', () {
    final NumberValue one = IntegerValue.valueOf(1);
    final NumberValue two = IntegerValue.valueOf(2);
    expect(NumericMinimumTransformOperation(one),
        NumericMinimumTransformOperation(IntegerValue.valueOf(1)));
    expect(NumericMinimumTransformOperation(one).hashCode,
        NumericMinimumTransformOperation(IntegerValue.valueOf(1)).hashCode);
    expect(NumericMaximumTransformOperation(one),
        NumericMaximumTransformOperation(IntegerValue.valueOf(1)));
    expect(NumericMinimumTransformOperation(one),
        isNot(NumericMinimumTransformOperation(two)));
    expect(NumericMinimumTransformOperation(one),
        isNot(NumericMaximumTransformOperation(one)));
    expect(NumericMaximumTransformOperation(one),
        isNot(NumericIncrementTransformOperation(one)));
    expect(NumericIncrementTransformOperation(one),
        NumericIncrementTransformOperation(IntegerValue.valueOf(1)));
  });
}

void _expectNoBaseValue(firestore.FieldValue sentinel) {
  final Map<String, Object> allValues = map<Object>(<dynamic>[
    'ignore', 'foo',
    'double', 42.0,
    'long', 42,
    'string', 'foo',
    'map', map<dynamic>(<dynamic>[]),
  ]);
  allValues['nested'] = Map<String, Object>.from(allValues);
  final Document baseDoc = doc('collection/key', 0, allValues);

  final Map<String, Object> allTransforms = map<Object>(<dynamic>[
    'double', sentinel,
    'long', sentinel,
    'string', sentinel,
    'map', sentinel,
    'missing', sentinel,
  ]);
  allTransforms['nested'] = Map<String, Object>.from(allTransforms);

  expect(
      transformMutation('collection/key', allTransforms)
          .extractTransformBaseValue(baseDoc),
      isNull);
}

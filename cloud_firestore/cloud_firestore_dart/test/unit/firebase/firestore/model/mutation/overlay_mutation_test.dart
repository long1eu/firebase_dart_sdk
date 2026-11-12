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

// Port of the overlay cases of the Android SDK's MutationTest (testOverlay*): for a document and a list of mutations,
// the overlay calculated from the local view must give the same local view when applied to the document. Every
// overlay also goes through the local serializer, which has to keep pending server timestamps.

import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart'
    as firestore;
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../../util/test_util.dart';

final UserDataConverter _converter =
    UserDataConverter(DatabaseId.forProject('project'));
final LocalSerializer _serializer =
    LocalSerializer(RemoteSerializer(DatabaseId.forProject('project')));

/// A set mutation, parsing field value sentinels.
Mutation _set(String path, Map<String, Object?> data) =>
    _converter.parseSetData(data).toMutation(key(path), Precondition.none);

/// An update (patch with `exists: true`), parsing field value sentinels.
Mutation _patch(String path, Map<String, Object?> data) => _converter
    .parseUpdateData(data)
    .toMutation(key(path), Precondition(exists: true));

/// A set with merge on [fields], parsing field value sentinels.
Mutation _merge(String path, Map<String, Object?> data, List<String> fields) =>
    _converter
        .parseMergeData(data, FieldMask(fields.map(field).toSet()))
        .toMutation(key(path), Precondition.none);

Mutation _delete(String path) => DeleteMutation(key(path), Precondition.none);

void _verifyOverlayRoundTrips(MaybeDocument? doc, List<Mutation> mutations) {
  final Timestamp now = Timestamp.now();

  MaybeDocument? docForMutations = doc;
  FieldMask? mask = FieldMask.empty;
  for (Mutation m in mutations) {
    (docForMutations, mask) =
        m.applyToLocalViewWithMask(docForMutations, docForMutations, mask, now);
  }

  final Mutation? overlay =
      Mutation.calculateOverlayMutation(docForMutations, mask);
  MaybeDocument? docForOverlay = doc;
  if (overlay != null) {
    final Mutation stored = _serializer
        .decodeOverlayMutation(_serializer.encodeOverlayMutation(overlay));
    expect(stored, overlay, reason: 'The overlay must survive serialization');
    docForOverlay = stored.applyToLocalView(docForOverlay, docForOverlay, now);
  }

  expect(docForOverlay, docForMutations,
      reason: 'Overlay mutation failed with:\ndocument: $doc\n'
          'mutations: $mutations\noverlay: $overlay');
}

/// Runs [_verifyOverlayRoundTrips] for each document and every permutation of [mutations]. Returns the number of
/// cases.
int _runPermutationTests(List<MaybeDocument?> docs, List<Mutation> mutations) {
  int testCases = 0;
  for (MaybeDocument? doc in docs) {
    for (List<Mutation> permutation in _permutations(mutations)) {
      _verifyOverlayRoundTrips(doc, permutation);
      testCases++;
    }
  }
  return testCases;
}

Iterable<List<T>> _permutations<T>(List<T> items) sync* {
  if (items.isEmpty) {
    yield <T>[];
    return;
  }
  for (int i = 0; i < items.length; i++) {
    final List<T> rest = <T>[...items.sublist(0, i), ...items.sublist(i + 1)];
    for (List<T> permutation in _permutations(rest)) {
      yield <T>[items[i], ...permutation];
    }
  }
}

Iterable<List<T>> _combinations<T>(List<T> items, int size) sync* {
  if (size == 0) {
    yield <T>[];
    return;
  }
  for (int i = 0; i <= items.length - size; i++) {
    for (List<T> rest in _combinations(items.sublist(i + 1), size - 1)) {
      yield <T>[items[i], ...rest];
    }
  }
}

int _runCombinationTests(List<MaybeDocument?> docs, List<Mutation> mutations) {
  int testCases = 0;
  for (int subsetSize = 0; subsetSize <= mutations.length; ++subsetSize) {
    for (List<Mutation> combination in _combinations(mutations, subsetSize)) {
      testCases += _runPermutationTests(docs, combination);
    }
  }
  return testCases;
}

void main() {
  test('testOverlayWithNoMutation', () {
    _verifyOverlayRoundTrips(
        doc('collection/key', 1,
            map(<dynamic>['foo', 'foo-value', 'baz', 'baz-value'])),
        <Mutation>[]);
  });

  test('testOverlayWithMutationsFailByPreconditions', () {
    _verifyOverlayRoundTrips(deletedDoc('collection/key', 1), <Mutation>[
      _patch('collection/key', map(<dynamic>['foo', 'bar'])),
      _patch('collection/key', map(<dynamic>['a', 1])),
    ]);
  });

  test('testOverlayWithPatchOnInvalidDocument', () {
    _verifyOverlayRoundTrips(null, <Mutation>[
      _patch('collection/key', map(<dynamic>['a', 1]))
    ]);
  });

  test('testOverlayWithOneSetMutation', () {
    _verifyOverlayRoundTrips(
        doc('collection/key', 1,
            map(<dynamic>['foo', 'foo-value', 'baz', 'baz-value'])),
        <Mutation>[
          _set('collection/key', map(<dynamic>['bar', 'bar-value']))
        ]);
  });

  test('testOverlayWithOnePatchMutation', () {
    _verifyOverlayRoundTrips(
        doc(
            'collection/key',
            1,
            map(<dynamic>[
              'foo',
              map(<dynamic>['bar', 'bar-value']),
              'baz',
              'baz-value'
            ])),
        <Mutation>[
          _patch('collection/key', map(<dynamic>['foo.bar', 'new-bar-value']))
        ]);
  });

  test('testOverlayWithPatchThenMerge', () {
    _verifyOverlayRoundTrips(deletedDoc('collection/key', 1), <Mutation>[
      _merge(
          'collection/key',
          map(<dynamic>[
            'foo',
            map(<dynamic>['bar', 'new-bar-value'])
          ]),
          <String>['foo.bar'])
    ]);
  });

  test('testOverlayWithDeleteThenPatch', () {
    _verifyOverlayRoundTrips(
        doc('collection/key', 1, map(<dynamic>['foo', 1])), <Mutation>[
      _delete('collection/key'),
      _patch('collection/key', map(<dynamic>['foo.bar', 'new-bar-value'])),
    ]);
  });

  test('testOverlayWithDeleteThenMerge', () {
    _verifyOverlayRoundTrips(
        doc('collection/key', 1, map(<dynamic>['foo', 1])), <Mutation>[
      _delete('collection/key'),
      _merge(
          'collection/key',
          map(<dynamic>[
            'foo',
            map(<dynamic>['bar', 'new-bar-value'])
          ]),
          <String>['foo.bar']),
    ]);
  });

  test('testOverlayWithPatchThenPatchToDeleteField', () {
    _verifyOverlayRoundTrips(
        doc('collection/key', 1, map(<dynamic>['foo', 1])), <Mutation>[
      _patch(
          'collection/key',
          map(<dynamic>[
            'foo',
            'foo-patched-value',
            'bar.baz',
            firestore.FieldValue.increment(1)
          ])),
      _patch(
          'collection/key',
          map(<dynamic>[
            'foo',
            'foo-patched-value',
            'bar.baz',
            firestore.FieldValue.delete()
          ])),
    ]);
  });

  test('testOverlayWithPatchThenMergeWithArrayUnion', () {
    _verifyOverlayRoundTrips(
        doc('collection/key', 1, map(<dynamic>['foo', 1])), <Mutation>[
      _patch(
          'collection/key',
          map(<dynamic>[
            'foo',
            'foo-patched-value',
            'bar.baz',
            firestore.FieldValue.increment(1)
          ])),
      _merge(
          'collection/key',
          map(<dynamic>[
            'arrays',
            firestore.FieldValue.arrayUnion(<int>[1, 2, 3])
          ]),
          <String>['arrays']),
    ]);
  });

  test('testOverlayWithArrayUnionThenRemove', () {
    _verifyOverlayRoundTrips(
        doc('collection/key', 1, map(<dynamic>['foo', 1])), <Mutation>[
      _merge(
          'collection/key',
          map(<dynamic>[
            'arrays',
            firestore.FieldValue.arrayUnion(<int>[1, 2, 3])
          ]),
          <String>[]),
      _merge(
          'collection/key',
          map(<dynamic>[
            'foo',
            'xxx',
            'arrays',
            firestore.FieldValue.arrayRemove(<int>[2])
          ]),
          <String>['foo']),
    ]);
  });

  test('testOverlayWithSetThenIncrement', () {
    _verifyOverlayRoundTrips(
        doc('collection/key', 1, map(<dynamic>['foo', 1])), <Mutation>[
      _set('collection/key', map(<dynamic>['foo', 2])),
      _patch('collection/key',
          map(<dynamic>['foo', firestore.FieldValue.increment(2)])),
    ]);
  });

  test('testOverlayWithSetThenPatchOnDeletedDoc', () {
    _verifyOverlayRoundTrips(deletedDoc('collection/key', 1), <Mutation>[
      _set('collection/key', map(<dynamic>['bar', 'bar-value'])),
      _patch(
          'collection/key',
          map(<dynamic>[
            'foo',
            'foo-patched-value',
            'bar.baz',
            firestore.FieldValue.serverTimestamp()
          ])),
    ]);
  });

  test('testOverlayWithFieldDeletionOfNestedField', () {
    _verifyOverlayRoundTrips(
        doc('collection/key', 1, map(<dynamic>['foo', 1])), <Mutation>[
      _patch(
          'collection/key',
          map(<dynamic>[
            'foo',
            'foo-patched-value',
            'bar.baz',
            firestore.FieldValue.increment(1)
          ])),
      _patch(
          'collection/key',
          map(<dynamic>[
            'foo',
            'foo-patched-value',
            'bar.baz',
            firestore.FieldValue.serverTimestamp()
          ])),
      _patch(
          'collection/key',
          map(<dynamic>[
            'foo',
            'foo-patched-value',
            'bar.baz',
            firestore.FieldValue.delete()
          ])),
    ]);
  });

  test('testOverlayCreatedFromSetToEmptyWithMerge', () {
    final Mutation merge =
        _merge('collection/key', <String, Object?>{}, <String>[]);
    _verifyOverlayRoundTrips(
        deletedDoc('collection/key', 1), <Mutation>[merge]);
    _verifyOverlayRoundTrips(
        doc('collection/key', 1, map(<dynamic>['foo', 'foo-value'])),
        <Mutation>[merge]);
  });

  test('testDeviationPatchWithEmptyMaskKeepsAnOverlay', () {
    // DEVIATION FROM UPSTREAM (empty patch mask): Mutation.calculateOverlayMutation returns null upstream whenever the
    // mask is empty, which loses a document created by `set({}, merge: true)` and the pending write state of an
    // existing one. The port keeps a patch overlay with an empty mask.
    final Mutation merge =
        _merge('collection/key', <String, Object?>{}, <String>[]);
    for (final MaybeDocument base in <MaybeDocument>[
      deletedDoc('collection/key', 1),
      doc('collection/key', 1, map(<dynamic>['foo', 'foo-value'])),
    ]) {
      final (MaybeDocument? local, FieldMask? mask) = merge
          .applyToLocalViewWithMask(base, base, FieldMask.empty, Timestamp.now());
      expect(mask, FieldMask.empty);
      final Mutation? overlay = Mutation.calculateOverlayMutation(local, mask);
      expect(overlay, isA<PatchMutation>());
      expect((overlay! as PatchMutation).mask.mask, isEmpty);
      expect(overlay.precondition, Precondition.none);
    }
    // No mutation applied: no overlay.
    expect(
        Mutation.calculateOverlayMutation(
            doc('collection/key', 1, map(<dynamic>['foo', 1])), FieldMask.empty),
        isNull);
    expect(Mutation.calculateOverlayMutation(null, FieldMask.empty), isNull);
  });

  test('testOverlayKeepsPendingServerTimestamps', () {
    // A pending server timestamp (with its previous value) is part of the patch overlay and must be stored as such.
    final MaybeDocument base =
        doc('collection/key', 1, map(<dynamic>['time', 42, 'other', true]));
    final Mutation patch = _patch('collection/key',
        map(<dynamic>['time', firestore.FieldValue.serverTimestamp()]));
    final (MaybeDocument? local, FieldMask? mask) = patch
        .applyToLocalViewWithMask(base, base, FieldMask.empty, Timestamp.now());
    final Mutation overlay = Mutation.calculateOverlayMutation(local, mask)!;
    expect(
        _serializer
            .decodeOverlayMutation(_serializer.encodeOverlayMutation(overlay)),
        overlay);
    expect(overlay.applyToLocalView(base, base, Timestamp.now()), local);
  });

  // Below tests run on automatically generated mutation list, they are deterministic, but hard to debug when they
  // fail. They will print the failure case, and the best way to debug is recreate the case manually in a separate test.

  test('testOverlayWithMutationWithMultipleDeletes', () {
    final List<MaybeDocument?> docs = <MaybeDocument?>[
      doc('collection/key', 1,
          map(<dynamic>['foo', 'foo-value', 'bar.baz', 1])),
      deletedDoc('collection/key', 1),
      unknownDoc('collection/key', 1),
    ];
    final List<Mutation> mutations = <Mutation>[
      _set('collection/key', map(<dynamic>['bar', 'bar-value'])),
      _delete('collection/key'),
      _delete('collection/key'),
      _patch(
          'collection/key',
          map(<dynamic>[
            'foo',
            'foo-patched-value',
            'bar.baz',
            firestore.FieldValue.serverTimestamp()
          ])),
    ];

    // There are 4! * 3 cases
    expect(_runPermutationTests(docs, mutations), 72);
  });

  test('testOverlayByCombinationsAndPermutations', () {
    final List<MaybeDocument?> docs = <MaybeDocument?>[
      doc('collection/key', 1, map(<dynamic>['foo', 'foo-value', 'bar', 1])),
      deletedDoc('collection/key', 1),
      unknownDoc('collection/key', 1),
    ];
    final List<Mutation> mutations = <Mutation>[
      _set('collection/key', map(<dynamic>['bar', 'bar-value'])),
      _set('collection/key', map(<dynamic>['bar.rab', 'bar.rab-value'])),
      _delete('collection/key'),
      _patch(
          'collection/key',
          map(<dynamic>[
            'foo',
            'foo-patched-value-incr',
            'bar',
            firestore.FieldValue.increment(1)
          ])),
      _patch(
          'collection/key',
          map(<dynamic>[
            'foo',
            'foo-patched-value-delete',
            'bar',
            firestore.FieldValue.delete()
          ])),
      _patch(
          'collection/key',
          map(<dynamic>[
            'foo',
            'foo-patched-value-st',
            'bar',
            firestore.FieldValue.serverTimestamp()
          ])),
      _merge(
          'collection/key',
          map(<dynamic>[
            'arrays',
            firestore.FieldValue.arrayUnion(<int>[1, 2, 3])
          ]),
          <String>['arrays']),
    ];

    // There are (0! + 7*1! + 21*2! + 35*3! + 35*4! + 21*5! + 7*6! + 7!) * 3 = 41100 cases.
    expect(_runCombinationTests(docs, mutations), 41100);
  });

  test('testOverlayByCombinationsAndPermutations_ArrayTransforms', () {
    final List<MaybeDocument?> docs = <MaybeDocument?>[
      doc('collection/key', 1,
          map(<dynamic>['foo', 'foo-value', 'bar.baz', 1])),
      deletedDoc('collection/key', 1),
      unknownDoc('collection/key', 1),
    ];
    final List<Mutation> mutations = <Mutation>[
      _set('collection/key', map(<dynamic>['bar', 'bar-value'])),
      _merge(
          'collection/key',
          map(<dynamic>[
            'foo',
            'xxx',
            'arrays',
            firestore.FieldValue.arrayRemove(<int>[2])
          ]),
          <String>['foo']),
      _delete('collection/key'),
      _patch(
          'collection/key',
          map(<dynamic>[
            'foo',
            'foo-patched-value-1',
            'arrays',
            firestore.FieldValue.arrayUnion(<int>[4, 5])
          ])),
      _patch(
          'collection/key',
          map(<dynamic>[
            'foo',
            'foo-patched-value-2',
            'arrays',
            firestore.FieldValue.arrayRemove(<int>[5, 6])
          ])),
      _merge(
          'collection/key',
          map(<dynamic>[
            'foo',
            'yyy',
            'arrays',
            firestore.FieldValue.arrayUnion(<int>[1, 2, 3, 999])
          ]),
          <String>['foo']),
    ];

    // There are (0! + 6*1! + 15*2! + 20*3! + 15*4! + 6*5! + 6!) * 3 = 5871 cases.
    expect(_runCombinationTests(docs, mutations), 5871);
  });

  test('testOverlayByCombinationsAndPermutations_Increments', () {
    final List<MaybeDocument?> docs = <MaybeDocument?>[
      doc('collection/key', 1, map(<dynamic>['foo', 'foo-value', 'bar', 1])),
      deletedDoc('collection/key', 1),
      unknownDoc('collection/key', 1),
    ];
    final List<Mutation> mutations = <Mutation>[
      _set('collection/key', map(<dynamic>['bar', 'bar-value'])),
      _merge(
          'collection/key',
          map(<dynamic>[
            'foo',
            'foo-merge',
            'bar',
            firestore.FieldValue.increment(2)
          ]),
          <String>['foo']),
      _delete('collection/key'),
      _patch(
          'collection/key',
          map(<dynamic>[
            'foo',
            'foo-patched-value-1',
            'bar',
            firestore.FieldValue.increment(-1.4)
          ])),
      _patch(
          'collection/key',
          map(<dynamic>[
            'foo',
            'foo-patched-value-2',
            'bar',
            firestore.FieldValue.increment(3.3)
          ])),
      _merge(
          'collection/key',
          map(<dynamic>[
            'foo',
            'yyy',
            'bar',
            firestore.FieldValue.increment(-41)
          ]),
          <String>['foo']),
    ];

    // There are (0! + 6*1! + 15*2! + 20*3! + 15*4! + 6*5! + 6!) * 3 = 5871 cases.
    expect(_runCombinationTests(docs, mutations), 5871);
  });
}

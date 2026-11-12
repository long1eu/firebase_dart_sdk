import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/index_helpers.dart';
import '../../../../util/test_util.dart';

/// Port of FieldIndexTest of the Android SDK.
void main() {
  test('comparatorIncludesCollectionGroup', () {
    final FieldIndex indexOriginal = fieldIndex('collA');
    final FieldIndex indexSame = fieldIndex('collA');
    final FieldIndex indexDifferent = fieldIndex('collB');
    expect(FieldIndex.semanticCompare(indexOriginal, indexSame), 0);
    expect(FieldIndex.semanticCompare(indexOriginal, indexDifferent), -1);
  });

  test('comparatorIgnoresIndexId', () {
    final FieldIndex indexOriginal = fieldIndex('collA', indexId: 1);
    final FieldIndex indexSame = fieldIndex('collA', indexId: 1);
    final FieldIndex indexDifferent = fieldIndex('collA', indexId: 2);
    expect(FieldIndex.semanticCompare(indexOriginal, indexSame), 0);
    expect(FieldIndex.semanticCompare(indexOriginal, indexDifferent), 0);
  });

  test('comparatorIgnoresIndexState', () {
    final FieldIndex indexOriginal = fieldIndex('collA', indexId: 1);
    final FieldIndex indexSame = fieldIndex('collA', indexId: 1);
    final FieldIndex indexDifferent = fieldIndex('collA',
        indexId: 1,
        indexState:
            IndexState(1, IndexOffset(version(2), DocumentKey.empty(), -1)));
    expect(FieldIndex.semanticCompare(indexOriginal, indexSame), 0);
    expect(FieldIndex.semanticCompare(indexOriginal, indexDifferent), 0);
  });

  test('comparatorIncludesFieldName', () {
    final FieldIndex indexOriginal = fieldIndex('collA',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]);
    final FieldIndex indexSame = fieldIndex('collA',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]);
    final FieldIndex indexDifferent = fieldIndex('collA',
        fieldsAndKinds: <Object>['b', SegmentKind.ascending]);
    expect(FieldIndex.semanticCompare(indexOriginal, indexSame), 0);
    expect(FieldIndex.semanticCompare(indexOriginal, indexDifferent), -1);
  });

  test('comparatorIncludesSegmentKind', () {
    final FieldIndex indexOriginal = fieldIndex('collA',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]);
    final FieldIndex indexSame = fieldIndex('collA',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]);
    final FieldIndex indexDifferent = fieldIndex('collA',
        fieldsAndKinds: <Object>['a', SegmentKind.descending]);
    expect(FieldIndex.semanticCompare(indexOriginal, indexSame), 0);
    expect(FieldIndex.semanticCompare(indexOriginal, indexDifferent), -1);
  });

  test('comparatorIncludesSegmentLength', () {
    final FieldIndex indexOriginal = fieldIndex('collA',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]);
    final FieldIndex indexSame = fieldIndex('collA',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]);
    final FieldIndex indexDifferent = fieldIndex('collA',
        fieldsAndKinds: <Object>[
          'a',
          SegmentKind.ascending,
          'b',
          SegmentKind.ascending
        ]);
    expect(FieldIndex.semanticCompare(indexOriginal, indexSame), 0);
    expect(FieldIndex.semanticCompare(indexOriginal, indexDifferent), -1);
    expect(FieldIndex.semanticCompare(indexDifferent, indexOriginal), 1);
  });

  test('indexOffsetComparator', () {
    final IndexOffset docAOffset = IndexOffset(version(1), key('foo/a'), -1);
    final IndexOffset docBOffset = IndexOffset(version(1), key('foo/b'), -1);
    final IndexOffset version1Offset =
        IndexOffset.createSuccessor(version(1), -1);
    final IndexOffset docCOffset = IndexOffset(version(2), key('foo/c'), -1);
    final IndexOffset version2Offset =
        IndexOffset.createSuccessor(version(2), -1);

    expect(docAOffset.compareTo(docBOffset), -1);
    expect(docAOffset.compareTo(version1Offset), -1);
    expect(version1Offset.compareTo(docCOffset), -1);
    expect(version1Offset.compareTo(version2Offset), -1);
    expect(docCOffset.compareTo(version2Offset), -1);
  });

  test('indexOffsetAdvancesSeconds', () {
    final IndexOffset actualSuccessor = IndexOffset.createSuccessor(
        const SnapshotVersion(Timestamp(1, 999999999)), -1);
    final IndexOffset expectedSuccessor = IndexOffset(
        const SnapshotVersion(Timestamp(2, 0)), DocumentKey.empty(), -1);
    expect(actualSuccessor, expectedSuccessor);
  });

  // Not upstream: the accessors and value semantics the index manager uses.
  test('directional and array segments', () {
    final FieldIndex index = fieldIndex('collA', fieldsAndKinds: <Object>[
      'a',
      SegmentKind.ascending,
      'tags',
      SegmentKind.contains,
      'b',
      SegmentKind.descending
    ]);
    expect(index.directionalSegments, <IndexSegment>[
      IndexSegment(field('a'), SegmentKind.ascending),
      IndexSegment(field('b'), SegmentKind.descending),
    ]);
    expect(
        index.arraySegment, IndexSegment(field('tags'), SegmentKind.contains));
    expect(fieldIndex('collA').arraySegment, isNull);
  });

  test('equality includes the id, the segments and the state', () {
    FieldIndex create({int id = 1, SegmentKind kind = SegmentKind.ascending}) =>
        fieldIndex('collA', indexId: id, fieldsAndKinds: <Object>['a', kind]);
    expect(create(), create());
    expect(create().hashCode, create().hashCode);
    expect(create(), isNot(create(id: 2)));
    expect(create(), isNot(create(kind: SegmentKind.descending)));
    expect(
        create(),
        isNot(fieldIndex('collA',
            indexId: 1,
            indexState: IndexState(1, IndexOffset.none),
            fieldsAndKinds: <Object>['a', SegmentKind.ascending])));
  });

  test('the initial state has no offset', () {
    expect(FieldIndex.initialState.sequenceNumber, 0);
    expect(FieldIndex.initialState.offset.readTime, SnapshotVersion.none);
    expect(FieldIndex.initialState.offset.documentKey, DocumentKey.empty());
    expect(FieldIndex.initialState.offset.largestBatchId, -1);
  });
}

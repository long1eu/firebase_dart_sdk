import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';

import 'test_util.dart';

/// `TestUtil.fieldIndex` of the Android SDK: [fieldsAndKinds] alternates field
/// paths and [SegmentKind]s.
FieldIndex fieldIndex(
  String collectionGroup, {
  int indexId = FieldIndex.unknownId,
  IndexState? indexState,
  List<Object> fieldsAndKinds = const <Object>[],
}) {
  final List<IndexSegment> segments = <IndexSegment>[
    for (int i = 0; i < fieldsAndKinds.length; i += 2)
      IndexSegment(field(fieldsAndKinds[i] as String),
          fieldsAndKinds[i + 1] as SegmentKind),
  ];
  return FieldIndex(indexId, collectionGroup, segments,
      indexState ?? FieldIndex.initialState);
}

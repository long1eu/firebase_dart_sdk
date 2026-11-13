// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/server_timestamp_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/unknown_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/admin/v1/index.dart'
    as admin;
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto_;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

import '../../../../util/index_helpers.dart';
import '../../../../util/test_util.dart';

void main() {
  late RemoteSerializer remoteSerializer;
  late LocalSerializer serializer;

  setUp(() {
    final DatabaseId databaseId = DatabaseId.forDatabase('p', 'd');
    remoteSerializer = RemoteSerializer(databaseId);
    serializer = LocalSerializer(remoteSerializer);
  });

  test('testEncodesMutationBatch', () {
    final Mutation baseWrite = PatchMutation(
      key('foo/bar'),
      wrapMap(map(<String>['a', 'b'])),
      FieldMask(<FieldPath>{field('a')}),
      Precondition.none,
    );
    final Mutation set = setMutation(
      'foo/bar',
      map(<dynamic>['a', 'b', 'num', 1]),
    );
    final Mutation patch = PatchMutation(
      key('bar/baz'),
      wrapMap(map(<dynamic>['a', 'b', 'num', 1])),
      fieldMask(<String>['a']),
      Precondition(exists: true),
    );

    final Mutation del = deleteMutation('baz/quux');
    final Timestamp writeTime = Timestamp.now();
    final MutationBatch model = MutationBatch(
      batchId: 42,
      localWriteTime: writeTime,
      baseMutations: <Mutation>[baseWrite],
      mutations: <Mutation>[set, patch, del],
    );

    final proto.Write baseWriteProto = proto.Write()
      ..update = (proto.Document()
        ..name = 'projects/p/databases/d/documents/foo/bar'
        ..fields['a'] = (proto_.Value()..stringValue = 'b'))
      ..updateMask = (proto.DocumentMask()..fieldPaths.add('a'));

    final proto.Write setProto =
        (proto.Write.create()
            ..update = (proto.Document.create()
              ..name = 'projects/p/databases/d/documents/foo/bar'
              ..fields['a'] = (proto_.Value.create()..stringValue = 'b')
              ..fields['num'] = (proto_.Value.create()
                ..integerValue = Int64(1))))
          ..freeze();

    final proto.Write patchProto =
        (proto.Write.create()
            ..update = (proto.Document.create()
              ..name = 'projects/p/databases/d/documents/bar/baz'
              ..fields['a'] = (proto_.Value.create()..stringValue = 'b')
              ..fields['num'] = (proto_.Value.create()
                ..integerValue = Int64(1)))
            ..updateMask = (proto.DocumentMask.create()..fieldPaths.add('a'))
            ..currentDocument = (proto.Precondition.create()..exists = true))
          ..freeze();

    final proto.Write delProto =
        (proto.Write.create()
            ..delete = 'projects/p/databases/d/documents/baz/quux')
          ..freeze();

    final proto.Timestamp writeTimeProto =
        (proto.Timestamp()
            ..seconds = Int64(writeTime.seconds)
            ..nanos = writeTime.nanoseconds)
          ..freeze();

    final proto.WriteBatch batchProto =
        (proto.WriteBatch.create()
            ..batchId = 42
            ..baseWrites.add(baseWriteProto)
            ..writes.addAll(<proto.Write>[setProto, patchProto, delProto])
            ..localWriteTime = writeTimeProto)
          ..freeze();

    expect(serializer.encodeMutationBatch(model), batchProto);
    final MutationBatch decoded = serializer.decodeMutationBatch(batchProto);
    expect(decoded.batchId, model.batchId);
    expect(decoded.localWriteTime, model.localWriteTime);
    expect(decoded.mutations, model.mutations);
    expect(decoded.baseMutations, model.baseMutations);
    expect(decoded.keys, model.keys);
  });

  group('transforms', () {
    proto.Write docWrite(
      String path, {
      bool mask = false,
      bool exists = false,
      String? value,
    }) {
      final proto.Write write = proto.Write.create()
        ..update = (proto.Document.create()
          ..name = 'projects/p/databases/d/documents/$path');
      if (value != null) {
        write.update.fields['a'] = (proto_.Value.create()..stringValue = value);
      }
      if (mask) {
        write.updateMask = proto.DocumentMask.create()..fieldPaths.add('a');
      }
      if (exists) {
        write.currentDocument = proto.Precondition.create()..exists = true;
      }
      return write;
    }

    proto_.DocumentTransform_FieldTransform serverTimestamp(String path) {
      return proto_.DocumentTransform_FieldTransform.create()
        ..fieldPath = path
        ..setToServerValue =
            proto_.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME;
    }

    proto.Write legacyTransform(String path, List<String> fields) {
      return proto.Write.create()
        ..transform = (proto.DocumentTransform.create()
          ..document = 'projects/p/databases/d/documents/$path'
          ..fieldTransforms.addAll(fields.map(serverTimestamp)))
        ..currentDocument = (proto.Precondition.create()..exists = true);
    }

    proto.WriteBatch batchOf(
      List<proto.Write> writes, {
      List<proto.Write> base = const <proto.Write>[],
    }) {
      return (proto.WriteBatch.create()
          ..batchId = 7
          ..baseWrites.addAll(base)
          ..writes.addAll(writes)
          ..localWriteTime = (proto.Timestamp()
            ..seconds = Int64(1)
            ..nanos = 2))
        ..freeze();
    }

    final List<FieldTransform> twoTransforms = <FieldTransform>[
      FieldTransform(field('t1'), ServerTimestampOperation()),
      FieldTransform(field('t2'), ServerTimestampOperation()),
    ];

    test('testEncodesAndDecodesMutationBatchWithTransforms', () {
      final Mutation set = SetMutation(
        key('foo/bar'),
        wrapMap(map(<String>['a', 'b'])),
        Precondition.none,
        twoTransforms,
      );
      final Mutation patch = PatchMutation(
        key('foo/baz'),
        wrapMap(map(<String>['a', 'b'])),
        fieldMask(<String>['a']),
        Precondition(exists: true),
        twoTransforms,
      );
      final MutationBatch model = MutationBatch(
        batchId: 7,
        localWriteTime: const Timestamp(1, 2),
        baseMutations: <Mutation>[],
        mutations: <Mutation>[set, patch],
      );

      final proto.WriteBatch encoded = serializer.encodeMutationBatch(model);
      expect(encoded.writes, hasLength(2));
      expect(encoded.writes[0].hasTransform(), isFalse);
      expect(encoded.writes[0].updateTransforms, hasLength(2));
      expect(encoded.writes[1].updateTransforms, hasLength(2));

      final MutationBatch decoded = serializer.decodeMutationBatch(encoded);
      expect(decoded.mutations, <Mutation>[set, patch]);
    });

    test('testDecodesLegacyTransformSquashedIntoPrecedingSet', () {
      final proto.WriteBatch legacy = batchOf(<proto.Write>[
        docWrite('foo/bar', value: 'b'),
        legacyTransform('foo/bar', <String>['t1', 't2']),
      ]);
      final MutationBatch decoded = serializer.decodeMutationBatch(legacy);
      expect(decoded.mutations, <Mutation>[
        SetMutation(
          key('foo/bar'),
          wrapMap(map(<String>['a', 'b'])),
          Precondition.none,
          twoTransforms,
        ),
      ]);
    });

    test('testDecodesLegacyTransformSquashedIntoPrecedingPatch', () {
      final proto.WriteBatch legacy = batchOf(<proto.Write>[
        docWrite('foo/bar', value: 'b', mask: true, exists: true),
        legacyTransform('foo/bar', <String>['t1', 't2']),
        (proto.Write.create()
          ..delete = 'projects/p/databases/d/documents/foo/gone'),
        docWrite('foo/baz', value: 'c'),
        legacyTransform('foo/baz', <String>['t1']),
        docWrite('foo/plain', value: 'd'),
      ]);
      final MutationBatch decoded = serializer.decodeMutationBatch(legacy);
      expect(decoded.mutations, <Mutation>[
        PatchMutation(
          key('foo/bar'),
          wrapMap(map(<String>['a', 'b'])),
          fieldMask(<String>['a']),
          Precondition(exists: true),
          twoTransforms,
        ),
        deleteMutation('foo/gone'),
        SetMutation(
          key('foo/baz'),
          wrapMap(map(<String>['a', 'c'])),
          Precondition.none,
          twoTransforms.sublist(0, 1),
        ),
        SetMutation(
          key('foo/plain'),
          wrapMap(map(<String>['a', 'd'])),
          Precondition.none,
        ),
      ]);
      expect(decoded.batchId, 7);
    });

    test('testDecodesLegacyTransformAloneAsExistingDocumentPatch', () {
      final proto.WriteBatch legacy = batchOf(<proto.Write>[
        legacyTransform('foo/bar', <String>['t1', 't2']),
      ]);
      final MutationBatch decoded = serializer.decodeMutationBatch(legacy);
      expect(decoded.mutations, <Mutation>[
        PatchMutation(
          key('foo/bar'),
          ObjectValue.empty,
          const FieldMask(<FieldPath>{}),
          Precondition(exists: true),
          twoTransforms,
        ),
      ]);
    });

    test('testLegacyBatchEvaluatesLikeBeforeTheFold', () {
      // [set {a: 'b'}, transform t1] must behave like the folded set when applied.
      final proto.WriteBatch legacy = batchOf(<proto.Write>[
        docWrite('foo/bar', value: 'b'),
        legacyTransform('foo/bar', <String>['t1']),
      ]);
      final Mutation mutation = serializer
          .decodeMutationBatch(legacy)
          .mutations
          .single;
      final Document result =
          mutation.applyToLocalView(null, null, const Timestamp(5, 0))!
              as Document;
      expect(result.data.get(field('a')), wrap('b'));
      expect(result.data.get(field('t1')), isA<ServerTimestampValue>());
    });
  });

  test('testEncodesDocumentAsMaybeDocument', () {
    final Document document = doc('some/path', 42, map(<String>['foo', 'bar']));

    final proto.MaybeDocument maybeDocProto = proto.MaybeDocument.create()
      ..document = (proto.Document.create()
        ..name = 'projects/p/databases/d/documents/some/path'
        ..fields['foo'] = (proto_.Value.create()..stringValue = 'bar')
        ..updateTime = (proto.Timestamp()
          ..seconds = Int64()
          ..nanos = 42000))
      ..hasCommittedMutations = false;

    expect(serializer.encodeMaybeDocument(document), maybeDocProto);
    final MaybeDocument decoded = serializer.decodeMaybeDocument(maybeDocProto);
    expect(decoded, document);
  });

  test('testEncodesDeletedDocumentAsMaybeDocument', () {
    final NoDocument deletedDocument = deletedDoc('some/path', 42);

    final proto.MaybeDocument maybeDocProto =
        (proto.MaybeDocument.create()
            ..noDocument = (proto.NoDocument.create()
              ..name = 'projects/p/databases/d/documents/some/path'
              ..readTime = (proto.Timestamp()
                ..seconds = Int64()
                ..nanos = 42000))
            ..hasCommittedMutations = false)
          ..freeze();

    expect(serializer.encodeMaybeDocument(deletedDocument), maybeDocProto);
    final MaybeDocument decoded = serializer.decodeMaybeDocument(maybeDocProto);
    expect(decoded, deletedDocument);
  });

  test('testEncodesUnknownDocumentAsMaybeDocument', () {
    final UnknownDocument unknownDocument = unknownDoc('some/path', 42);

    final proto.MaybeDocument maybeDocProto = proto.MaybeDocument.create()
      ..unknownDocument = (proto.UnknownDocument.create()
        ..name = 'projects/p/databases/d/documents/some/path'
        ..version = (proto.Timestamp()
          ..seconds = Int64()
          ..nanos = 42000))
      ..hasCommittedMutations = true
      ..freeze();

    expect(serializer.encodeMaybeDocument(unknownDocument), maybeDocProto);
    final MaybeDocument decoded = serializer.decodeMaybeDocument(maybeDocProto);
    expect(decoded, unknownDocument);
  });

  test('testEncodesQueryData', () {
    final Query _query = query('room');
    const int targetId = 42;
    const int sequenceNumber = 10;
    final SnapshotVersion _version = version(1039);
    final SnapshotVersion limboFreeVersion = version(1000);
    final Uint8List _resumeToken = resumeToken(1039)!;

    final QueryData queryData = QueryData(
      _query.toTarget(),
      targetId,
      sequenceNumber,
      QueryPurpose.listen,
      _version,
      _resumeToken,
      null,
      limboFreeVersion,
    );

    // Let the RPC serializer test various permutations of query serialization.
    final proto.Target_QueryTarget queryTarget = remoteSerializer
        .encodeQueryTarget(_query.toTarget());

    final proto.Target expected =
        (proto.Target.create()
            ..targetId = targetId
            ..lastListenSequenceNumber = Int64(sequenceNumber)
            ..snapshotVersion = (proto.Timestamp()
              ..seconds = Int64()
              ..nanos = 1039000)
            ..resumeToken = _resumeToken
            ..query = (proto.Target_QueryTarget.create()
              ..parent = queryTarget.parent
              ..structuredQuery = queryTarget.structuredQuery)
            ..lastLimboFreeSnapshotVersion = (proto.Timestamp()
              ..seconds = Int64()
              ..nanos = 1000000))
          ..freeze();

    expect(serializer.encodeQueryData(queryData), expected);
    final QueryData decoded = serializer.decodeQueryData(expected);
    expect(decoded, queryData);
  });

  test('localSerializerShouldDropExpectedCountInQueryData', () {
    final Query _query = query('room');
    final QueryData queryData = QueryData(
      _query.toTarget(),
      42,
      10,
      QueryPurpose.listen,
      version(1039),
      resumeToken(1039)!,
      1234,
    );

    final proto.Target encoded = serializer.encodeQueryData(queryData);
    final QueryData decoded = serializer.decodeQueryData(encoded);
    // The expected count is not persisted: it is recomputed for every listen request.
    expect(decoded, queryData.withExpectedCount(null));
  });

  /// Port of the JS SDK's `serializes overlay` (local_serializer.test.ts). The collection path, document id, collection
  /// group and largest batch id are columns of the SQLite overlay table; the serializer encodes the mutation.
  test('serializes overlay', () {
    final Mutation m = patchMutation(
      'coll1/doc1/coll2/doc2',
      map(<dynamic>['foo', 'bar']),
    );

    final proto.Write serialized = serializer.encodeOverlayMutation(m);
    expect(serialized, remoteSerializer.encodeMutation(m));

    expect(serializer.decodeOverlayMutation(serialized), m);
  });

  /// Port of the JS SDK's `serializes FieldIndex` (local_serializer.test.ts). The collection group and index id are
  /// columns of the SQLite index configuration table; the serializer encodes the segments.
  test('serializes FieldIndex', () {
    final FieldIndex index = fieldIndex(
      'foo',
      fieldsAndKinds: <Object>[
        'a',
        SegmentKind.ascending,
        'b',
        SegmentKind.descending,
        'c',
        SegmentKind.contains,
      ],
    );

    final admin.Index encoded = serializer.encodeFieldIndexSegments(
      index.segments,
    );
    expect(
      <Object>[
        for (final admin.Index_IndexField field in encoded.fields)
          field.whichValueMode() == admin.Index_IndexField_ValueMode.arrayConfig
              ? <Object>[field.fieldPath, field.arrayConfig]
              : <Object>[field.fieldPath, field.order],
      ],
      <Object>[
        <Object>['a', admin.Index_IndexField_Order.ASCENDING],
        <Object>['b', admin.Index_IndexField_Order.DESCENDING],
        <Object>['c', admin.Index_IndexField_ArrayConfig.CONTAINS],
      ],
    );

    expect(serializer.decodeFieldIndexSegments(encoded), index.segments);
  });
}

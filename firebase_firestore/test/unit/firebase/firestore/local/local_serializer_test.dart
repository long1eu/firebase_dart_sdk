// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:typed_data';

import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/unknown_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/index.dart' as proto_beta;
import 'package:firebase_firestore/src/proto/google/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  RemoteSerializer remoteSerializer;
  LocalSerializer serializer;

  setUp(() {
    final DatabaseId databaseId = DatabaseId.forDatabase('p', 'd');
    remoteSerializer = RemoteSerializer(databaseId);
    serializer = LocalSerializer(remoteSerializer);
  });

  test('testEncodesMutationBatch', () {
    final Mutation set = setMutation('foo/bar', map(<dynamic>['a', 'b', 'num', 1]));
    final Mutation patch = PatchMutation(key('bar/baz'), wrapMap(map(<dynamic>['a', 'b', 'num', 1])),
        fieldMask(<String>['a']), Precondition(exists: true));

    final Mutation del = deleteMutation('baz/quux');
    final Timestamp writeTime = Timestamp.now();
    final MutationBatch model = MutationBatch(42, writeTime, <Mutation>[set, patch, del]);

    final proto.Write setProto = (proto.Write.create()
          ..update = (proto.Document.create()
            ..name = 'projects/p/databases/d/documents/foo/bar'
            ..fields['a'] = (proto_beta.Value.create()..stringValue = 'b')
            ..fields['num'] = (proto_beta.Value.create()..integerValue = Int64(1))))
        .freeze();

    final proto.Write patchProto = (proto.Write.create()
          ..update = (proto.Document.create()
            ..name = 'projects/p/databases/d/documents/bar/baz'
            ..fields['a'] = (proto_beta.Value.create()..stringValue = 'b')
            ..fields['num'] = (proto_beta.Value.create()..integerValue = Int64(1)))
          ..updateMask = (proto.DocumentMask.create()..fieldPaths.add('a'))
          ..currentDocument = (proto.Precondition.create()..exists = true))
        .freeze();

    final proto.Write delProto = (proto.Write.create()..delete = 'projects/p/databases/d/documents/baz/quux').freeze();

    final proto.Timestamp writeTimeProto = (proto.Timestamp.create()
          ..seconds = Int64(writeTime.seconds)
          ..nanos = writeTime.nanoseconds)
        .freeze();

    final proto.WriteBatch batchProto = (proto.WriteBatch.create()
          ..batchId = 42
          ..writes.addAll(<proto.Write>[setProto, patchProto, delProto])
          ..localWriteTime = writeTimeProto)
        .freeze();

    expect(serializer.encodeMutationBatch(model), batchProto);
    final MutationBatch decoded = serializer.decodeMutationBatch(batchProto);
    expect(decoded.batchId, model.batchId);
    expect(decoded.localWriteTime, model.localWriteTime);
    expect(decoded.mutations, model.mutations);
    expect(decoded.keys, model.keys);
  });

  test('testEncodesDocumentAsMaybeDocument', () {
    final Document document = doc('some/path', 42, map(<String>['foo', 'bar']));

    final proto.MaybeDocument maybeDocProto = proto.MaybeDocument.create()
      ..document = (proto.Document.create()
        ..name = 'projects/p/databases/d/documents/some/path'
        ..fields['foo'] = (proto_beta.Value.create()..stringValue = 'bar')
        ..updateTime = (proto.Timestamp.create()
          ..seconds = Int64()
          ..nanos = 42000))
      ..hasCommittedMutations = false;

    expect(serializer.encodeMaybeDocument(document), maybeDocProto);
    final MaybeDocument decoded = serializer.decodeMaybeDocument(maybeDocProto);
    expect(decoded, document);
  });

  test('testEncodesDeletedDocumentAsMaybeDocument', () {
    final NoDocument deletedDocument = deletedDoc('some/path', 42);

    final proto.MaybeDocument maybeDocProto = (proto.MaybeDocument.create()
          ..noDocument = (proto.NoDocument.create()
            ..name = 'projects/p/databases/d/documents/some/path'
            ..readTime = (proto.Timestamp.create()
              ..seconds = Int64()
              ..nanos = 42000))
          ..hasCommittedMutations = false)
        .freeze();

    expect(serializer.encodeMaybeDocument(deletedDocument), maybeDocProto);
    final MaybeDocument decoded = serializer.decodeMaybeDocument(maybeDocProto);
    expect(decoded, deletedDocument);
  });

  test('testEncodesUnknownDocumentAsMaybeDocument', () {
    final UnknownDocument unknownDocument = unknownDoc('some/path', 42);

    final proto.MaybeDocument maybeDocProto = proto.MaybeDocument.create()
      ..unknownDocument = (proto.UnknownDocument.create()
        ..name = 'projects/p/databases/d/documents/some/path'
        ..version = (proto.Timestamp.create()
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
    final Uint8List _resumeToken = resumeToken(1039);

    final QueryData queryData = QueryData(
      _query,
      targetId,
      sequenceNumber,
      QueryPurpose.listen,
      _version,
      _resumeToken,
    );

    // Let the RPC serializer test various permutations of query serialization.
    final proto.Target_QueryTarget queryTarget = remoteSerializer.encodeQueryTarget(_query);

    final proto.Target expected = (proto.Target.create()
          ..targetId = targetId
          ..lastListenSequenceNumber = Int64(sequenceNumber)
          ..snapshotVersion = (proto.Timestamp.create()
            ..seconds = Int64()
            ..nanos = 1039000)
          ..resumeToken = _resumeToken
          ..query = (proto.Target_QueryTarget.create()
            ..parent = queryTarget.parent
            ..structuredQuery = queryTarget.structuredQuery))
        .freeze();

    expect(serializer.encodeQueryData(queryData), expected);
    final QueryData decoded = serializer.decodeQueryData(expected);
    expect(decoded, queryData);
  });
}

// Builds a SQLite cache the way cloud_firestore_vm 0.0.7 (the last version
// published before the rename, schema version 8) left it on disk.
//
// 0.0.7 is Dart 2.7 code and cannot run under Dart 3, so this file reproduces
// what it wrote, from its sources at git commit 515bcd0 (read them with
// `git show 515bcd0:cloud_firestore/cloud_firestore_vm/lib/src/firebase/firestore/<path>`):
//
//  * the tables: the DDL of `local/sqlite/sqlite_schema.dart` after
//    `runMigrations(0, 8)`, copied statement by statement into [_ddl];
//  * the rows: the INSERT statements and column values of
//    `local/sqlite/sqlite_{query_cache,remote_document_cache,mutation_queue,
//    lru_reference_delegate,index_manager}.dart`;
//  * the blobs: the protos of `local/local_serializer.dart` and
//    `remote/remote_serializer.dart`, built here field by field with the
//    generated proto classes (the .proto files are the same) and deliberately
//    NOT with the current serializers, so that this file keeps describing the
//    old format when the serializers change;
//  * `canonical_id`: `core/query.dart` `Query.canonicalId` of 0.0.7, written
//    out as the string literals it produced.
//
// The result is committed as test/res/legacy/cloud_firestore_vm_0.0.7_schema8.db.
// Regenerate it with
//
//     UPDATE_GOLDEN=1 dart test test/unit/firebase/firestore/local/legacy_cache_upgrade_test.dart
//
// (legacy_cache_upgrade_test.dart fails when the committed file and this
// builder disagree). Do not change this file to make a newer SDK pass: 0.0.7
// is published and its format is fixed.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto_v1;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';

/// The schema version of 0.0.7 (`SQLiteSchema.version`).
const int legacySchemaVersion = 8;

const String legacyProjectId = 'legacy-project';
const String _documents =
    'projects/$legacyProjectId/databases/(default)/documents';

/// `uid` of the mutation queue of the unauthenticated user in 0.0.7:
/// `user.isAuthenticated ? user.uid : ''`.
const String legacyUid = '';

/// The stream token the write stream last got (`mutation_queues.last_stream_token`).
final Uint8List legacyStreamToken = Uint8List.fromList(utf8.encode('token-7'));

/// One target of the fixture.
class LegacyTarget {
  const LegacyTarget(
      this.targetId, this.canonicalId, this.sequenceNumber, this.documents);

  final int targetId;

  /// What 0.0.7 `Query.canonicalId` returned for the query.
  final String canonicalId;
  final int sequenceNumber;

  /// The paths of `target_documents`.
  final List<String> documents;
}

/// The targets, in the order of their ids (0.0.7 handed out even ids from 2).
const List<LegacyTarget> legacyTargets = <LegacyTarget>[
  // firestore.collection('rooms')
  LegacyTarget(
      2, 'rooms|f:|ob:__name__asc', 3, <String>['rooms/eros', 'rooms/hades']),
  // .collection('rooms').whereGreaterThan('members', 5)
  //     .orderBy('members', descending).limit(10)
  LegacyTarget(4, 'rooms|f:members > 5|ob:membersdesc__name__desc|l:10', 5,
      <String>['rooms/hades']),
  // firestore.document('rooms/eros')
  LegacyTarget(6, 'rooms/eros|f:|ob:__name__asc', 6, <String>['rooms/eros']),
  // firestore.collectionGroup('messages')
  LegacyTarget(8, '|cg:messages|f:|ob:__name__asc', 8,
      <String>['rooms/eros/messages/1']),
];

/// `target_globals.highest_listen_sequence_number`.
const int legacyHighestSequenceNumber = 9;

/// `target_globals.last_remote_snapshot_version_*`.
const int legacyLastRemoteSnapshotSeconds = 1586000300;

/// The id of the pending batch (`mutations.batch_id`).
const int legacyBatchId = 7;

/// `local/encoded_path.dart` of 0.0.7 (`EncodedPath.encode`): every segment
/// is followed by the separator `\u0001\u0001`, and `\u0000` / `\u0001` inside
/// a segment are escaped as `\u0001\u0010` / `\u0001\u0011`. The empty path
/// is one separator.
String legacyEncodePath(String path) {
  if (path.isEmpty) {
    return '\u0001\u0001';
  }
  final StringBuffer result = StringBuffer();
  for (final String segment in path.split('/')) {
    for (final int c in segment.codeUnits) {
      if (c == 0) {
        result
          ..writeCharCode(1)
          ..writeCharCode(0x10);
      } else if (c == 1) {
        result
          ..writeCharCode(1)
          ..writeCharCode(0x11);
      } else {
        result.writeCharCode(c);
      }
    }
    result
      ..writeCharCode(1)
      ..writeCharCode(1);
  }
  return result.toString();
}

/// `sqlite_schema.dart` of 0.0.7, the statements `runMigrations(0, 8)` runs.
const List<String> _ddl = <String>[
  // _createV1MutationQueue
  '''
  CREATE TABLE mutation_queues (
    uid                        TEXT PRIMARY KEY,
    last_acknowledged_batch_id INTEGER,
    last_stream_token          BLOB
  );''',
  '''
  CREATE TABLE mutations (
    uid       TEXT,
    batch_id  INTEGER,
    mutations BLOB,
    PRIMARY KEY (uid, batch_id)
  );''',
  '''
  CREATE TABLE document_mutations (
    uid      TEXT,
    path     TEXT,
    batch_id INTEGER,
    PRIMARY KEY (uid, path, batch_id)
  );''',
  // _createV1QueryCache
  '''
  CREATE TABLE targets (
    target_id                   INTEGER PRIMARY KEY,
    canonical_id                TEXT,
    snapshot_version_seconds    INTEGER,
    snapshot_version_nanos      INTEGER,
    resume_token                BLOB,
    last_listen_sequence_number INTEGER,
    target_proto                BLOB
  );''',
  'CREATE INDEX query_targets ON targets (canonical_id, target_id);',
  '''
  CREATE TABLE target_globals (
    highest_target_id                    INTEGER,
    highest_listen_sequence_number       INTEGER,
    last_remote_snapshot_version_seconds INTEGER,
    last_remote_snapshot_version_nanos   INTEGER
  );''',
  '''
  CREATE TABLE target_documents (
    target_id       INTEGER,
    path            TEXT,
    PRIMARY KEY (target_id, path)
  );''',
  'CREATE INDEX document_targets ON target_documents (path, target_id);',
  // _createV1RemoteDocumentCache
  '''
  CREATE TABLE remote_documents (
    path     TEXT PRIMARY KEY,
    contents BLOB
  );''',
  // _ensureTargetGlobal, _addTargetCount (v4)
  '''
  INSERT INTO target_globals
    (highest_target_id, highest_listen_sequence_number,
     last_remote_snapshot_version_seconds, last_remote_snapshot_version_nanos)
  VALUES (0, 0, 0, 0);''',
  'ALTER TABLE target_globals ADD COLUMN target_count INTEGER;',
  'UPDATE target_globals SET target_count = 0;',
  // _addSequenceNumber (v5)
  'ALTER TABLE target_documents ADD COLUMN sequence_number INTEGER;',
  // _createV8CollectionParentsIndex
  '''
  CREATE TABLE collection_parents (
    collection_id TEXT,
    parent        TEXT,
    PRIMARY KEY (collection_id, parent)
  );''',
];

proto.Timestamp _timestamp(int seconds, [int nanos = 0]) =>
    proto.Timestamp()
      ..seconds = Int64(seconds)
      ..nanos = nanos;

proto_v1.Value _string(String value) =>
    proto_v1.Value.create()..stringValue = value;

proto_v1.Value _int(int value) =>
    proto_v1.Value.create()..integerValue = Int64(value);

/// `LocalSerializer.encodeMaybeDocument` for a `Document` that came from the
/// backend (0.0.7 stored the proto it received, which has a create time).
proto.MaybeDocument _document(
    String path, Map<String, proto_v1.Value> fields, int updateSeconds) {
  return proto.MaybeDocument.create()
    ..document = (proto.Document.create()
      ..name = '$_documents/$path'
      ..fields.addAll(fields)
      ..createTime = _timestamp(1586000000)
      ..updateTime = _timestamp(updateSeconds))
    ..hasCommittedMutations = false;
}

/// `LocalSerializer.encodeMaybeDocument` for a `NoDocument`.
proto.MaybeDocument _noDocument(String path, int readSeconds) {
  return proto.MaybeDocument.create()
    ..noDocument = (proto.NoDocument.create()
      ..name = '$_documents/$path'
      ..readTime = _timestamp(readSeconds))
    ..hasCommittedMutations = false;
}

/// The remote documents of the fixture, by path.
Map<String, proto.MaybeDocument> legacyRemoteDocuments() {
  return <String, proto.MaybeDocument>{
    'rooms/eros': _document(
        'rooms/eros',
        <String, proto_v1.Value>{'name': _string('Eros'), 'members': _int(3)},
        1586000100),
    'rooms/hades': _document(
        'rooms/hades',
        <String, proto_v1.Value>{'name': _string('Hades'), 'members': _int(10)},
        1586000200),
    'rooms/eros/messages/1': _document('rooms/eros/messages/1',
        <String, proto_v1.Value>{'text': _string('hi')}, 1586000250),
    'rooms/gone': _noDocument('rooms/gone', 1586000260),
  };
}

proto.StructuredQuery_Order _order(
        String field, proto.StructuredQuery_Direction direction) =>
    proto.StructuredQuery_Order.create()
      ..field_1 =
          (proto.StructuredQuery_FieldReference.create()..fieldPath = field)
      ..direction = direction;

/// `LocalSerializer.encodeQueryData` (with `RemoteSerializer.encodeQueryTarget`
/// / `encodeDocumentsTarget`) for each of [legacyTargets].
Map<int, proto.Target> legacyTargetProtos() {
  proto.Target base(LegacyTarget target) => proto.Target.create()
    ..targetId = target.targetId
    ..lastListenSequenceNumber = Int64(target.sequenceNumber)
    ..snapshotVersion = _timestamp(1586000300)
    ..resumeToken = utf8.encode('resume-${target.targetId}');

  const proto.StructuredQuery_Direction asc =
      proto.StructuredQuery_Direction.ASCENDING;
  const proto.StructuredQuery_Direction desc =
      proto.StructuredQuery_Direction.DESCENDING;

  return <int, proto.Target>{
    2: base(legacyTargets[0])
      ..query = (proto.Target_QueryTarget.create()
        ..parent = _documents
        ..structuredQuery = (proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'rooms')
          ..orderBy.add(_order('__name__', asc)))),
    4: base(legacyTargets[1])
      ..query = (proto.Target_QueryTarget.create()
        ..parent = _documents
        ..structuredQuery = (proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'rooms')
          ..where = (proto.StructuredQuery_Filter.create()
            ..fieldFilter = (proto.StructuredQuery_FieldFilter.create()
              ..field_1 = (proto.StructuredQuery_FieldReference.create()
                ..fieldPath = 'members')
              ..op = proto.StructuredQuery_FieldFilter_Operator.GREATER_THAN
              ..value = _int(5)))
          ..orderBy.addAll(<proto.StructuredQuery_Order>[
            _order('members', desc),
            _order('__name__', desc),
          ])
          ..limit = (proto.Int32Value()..value = 10))),
    6: base(legacyTargets[2])
      ..documents = (proto.Target_DocumentsTarget.create()
        ..documents.add('$_documents/rooms/eros')),
    8: base(legacyTargets[3])
      ..query = (proto.Target_QueryTarget.create()
        ..parent = _documents
        ..structuredQuery = (proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'messages'
            ..allDescendants = true)
          ..orderBy.add(_order('__name__', asc)))),
  };
}

/// The pending batch, as `LocalSerializer.encodeMutationBatch` of 0.0.7 wrote
/// it for
///
///     batch.set(rooms/eros, {name: 'Eros II', updatedAt: serverTimestamp()})
///     batch.update(rooms/hades, {members: increment(1)})
///     batch.delete(rooms/gone)
///
/// 0.0.7 turned field transforms into a separate `TransformMutation` after
/// the set / patch (`UserDataParsedSetData.toMutationList`), encoded as a
/// `Write` with the `transform` field and an `exists: true` precondition.
/// Those are the "legacy transform writes" newer versions fold into the
/// preceding write when they load the batch. For the non-idempotent
/// increment, 0.0.7 also stored a base write with the value the document had.
proto.WriteBatch legacyPendingBatch() {
  proto.Precondition exists() => proto.Precondition.create()..exists = true;

  return proto.WriteBatch.create()
    ..batchId = legacyBatchId
    ..localWriteTime = _timestamp(1586000400, 5000)
    ..baseWrites.add(proto.Write.create()
      ..update = (proto.Document.create()
        ..name = '$_documents/rooms/hades'
        ..fields['members'] = _int(10))
      ..updateMask = (proto.DocumentMask.create()..fieldPaths.add('members'))
      ..currentDocument = exists())
    ..writes.addAll(<proto.Write>[
      proto.Write.create()
        ..update = (proto.Document.create()
          ..name = '$_documents/rooms/eros'
          ..fields['name'] = _string('Eros II')),
      proto.Write.create()
        ..transform = (proto.DocumentTransform.create()
          ..document = '$_documents/rooms/eros'
          ..fieldTransforms.add(proto.DocumentTransform_FieldTransform.create()
            ..fieldPath = 'updatedAt'
            ..setToServerValue = proto
                .DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME))
        ..currentDocument = exists(),
      proto.Write.create()
        ..update = (proto.Document.create()..name = '$_documents/rooms/hades')
        ..updateMask = proto.DocumentMask.create()
        ..currentDocument = exists(),
      proto.Write.create()
        ..transform = (proto.DocumentTransform.create()
          ..document = '$_documents/rooms/hades'
          ..fieldTransforms.add(proto.DocumentTransform_FieldTransform.create()
            ..fieldPath = 'members'
            ..increment = _int(1)))
        ..currentDocument = exists(),
      proto.Write.create()..delete = '$_documents/rooms/gone',
    ]);
}

/// The paths `document_mutations` has for the pending batch.
const List<String> legacyMutatedPaths = <String>[
  'rooms/eros',
  'rooms/hades',
  'rooms/gone',
];

/// Creates the tables of schema 8 in the empty database [db] and fills them.
/// The caller sets `PRAGMA user_version` to [legacySchemaVersion].
Future<void> buildSchema8Database(Database db) async {
  for (final String statement in _ddl) {
    await db.execute(statement);
  }

  // SQLiteRemoteDocumentCache.add, with the sentinel row of
  // SQLiteLruReferenceDelegate (target_id 0) for documents no target holds.
  final Map<String, proto.MaybeDocument> documents = legacyRemoteDocuments();
  for (final MapEntry<String, proto.MaybeDocument> entry in documents.entries) {
    await db.execute(
        'INSERT OR REPLACE INTO remote_documents (path, contents) VALUES (?, ?);',
        <Object?>[legacyEncodePath(entry.key), entry.value.writeToBuffer()]);
  }
  await db.execute(
      'INSERT OR REPLACE INTO target_documents (target_id, path, sequence_number) VALUES (0, ?, ?);',
      <Object?>[legacyEncodePath('rooms/gone'), 7]);

  // SQLiteQueryCache.addQueryData / addMatchingKeys / _writeMetadata.
  final Map<int, proto.Target> targetProtos = legacyTargetProtos();
  for (final LegacyTarget target in legacyTargets) {
    final proto.Target targetProto = targetProtos[target.targetId]!;
    await db.execute('''
        INSERT OR REPLACE INTO targets (target_id, canonical_id,
            snapshot_version_seconds, snapshot_version_nanos, resume_token,
            last_listen_sequence_number, target_proto)
        VALUES (?, ?, ?, ?, ?, ?, ?);''', <Object?>[
      target.targetId,
      target.canonicalId,
      targetProto.snapshotVersion.seconds.toInt(),
      targetProto.snapshotVersion.nanos,
      Uint8List.fromList(targetProto.resumeToken),
      target.sequenceNumber,
      targetProto.writeToBuffer(),
    ]);
    for (final String path in target.documents) {
      await db.execute(
          'INSERT OR IGNORE INTO target_documents (target_id, path) VALUES (?, ?);',
          <Object?>[target.targetId, legacyEncodePath(path)]);
    }
  }
  await db.execute('''
      UPDATE target_globals
      SET highest_target_id                    = ?,
          highest_listen_sequence_number       = ?,
          last_remote_snapshot_version_seconds = ?,
          last_remote_snapshot_version_nanos   = ?,
          target_count                         = ?;''', <Object?>[
    legacyTargets.last.targetId,
    legacyHighestSequenceNumber,
    legacyLastRemoteSnapshotSeconds,
    0,
    legacyTargets.length,
  ]);

  // SQLiteMutationQueue._writeMutationQueueMetadata / addMutationBatch.
  await db.execute(
      'INSERT OR REPLACE INTO mutation_queues (uid, last_acknowledged_batch_id, last_stream_token) VALUES (?, ?, ?);',
      <Object?>[legacyUid, -1, legacyStreamToken]);
  await db.execute(
      'INSERT INTO mutations (uid, batch_id, mutations) VALUES (?, ?, ?);',
      <Object?>[
        legacyUid,
        legacyBatchId,
        legacyPendingBatch().writeToBuffer()
      ]);
  for (final String path in legacyMutatedPaths) {
    await db.execute(
        'INSERT INTO document_mutations (uid, path, batch_id) VALUES (?, ?, ?);',
        <Object?>[legacyUid, legacyEncodePath(path), legacyBatchId]);
  }

  // SqliteIndexManager.addToCollectionParentIndex, called for every remote
  // document and every mutated key.
  for (final List<String> entry in const <List<String>>[
    <String>['rooms', ''],
    <String>['messages', 'rooms/eros'],
  ]) {
    await db.execute(
        'INSERT OR REPLACE INTO collection_parents (collection_id, parent) VALUES (?, ?);',
        <Object?>[entry[0], legacyEncodePath(entry[1])]);
  }
}

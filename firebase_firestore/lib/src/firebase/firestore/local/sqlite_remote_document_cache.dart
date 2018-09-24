// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

import 'dart:async';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/encoded_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/remote_document_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart'
    as sq;
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/proto/firestore/local/maybe_document.pb.dart'
    as proto;
import 'package:protobuf/protobuf.dart';
import 'package:sqflite/sqflite.dart';

class SQLiteRemoteDocumentCache implements RemoteDocumentCache {
  final sq.SQLitePersistence db;

  final LocalSerializer serializer;

  SQLiteRemoteDocumentCache(this.db, this.serializer);

  @override
  Future<void> add(DatabaseExecutor tx, MaybeDocument maybeDocument) async {
    String path = _pathForKey(maybeDocument.key);
    GeneratedMessage message = serializer.encodeMaybeDocument(maybeDocument);

    await db.execute(tx,
        // @formatter:off
        '''
          INSERT
          OR REPLACE INTO remote_documents (path, contents)
          VALUES (?, ?);
        ''',
        // @formatter:on
        [path, message.writeToBuffer()]);
  }

  @override
  Future<void> remove(DatabaseExecutor tx, DocumentKey documentKey) async {
    String path = _pathForKey(documentKey);

    await db.execute(tx,
        // @formatter:off
        '''
          DELETE
          FROM remote_documents
          WHERE path = ?;
        ''',
        // @formatter:on
        [path]);
  }

  @override
  Future<MaybeDocument> get(
      DatabaseExecutor tx, DocumentKey documentKey) async {
    String path = _pathForKey(documentKey);

    final Map<String, dynamic> row = (await db.query(tx,
        // @formatter:off
        '''
          SELECT contents
          FROM remote_documents
          WHERE path = ?;
        ''',
        // @formatter:on
        [path])).first;

    return decodeMaybeDocument(row['contents']);
  }

  @override
  Future<ImmutableSortedMap<DocumentKey, Document>>
      getAllDocumentsMatchingQuery(DatabaseExecutor tx, Query query) async {
    // Use the query path as a prefix for testing if a document matches the
    // query.
    ResourcePath prefix = query.path;
    int immediateChildrenPathLength = prefix.length + 1;

    String prefixPath = EncodedPath.encode(prefix);
    String prefixSuccessorPath = EncodedPath.prefixSuccessor(prefixPath);

    Map<DocumentKey, Document> results = <DocumentKey, Document>{};

    final List<Map<String, dynamic>> result = await db.query(tx,
        // @formatter:off
        '''
          SELECT path, contents
          FROM remote_documents
          WHERE path >= ?
            AND path < ?;
        ''',
        // @formatter:on
        [prefixPath, prefixSuccessorPath]);

    for (var row in result) {
      // TODO: Actually implement a single-collection query
      //
      // The query is actually returning any path that starts with the query
      // path prefix which may include documents in subcollections. For example,
      // a query on 'rooms' will return rooms/abc/messages/xyx but we shouldn't
      // match it. Fix this by discarding rows with document keys more than one
      // segment longer than the query path.
      final ResourcePath path = EncodedPath.decodeResourcePath(row['path']);
      if (path.length != immediateChildrenPathLength) continue;

      final MaybeDocument maybeDoc =
          decodeMaybeDocument(row['remote_documents']);
      if (maybeDoc is! Document) continue;

      Document doc = maybeDoc;
      if (!query.matches(doc)) continue;

      results[doc.key] = doc;
    }

    return ImmutableSortedMap.fromMap(results, DocumentKey.comparator);
  }

  String _pathForKey(DocumentKey key) {
    return EncodedPath.encode(key.path);
  }

  MaybeDocument decodeMaybeDocument(List<int> bytes) {
    try {
      return serializer
          .decodeMaybeDocument(proto.MaybeDocument.fromBuffer(bytes));
    } on InvalidProtocolBufferException catch (e) {
      throw Assert.fail("MaybeDocument failed to parse: $e");
    }
  }
}

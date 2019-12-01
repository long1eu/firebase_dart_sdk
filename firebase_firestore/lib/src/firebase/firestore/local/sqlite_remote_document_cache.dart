// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/encoded_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/remote_document_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart' as sq;
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/proto/google/firebase/firestore/proto/maybe_document.pb.dart'
    as proto;
import 'package:protobuf/protobuf.dart';

class SQLiteRemoteDocumentCache implements RemoteDocumentCache {
  SQLiteRemoteDocumentCache(this.db, this.serializer);

  final sq.SQLitePersistence db;

  final LocalSerializer serializer;

  @override
  Future<void> add(MaybeDocument maybeDocument) async {
    final String path = _pathForKey(maybeDocument.key);
    final GeneratedMessage message = serializer.encodeMaybeDocument(maybeDocument);

    await db.execute(
        // @formatter:off
        '''
          INSERT
          OR REPLACE INTO remote_documents (path, contents)
          VALUES (?, ?);
        ''',
        // @formatter:on
        <dynamic>[path, message.writeToBuffer()]);
  }

  @override
  Future<void> remove(DocumentKey documentKey) async {
    final String path = _pathForKey(documentKey);

    await db.execute(
        // @formatter:off
        '''
          DELETE
          FROM remote_documents
          WHERE path = ?;
        ''',
        // @formatter:on
        <String>[path]);
  }

  @override
  Future<MaybeDocument> get(DocumentKey documentKey) async {
    final String path = _pathForKey(documentKey);

    final List<Map<String, dynamic>> result = await db.query(
        // @formatter:off
        '''
          SELECT contents
          FROM remote_documents
          WHERE path = ?;
        ''',
        // @formatter:on
        <String>[path]);

    if (result.isEmpty) {
      return null;
    }
    final Map<String, dynamic> row = result.first;
    final Uint8List contents = row['contents'];
    return decodeMaybeDocument(contents);
  }

  @override
  Future<Map<DocumentKey, MaybeDocument>> getAll(Iterable<DocumentKey> documentKeys) async {
    final List<Object> args = <Object>[];
    for (DocumentKey key in documentKeys) {
      args.add(EncodedPath.encode(key.path));
    }

    final Map<DocumentKey, MaybeDocument> results = <DocumentKey, MaybeDocument>{};
    for (DocumentKey key in documentKeys) {
      // Make sure each key has a corresponding entry, which is null in case the document is not found.
      results[key] = null;
    }

    final LongQuery longQuery = LongQuery(
        db, 'SELECT contents FROM remote_documents WHERE path IN (', null, args, ') ORDER BY path');

    while (longQuery.hasMoreSubqueries) {
      final List<Map<String, dynamic>> rows = await longQuery.performNextSubquery();
      for (Map<String, dynamic> row in rows) {
        final MaybeDocument decoded = decodeMaybeDocument(row['contents']);
        results[decoded.key] = decoded;
      }
    }

    return results;
  }

  @override
  Future<ImmutableSortedMap<DocumentKey, Document>> getAllDocumentsMatchingQuery(
      Query query) async {
    // Use the query path as a prefix for testing if a document matches the query.
    final ResourcePath prefix = query.path;
    final int immediateChildrenPathLength = prefix.length + 1;

    final String prefixPath = EncodedPath.encode(prefix);
    final String prefixSuccessorPath = EncodedPath.prefixSuccessor(prefixPath);

    final Map<DocumentKey, Document> results = <DocumentKey, Document>{};

    final List<Map<String, dynamic>> result = await db.query(
        // @formatter:off
        '''
          SELECT path, contents
          FROM remote_documents
          WHERE path >= ?
            AND path < ?;
        ''',
        // @formatter:on
        <String>[prefixPath, prefixSuccessorPath]);

    for (Map<String, dynamic> row in result) {
      // TODO(long1eu): Actually implement a single-collection query
      //  The query is actually returning any path that starts with the query path prefix which may include documents in
      //  subcollections. For example, a query on 'rooms' will return rooms/abc/messages/xyx but we shouldn't match it.
      //  Fix this by discarding rows with document keys more than one segment longer than the query path.

      final String _path = row['path'];
      final ResourcePath path = EncodedPath.decodeResourcePath(_path);
      if (path.length != immediateChildrenPathLength) {
        continue;
      }

      final Uint8List contents = row['contents'];
      final MaybeDocument maybeDoc = decodeMaybeDocument(contents);

      if (maybeDoc is! Document) {
        continue;
      }

      final Document doc = maybeDoc;
      if (!query.matches(doc)) {
        continue;
      }

      results[doc.key] = doc;
    }

    return ImmutableSortedMap<DocumentKey, Document>.fromMap(results, DocumentKey.comparator);
  }

  String _pathForKey(DocumentKey key) {
    return EncodedPath.encode(key.path);
  }

  MaybeDocument decodeMaybeDocument(Uint8List bytes) {
    try {
      return serializer.decodeMaybeDocument(proto.MaybeDocument.fromBuffer(bytes));
    } on InvalidProtocolBufferException catch (e) {
      throw fail('MaybeDocument failed to parse: $e');
    }
  }
}

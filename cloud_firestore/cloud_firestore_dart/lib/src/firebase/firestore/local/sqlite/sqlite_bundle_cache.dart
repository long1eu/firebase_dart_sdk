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

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/bundle_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/stored_proto.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;

/// A SQLite-backed implementation of the bundle cache (tables `bundles` and `named_queries`, schema migration 9).
class SQLiteBundleCache implements BundleCache {
  const SQLiteBundleCache(this._db, this._serializer);

  final SQLitePersistence _db;
  final LocalSerializer _serializer;

  @override
  Future<BundleMetadata?> getBundleMetadata(String bundleId) async {
    final List<Map<String, dynamic>> rows = await _db.query(
      // @formatter:off
      '''
          SELECT schema_version,
                 create_time_seconds,
                 create_time_nanos,
                 total_documents,
                 total_bytes
          FROM bundles
          WHERE bundle_id = ?;
        ''',
      // @formatter:on
      <Object?>[bundleId],
    );
    if (rows.isEmpty) {
      return null;
    }

    final Map<String, dynamic> row = rows.first;
    return BundleMetadata(
      bundleId,
      row['schema_version'],
      SnapshotVersion(
        Timestamp(row['create_time_seconds'], row['create_time_nanos']),
      ),
      row['total_documents'],
      row['total_bytes'],
    );
  }

  @override
  Future<void> saveBundleMetadata(BundleMetadata metadata) {
    return _db.execute(
      // @formatter:off
      '''
          INSERT OR REPLACE INTO bundles (bundle_id,
                                          schema_version,
                                          create_time_seconds,
                                          create_time_nanos,
                                          total_documents,
                                          total_bytes)
          VALUES (?, ?, ?, ?, ?, ?);
        ''',
      // @formatter:on
      <Object?>[
        metadata.bundleId,
        metadata.schemaVersion,
        metadata.createTime.timestamp.seconds,
        metadata.createTime.timestamp.nanoseconds,
        metadata.totalDocuments,
        metadata.totalBytes,
      ],
    );
  }

  @override
  Future<NamedQuery?> getNamedQuery(String queryName) async {
    final List<Map<String, dynamic>> rows = await _db.query(
      // @formatter:off
      '''
          SELECT read_time_seconds,
                 read_time_nanos,
                 bundled_query_proto
          FROM named_queries
          WHERE name = ?;
        ''',
      // @formatter:on
      <Object?>[queryName],
    );
    if (rows.isEmpty) {
      return null;
    }

    final Map<String, dynamic> row = rows.first;
    final BundledQuery bundledQuery = _serializer.decodeBundledQuery(
      parseStoredProto(
        'NamedQuery',
        () => proto.BundledQuery.fromBuffer(
          row['bundled_query_proto'] as Uint8List,
        ),
      ),
    );
    return NamedQuery(
      queryName,
      bundledQuery,
      SnapshotVersion(
        Timestamp(row['read_time_seconds'], row['read_time_nanos']),
      ),
    );
  }

  @override
  Future<void> saveNamedQuery(NamedQuery query) {
    final proto.BundledQuery bundledQuery = _serializer.encodeBundledQuery(
      query.bundledQuery,
    );

    return _db.execute(
      // @formatter:off
      '''
          INSERT OR REPLACE INTO named_queries (name,
                                                read_time_seconds,
                                                read_time_nanos,
                                                bundled_query_proto)
          VALUES (?, ?, ?, ?);
        ''',
      // @formatter:on
      <Object?>[
        query.name,
        query.readTime.timestamp.seconds,
        query.readTime.timestamp.nanoseconds,
        bundledQuery.writeToBuffer(),
      ],
    );
  }
}

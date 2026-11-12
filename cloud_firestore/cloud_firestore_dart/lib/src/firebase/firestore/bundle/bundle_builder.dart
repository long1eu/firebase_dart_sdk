// Copyright 2025 Google LLC
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

import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;

/// Builds a Firestore data bundle (the length-prefixed proto3 JSON format read by `BundleReader`) from documents and
/// queries the client already has.
///
/// Port of the JS SDK `BundleBuilder` (`util/bundle_builder_impl.ts`), used by `DocumentSnapshot.toJson()` and
/// `QuerySnapshot.toJson()`.
///
/// PORTING NOTE: the JS builder converts the snapshot data back to user data and parses it again; the port encodes the
/// stored values directly with the [RemoteSerializer], which is lossless. Documents of the port have no read time, so
/// callers pass one (see `ViewSnapshot.readTime`) or the document version is used.
class BundleBuilder {
  BundleBuilder(this._serializer, this.bundleId);

  static const int _bundleVersion = 1;

  final RemoteSerializer _serializer;

  /// The id written in the bundle metadata.
  final String bundleId;

  // Keyed by document path, in insertion order.
  final Map<String, _BundledDocument> _documents = <String, _BundledDocument>{};

  // Keyed by query name, in insertion order.
  final Map<String, Map<String, Object?>> _namedQueries =
      <String, Map<String, Object?>>{};

  // The latest read time among all bundled documents and queries.
  SnapshotVersion _latestReadTime = SnapshotVersion.none;

  /// Adds [document] to the bundle, read at [readTime] (the document version when null).
  ///
  /// [queryName] is the name of the named query the document belongs to, if any.
  void addDocument(Document document,
      {SnapshotVersion? readTime, String? queryName}) {
    final String path = document.key.path.canonicalString;
    final SnapshotVersion docReadTime = readTime ?? document.version;
    final _BundledDocument? original = _documents[path];

    _BundledDocument bundled;
    if (original == null || original.readTime.compareTo(docReadTime) < 0) {
      bundled = _BundledDocument(
        docReadTime,
        _encodeDocument(document),
        <String>[...?original?.queries],
      );
      _documents[path] = bundled;
    } else {
      bundled = original;
    }
    if (queryName != null) {
      bundled.queries.add(queryName);
    }
    _updateLatestReadTime(docReadTime);
  }

  /// Adds the named query [name] for [query] with its result [documents], read at [readTime].
  ///
  /// The documents are read at [readTime] too, or at their own version when [readTime] is [SnapshotVersion.none].
  void addNamedQuery(String name, Query query, Iterable<Document> documents,
      SnapshotVersion readTime) {
    if (_namedQueries.containsKey(name)) {
      throw ArgumentError('Query name conflict: $name has already been added.');
    }
    final bool hasReadTime = readTime.compareTo(SnapshotVersion.none) > 0;
    for (final Document document in documents) {
      addDocument(document,
          readTime: hasReadTime ? readTime : null, queryName: name);
    }

    // A limit-to-last query is stored as written by the user (orders not inverted) with the 'LAST' limit type, which
    // is how the backend bundle builders write it and how `BundleSerializer` reads it back.
    // PORTING NOTE: the JS builder writes the target of the query (orders inverted) without a limit type, so a
    // limitToLast() query does not round-trip there.
    final bool isLimitToLast = query.hasLimitToLast;
    final Query firstQuery = isLimitToLast
        ? query.copyWith(limitType: LimitType.limitToFirst)
        : query;
    final proto.Target_QueryTarget queryTarget =
        _serializer.encodeQueryTarget(firstQuery.toTarget());
    _namedQueries[name] = <String, Object?>{
      'name': name,
      'bundledQuery': <String, Object?>{
        'parent': queryTarget.parent,
        'structuredQuery': queryTarget.structuredQuery.toProto3Json(),
        'limitType': isLimitToLast ? 'LAST' : 'FIRST',
      },
      'readTime': _encodeVersion(readTime),
    };
    _updateLatestReadTime(readTime);
  }

  /// Returns the bundle with everything added so far.
  String build() {
    final StringBuffer elements = StringBuffer();
    for (final Map<String, Object?> namedQuery in _namedQueries.values) {
      elements
          .write(_lengthPrefixed(<String, Object?>{'namedQuery': namedQuery}));
    }
    _documents.forEach((String path, _BundledDocument bundled) {
      elements
        ..write(_lengthPrefixed(<String, Object?>{
          'documentMetadata': <String, Object?>{
            'name': bundled.document['name'],
            'readTime': _encodeVersion(bundled.readTime),
            'exists': true,
            if (bundled.queries.isNotEmpty) 'queries': bundled.queries,
          },
        }))
        ..write(
            _lengthPrefixed(<String, Object?>{'document': bundled.document}));
    });
    final String body = elements.toString();

    final String metadata = _lengthPrefixed(<String, Object?>{
      'metadata': <String, Object?>{
        'id': bundleId,
        'createTime': _encodeVersion(_latestReadTime),
        'version': _bundleVersion,
        'totalDocuments': _documents.length,
        'totalBytes': utf8.encode(body).length,
      },
    });
    return '$metadata$body';
  }

  Map<String, Object?> _encodeDocument(Document document) {
    final proto.Document encoded =
        _serializer.encodeDocument(document.key, document.data);
    final Map<String, Object?> result = <String, Object?>{
      'name': encoded.name,
      'fields': (encoded.toProto3Json()! as Map<String, Object?>)['fields'] ??
          <String, Object?>{},
      'updateTime': _encodeVersion(document.version),
    };
    // Documents received from the backend keep their create time in the proto.
    final proto.Document? original = document.proto;
    if (original != null && original.hasCreateTime()) {
      result['createTime'] = original.createTime.toProto3Json();
    }
    return result;
  }

  Object? _encodeVersion(SnapshotVersion version) =>
      _serializer.encodeVersion(version).toProto3Json();

  void _updateLatestReadTime(SnapshotVersion readTime) {
    if (readTime.compareTo(_latestReadTime) > 0) {
      _latestReadTime = readTime;
    }
  }

  static String _lengthPrefixed(Map<String, Object?> element) {
    final String json = jsonEncode(element);
    return '${utf8.encode(json).length}$json';
  }
}

class _BundledDocument {
  _BundledDocument(this.readTime, this.document, this.queries);

  final SnapshotVersion readTime;
  final Map<String, Object?> document;
  final List<String> queries;
}

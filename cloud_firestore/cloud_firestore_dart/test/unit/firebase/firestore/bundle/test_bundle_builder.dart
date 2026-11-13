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

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';

import '../../../../util/test_util.dart';

/// Builds length-prefixed bundles, like the ones the server SDKs produce, for the bundle tests.
///
/// Port of the `TestBundleBuilder` in the Android `BundleReaderTest`. The elements are strict JSON (the Android test
/// uses the lenient `org.json` syntax with unquoted keys).
class TestBundleBuilder {
  TestBundleBuilder(this.databaseId)
      : serializer = RemoteSerializer(databaseId);

  final List<String> elements = <String>[];
  final DatabaseId databaseId;
  final RemoteSerializer serializer;

  int totalDocuments = 0;
  int totalBytes = 0;

  static Map<String, int> timestamp(SnapshotVersion version) {
    return <String, int>{
      'seconds': version.timestamp.seconds,
      'nanos': version.timestamp.nanoseconds,
    };
  }

  String addDocumentMetadata(String path, int readTimeMicros, bool exists,
      [List<String>? queries]) {
    final String json = jsonEncode(<String, dynamic>{
      'documentMetadata': <String, dynamic>{
        'name': serializer.encodeKey(key(path)),
        'readTime': timestamp(version(readTimeMicros)),
        'exists': exists,
        'queries': ?queries,
      },
    });
    elements.add(json);
    if (!exists) {
      totalDocuments++;
    }
    totalBytes += _utf8BytesCountWithPrefix(json);
    return json;
  }

  String addDocument(String path, int createTimeMicros, int updateTimeMicros,
      Map<String, dynamic> fields) {
    final String json = jsonEncode(<String, dynamic>{
      'document': <String, dynamic>{
        'name': serializer.encodeKey(key(path)),
        'createTime': timestamp(version(createTimeMicros)),
        'updateTime': timestamp(version(updateTimeMicros)),
        'fields': fields,
      },
    });
    elements.add(json);
    totalDocuments++;
    totalBytes += _utf8BytesCountWithPrefix(json);
    return json;
  }

  String addNamedQuery(
      String name,
      int readTimeMicros,
      BundledQueryLimitType limitType,
      String parent,
      Map<String, dynamic> structuredQuery) {
    final String json = jsonEncode(<String, dynamic>{
      'namedQuery': <String, dynamic>{
        'name': name,
        'readTime': timestamp(version(readTimeMicros)),
        'bundledQuery': <String, dynamic>{
          'parent':
              'projects/${databaseId.projectId}/databases/${databaseId.databaseId}/documents/$parent',
          'structuredQuery': structuredQuery,
          'limitType':
              limitType == BundledQueryLimitType.first ? 'FIRST' : 'LAST',
        },
      },
    });
    elements.add(json);
    totalBytes += _utf8BytesCountWithPrefix(json);
    return json;
  }

  static int utf8BytesCount(String json) => utf8.encode(json).length;

  static int _utf8BytesCountWithPrefix(String json) {
    final int elementLength = utf8BytesCount(json);
    return '$elementLength'.length + elementLength;
  }

  String getMetadataElement(String id, int createTimeMicros, int version) {
    return jsonEncode(<String, dynamic>{
      'metadata': <String, dynamic>{
        'id': id,
        'createTime': timestamp(_version(createTimeMicros)),
        'version': version,
        'totalDocuments': totalDocuments,
        'totalBytes': totalBytes,
      },
    });
  }

  static SnapshotVersion _version(int micros) => version(micros);

  /// Returns the whole bundle as a string.
  String build(String id, int createTimeMicros, int version) {
    final StringBuffer builder = StringBuffer();

    final String metadataElement =
        getMetadataElement(id, createTimeMicros, version);
    builder
      ..write(utf8BytesCount(metadataElement))
      ..write(metadataElement);

    for (final String element in elements) {
      builder
        ..write(utf8BytesCount(element))
        ..write(element);
    }

    return builder.toString();
  }

  /// Returns the whole bundle as UTF-8 bytes.
  Uint8List buildBytes(String id, int createTimeMicros, int version) {
    return Uint8List.fromList(
        utf8.encode(build(id, createTimeMicros, version)));
  }
}

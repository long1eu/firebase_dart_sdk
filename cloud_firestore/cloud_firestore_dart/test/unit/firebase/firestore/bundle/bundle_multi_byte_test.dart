// Copyright 2020 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Port of the 'Bundle with multi-byte UTF-8 characters' group of the JS SDK
// test/unit/util/bundle.test.ts. The port has only the streaming BundleReader
// (the JS newBundleReaderSync has no counterpart), so the BundleReaderSync
// cases run against BundleReader with the whole bundle in one chunk. The JS
// SizedBundleElement.byteLength is the growth of BundleReader.bytesRead.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_element.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_reader.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_document_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

const Map<String, String> multiByteValues = <String, String>{
  'empty string (control)': '',
  'em-dash': '—',
  'emoji (surrogate pairs)': '\u{1F600} \u{1F525}',
  'single 4-byte emoji': '\u{1F600}',
  'accented characters': 'café naïve Ångström',
};

const String documentsPrefix =
    'projects/test-project/databases/(default)/'
    'documents';

String lengthPrefixedString(Map<String, dynamic> element) {
  final String json = jsonEncode(element);
  return '${utf8.encode(json).length}$json';
}

Map<String, dynamic> multiByteMeta(String value) => <String, dynamic>{
  'metadata': <String, dynamic>{
    'id': 'test-bundle$value',
    'createTime': <String, dynamic>{'seconds': 1577836805, 'nanos': 6},
    'version': 1,
    'totalDocuments': 1,
    'totalBytes': 416,
  },
};

Map<String, dynamic> multiByteDocMeta(String value) => <String, dynamic>{
  'documentMetadata': <String, dynamic>{
    'name': '$documentsPrefix/collectionId/doc$value',
    'readTime': <String, dynamic>{'seconds': 5, 'nanos': 6},
    'exists': true,
  },
};

Map<String, dynamic> multiByteDoc(String value) => <String, dynamic>{
  'document': <String, dynamic>{
    'name': '$documentsPrefix/collectionId/doc$value',
    'createTime': <String, dynamic>{'seconds': 1, 'nanos': 2},
    'updateTime': <String, dynamic>{'seconds': 3, 'nanos': 4},
    'fields': <String, dynamic>{
      'k$value': <String, dynamic>{'integerValue': '1'},
      // Last so that the value sits right before the element's closing
      // bytes.
      'foo': <String, dynamic>{'stringValue': value},
    },
  },
};

final Map<String, dynamic> doc2 = <String, dynamic>{
  'document': <String, dynamic>{
    'name': '$documentsPrefix/collectionId/doc2',
    'createTime': <String, dynamic>{'seconds': 1, 'nanos': 2},
    'updateTime': <String, dynamic>{'seconds': 3, 'nanos': 4},
    'fields': <String, dynamic>{
      'foo': <String, dynamic>{'stringValue': 'value1'},
      'bar': <String, dynamic>{'integerValue': -42},
    },
  },
};

void main() {
  final BundleSerializer serializer = BundleSerializer(
    RemoteSerializer(DatabaseId.forProject('test-project')),
  );

  Stream<List<int>> byteStreamFromString(String content, int bytesPerRead) {
    final Uint8List data = Uint8List.fromList(utf8.encode(content));
    return Stream<List<int>>.fromIterable(<List<int>>[
      for (int i = 0; i < data.length; i += bytesPerRead)
        data.sublist(
          i,
          i + bytesPerRead > data.length ? data.length : i + bytesPerRead,
        ),
    ]);
  }

  /// Verifies an element's payload, and that the bytes read for it are the
  /// full UTF-8 byte length of its length-prefixed serialization.
  Future<void> verifyNextElement(
    BundleReader reader,
    Object expectedPayload,
    String lengthPrefixedPayload,
  ) async {
    final int bytesBefore = reader.bytesRead;
    final BundleElement? element = await reader.getNextElement();
    expect(element, expectedPayload);
    expect(
      reader.bytesRead - bytesBefore,
      utf8.encode(lengthPrefixedPayload).length,
    );
  }

  group('Bundle with multi-byte UTF-8 characters', () {
    for (final MapEntry<String, String> entry in multiByteValues.entries) {
      final String name = entry.key;
      final String value = entry.value;
      final Map<String, dynamic> metaElement = multiByteMeta(value);
      final Map<String, dynamic> docMetaElement = multiByteDocMeta(value);
      final Map<String, dynamic> docElement = multiByteDoc(value);
      final String docMetaString = lengthPrefixedString(docMetaElement);
      final String docString = lengthPrefixedString(docElement);
      final String doc2String = lengthPrefixedString(doc2);
      final String bundleString =
          lengthPrefixedString(metaElement) +
          docMetaString +
          docString +
          doc2String;

      final BundleMetadata expectedMetadata = serializer.decodeBundleMetadata(
        metaElement['metadata'] as Map<String, dynamic>,
      );
      final BundledDocumentMetadata expectedDocMeta = serializer
          .decodeBundledDocumentMetadata(
            docMetaElement['documentMetadata'] as Map<String, dynamic>,
          );
      final BundleDocument expectedDoc = serializer.decodeDocument(
        docElement['document'] as Map<String, dynamic>,
      );
      final BundleDocument expectedDoc2 = serializer.decodeDocument(
        doc2['document'] as Map<String, dynamic>,
      );

      test('the expected elements hold $name', () {
        expect(expectedMetadata.bundleId, 'test-bundle$value');
        expect(expectedDocMeta.key, key('collectionId/doc$value'));
        expect(expectedDoc.key, key('collectionId/doc$value'));
        expect(
          expectedDoc.document.data,
          wrapMap(<String, Object?>{'k$value': 1, 'foo': value}),
        );
      });

      Future<void> readAndVerify(BundleReader reader) async {
        expect(await reader.getBundleMetadata(), expectedMetadata);
        await verifyNextElement(reader, expectedDocMeta, docMetaString);
        await verifyNextElement(reader, expectedDoc, docString);
        await verifyNextElement(reader, expectedDoc2, doc2String);
        expect(await reader.getNextElement(), isNull);
      }

      test('BundleReaderSync reads elements containing $name', () async {
        await readAndVerify(
          BundleReader.fromBytes(
            serializer,
            Uint8List.fromList(utf8.encode(bundleString)),
          ),
        );
      });

      for (final int bytesPerRead in <int>[1, 4, 1024]) {
        test('BundleReader reads elements containing $name with bytesPerRead '
            '$bytesPerRead', () async {
          await readAndVerify(
            BundleReader(
              serializer,
              byteStreamFromString(bundleString, bytesPerRead),
            ),
          );
        });
      }
    }

    for (final String prefix in <String>['abc', '-5', '1.5']) {
      test(
        "BundleReaderSync throws on an invalid length prefix '$prefix'",
        () async {
          final BundleReader reader = BundleReader.fromBytes(
            serializer,
            Uint8List.fromList(
              utf8.encode(prefix + jsonEncode(multiByteMeta(''))),
            ),
          );
          await expectLater(
            reader.getBundleMetadata(),
            throwsA(isA<ArgumentError>()),
          );
        },
      );
    }
  });
}

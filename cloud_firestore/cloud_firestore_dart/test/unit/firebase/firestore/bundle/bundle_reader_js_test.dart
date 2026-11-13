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

// Port of the 'Bundle ' group (genericBundleReadingTests) of the JS SDK
// test/unit/util/bundle.test.ts, with the bundle elements of
// test/unit/util/bundle_data.ts. The same scenarios run under the Android
// BundleReaderTest names in bundle_reader_test.dart; this file keeps the JS
// names, JS data and JS bytesPerRead values (1, 4, 64, 1024).
//
// PORTING NOTE: the JS reader returns the raw JSON payload of an element; the
// port returns decoded elements, so a payload is compared with the element
// the BundleSerializer decodes from the same JSON. The JS
// SizedBundleElement.byteLength is the growth of BundleReader.bytesRead.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_element.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_reader.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_document_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

String lengthPrefixedString(Map<String, dynamic> o) {
  final String str = jsonEncode(o);
  return '${utf8.encode(str).length}$str';
}

const String documentsPrefix =
    'projects/test-project/databases/(default)/documents';

final Map<String, dynamic> meta = <String, dynamic>{
  'metadata': <String, dynamic>{
    'id': 'test-bundle',
    'createTime': <String, dynamic>{'seconds': 1577836805, 'nanos': 6},
    'version': 1,
    'totalDocuments': 1,
    'totalBytes': 416,
  },
};

final Map<String, dynamic> doc1Meta = <String, dynamic>{
  'documentMetadata': <String, dynamic>{
    'name': '$documentsPrefix/collectionId/doc1',
    'readTime': <String, dynamic>{'seconds': 5, 'nanos': 6},
    'exists': true,
  },
};

final Map<String, dynamic> doc1 = <String, dynamic>{
  'document': <String, dynamic>{
    'name': '$documentsPrefix/collectionId/doc1',
    'createTime': <String, dynamic>{'seconds': 1, 'nanos': 2000000},
    'updateTime': <String, dynamic>{'seconds': 3, 'nanos': 4000},
    'fields': <String, dynamic>{
      'foo': <String, dynamic>{'stringValue': 'value'},
      'bar': <String, dynamic>{'integerValue': -42},
    },
  },
};

final Map<String, dynamic> doc2Meta = <String, dynamic>{
  'documentMetadata': <String, dynamic>{
    'name': '$documentsPrefix/collectionId/doc2',
    'readTime': <String, dynamic>{'seconds': 5, 'nanos': 6},
    'exists': true,
  },
};

final Map<String, dynamic> doc2 = <String, dynamic>{
  'document': <String, dynamic>{
    'name': '$documentsPrefix/collectionId/doc2',
    'createTime': <String, dynamic>{'seconds': 1, 'nanos': 2000000},
    'updateTime': <String, dynamic>{'seconds': 3, 'nanos': 4000},
    'fields': <String, dynamic>{
      'foo': <String, dynamic>{'stringValue': 'value1'},
      'bar': <String, dynamic>{'integerValue': 42},
      'emptyArray': <String, dynamic>{'arrayValue': <String, dynamic>{}},
      'emptyMap': <String, dynamic>{'mapValue': <String, dynamic>{}},
    },
  },
};

final Map<String, dynamic> noDocMeta = <String, dynamic>{
  'documentMetadata': <String, dynamic>{
    'name': '$documentsPrefix/collectionId/nodoc',
    'readTime': <String, dynamic>{'seconds': 5, 'nanos': 6},
    'exists': false,
  },
};

Map<String, dynamic> namedQuery(
  String name,
  String direction,
  String limitType,
  int nanos,
) => <String, dynamic>{
  'namedQuery': <String, dynamic>{
    'name': name,
    'bundledQuery': <String, dynamic>{
      // PORTING NOTE: the JS data has the parent
      // 'projects/fireeats-97d5e/databases/(default)/documents'. The JS reader
      // never decodes the query, but the port (like the Android
      // BundleSerializer.decodeName) rejects a parent of another database, so
      // the parent is the test project's.
      'parent': documentsPrefix,
      'structuredQuery': <String, dynamic>{
        'from': <dynamic>[
          <String, dynamic>{'collectionId': 'node_3.7.5_7Li7XoCjutvNxwD0tpo9'},
        ],
        'orderBy': <dynamic>[
          <String, dynamic>{
            'field': <String, dynamic>{'fieldPath': 'sort'},
            'direction': direction,
          },
        ],
        'limit': <String, dynamic>{'value': 1},
      },
      'limitType': limitType,
    },
    'readTime': <String, dynamic>{'seconds': 1590011379, 'nanos': nanos},
  },
};

final Map<String, dynamic> limitQuery = namedQuery(
  'limitQuery',
  'DESCENDING',
  'FIRST',
  191164000,
);

final Map<String, dynamic> limitToLastQuery = namedQuery(
  'limitToLastQuery',
  'ASCENDING',
  'LAST',
  543063000,
);

final String metaString = lengthPrefixedString(meta);
final String doc1MetaString = lengthPrefixedString(doc1Meta);
final String doc1String = lengthPrefixedString(doc1);
final String doc2MetaString = lengthPrefixedString(doc2Meta);
final String doc2String = lengthPrefixedString(doc2);
final String noDocMetaString = lengthPrefixedString(noDocMeta);
final String limitQueryString = lengthPrefixedString(limitQuery);
final String limitToLastQueryString = lengthPrefixedString(limitToLastQuery);

final BundleSerializer serializer = BundleSerializer(
  RemoteSerializer(DatabaseId.forProject('test-project')),
);

/// The element the port decodes from the JSON [element] of the JS data.
Object decoded(Map<String, dynamic> element) {
  final MapEntry<String, dynamic> entry = element.entries.single;
  final Map<String, dynamic> json = entry.value as Map<String, dynamic>;
  switch (entry.key) {
    case 'metadata':
      return serializer.decodeBundleMetadata(json);
    case 'namedQuery':
      return serializer.decodeNamedQuery(json);
    case 'documentMetadata':
      return serializer.decodeBundledDocumentMetadata(json);
    case 'document':
      return serializer.decodeDocument(json);
  }
  throw ArgumentError('Unknown element: ${entry.key}');
}

/// The JS byteStreamReaderFromString(): [content] in chunks of
/// [bytesPerRead] bytes.
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

typedef SizedBundleElement = ({BundleElement payload, int byteLength});

void genericBundleReadingTests(int bytesPerRead) {
  BundleReader bundleFromString(String s) =>
      BundleReader(serializer, byteStreamFromString(s, bytesPerRead));

  Future<List<SizedBundleElement>> getAllElements(BundleReader bundle) async {
    await bundle.getBundleMetadata();
    final List<SizedBundleElement> result = <SizedBundleElement>[];
    while (true) {
      final int before = bundle.bytesRead;
      final BundleElement? element = await bundle.getNextElement();
      if (element == null) {
        break;
      }
      result.add((payload: element, byteLength: bundle.bytesRead - before));
    }
    return result;
  }

  void verifySizedElement(
    SizedBundleElement element,
    Map<String, dynamic> payload,
    String lengthPrefixedPayload,
  ) {
    expect(element.payload, decoded(payload));
    expect(element.byteLength, utf8.encode(lengthPrefixedPayload).length);
  }

  Matcher throwsInvalidBundleWith(String message) => throwsA(
    isA<ArgumentError>().having(
      (ArgumentError e) => '${e.message}',
      'message',
      contains(message),
    ),
  );

  Future<void> generateBundleAndParse(
    String bundleString, {
    bool validMeta = false,
  }) async {
    final BundleReader bundle = bundleFromString(bundleString);
    if (validMeta) {
      expect(await bundle.getBundleMetadata(), decoded(meta));
    }
    await getAllElements(bundle);
  }

  test('reads with query and doc with bytesPerRead $bytesPerRead', () async {
    final BundleReader bundle = bundleFromString(
      metaString +
          limitQueryString +
          limitToLastQueryString +
          doc1MetaString +
          doc1String,
    );

    expect(await bundle.getBundleMetadata(), decoded(meta));

    final List<SizedBundleElement> actual = await getAllElements(bundle);
    expect(actual.length, 4);
    verifySizedElement(actual[0], limitQuery, limitQueryString);
    verifySizedElement(actual[1], limitToLastQuery, limitToLastQueryString);
    verifySizedElement(actual[2], doc1Meta, doc1MetaString);
    verifySizedElement(actual[3], doc1, doc1String);

    // The limit types survive decoding.
    expect(
      (actual[0].payload as NamedQuery).bundledQuery.limitType,
      BundledQueryLimitType.first,
    );
    expect(
      (actual[1].payload as NamedQuery).bundledQuery.limitType,
      BundledQueryLimitType.last,
    );
  });

  test(
    'reads with unexpected orders with bytesPerRead $bytesPerRead',
    () async {
      final BundleReader bundle = bundleFromString(
        metaString +
            doc1MetaString +
            doc1String +
            limitQueryString +
            doc2MetaString +
            doc2String,
      );

      final List<SizedBundleElement> actual = await getAllElements(bundle);
      expect(actual.length, 5);
      verifySizedElement(actual[0], doc1Meta, doc1MetaString);
      verifySizedElement(actual[1], doc1, doc1String);
      verifySizedElement(actual[2], limitQuery, limitQueryString);
      verifySizedElement(actual[3], doc2Meta, doc2MetaString);
      verifySizedElement(actual[4], doc2, doc2String);

      // Reading metadata after other elements should also work.
      expect(await bundle.getBundleMetadata(), decoded(meta));
    },
  );

  test('reads without named query with bytesPerRead $bytesPerRead', () async {
    final BundleReader bundle = bundleFromString(
      metaString + doc1MetaString + doc1String,
    );

    expect(await bundle.getBundleMetadata(), decoded(meta));

    final List<SizedBundleElement> actual = await getAllElements(bundle);
    expect(actual.length, 2);
    verifySizedElement(actual[0], doc1Meta, doc1MetaString);
    verifySizedElement(actual[1], doc1, doc1String);
  });

  test('reads with deleted doc with bytesPerRead $bytesPerRead', () async {
    final BundleReader bundle = bundleFromString(
      metaString + noDocMetaString + doc1MetaString + doc1String,
    );

    expect(await bundle.getBundleMetadata(), decoded(meta));

    final List<SizedBundleElement> actual = await getAllElements(bundle);
    expect(actual.length, 3);
    verifySizedElement(actual[0], noDocMeta, noDocMetaString);
    verifySizedElement(actual[1], doc1Meta, doc1MetaString);
    verifySizedElement(actual[2], doc1, doc1String);
    expect((actual[0].payload as BundledDocumentMetadata).exists, isFalse);
  });

  test(
    'reads without documents or query with bytesPerRead $bytesPerRead',
    () async {
      final BundleReader bundle = bundleFromString(metaString);

      expect(await bundle.getBundleMetadata(), decoded(meta));

      final List<SizedBundleElement> actual = await getAllElements(bundle);
      expect(actual.length, 0);
    },
  );

  test(
    'throws with ill-formatted bundle with bytesPerRead $bytesPerRead',
    () async {
      // PORTING NOTE: JS fails with "Reached the end of bundle when a length
      // string is expected."; the port stops looking for the '{' that ends a
      // length prefix after 10 digits (see bundle_hostile_input_test.dart), so
      // these inputs, which have more than 10 bytes before the end, are
      // rejected by that limit.
      await expectLater(
        generateBundleAndParse('metadata: "no length prefix"'),
        throwsInvalidBundleWith('Expected a length prefix of at most 10'),
      );

      // PORTING NOTE: JS reads the empty length prefix as 0 and then fails to
      // parse an empty JSON string ("Unexpected end of JSON input"); the port
      // rejects the empty length prefix itself.
      await expectLater(
        generateBundleAndParse('{metadata: "no length prefix"}'),
        throwsInvalidBundleWith('Invalid length prefix'),
      );

      await expectLater(
        generateBundleAndParse('${metaString}invalid-string', validMeta: true),
        throwsInvalidBundleWith('Expected a length prefix of at most 10'),
      );
      // Not in JS: shorter trailing garbage still ends the stream before a '{'
      // and gets the JS message.
      await expectLater(
        generateBundleAndParse('${metaString}invalid', validMeta: true),
        throwsInvalidBundleWith(
          'Reached the end of bundle when a length string is expected.',
        ),
      );

      // PORTING NOTE: the JS message is "Reached the end of bundle when more
      // is expected."; the port says "... when more data was expected.".
      await expectLater(
        generateBundleAndParse('1$metaString'),
        throwsInvalidBundleWith('Reached the end of bundle when more'),
      );

      // First element is not BundleMetadata. PORTING NOTE: the JS message is
      // "The first element of the bundle is not a metadata".
      await expectLater(
        generateBundleAndParse(doc1MetaString + doc1String),
        throwsInvalidBundleWith(
          'Expected first element in bundle to be a metadata object',
        ),
      );
    },
  );
}

void main() {
  test('the JS bundle data decodes to the expected elements', () {
    final BundleMetadata metadata = decoded(meta) as BundleMetadata;
    expect(metadata.bundleId, 'test-bundle');
    expect(metadata.totalDocuments, 1);
    expect(
      (decoded(doc1) as BundleDocument).document.data,
      wrapMap(<String, Object?>{'foo': 'value', 'bar': -42}),
    );
    expect(
      (decoded(noDocMeta) as BundledDocumentMetadata).key,
      key('collectionId/nodoc'),
    );
  });

  group('Bundle ', () {
    genericBundleReadingTests(1);
    genericBundleReadingTests(4);
    genericBundleReadingTests(64);
    genericBundleReadingTests(1024);
  });
}

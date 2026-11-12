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

import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_element.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_reader.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundled_document_metadata.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'test_bundle_builder.dart';

// Port of the Android BundleReaderTest.
void main() {
  final DatabaseId testProject = DatabaseId.forProject('test-project');
  final BundleSerializer serializer =
      BundleSerializer(RemoteSerializer(testProject));

  final BundleMetadata bundleMetadata =
      BundleMetadata('bundle-1', 1, version(6000000), 1, 1);
  final NamedQuery limitQuery = NamedQuery(
    'limitQuery',
    BundledQuery(
      Query(path('foo'),
          explicitSortOrder: <OrderBy>[orderBy('sort')], limit: 1),
      BundledQueryLimitType.first,
    ),
    version(1590011379000001),
  );
  final NamedQuery limitToLastQuery = NamedQuery(
    'limitToLastQuery',
    BundledQuery(
      // The query is stored as the backend sees it: limit to first.
      Query(path('foo'),
          explicitSortOrder: <OrderBy>[orderBy('sort')], limit: 1),
      BundledQueryLimitType.last,
    ),
    version(1590011379000002),
  );
  final BundledDocumentMetadata deletedDocMetadata = BundledDocumentMetadata(
      key('coll/nodoc'), version(5000600), false, const <String>[]);
  final BundledDocumentMetadata doc1Metadata = BundledDocumentMetadata(
      key('coll/doc1'), version(5600000), true, const <String>[]);
  final BundleDocument doc1 = BundleDocument(doc(
      'coll/doc1', 30004000, <String, Object?>{'foo': 'value1', 'bar': -42}));
  final BundledDocumentMetadata doc2Metadata = BundledDocumentMetadata(
      key('coll/doc1'), version(5600001), true, const <String>[]);
  final BundleDocument doc2 =
      BundleDocument(doc('coll/doc2', 30004001, <String, Object?>{
    'foo': 'value2',
    'bar': 42,
    'emptyArray': <Object?>[],
    'emptyMap': <String, Object?>{},
  }));
  final BundledDocumentMetadata doc3Metadata = BundledDocumentMetadata(
      key('coll/doc3'), version(5600002), true, const <String>[]);
  final BundleDocument doc3 = BundleDocument(doc(
      'coll/doc3', 30004002, <String, Object?>{'unicodeValue': '\u{1F60A}'}));

  String addDeletedDocMetadata(TestBundleBuilder builder) =>
      builder.addDocumentMetadata('coll/nodoc', 5000600, false);

  String addDoc1Metadata(TestBundleBuilder builder) =>
      builder.addDocumentMetadata('coll/doc1', 5600000, true);

  String addDoc1(TestBundleBuilder builder) =>
      builder.addDocument('coll/doc1', 1200000, 30004000, <String, dynamic>{
        'foo': <String, dynamic>{'stringValue': 'value1'},
        'bar': <String, dynamic>{'integerValue': -42},
      });

  String addDoc2Metadata(TestBundleBuilder builder) =>
      builder.addDocumentMetadata('coll/doc1', 5600001, true);

  String addDoc2(TestBundleBuilder builder) =>
      builder.addDocument('coll/doc2', 1200001, 30004001, <String, dynamic>{
        'foo': <String, dynamic>{'stringValue': 'value2'},
        'bar': <String, dynamic>{'integerValue': 42},
        'emptyArray': <String, dynamic>{'arrayValue': <String, dynamic>{}},
        'emptyMap': <String, dynamic>{'mapValue': <String, dynamic>{}},
      });

  String addDoc3Metadata(TestBundleBuilder builder) =>
      builder.addDocumentMetadata('coll/doc3', 5600002, true);

  String addDoc3(TestBundleBuilder builder) =>
      builder.addDocument('coll/doc3', 1200002, 30004002, <String, dynamic>{
        'unicodeValue': <String, dynamic>{'stringValue': '\u{1F60A}'},
      });

  String addLimitQuery(TestBundleBuilder builder) => builder.addNamedQuery(
          'limitQuery',
          1590011379000001,
          BundledQueryLimitType.first,
          '', <String, dynamic>{
        'from': <Object?>[
          <String, dynamic>{'collectionId': 'foo'}
        ],
        'orderBy': <Object?>[
          <String, dynamic>{
            'field': <String, dynamic>{'fieldPath': 'sort'}
          }
        ],
        'limit': <String, dynamic>{'value': 1},
      });

  String addLimitToLastQuery(TestBundleBuilder builder) =>
      builder.addNamedQuery('limitToLastQuery', 1590011379000002,
          BundledQueryLimitType.last, '', <String, dynamic>{
        'from': <Object?>[
          <String, dynamic>{'collectionId': 'foo'}
        ],
        'orderBy': <Object?>[
          <String, dynamic>{
            'field': <String, dynamic>{'fieldPath': 'sort'}
          }
        ],
        'limit': <String, dynamic>{'value': 1},
      });

  /// Splits [bytes] into chunks of [chunkSize] bytes (the last one may be shorter).
  Stream<List<int>> chunked(Uint8List bytes, int chunkSize) async* {
    for (int i = 0; i < bytes.length; i += chunkSize) {
      yield bytes.sublist(
          i, i + chunkSize > bytes.length ? bytes.length : i + chunkSize);
    }
  }

  BundleReader readerFor(String bundle, {int? chunkSize}) {
    final Uint8List bytes = Uint8List.fromList(utf8.encode(bundle));
    return chunkSize == null
        ? BundleReader.fromBytes(serializer, bytes)
        : BundleReader(serializer, chunked(bytes, chunkSize));
  }

  Future<List<BundleElement>> verifyAllElements(
      BundleReader bundleReader, List<String> expectedElements) async {
    final List<BundleElement> elements = <BundleElement>[];

    final BundleMetadata actualMetadata =
        await bundleReader.getBundleMetadata();
    expect(actualMetadata.bundleId, bundleMetadata.bundleId);
    expect(actualMetadata.schemaVersion, bundleMetadata.schemaVersion);
    expect(actualMetadata.createTime, bundleMetadata.createTime);

    // The bundle metadata is not considered part of the bytes read. Instead, it encodes the expected size of all
    // elements.
    expect(bundleReader.bytesRead, 0);

    int actualBytesRead = 0;
    int actualDocumentsRead = 0;

    for (final String expectedElement in expectedElements) {
      final BundleElement? nextElement = await bundleReader.getNextElement();
      expect(nextElement, isNotNull);

      if (nextElement is BundleDocument ||
          (nextElement is BundledDocumentMetadata && !nextElement.exists)) {
        actualDocumentsRead++;
      }
      elements.add(nextElement!);

      final int elementLength = utf8.encode(expectedElement).length;
      actualBytesRead += '$elementLength'.length + elementLength;
      expect(bundleReader.bytesRead, actualBytesRead);
    }

    // The end of the bundle.
    expect(await bundleReader.getNextElement(), isNull);

    expect(actualBytesRead, actualMetadata.totalBytes);
    expect(actualDocumentsRead, actualMetadata.totalDocuments);

    return elements;
  }

  // Each test runs with the bundle in a single chunk and with several chunk sizes, which splits the elements at
  // arbitrary positions (also inside length prefixes and inside multi-byte characters).
  const List<int?> chunkSizes = <int?>[null, 1, 2, 7, 64];

  for (final int? chunkSize in chunkSizes) {
    group('chunkSize=$chunkSize', () {
      test('testReadsQueryAndDocument', () async {
        final TestBundleBuilder bundleBuilder = TestBundleBuilder(testProject);
        final String limitQueryJson = addLimitQuery(bundleBuilder);
        final String limitToLastQueryJson = addLimitToLastQuery(bundleBuilder);
        final String documentMetadata = addDoc1Metadata(bundleBuilder);
        final String document = addDoc1(bundleBuilder);
        final String bundle = bundleBuilder.build('bundle-1', 6000000, 1);

        final List<BundleElement> bundleElements = await verifyAllElements(
            readerFor(bundle, chunkSize: chunkSize), <String>[
          limitQueryJson,
          limitToLastQueryJson,
          documentMetadata,
          document
        ]);

        expect(bundleElements[0], limitQuery);
        expect(bundleElements[1], limitToLastQuery);
        expect(bundleElements[2], doc1Metadata);
        expect(bundleElements[3], doc1);
      });

      test('testReadsQueryAndDocumentWithUnexpectedOrder', () async {
        final TestBundleBuilder bundleBuilder = TestBundleBuilder(testProject);
        final String doc1MetadataJson = addDoc1Metadata(bundleBuilder);
        final String doc1Json = addDoc1(bundleBuilder);
        final String limitQueryJson = addLimitQuery(bundleBuilder);
        final String doc2MetadataJson = addDoc2Metadata(bundleBuilder);
        final String doc2Json = addDoc2(bundleBuilder);
        final String bundle = bundleBuilder.build('bundle-1', 6000000, 1);

        final List<BundleElement> bundleElements = await verifyAllElements(
            readerFor(bundle, chunkSize: chunkSize), <String>[
          doc1MetadataJson,
          doc1Json,
          limitQueryJson,
          doc2MetadataJson,
          doc2Json
        ]);

        expect(bundleElements[0], doc1Metadata);
        expect(bundleElements[1], doc1);
        expect(bundleElements[2], limitQuery);
        expect(bundleElements[3], doc2Metadata);
        expect(bundleElements[4], doc2);
      });

      test('testReadsWithoutNamedQuery', () async {
        final TestBundleBuilder bundleBuilder = TestBundleBuilder(testProject);
        final String documentMetadata = addDoc1Metadata(bundleBuilder);
        final String document = addDoc1(bundleBuilder);
        final String bundle = bundleBuilder.build('bundle-1', 6000000, 1);

        final List<BundleElement> bundleElements = await verifyAllElements(
            readerFor(bundle, chunkSize: chunkSize),
            <String>[documentMetadata, document]);

        expect(bundleElements[0], doc1Metadata);
        expect(bundleElements[1], doc1);
      });

      test('testReadsWithDeletedDocument', () async {
        final TestBundleBuilder bundleBuilder = TestBundleBuilder(testProject);
        final String deletedDocumentMetadata =
            addDeletedDocMetadata(bundleBuilder);
        final String documentMetadata = addDoc1Metadata(bundleBuilder);
        final String document = addDoc1(bundleBuilder);
        final String bundle = bundleBuilder.build('bundle-1', 6000000, 1);

        final List<BundleElement> bundleElements = await verifyAllElements(
            readerFor(bundle, chunkSize: chunkSize),
            <String>[deletedDocumentMetadata, documentMetadata, document]);

        expect(bundleElements[0], deletedDocMetadata);
        expect(bundleElements[1], doc1Metadata);
        expect(bundleElements[2], doc1);
      });

      test('testReadsWithoutDocumentOrQuery', () async {
        final TestBundleBuilder bundleBuilder = TestBundleBuilder(testProject);
        final String bundle = bundleBuilder.build('bundle-1', 6000000, 1);

        await verifyAllElements(
            readerFor(bundle, chunkSize: chunkSize), <String>[]);
      });

      test('testThrowsWithoutLengthPrefix', () async {
        const String bundle = '{"metadata": "no length prefix" }';

        final BundleReader bundleReader =
            readerFor(bundle, chunkSize: chunkSize);

        expect(bundleReader.getBundleMetadata(), throwsA(isA<ArgumentError>()));
      });

      test('testThrowsWithMissingBrackets', () async {
        final BundleReader bundleReader =
            readerFor('3abc', chunkSize: chunkSize);

        expect(bundleReader.getBundleMetadata(), throwsA(isA<ArgumentError>()));
      });

      test('testThrowsWithInvalidJSON', () async {
        // Android throws a JSONException here; the Dart reader reports every malformed bundle as an ArgumentError.
        final BundleReader bundleReader =
            readerFor('3{abc}', chunkSize: chunkSize);

        expect(bundleReader.getBundleMetadata(), throwsA(isA<ArgumentError>()));
      });

      test('testThrowsWhenSecondElementIsMissing', () async {
        final TestBundleBuilder bundleBuilder = TestBundleBuilder(testProject);
        final String bundle =
            '${bundleBuilder.build('bundle-1', 6000000, 1)}foo';

        final BundleReader bundleReader =
            readerFor(bundle, chunkSize: chunkSize);

        expect(bundleReader.getNextElement(), throwsA(isA<ArgumentError>()));
      });

      test('testThrowsWhenBundleDoesNotContainEnoughData', () async {
        final BundleReader bundleReader =
            readerFor('3{}', chunkSize: chunkSize);

        expect(bundleReader.getBundleMetadata(), throwsA(isA<ArgumentError>()));
      });

      test('testWhenFirstElementIsNotBundleMetadata', () async {
        final String json = jsonEncode(<String, dynamic>{
          'document': <String, dynamic>{
            'name':
                'projects/${testProject.projectId}/databases/${testProject.databaseId}/documents/coll/doc',
            'createTime': <String, dynamic>{'seconds': 1, 'nanos': 2},
            'updateTime': <String, dynamic>{'seconds': 3, 'nanos': 4},
            'fields': <String, dynamic>{},
          },
        });
        final String bundle = '${utf8.encode(json).length}$json';

        final BundleReader bundleReader =
            readerFor(bundle, chunkSize: chunkSize);

        expect(bundleReader.getBundleMetadata(), throwsA(isA<ArgumentError>()));
      });

      test('testCombinesMultipleBufferReads', () async {
        // Create a BundleMetadata element that is much longer than a chunk.
        final String longString = 'a' * 1024;
        final TestBundleBuilder bundleBuilder = TestBundleBuilder(testProject);
        final String json =
            bundleBuilder.build('bundle-$longString', 6000000, 1);

        final BundleReader bundleReader = readerFor(json, chunkSize: chunkSize);

        final BundleMetadata expectedMetadata =
            BundleMetadata('bundle-$longString', 1, version(6000000), 0, 0);
        final BundleMetadata actualMetadata =
            await bundleReader.getBundleMetadata();
        expect(actualMetadata, expectedMetadata);
      });

      test('testReadsUnicodeData', () async {
        final TestBundleBuilder bundleBuilder = TestBundleBuilder(testProject);
        final String docMetadata = addDoc3Metadata(bundleBuilder);
        final String doc = addDoc3(bundleBuilder); // doc3 contains Unicode data
        final String json = bundleBuilder.build('bundle-1', 6000000, 1);

        final List<BundleElement> bundleElements = await verifyAllElements(
            readerFor(json, chunkSize: chunkSize), <String>[docMetadata, doc]);

        expect(bundleElements[0], doc3Metadata);
        expect(bundleElements[1], doc3);
      });
    });
  }

  test('testReadsMultiByteCharactersInTheLengthOfTheElement', () async {
    // Regression test for the Android fix 76b029c: the length prefix counts bytes, not characters.
    final TestBundleBuilder bundleBuilder = TestBundleBuilder(testProject);
    final String doc = bundleBuilder
        .addDocument('coll/doc3', 1200002, 30004002, <String, dynamic>{
      'unicodeValue': <String, dynamic>{'stringValue': 'é€\u{1F60A}'},
    });
    final String json = bundleBuilder.build('bundle-1', 6000000, 1);
    expect(utf8.encode(doc).length, greaterThan(doc.runes.length));

    final BundleReader bundleReader = readerFor(json, chunkSize: 3);
    await bundleReader.getBundleMetadata();
    final BundleElement? element = await bundleReader.getNextElement();
    expect(element, isA<BundleDocument>());
    expect((element! as BundleDocument).document.data,
        wrapMap(<String, Object?>{'unicodeValue': 'é€\u{1F60A}'}));
    expect(await bundleReader.getNextElement(), isNull);
  });

  test('close stops reading', () async {
    final TestBundleBuilder bundleBuilder = TestBundleBuilder(testProject);
    addDoc1(bundleBuilder);
    final BundleReader bundleReader =
        readerFor(bundleBuilder.build('bundle-1', 6000000, 1), chunkSize: 16);
    await bundleReader.getBundleMetadata();
    await bundleReader.close();
    // Closing twice is fine.
    await bundleReader.close();
  });
}

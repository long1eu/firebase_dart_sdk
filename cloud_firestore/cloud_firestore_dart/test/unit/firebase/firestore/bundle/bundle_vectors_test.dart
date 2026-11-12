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
import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_element.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_reader.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_document_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

/// Reads the bundles that the upstream spec tests (`bundle_spec_test.json`, step `loadBundle`) feed to the SDK. They
/// are the bundles of the 'Bundles query can be loaded and resumed from different tabs' spec test, saved as is under
/// `test/res/bundle`.
///
/// PORTING NOTE: the spec tests themselves are not ported, see the porting notes.
void main() {
  final BundleSerializer serializer =
      BundleSerializer(RemoteSerializer(DatabaseId.forProject('test-project')));

  Future<List<BundleElement>> readAll(String resource,
      {required BundleMetadata expectedMetadata}) async {
    final File file =
        File('${Directory.current.path}/test/res/bundle/$resource');
    final BundleReader reader = BundleReader.fromBytes(
        serializer, utf8.encode(file.readAsStringSync()));

    expect(await reader.getBundleMetadata(), expectedMetadata);
    final List<BundleElement> elements = <BundleElement>[];
    BundleElement? element;
    while ((element = await reader.getNextElement()) != null) {
      elements.add(element!);
    }
    // The size of the metadata is not part of the bytes of the bundle.
    expect(reader.bytesRead, expectedMetadata.totalBytes);
    return elements;
  }

  BundledDocumentMetadata documentMetadata(int readTimeNanos) =>
      BundledDocumentMetadata(key('collection/a'),
          SnapshotVersion(Timestamp(0, readTimeNanos)), true, const <String>[]);

  test('first bundle of the multi tab spec test', () async {
    final List<BundleElement> elements = await readAll('spec_bundle_1.txt',
        expectedMetadata: const BundleMetadata(
            'test-bundle', 1, SnapshotVersion(Timestamp(0, 500000)), 1, 675));

    expect(elements, <BundleElement>[
      NamedQuery(
        'bundled-query',
        BundledQuery(
          Query(path('collection'),
              explicitSortOrder: <OrderBy>[orderBy('__name__')]),
          BundledQueryLimitType.first,
        ),
        const SnapshotVersion(Timestamp(0, 400000)),
      ),
      documentMetadata(500000),
      BundleDocument(doc('collection/a', 500, <String, Object?>{'value': 'b'})),
    ]);
  });

  test('second bundle of the multi tab spec test', () async {
    final List<BundleElement> elements = await readAll('spec_bundle_2.txt',
        expectedMetadata: const BundleMetadata(
            'test-bundle', 1, SnapshotVersion(Timestamp(0, 600000)), 1, 772));

    expect(elements, <BundleElement>[
      NamedQuery(
        'bundled-query',
        BundledQuery(
          query('collection')
              .filter(filter('value', '==', 'c'))
              .orderBy(orderBy('__name__')),
          BundledQueryLimitType.first,
        ),
        const SnapshotVersion(Timestamp(0, 560000)),
      ),
      documentMetadata(600000),
      BundleDocument(doc('collection/a', 550, <String, Object?>{'value': 'c'})),
    ]);
  });
}

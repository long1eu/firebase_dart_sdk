// Copyright 2018 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Ported from upstream ViewTest.testViewsWithLimboDocumentsAreMarkedFromCache.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  test('testViewsWithLimboDocumentsAreMarkedFromCache', () {
    final Query query = Query(ResourcePath.fromString('rooms/eros/messages'));
    final View view = View(query, DocumentKey.emptyKeySet);
    final Document doc1 = doc('rooms/eros/messages/0', 0, map());
    final Document doc2 = doc('rooms/eros/messages/1', 0, map());

    // Doc1 is contained in the local view, but we are not yet CURRENT so it is
    // expected that the backend hasn't told us about all documents yet.
    ViewChange change =
        view.applyChanges(view.computeDocChanges(docUpdates(<Document>[doc1])));
    expect(change.snapshot!.isFromCache, isTrue);

    // Add doc2 to generate a snapshot. Doc1 is still missing.
    final ViewDocumentChanges viewDocChanges =
        view.computeDocChanges(docUpdates(<Document>[doc2]));
    change = view.applyChanges(
        viewDocChanges,
        targetChange(Uint8List(0), <Document>[doc2], null, null,
            current: true));
    // We are CURRENT but doc1 is in limbo.
    expect(change.snapshot!.isFromCache, isTrue);

    // Add doc1 to the backend's result set.
    change = view.applyChanges(
        viewDocChanges,
        targetChange(Uint8List(0), <Document>[doc1], null, null,
            current: true));
    expect(change.snapshot!.isFromCache, isFalse);
  });
}

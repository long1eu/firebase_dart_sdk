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

// Ported from the Firestore Android SDK (com.google.firebase.firestore.bundle).

import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_element.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';

/// A document that was saved to a bundle.
class BundleDocument implements BundleElement {
  const BundleDocument(this.document);

  /// The document.
  final Document document;

  /// The key for this document.
  DocumentKey get key => document.key;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BundleDocument &&
          runtimeType == other.runtimeType &&
          document == other.document;

  @override
  int get hashCode => document.hashCode;

  @override
  String toString() => 'BundleDocument{document: $document}';
}

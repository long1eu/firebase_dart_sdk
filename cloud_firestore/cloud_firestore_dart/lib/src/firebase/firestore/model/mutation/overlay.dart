// Copyright 2022 Google LLC
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

import 'package:firebase_app_dart/internal.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';

/// Representation of an overlay computed by Firestore.
///
/// Holds information about a mutation and the largest batch id in Firestore when the mutation was created. The
/// mutation is the result of applying every pending mutation batch of a document to its remote version: applying it
/// to the remote document yields the local view of the document.
class Overlay {
  const Overlay(this.largestBatchId, this.mutation);

  /// The id of the newest mutation batch that contributed to this overlay.
  final int largestBatchId;

  /// The mutation that, applied to the remote document, results in the local view (a set, patch or delete without
  /// precondition or field transforms).
  final Mutation mutation;

  DocumentKey get key => mutation.key;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Overlay &&
          largestBatchId == other.largestBatchId &&
          mutation == other.mutation;

  @override
  int get hashCode => largestBatchId * 31 + mutation.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('largestBatchId', largestBatchId)
          ..add('mutation', mutation))
        .toString();
  }
}

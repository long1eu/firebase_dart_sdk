// Copyright 2026 Google LLC
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

import 'package:cloud_firestore_dart/src/firebase/firestore/core/user_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/set_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:meta/meta.dart';

/// A write batch, used to perform multiple writes as a single atomic unit.
///
/// Get one with [Firestore.batch]. None of the writes are sent until
/// [commit] is called.
class WriteBatch {
  /// Implementation detail of the SDK; not part of the supported API. Use
  /// [Firestore.batch].
  @internal
  WriteBatch(this._firestore);

  final Firestore _firestore;
  final List<Mutation> _mutations = <Mutation>[];

  bool _committed = false;

  /// Writes [data] to the document referred to by [documentRef]. If the
  /// document does not exist yet, it is created. With merge [options] the
  /// data is merged into the existing document.
  WriteBatch set<T extends Object?>(
    DocumentReference<T> documentRef,
    T data, [
    SetOptions? options,
  ]) {
    final SetOptions setOptions = options ?? SetOptions.overwrite;
    _firestore.validateReference(documentRef);
    checkNotNull<Object>(data, 'Provided data must not be null.');
    _verifyNotCommitted();
    final Map<String, Object?> rawData = toRawData<T>(
      data,
      documentRef.converter,
      options,
    );
    final UserDataParsedSetData parsed = setOptions.merge
        ? _firestore.dataConverter.parseMergeData(
            rawData,
            setOptions.fieldMask,
            methodName: 'WriteBatch.set',
            targetDoc: documentRef.key,
            hasConverter: documentRef.converter != null,
          )
        : _firestore.dataConverter.parseSetData(
            rawData,
            methodName: 'WriteBatch.set',
            targetDoc: documentRef.key,
            hasConverter: documentRef.converter != null,
          );
    _mutations.add(parsed.toMutation(documentRef.key, Precondition.none));
    return this;
  }

  /// Updates the fields in [data] (dot-separated field paths to values) of the
  /// document referred to by [documentRef]. The batch fails if the document
  /// does not exist.
  WriteBatch update(
    DocumentReference<Object?> documentRef,
    Map<String, Object?> data,
  ) {
    final UserDataParsedUpdateData parsed = _firestore.dataConverter
        .parseUpdateData(
          data,
          methodName: 'WriteBatch.update',
          targetDoc: documentRef.key,
        );
    _firestore.validateReference(documentRef);
    _verifyNotCommitted();
    _mutations.add(
      parsed.toMutation(documentRef.key, Precondition(exists: true)),
    );
    return this;
  }

  /// Updates fields of the document referred to by [documentRef]. [data]
  /// alternates fields (a `String` or a `FieldPath`) and values.
  WriteBatch updateFromList(
    DocumentReference<Object?> documentRef,
    List<Object?> data,
  ) {
    const String methodName = 'WriteBatch.updateFromList';
    final UserDataParsedUpdateData parsed = _firestore.dataConverter
        .parseUpdateDataFromList(
          collectUpdateArguments(1, data, methodName: methodName),
          methodName: methodName,
          targetDoc: documentRef.key,
        );
    _firestore.validateReference(documentRef);
    _verifyNotCommitted();
    _mutations.add(
      parsed.toMutation(documentRef.key, Precondition(exists: true)),
    );
    return this;
  }

  /// Deletes the document referred to by [documentRef].
  WriteBatch delete(DocumentReference<Object?> documentRef) {
    _firestore.validateReference(documentRef);
    _verifyNotCommitted();
    _mutations.add(DeleteMutation(documentRef.key, Precondition.none));
    return this;
  }

  /// Commits all of the writes in this batch as a single atomic unit. The
  /// future completes when the backend has applied them.
  Future<void> commit() async {
    _verifyNotCommitted();
    _committed = true;
    // An empty batch sends nothing, but still fails on a terminated instance.
    await _firestore.run<void>(
      (Datastore datastore) => _mutations.isEmpty
          ? Future<void>.value()
          : datastore.transactionClient.commit(_mutations),
    );
  }

  void _verifyNotCommitted() {
    if (_committed) {
      throw StateError(
        'A write batch can no longer be used after commit() has been called.',
      );
    }
  }
}

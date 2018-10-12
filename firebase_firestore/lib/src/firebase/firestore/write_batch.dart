// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'dart:async';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:firebase_firestore/src/firebase/firestore/set_options.dart';
import 'package:firebase_firestore/src/firebase/firestore/user_data_converter.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/util.dart';

/// A write batch, used to perform multiple writes as a single atomic unit.
///
/// * A Batch object can be acquired by calling [FirebaseFirestore.batch]. It
/// provides methods for adding writes to the write batch. None of the writes
/// will be committed (or visible locally) until [commit] is called.
///
/// * Unlike transactions, write batches are persisted offline and therefore are
/// preferable when you don't need to condition your writes on read data.
///
/// * <b>Subclassing Note</b>: Firestore classes are not meant to be subclassed
/// except for use in test mocks. Subclassing is not supported in production
/// code and new SDK releases may break code that does so.
@publicApi
class WriteBatch {
  final FirebaseFirestore _firestore;
  final List<Mutation> _mutations = <Mutation>[];

  bool _committed = false;

  WriteBatch(this._firestore) : assert(_firestore != null);

  /// Writes to the document referred to by the provided DocumentReference. If the document does not
  /// yet exist, it will be created. If you pass {@link SetOptions}, the provided data can be merged
  /// into an existing document.
  ///
  /// @param documentRef The DocumentReference to overwrite.
  /// @param data A map of the fields and values for the document.
  /// @param options An object to configure the set behavior.
  /// @return This WriteBatch instance. Used for chaining method calls.
  @publicApi
  WriteBatch set(DocumentReference documentRef, Map<String, Object> data,
      [SetOptions options]) {
    options ??= SetOptions.overwrite;
    _firestore.validateReference(documentRef);
    Assert.checkNotNull(data, 'Provided data must not be null.');
    _verifyNotCommitted();
    final ParsedDocumentData parsed = options.merge
        ? _firestore.dataConverter.parseMergeData(data, options.fieldMask)
        : _firestore.dataConverter.parseSetData(data);
    _mutations
        .addAll(parsed.toMutationList(documentRef.key, Precondition.none));
    return this;
  }

  // todo update this docs
  /// Updates fields in the document referred to by the provided
  /// [DocumentReference]. If no document exists yet, the update will fail.
  ///
  /// [documentRef] The [DocumentReference] to update.
  /// [data] a map of field / value pairs to update. Fields can contain dots to
  /// reference nested fields within the document.
  /// Returns this [WriteBatch] instance. Used for chaining method calls.
  @publicApi
  WriteBatch updateFromList(DocumentReference documentRef, List<Object> data) {
    final ParsedUpdateData parsedData = _firestore.dataConverter
        .parseUpdateDataFromList(Util.collectUpdateArguments(1, data));

    _firestore.validateReference(documentRef);
    _verifyNotCommitted();
    _mutations.addAll(parsedData.toMutationList(
        documentRef.key, Precondition.fromExists(true)));
    return this;
  }

  /// Updates fields in the document referred to by the provided
  /// [DocumentReference]. If no document exists yet, the update will fail.
  ///
  /// [documentRef] The [DocumentReference] to update.
  /// [data] a map of field / value pairs to update. Fields can contain dots to
  /// reference nested fields within the document.
  /// Returns this [WriteBatch] instance. Used for chaining method calls.
  @publicApi
  WriteBatch update(DocumentReference documentRef, Map<String, Object> data) {
    final ParsedUpdateData parsedData =
        _firestore.dataConverter.parseUpdateData(data);

    _firestore.validateReference(documentRef);
    _verifyNotCommitted();
    _mutations.addAll(parsedData.toMutationList(
        documentRef.key, Precondition.fromExists(true)));
    return this;
  }

  /// Deletes the document referred to by the provided [DocumentReference].
  ///
  /// [documentRef] The [DocumentReference] to delete.
  /// Returns this [WriteBatch] instance. Used for chaining method calls.
  @publicApi
  WriteBatch delete(DocumentReference documentRef) {
    _firestore.validateReference(documentRef);
    _verifyNotCommitted();
    _mutations.add(DeleteMutation(documentRef.key, Precondition.none));
    return this;
  }

  /// Commits all of the writes in this write batch as a single atomic unit.
  @publicApi
  Future<void> commit() async {
    _verifyNotCommitted();
    _committed = true;
    if (_mutations.isNotEmpty) {
      await _firestore.client.write(_mutations);
    }
  }

  void _verifyNotCommitted() {
    if (_committed) {
      throw StateError(
          'A write batch can no longer be used after commit() has been called.');
    }
  }
}

// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/core/user_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/set_options.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/util.dart';

/// The signature for providing code to be executed within a [WriteBatch]
/// context.
typedef BatchCallback = Future<void> Function(WriteBatch);

/// A write batch, used to perform multiple writes as a single atomic unit.
///
/// A Batch object can be acquired by calling [Firestore.batch]. It provides methods for
/// adding writes to the write batch. None of the writes will be committed (or visible locally)
/// until [commit] is called.
///
/// Unlike transactions, write batches are persisted offline and therefore are preferable when you
/// don't need to condition your writes on read data.
///
/// **Subclassing Note**: Cloud Firestore classes are not meant to be subclassed except for use in test
/// mocks. Subclassing is not supported in production code and new SDK releases may break code that
/// does so.
class WriteBatch {
  WriteBatch(this._firestore) : assert(_firestore != null);

  final Firestore _firestore;
  final List<Mutation> _mutations = <Mutation>[];

  bool _committed = false;

  /// Writes to the document referred to by the provided [DocumentReference]. If the document does
  /// not yet exist, it will be created. If you pass [SetOptions], the provided data can be merged
  /// into an existing document.
  ///
  /// The documentRef to overwrite, [data] is a map of the fields and values for the document and
  /// [options] is an object to configure the set behavior.
  ///
  /// Returns this [WriteBatch] instance. Used for chaining method calls.
  WriteBatch set(DocumentReference documentRef, Map<String, Object> data, [SetOptions options]) {
    options ??= SetOptions.overwrite;
    _firestore.validateReference(documentRef);
    checkNotNull(data, 'Provided data must not be null.');
    _verifyNotCommitted();
    final UserDataParsedSetData parsed = options.merge
        ? _firestore.userDataReader.parseMergeData(data, options.fieldMask)
        : _firestore.userDataReader.parseSetData(data);
    _mutations.add(parsed.toMutation(documentRef.key, Precondition.none));
    return this;
  }

  // todo update this docs
  /// Updates fields in the document referred to by the provided [DocumentReference]. If no document
  /// exists yet, the update will fail.
  ///
  /// [documentRef] The [DocumentReference] to update.
  /// [data] a map of field / value pairs to update. Fields can contain dots to
  /// reference nested fields within the document.
  ///
  /// Returns this [WriteBatch] instance. Used for chaining method calls.
  WriteBatch updateFromList(DocumentReference documentRef, List<Object> data) {
    final UserDataParsedUpdateData parsedData =
        _firestore.userDataReader.parseUpdateDataFromList(collectUpdateArguments(1, data));

    _firestore.validateReference(documentRef);
    _verifyNotCommitted();
    _mutations.add(parsedData.toMutation(documentRef.key, Precondition(exists: true)));
    return this;
  }

  /// Updates fields in the document referred to by the provided [DocumentReference]. If no document
  /// exists yet, the update will fail.
  ///
  /// [documentRef] The [DocumentReference] to update.
  /// [data] a map of field / value pairs to update. Fields can contain dots to reference nested
  /// fields within the document.
  ///
  /// Returns this [WriteBatch] instance. Used for chaining method calls.
  WriteBatch update(DocumentReference documentRef, Map<String, Object> data) {
    final UserDataParsedUpdateData parsedData = _firestore.userDataReader.parseUpdateData(data);

    _firestore.validateReference(documentRef);
    _verifyNotCommitted();
    _mutations.add(parsedData.toMutation(documentRef.key, Precondition(exists: true)));
    return this;
  }

  /// Deletes the document referred to by the provided [DocumentReference].
  ///
  /// [documentRef] The [DocumentReference] to delete.
  ///
  /// Returns this [WriteBatch] instance. Used for chaining method calls.
  WriteBatch delete(DocumentReference documentRef) {
    _firestore.validateReference(documentRef);
    _verifyNotCommitted();
    _mutations.add(DeleteMutation(documentRef.key, Precondition.none));
    return this;
  }

  /// Commits all of the writes in this write batch as a single atomic unit.
  Future<void> commit() async {
    _verifyNotCommitted();
    _committed = true;
    if (_mutations.isNotEmpty) {
      await _firestore.client.write(_mutations);
    }
  }

  void _verifyNotCommitted() {
    if (_committed) {
      throw StateError('A write batch can no longer be used after commit() has been called.');
    }
  }
}

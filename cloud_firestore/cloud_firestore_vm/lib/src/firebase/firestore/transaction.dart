// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/core/transaction.dart'
    as core;
import 'package:cloud_firestore_vm/src/firebase/firestore/core/user_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/set_options.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/util.dart';

/// The signature for providing code to be executed within a transaction context.
typedef TransactionCallback<T> = Future<T> Function(Transaction);

/// A [Transaction] is passed to a [Function] to provide the methods to read and write data within
/// the transaction context.
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test
/// mocks. Subclassing is not supported in production code and new SDK releases may break code that
/// does so.
class Transaction {
  Transaction(this._transaction, this._firestore)
      : assert(_transaction != null),
        assert(_firestore != null);

  final core.Transaction _transaction;

  final Firestore _firestore;

  /// Writes to the document referred to by the provided [DocumentReference]. If the document does
  /// not yet exist, it will be created. If you pass [SetOptions], the provided data can be merged
  /// into an existing document.
  ///
  /// [documentRef] The [DocumentReference] to overwrite.
  /// [data] A map of the fields and values for the document.
  /// [options] An object to configure the set behavior.
  ///
  /// Returns this Transaction instance. Used for chaining method calls.
  Transaction set(DocumentReference documentRef, Map<String, Object> data,
      [SetOptions options]) {
    options ??= SetOptions.overwrite;
    _firestore.validateReference(documentRef);
    checkNotNull(data, 'Provided data must not be null.');
    checkNotNull(options, 'Provided options must not be null.');
    final UserDataParsedSetData parsed = options.merge
        ? _firestore.dataConverter.parseMergeData(data, options.fieldMask)
        : _firestore.dataConverter.parseSetData(data);
    _transaction.set(documentRef.key, parsed);
    return this;
  }

  /// Updates fields in the document referred to by the provided [DocumentReference]. If no document
  /// exists yet, the update will fail.
  ///
  /// [documentRef] The [DocumentReference] to update.
  /// [data] A map of field / value pairs to update. Fields can contain dots to reference nested
  /// fields within the document.
  ///
  /// Return this [Transaction] instance. Used for chaining method calls.
  Transaction updateFromList(DocumentReference documentRef, List<Object> data) {
    final UserDataParsedUpdateData parsedData = _firestore.dataConverter
        .parseUpdateDataFromList(collectUpdateArguments(1, data));
    return _update(documentRef, parsedData);
  }

  /// Updates fields in the document referred to by the provided [DocumentReference]. If no document
  /// exists yet, the update will fail.
  ///
  /// [documentRef] The [DocumentReference] to update.
  /// [data] A map of field / value pairs to update. Fields can contain dots to reference nested
  /// fields within the document.
  ///
  /// Return this [Transaction] instance. Used for chaining method calls.
  Transaction update(DocumentReference documentRef, Map<String, Object> data) {
    final UserDataParsedUpdateData parsedData =
        _firestore.dataConverter.parseUpdateData(data);
    return _update(documentRef, parsedData);
  }

  Transaction _update(
      DocumentReference documentRef, UserDataParsedUpdateData updateData) {
    _firestore.validateReference(documentRef);
    _transaction.update(documentRef.key, updateData);
    return this;
  }

  /// Deletes the document referred to by the provided [DocumentReference].
  ///
  /// [documentRef] The [DocumentReference] to delete.
  ///
  /// Return this [Transaction] instance. Used for chaining method calls.
  Transaction delete(DocumentReference documentRef) {
    _firestore.validateReference(documentRef);
    _transaction.delete(documentRef.key);
    return this;
  }

  /// Reads the document referenced by the provided [DocumentReference]
  ///
  /// [documentRef] The [DocumentReference] to read.
  ///
  /// Returns a Future that will be resolved with the contents of the [Document] at this
  /// [DocumentReference].
  Future<DocumentSnapshot> get(DocumentReference documentRef) async {
    _firestore.validateReference(documentRef);
    final List<MaybeDocument> result =
        await _transaction.lookup(<DocumentKey>[documentRef.key]);

    if (result.length != 1) {
      throw fail('Mismatch in docs returned from document lookup.');
    }

    final MaybeDocument doc = result.first;
    if (doc is Document) {
      return DocumentSnapshot.fromDocument(
        _firestore,
        doc,
        isFromCache: false,
        hasPendingWrites: false,
      );
    } else if (doc is NoDocument) {
      return DocumentSnapshot.fromNoDocument(
        _firestore,
        doc.key,
        isFromCache: false,
        hasPendingWrites: false,
      );
    } else {
      throw fail('BatchGetDocumentsRequest returned unexpected document type: '
          '${doc.runtimeType}');
    }
  }
}

// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/converter_util.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/transaction.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/user_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/set_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';

/// The signature for providing code to be executed within a transaction context.
typedef TransactionCallback<T> = Future<T> Function(Transaction);

/// A [Transaction] is passed to a [Function] to provide the methods to read and write data within
/// the transaction context.
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test
/// mocks. Subclassing is not supported in production code and new SDK releases may break code that
/// does so.
class Transaction {
  /// Implementation detail of the SDK; not part of the supported API. Use
  /// [Firestore.runTransaction].
  Transaction._(this._transaction, this._firestore);

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
  Transaction set<T extends Object?>(
    DocumentReference<T> documentRef,
    T data, [
    SetOptions? options,
  ]) {
    final SetOptions? userOptions = options;
    options ??= SetOptions.overwrite;
    _firestore.validateReference(documentRef);
    checkNotNull<Object>(data, 'Provided data must not be null.');
    final Map<String, Object?> rawData = toRawData<T>(
      data,
      documentRef.converter,
      userOptions,
    );
    final UserDataParsedSetData parsed = options.merge
        ? _firestore.dataConverter.parseMergeData(rawData, options.fieldMask)
        : _firestore.dataConverter.parseSetData(rawData);
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
  Transaction updateFromList(
    DocumentReference<Object?> documentRef,
    List<Object?> data,
  ) {
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
  Transaction update(
    DocumentReference<Object?> documentRef,
    Map<String, Object?> data,
  ) {
    final UserDataParsedUpdateData parsedData = _firestore.dataConverter
        .parseUpdateData(data);
    return _update(documentRef, parsedData);
  }

  Transaction _update(
    DocumentReference<Object?> documentRef,
    UserDataParsedUpdateData updateData,
  ) {
    _firestore.validateReference(documentRef);
    _transaction.update(documentRef.key, updateData);
    return this;
  }

  /// Deletes the document referred to by the provided [DocumentReference].
  ///
  /// [documentRef] The [DocumentReference] to delete.
  ///
  /// Return this [Transaction] instance. Used for chaining method calls.
  Transaction delete(DocumentReference<Object?> documentRef) {
    _firestore.validateReference(documentRef);
    _transaction.delete(documentRef.key);
    return this;
  }

  /// Runs [query] on the server inside this transaction and returns its
  /// results. Only in a read-only transaction
  /// (`TransactionOptions(readOnly: true)`): the documents are those of the
  /// snapshot of the database that every read of the transaction sees.
  ///
  /// In a read-write transaction the returned Future fails with a
  /// [FirestoreError] with code `invalidArgument`: such a transaction verifies
  /// at commit that the documents it read did not change, which is not possible
  /// for the result of a query.
  ///
  /// The snapshot never comes from the cache and has no pending writes; local
  /// writes that the server has not seen are not part of it.
  Future<QuerySnapshot<T>> getQuery<T extends Object?>(Query<T> query) async {
    _validateQuery(query);
    final List<Document> documents = await _transaction.runQuery(query.query);
    DocumentSet documentSet = DocumentSet.emptySet(query.query.comparator);
    for (final Document document in documents) {
      documentSet = documentSet.add(document);
    }
    return QuerySnapshotInternal.create<T>(
      query,
      ViewSnapshot.fromInitialDocuments(
        query.query,
        documentSet,
        DocumentKey.emptyKeySet,
        isFromCache: false,
        excludesMetadataChanges: false,
        hasCachedResults: false,
      ),
      _firestore,
    );
  }

  /// Runs the aggregation [aggregateQuery] on the server inside this
  /// transaction. Only in a read-only transaction, like [getQuery]: the
  /// aggregation is computed over the snapshot of the database that every read
  /// of the transaction sees.
  Future<AggregateQuerySnapshot> getAggregate(
    AggregateQuery aggregateQuery,
  ) async {
    _validateQuery(aggregateQuery.query);
    final Map<String, FieldValue> data = await _transaction.runAggregateQuery(
      aggregateQuery.query.query,
      aggregateQuery.aggregateFields,
    );
    return AggregateQuerySnapshotInternal.create(aggregateQuery, data);
  }

  void _validateQuery(Query<Object?> query) {
    if (query.firestore != _firestore) {
      throw ArgumentError(
        'Provided query is from a different Cloud Firestore instance.',
      );
    }
  }

  /// Reads the document referenced by the provided [DocumentReference]
  ///
  /// [documentRef] The [DocumentReference] to read.
  ///
  /// Returns a Future that will be resolved with the contents of the [Document] at this
  /// [DocumentReference].
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentRef,
  ) async {
    _firestore.validateReference(documentRef);
    final List<MaybeDocument> result = await _transaction.lookup(<DocumentKey>[
      documentRef.key,
    ]);

    if (result.length != 1) {
      throw fail('Mismatch in docs returned from document lookup.');
    }

    final MaybeDocument doc = result.first;
    if (doc is Document) {
      return DocumentSnapshotInternal.fromDocument<T>(
        _firestore,
        doc,
        isFromCache: false,
        hasPendingWrites: false,
        converter: documentRef.converter,
      );
    } else if (doc is NoDocument) {
      return DocumentSnapshotInternal.fromNoDocument<T>(
        _firestore,
        doc.key,
        isFromCache: false,
        hasPendingWrites: false,
        converter: documentRef.converter,
      );
    } else {
      throw fail(
        'BatchGetDocumentsRequest returned unexpected document type: '
        '${doc.runtimeType}',
      );
    }
  }
}

/// Members of [Transaction] for the SDK itself. Not exported by the public libraries.
extension TransactionInternal on Transaction {
  /// Wraps the core [transaction] of [firestore].
  static Transaction create(
    core.Transaction transaction,
    Firestore firestore,
  ) => Transaction._(transaction, firestore);

  /// The core transaction this transaction wraps.
  core.Transaction get coreTransaction => _transaction;

  /// The database this transaction runs against.
  Firestore get firestore => _firestore;
}

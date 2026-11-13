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

import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/transaction.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/user_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/aggregate.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_builder.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/set_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:meta/meta.dart';

/// A [Transaction] is passed to the function given to
/// [Firestore.runTransaction], to read and write documents within the
/// transaction.
///
/// All the reads must come before the first write.
class Transaction {
  /// Implementation detail of the SDK; not part of the supported API. Use
  /// [Firestore.runTransaction].
  @internal
  Transaction(this._transaction, this._firestore);

  final core.Transaction _transaction;
  final Firestore _firestore;

  /// Reads the document referred to by [documentRef].
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
    return DocumentSnapshot<T>(
      _firestore,
      documentRef.key,
      doc is Document ? doc : null,
      documentRef.converter,
    );
  }

  /// Runs [query] on the backend inside this transaction. Only in a read-only
  /// transaction (`TransactionOptions(readOnly: true)`): the documents are
  /// those of the snapshot of the database that every read of the transaction
  /// sees.
  ///
  /// In a read-write transaction the returned future fails with a
  /// [FirestoreError] with code `invalidArgument`: such a transaction verifies
  /// at commit that the documents it read did not change, which is not possible
  /// for the result of a query.
  Future<QuerySnapshot<T>> getQuery<T extends Object?>(Query<T> query) async {
    _validateQuery(query);
    final core.Query internalQuery = query.query;
    QueryBuilder.validateHasExplicitOrderByForLimitToLast(internalQuery);
    final List<Document> documents = await _transaction.runQuery(internalQuery);
    return QuerySnapshot<T>(
      query,
      // The flipped query was sent, see [Query.get].
      internalQuery.hasLimitToLast ? documents.reversed.toList() : documents,
    );
  }

  /// Runs the aggregation [aggregateQuery] on the backend inside this
  /// transaction. Only in a read-only transaction, like [getQuery].
  Future<AggregateQuerySnapshot> getAggregate(
    AggregateQuery aggregateQuery,
  ) async {
    _validateQuery(aggregateQuery.query);
    final Map<String, FieldValue> data = await _transaction.runAggregateQuery(
      aggregateQuery.query.query,
      aggregateQuery.aggregateFields,
    );
    return AggregateQuerySnapshot(aggregateQuery, data);
  }

  void _validateQuery(Query<Object?> query) {
    if (!identical(query.firestore, _firestore)) {
      throw ArgumentError(
        'Provided query is from a different Cloud Firestore instance.',
      );
    }
  }

  /// Writes [data] to the document referred to by [documentRef]. If the
  /// document does not exist yet, it is created. With merge [options] the
  /// data is merged into the existing document.
  Transaction set<T extends Object?>(
    DocumentReference<T> documentRef,
    T data, [
    SetOptions? options,
  ]) {
    final SetOptions setOptions = options ?? SetOptions.overwrite;
    _firestore.validateReference(documentRef);
    checkNotNull<Object>(data, 'Provided data must not be null.');
    final Map<String, Object?> rawData = toRawData<T>(
      data,
      documentRef.converter,
      options,
    );
    final UserDataParsedSetData parsed = setOptions.merge
        ? _firestore.dataConverter.parseMergeData(
            rawData,
            setOptions.fieldMask,
            methodName: 'Transaction.set',
            targetDoc: documentRef.key,
            hasConverter: documentRef.converter != null,
          )
        : _firestore.dataConverter.parseSetData(
            rawData,
            methodName: 'Transaction.set',
            targetDoc: documentRef.key,
            hasConverter: documentRef.converter != null,
          );
    _transaction.set(documentRef.key, parsed);
    return this;
  }

  /// Updates the fields in [data] (dot-separated field paths to values) of the
  /// document referred to by [documentRef]. The transaction fails if the
  /// document does not exist.
  Transaction update(
    DocumentReference<Object?> documentRef,
    Map<String, Object?> data,
  ) {
    _firestore.validateReference(documentRef);
    _transaction.update(
      documentRef.key,
      _firestore.dataConverter.parseUpdateData(
        data,
        methodName: 'Transaction.update',
        targetDoc: documentRef.key,
      ),
    );
    return this;
  }

  /// Updates fields of the document referred to by [documentRef]. [data]
  /// alternates fields (a `String` or a `FieldPath`) and values.
  Transaction updateFromList(
    DocumentReference<Object?> documentRef,
    List<Object?> data,
  ) {
    _firestore.validateReference(documentRef);
    _transaction.update(
      documentRef.key,
      _firestore.dataConverter.parseUpdateDataFromList(
        collectUpdateArguments(
          1,
          data,
          methodName: 'Transaction.updateFromList',
        ),
        methodName: 'Transaction.updateFromList',
        targetDoc: documentRef.key,
      ),
    );
    return this;
  }

  /// Deletes the document referred to by [documentRef].
  Transaction delete(DocumentReference<Object?> documentRef) {
    _firestore.validateReference(documentRef);
    _transaction.delete(documentRef.key);
    return this;
  }
}

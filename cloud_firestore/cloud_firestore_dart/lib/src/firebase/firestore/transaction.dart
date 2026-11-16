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
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
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

/// The function that [FirebaseFirestore.runTransaction] runs inside a transaction,
/// and runs again for each retry.
///
/// It receives the [Transaction] to read and write with. The value its
/// future completes with is what [FirebaseFirestore.runTransaction] returns. If it
/// throws, the transaction is not committed.
typedef TransactionHandler<T> = Future<T> Function(Transaction);

/// Reads and writes documents inside a transaction started with
/// [FirebaseFirestore.runTransaction].
///
/// You never create a transaction yourself: [FirebaseFirestore.runTransaction] passes
/// one to your function. A read-write transaction (the default) reads
/// documents with [get], then writes with [set], [update], [updateFromList]
/// and [delete]. When the function completes, the writes are committed
/// together, and only if none of the documents the function read has changed
/// on the server since it read them.
///
/// ```dart
/// final DocumentReference<Map<String, Object?>> counter =
///     firestore.doc('counters/visits');
/// final int next = await firestore.runTransaction<int>((
///   Transaction transaction,
/// ) async {
///   final DocumentSnapshot<Map<String, Object?>> snapshot =
///       await transaction.get(counter);
///   final int value = (snapshot.data?['value'] as int?) ?? 0;
///   transaction.set(counter, <String, Object?>{'value': value + 1});
///   return value + 1;
/// });
/// ```
///
/// Rules for the function:
///
/// * Do every read before the first write. A [get] after a write fails with
///   [FirestoreErrorCode.invalidArgument], and so does the commit.
/// * The function can run several times. When a document it read changed
///   before the commit, the client runs it again after a backoff (about one
///   second at first, then longer), up to [TransactionOptions.maxAttempts]
///   attempts (5 by default). Keep side effects, such as changing your app's
///   state, out of the function, or make them safe to repeat.
/// * Errors with the codes [FirestoreErrorCode.aborted],
///   [FirestoreErrorCode.alreadyExists] and
///   [FirestoreErrorCode.failedPrecondition], and errors that a new attempt
///   can fix (such as [FirestoreErrorCode.unavailable]), cause a retry, also
///   when your function throws them. Any other error, and any error that is
///   not a [FirestoreException], ends the transaction: nothing is written and the
///   future of [FirebaseFirestore.runTransaction] fails with that error. When the
///   attempts are used up it fails with the last error, for example
///   [FirestoreErrorCode.failedPrecondition] after repeated conflicts.
/// * Do not keep the transaction after the function has completed.
///
/// A transaction needs the backend: its reads never come from the local
/// cache, and it is not queued while the client is offline, unlike a
/// `WriteBatch`. Without a connection the reads or the commit fail, the
/// client retries until the attempts are used up, and then the future
/// fails. The writes of a transaction are sent to the server at commit and
/// are not applied to the local cache as pending writes: listeners see them
/// only once the server reports the change.
///
/// A read-only transaction (`TransactionOptions(readOnly: true)`) reads a
/// consistent snapshot of the database and can also run queries with
/// [getQuery] and aggregations with [getAggregate]; it cannot write. Read-only
/// transactions, [getQuery] and [getAggregate] are not in the JS client SDK;
/// they follow the server SDKs.
///
/// A commit that is lost on the way back can make the client retry a
/// transaction that the backend already applied, so the same writes can be
/// applied twice. The JS and Android SDKs have the same exposure. Make such
/// writes idempotent where it matters.
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test
/// mocks. Subclassing is not supported in production code and new SDK releases may break code that
/// does so.
class Transaction {
  /// Implementation detail of the SDK; not part of the supported API. Use
  /// [FirebaseFirestore.runTransaction].
  Transaction._(this._transaction, this._firestore);

  final core.Transaction _transaction;

  final FirebaseFirestore _firestore;

  /// Writes [data] to the document [documentRef] when the transaction
  /// commits: the document is created if it does not exist, and replaced if
  /// it does.
  ///
  /// With [options] set to [SetOptions.mergeAllFields],
  /// [SetOptions.mergeFields] or [SetOptions.mergeFieldPaths], [data] is
  /// merged into the existing document instead. When [documentRef] has a
  /// converter, [data] is a [T] and is converted with
  /// `FirestoreDataConverter.toFirestore`.
  ///
  /// If the transaction read [documentRef] before, the commit checks that the
  /// document has not changed since.
  ///
  /// ```dart
  /// transaction.set(
  ///   firestore.doc('cities/SF'),
  ///   <String, Object?>{'visited': true},
  ///   SetOptions.mergeAllFields,
  /// );
  /// ```
  ///
  /// Throws an [ArgumentError] if [data] holds a value Firestore cannot store,
  /// or if [documentRef] belongs to another [FirebaseFirestore] instance. Throws a
  /// [FirestoreException] with [FirestoreErrorCode.invalidArgument] in a
  /// read-only transaction.
  ///
  /// Returns this transaction, so that calls can be chained.
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
        ? _firestore.dataConverter.parseMergeData(
            rawData,
            options.fieldMask,
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

  /// Updates some fields of the existing document [documentRef] when the
  /// transaction commits. [data] alternates fields (a dot-separated `String`
  /// or a [FieldPath]) and their values.
  ///
  /// ```dart
  /// transaction.updateFromList(firestore.doc('cities/SF'), <Object?>[
  ///   'population', 870000,
  ///   FieldPath.of(<String>['stats.v2', 'visits']), FieldValue.increment(1),
  /// ]);
  /// ```
  ///
  /// Behaves as [update] otherwise; use this form when a field name contains
  /// a dot.
  ///
  /// Returns this transaction, so that calls can be chained.
  Transaction updateFromList(
    DocumentReference<Object?> documentRef,
    List<Object?> data,
  ) {
    const String methodName = 'Transaction.updateFromList';
    final UserDataParsedUpdateData parsedData = _firestore.dataConverter
        .parseUpdateDataFromList(
          collectUpdateArguments(1, data, methodName: methodName),
          methodName: methodName,
          targetDoc: documentRef.key,
        );
    return _update(documentRef, parsedData);
  }

  /// Updates the fields in [data] of the existing document [documentRef] when
  /// the transaction commits. Fields that are not in [data] keep their
  /// values.
  ///
  /// The keys of [data] are field paths: `'address.city'` changes only `city`
  /// inside the map `address`. A converter of [documentRef] is not used.
  ///
  /// ```dart
  /// transaction.update(firestore.doc('cities/SF'), <String, Object?>{
  ///   'population': FieldValue.increment(1),
  /// });
  /// ```
  ///
  /// The document must exist. If the transaction read it and it was missing,
  /// the commit fails with [FirestoreErrorCode.invalidArgument]; if the
  /// transaction did not read it and it is missing, the commit fails with
  /// [FirestoreErrorCode.notFound]. Neither is retried.
  ///
  /// Throws an [ArgumentError] if [data] holds an invalid field path or value,
  /// or if [documentRef] belongs to another [FirebaseFirestore] instance. Throws a
  /// [FirestoreException] with [FirestoreErrorCode.invalidArgument] in a
  /// read-only transaction.
  ///
  /// Returns this transaction, so that calls can be chained.
  Transaction update(
    DocumentReference<Object?> documentRef,
    Map<String, Object?> data,
  ) {
    final UserDataParsedUpdateData parsedData = _firestore.dataConverter
        .parseUpdateData(
          data,
          methodName: 'Transaction.update',
          targetDoc: documentRef.key,
        );
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

  /// Deletes the document [documentRef] when the transaction commits.
  ///
  /// Deleting a missing document is not an error. If the transaction read
  /// [documentRef] before, the commit checks that it has not changed since.
  ///
  /// ```dart
  /// transaction.delete(firestore.doc('cities/SF'));
  /// ```
  ///
  /// Throws an [ArgumentError] if [documentRef] belongs to another
  /// [FirebaseFirestore] instance, and a [FirestoreException] with
  /// [FirestoreErrorCode.invalidArgument] in a read-only transaction.
  ///
  /// Returns this transaction, so that calls can be chained.
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
  /// ```dart
  /// final QuerySnapshot<Map<String, Object?>> cities =
  ///     await firestore.runTransaction(
  ///       (Transaction transaction) => transaction.getQuery(
  ///         firestore.collection('cities').where('capital', isEqualTo: true),
  ///       ),
  ///       options: TransactionOptions(readOnly: true),
  ///     );
  /// ```
  ///
  /// In a read-write transaction the returned Future fails with a
  /// [FirestoreException] with code `invalidArgument`: such a transaction verifies
  /// at commit that the documents it read did not change, which is not possible
  /// for the result of a query. It fails with an [ArgumentError] if [query]
  /// belongs to another [FirebaseFirestore] instance.
  ///
  /// The snapshot never comes from the cache and has no pending writes; local
  /// writes that the server has not seen are not part of it.
  ///
  /// Not in the JS client SDK (its server SDKs have queries in transactions).
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
  ///
  /// ```dart
  /// final AggregateQuerySnapshot result = await firestore.runTransaction(
  ///   (Transaction transaction) =>
  ///       transaction.getAggregate(firestore.collection('cities').count()),
  ///   options: TransactionOptions(readOnly: true),
  /// );
  /// print(result.getCount());
  /// ```
  ///
  /// In a read-write transaction the returned Future fails with a
  /// [FirestoreException] with code `invalidArgument`. It fails with an
  /// [ArgumentError] if the query belongs to another [FirebaseFirestore] instance.
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

  /// Reads the document [documentRef] from the server.
  ///
  /// The read never uses the local cache, and the snapshot has no pending
  /// writes. A missing document is not an error: the snapshot then has
  /// `exists` false. When [documentRef] has a converter, the snapshot's data
  /// is converted with it.
  ///
  /// In a read-write transaction the commit checks that the document has not
  /// changed since this read; if it has, the transaction is retried. Every
  /// read must come before the first write: after a write the future fails
  /// with [FirestoreErrorCode.invalidArgument] and the transaction does not
  /// commit. In a read-only transaction every read sees the same snapshot of
  /// the database.
  ///
  /// ```dart
  /// final DocumentSnapshot<Map<String, Object?>> snapshot =
  ///     await transaction.get(firestore.doc('cities/SF'));
  /// ```
  ///
  /// The future fails with an [ArgumentError] if [documentRef] belongs to
  /// another [FirebaseFirestore] instance, and with a [FirestoreException] when the server
  /// cannot be reached or rejects the read (for example
  /// [FirestoreErrorCode.permissionDenied]).
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
    FirebaseFirestore firestore,
  ) => Transaction._(transaction, firestore);

  /// The core transaction this transaction wraps.
  core.Transaction get coreTransaction => _transaction;

  /// The database this transaction runs against.
  FirebaseFirestore get firestore => _firestore;
}

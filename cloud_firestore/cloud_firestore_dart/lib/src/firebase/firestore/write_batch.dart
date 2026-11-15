// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/converter_util.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/user_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/set_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';

/// The function that [Firestore.runBatch] calls with a new [WriteBatch].
///
/// Add writes to the batch in the function; [Firestore.runBatch] commits them
/// when the returned future completes.
typedef BatchCallback = Future<void> Function(WriteBatch);

/// A set of writes that Firestore applies together, as a single atomic unit:
/// either all of them or none.
///
/// Get a batch from [Firestore.batch], add writes with [set], [update],
/// [updateFromList] and [delete], then call [commit]. None of the writes is
/// applied, not even to the local cache, until [commit] is called.
/// [Firestore.runBatch] does the same and commits for you.
///
/// ```dart
/// final DocumentReference<Map<String, Object?>> sf = firestore.doc('cities/SF');
/// final DocumentReference<Map<String, Object?>> la = firestore.doc('cities/LA');
/// await firestore
///     .batch()
///     .set(sf, <String, Object?>{'name': 'San Francisco'})
///     .update(la, <String, Object?>{'population': FieldValue.increment(1)})
///     .delete(firestore.doc('cities/OLD'))
///     .commit();
/// ```
///
/// A batch does not read, so it cannot make a write depend on the current
/// value of a document; use [Firestore.runTransaction] for that. In return a
/// batch works offline: [commit] applies the writes to the local cache at
/// once and sends them when the client is online again, while a transaction
/// needs the backend.
///
/// The client sets no limit on the number of writes. The backend rejects a
/// commit request larger than 10 MiB, and allows at most 500 field transforms
/// (such as [FieldValue.serverTimestamp] or [FieldValue.increment]) per
/// document. Unlike in earlier versions of the Firebase SDKs, there is no
/// limit of 500 writes per batch.
///
/// A batch belongs to the [Firestore] instance that created it: every
/// [DocumentReference] passed to it must come from the same instance.
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test
/// mocks. Subclassing is not supported in production code and new SDK releases may break code that
/// does so.
class WriteBatch {
  /// Implementation detail of the SDK; not part of the supported API. Use [Firestore.batch].
  WriteBatch._(this._firestore);

  final Firestore _firestore;
  final List<Mutation> _mutations = <Mutation>[];

  bool _committed = false;

  /// Adds a write of [data] to the document [documentRef]: the document is
  /// created if it does not exist, and replaced if it does.
  ///
  /// With [options] set to [SetOptions.mergeAllFields],
  /// [SetOptions.mergeFields] or [SetOptions.mergeFieldPaths], [data] is
  /// merged into the existing document instead of replacing it. Without
  /// [options] the document is overwritten ([SetOptions.overwrite]).
  ///
  /// When [documentRef] has a converter (`withConverter`), [data] is a [T]
  /// and is converted with `FirestoreDataConverter.toFirestore`; otherwise
  /// it is a map of fields to values.
  ///
  /// ```dart
  /// batch.set(
  ///   firestore.doc('cities/SF'),
  ///   <String, Object?>{'capital': false},
  ///   SetOptions.mergeAllFields,
  /// );
  /// ```
  ///
  /// Throws an [ArgumentError] if [data] holds a value Firestore cannot store
  /// or a [FieldValue] where it is not allowed (for example
  /// [FieldValue.delete] without a merge), or if [documentRef] belongs to
  /// another [Firestore] instance. Throws a [StateError] if the batch was
  /// already committed.
  ///
  /// Returns this batch, so that calls can be chained.
  WriteBatch set<T extends Object?>(
    DocumentReference<T> documentRef,
    T data, [
    SetOptions? options,
  ]) {
    final SetOptions? userOptions = options;
    options ??= SetOptions.overwrite;
    _firestore.validateReference(documentRef);
    checkNotNull<Object>(data, 'Provided data must not be null.');
    _verifyNotCommitted();
    final Map<String, Object?> rawData = toRawData<T>(
      data,
      documentRef.converter,
      userOptions,
    );
    final UserDataParsedSetData parsed = options.merge
        ? _firestore.dataConverter.parseMergeData(
            rawData,
            options.fieldMask,
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

  /// Adds an update of some fields of the existing document [documentRef],
  /// given as a flat list of alternating fields and values.
  ///
  /// [data] holds a field (a `String` with dot-separated segments, or a
  /// [FieldPath]) followed by its value, then the next field and value, and
  /// so on. Use it instead of [update] when a field name contains a dot.
  ///
  /// ```dart
  /// batch.updateFromList(firestore.doc('cities/SF'), <Object?>[
  ///   'population', 870000,
  ///   FieldPath.of(<String>['stats.v2', 'visits']), FieldValue.increment(1),
  /// ]);
  /// ```
  ///
  /// The document must exist when the batch is committed. If it does not,
  /// [commit] fails with [FirestoreErrorCode.notFound] and none of the
  /// writes of the batch is applied.
  ///
  /// Throws an [ArgumentError] if [data] does not alternate fields and values
  /// or holds an invalid value, or if [documentRef] belongs to another
  /// [Firestore] instance. Throws a [StateError] if the batch was already
  /// committed.
  ///
  /// Returns this batch, so that calls can be chained.
  WriteBatch updateFromList(
    DocumentReference<Object?> documentRef,
    List<Object?> data,
  ) {
    const String methodName = 'WriteBatch.updateFromList';
    final UserDataParsedUpdateData parsedData = _firestore.dataConverter
        .parseUpdateDataFromList(
          collectUpdateArguments(1, data, methodName: methodName),
          methodName: methodName,
          targetDoc: documentRef.key,
        );

    _firestore.validateReference(documentRef);
    _verifyNotCommitted();
    _mutations.add(
      parsedData.toMutation(documentRef.key, Precondition(exists: true)),
    );
    return this;
  }

  /// Adds an update of the fields in [data] of the existing document
  /// [documentRef]. Fields that are not in [data] keep their values.
  ///
  /// The keys of [data] are field paths: a dot reaches into a nested map, so
  /// `'address.city'` changes only `city` inside `address`. The values can
  /// be [FieldValue] sentinels, for example [FieldValue.delete] to remove a
  /// field. A converter of [documentRef] is not used: [data] is always a
  /// map.
  ///
  /// ```dart
  /// batch.update(firestore.doc('cities/SF'), <String, Object?>{
  ///   'address.city': 'San Francisco',
  ///   'updatedAt': FieldValue.serverTimestamp(),
  /// });
  /// ```
  ///
  /// The document must exist when the batch is committed. If it does not,
  /// [commit] fails with [FirestoreErrorCode.notFound] and none of the
  /// writes of the batch is applied.
  ///
  /// Throws an [ArgumentError] if [data] holds an invalid field path or
  /// value, or if [documentRef] belongs to another [Firestore] instance.
  /// Throws a [StateError] if the batch was already committed.
  ///
  /// Returns this batch, so that calls can be chained.
  WriteBatch update(
    DocumentReference<Object?> documentRef,
    Map<String, Object?> data,
  ) {
    final UserDataParsedUpdateData parsedData = _firestore.dataConverter
        .parseUpdateData(
          data,
          methodName: 'WriteBatch.update',
          targetDoc: documentRef.key,
        );

    _firestore.validateReference(documentRef);
    _verifyNotCommitted();
    _mutations.add(
      parsedData.toMutation(documentRef.key, Precondition(exists: true)),
    );
    return this;
  }

  /// Adds a delete of the document [documentRef].
  ///
  /// Deleting a document that does not exist is not an error. The
  /// subcollections of the document are not deleted.
  ///
  /// ```dart
  /// batch.delete(firestore.doc('cities/SF'));
  /// ```
  ///
  /// Throws an [ArgumentError] if [documentRef] belongs to another
  /// [Firestore] instance and a [StateError] if the batch was already
  /// committed.
  ///
  /// Returns this batch, so that calls can be chained.
  WriteBatch delete(DocumentReference<Object?> documentRef) {
    _firestore.validateReference(documentRef);
    _verifyNotCommitted();
    _mutations.add(DeleteMutation(documentRef.key, Precondition.none));
    return this;
  }

  /// Commits all the writes of this batch as a single atomic unit.
  ///
  /// The writes are applied to the local cache at once: listeners see them
  /// right away, with `hasPendingWrites` set in their metadata. The returned
  /// future completes when the backend has acknowledged the batch.
  ///
  /// While the client is offline the future does not complete: the batch
  /// stays queued and is sent when the client is online again (with a
  /// persistent cache, also after the app restarts). Do not wait for the
  /// future if your app must keep going offline.
  ///
  /// If the backend rejects the batch, for example with
  /// [FirestoreErrorCode.permissionDenied] from the security rules or
  /// [FirestoreErrorCode.notFound] for an [update] of a missing document,
  /// the future fails with that [FirestoreError] and the writes are removed
  /// from the local cache again. Errors that a retry can fix (such as
  /// [FirestoreErrorCode.unavailable]) are retried by the client and are
  /// not reported.
  ///
  /// ```dart
  /// final WriteBatch batch = firestore.batch()
  ///   ..set(firestore.doc('cities/SF'), <String, Object?>{'name': 'SF'});
  /// await batch.commit();
  /// ```
  ///
  /// A batch can be committed once; afterwards every call on it throws a
  /// [StateError]. If the [Firestore] instance was terminated, the future
  /// fails with [FirestoreErrorCode.failedPrecondition]; an empty batch
  /// completes at once without any check.
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
        'A write batch can no longer be used after commit() has been called.',
      );
    }
  }
}

/// Members of [WriteBatch] for the SDK itself. Not exported by the public libraries.
extension WriteBatchInternal on WriteBatch {
  /// A new, empty batch of [firestore].
  static WriteBatch create(Firestore firestore) => WriteBatch._(firestore);
}

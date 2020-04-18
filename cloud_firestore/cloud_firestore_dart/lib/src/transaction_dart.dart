// Copyright 2017, the Chromium project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of cloud_firestore_dart_implementation;

class TransactionDart extends TransactionPlatform {
  TransactionDart(this._dartTransaction, FirestorePlatform firestore)
      : super(firestore);

  final dart.Transaction _dartTransaction;

  @override
  Future<void> delete(DocumentReferencePlatform documentReference) async {
    assert(documentReference is DocumentReferenceDart);
    final DocumentReferenceDart ref = documentReference;

    _dartTransaction.delete(ref._delegate);
  }

  @override
  Future<DocumentSnapshotPlatform> get(
    DocumentReferencePlatform documentReference,
  ) async {
    assert(documentReference is DocumentReferenceDart);
    final DocumentReferenceDart ref = documentReference;

    final dart.DocumentSnapshot dartSnapshot =
        await _dartTransaction.get(ref._delegate);
    return fromDartDocumentSnapshotToPlatformDocumentSnapshot(
        dartSnapshot, firestore);
  }

  @override
  Future<void> set(
    DocumentReferencePlatform documentReference,
    Map<String, dynamic> data,
  ) async {
    assert(documentReference is DocumentReferenceDart);
    final DocumentReferenceDart ref = documentReference;

    _dartTransaction.set(ref._delegate, CodecUtility.encodeMapData(data));
  }

  @override
  Future<void> update(
    DocumentReferencePlatform documentReference,
    Map<String, dynamic> data,
  ) async {
    assert(documentReference is DocumentReferenceDart);
    final DocumentReferenceDart ref = documentReference;

    _dartTransaction.update(ref._delegate, CodecUtility.encodeMapData(data));
  }

  @override
  Future<void> finish() {
    return Future<void>.value();
  }
}

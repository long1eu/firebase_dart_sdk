// Copyright 2017, the Chromium project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of cloud_firestore_dart_implementation;

class WriteBatchDart extends WriteBatchPlatform {
  WriteBatchDart(this._delegate);

  final dart.WriteBatch _delegate;

  @override
  Future<void> commit() async {
    await _delegate.commit();
  }

  @override
  void delete(DocumentReferencePlatform document) {
    assert(document is DocumentReferenceDart);
    final DocumentReferenceDart ref = document;
    _delegate.delete(ref._delegate);
  }

  @override
  void setData(
    DocumentReferencePlatform document,
    Map<String, dynamic> data, {
    bool merge = false,
  }) {
    assert(document is DocumentReferenceDart);
    final DocumentReferenceDart ref = document;
    _delegate.set(ref._delegate, CodecUtility.encodeMapData(data),
        merge ? dart.SetOptions.mergeAllFields : null);
  }

  @override
  void updateData(
    DocumentReferencePlatform document,
    Map<String, dynamic> data,
  ) {
    assert(document is DocumentReferenceDart);
    final DocumentReferenceDart ref = document;

    _delegate.update(ref._delegate, CodecUtility.encodeMapData(data));
  }
}

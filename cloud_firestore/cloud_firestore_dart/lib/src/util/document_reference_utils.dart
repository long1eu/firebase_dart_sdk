// Copyright 2017, the Chromium project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of cloud_firestore_dart_implementation;

/// Builds [DocumentSnapshotPlatform] instance form dart snapshot instance
DocumentSnapshotPlatform fromDartDocumentSnapshotToPlatformDocumentSnapshot(
    dart.DocumentSnapshot dartSnapshot, FirestorePlatform firestore) {
  return DocumentSnapshotPlatform(
      dartSnapshot.reference.path,
      CodecUtility.decodeMapData(dartSnapshot.data),
      SnapshotMetadataPlatform(
        dartSnapshot.metadata.hasPendingWrites,
        dartSnapshot.metadata.isFromCache,
      ),
      firestore);
}

// File created by
// Lung Razvan <long1eu>
// on 15/10/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_app_dart/internal.dart';

/// A class representing an existing document whose data is unknown (e.g. a document that was
/// updated without a known base document).
class UnknownDocument extends MaybeDocument {
  UnknownDocument(super.key, super.version);

  @override
  bool get hasPendingWrites => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnknownDocument &&
          runtimeType == other.runtimeType &&
          version == other.version &&
          key == other.key;

  @override
  int get hashCode => key.hashCode ^ version.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('key', key)
          ..add('version', version))
        .toString();
  }
}

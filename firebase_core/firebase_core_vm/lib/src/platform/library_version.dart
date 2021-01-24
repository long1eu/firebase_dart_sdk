// File created by
// Lung Razvan <long1eu>
// on 24/01/2021

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';

class LibraryVersion {
  const LibraryVersion(this.libraryName, this.version);

  final String libraryName;

  final String version;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryVersion && //
          runtimeType == other.runtimeType &&
          libraryName == other.libraryName &&
          version == other.version;

  @override
  int get hashCode => libraryName.hashCode ^ version.hashCode;

  @override
  String toString() {
    return (ToStringHelper(LibraryVersion) //
          ..add('libraryName', libraryName)
          ..add('version', version))
        .toString();
  }
}

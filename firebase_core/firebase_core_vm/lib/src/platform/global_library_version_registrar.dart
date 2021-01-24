// File created by
// Lung Razvan <long1eu>
// on 24/01/2021

import 'package:firebase_core_vm/src/platform/library_version.dart';

class GlobalLibraryVersionRegistrar {
  GlobalLibraryVersionRegistrar._([Set<LibraryVersion> infos]) : _infos = infos ?? <LibraryVersion>{};

  static final GlobalLibraryVersionRegistrar instance = GlobalLibraryVersionRegistrar._();

  final Set<LibraryVersion> _infos;

  Set<LibraryVersion> get registeredVersions => <LibraryVersion>{..._infos};

  /// Use to publish versions outside of the components mechanics.
  ///
  /// It is the responsibility of the caller to register the version at app launch.
  void registerVersion(String sdkName, String version) {
    _infos.add(LibraryVersion(sdkName, version));
  }
}

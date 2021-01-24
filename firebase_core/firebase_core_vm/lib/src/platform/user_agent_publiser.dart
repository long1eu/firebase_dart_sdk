// File created by
// Lung Razvan <long1eu>
// on 24/01/2021

import 'dart:io';

import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:firebase_core_vm/src/platform/global_library_version_registrar.dart';
import 'package:firebase_core_vm/src/platform/library_version.dart';

class UserAgentPublisher {
  UserAgentPublisher([GlobalLibraryVersionRegistrar registrar])
      : _registrar = registrar ?? GlobalLibraryVersionRegistrar.instance;

  static final UserAgentPublisher instance = UserAgentPublisher();

  final GlobalLibraryVersionRegistrar _registrar;

  String get userAgent {
    if (_registrar.registeredVersions.isEmpty) {
      if (kIsWeb) {
        return 'dart-js';
      } else {
        return Platform.version;
      }
    }

    return _registrar.registeredVersions
        .map((LibraryVersion library) => '${library.libraryName}/${library.version}')
        .join(' ');
  }
}

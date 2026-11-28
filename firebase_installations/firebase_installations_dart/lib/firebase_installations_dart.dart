/// Firebase Installations for pure Dart: installation ids (FIDs) and auth tokens on the VM and the web.
///
/// Create a [KeyValueStore], then one [FirebaseInstallations] per app. On the VM use `FileKeyValueStore`
/// from `package:firebase_installations_dart/io.dart`; on the web `IndexedDbKeyValueStore` from
/// `package:firebase_installations_dart/web.dart`.
library firebase_installations_dart;

import 'package:firebase_installations_dart/src/firebase_installations.dart';
import 'package:firebase_installations_dart/src/store/key_value_store.dart';

export 'package:firebase_installations_dart/src/exception.dart'
    show FirebaseInstallationsException, firebaseInstallationsExceptionCodes;
export 'package:firebase_installations_dart/src/firebase_installations.dart'
    show FirebaseInstallations;
export 'package:firebase_installations_dart/src/logger.dart'
    show InstallationsLogLevel, InstallationsLogger;
export 'package:firebase_installations_dart/src/store/key_value_store.dart'
    show KeyValueStore, MemoryKeyValueStore;

/// The environment on the VM: environment variables, and whether the process runs on Android.
///
/// Imported only behind `if (dart.library.io)`; `environment_stub.dart` is the default.
library;

import 'dart:io';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart'
    as transport;

/// The trimmed value of the environment variable [name], or null when it is unset or empty (SHARED
/// `environmentVariable`).
String? environmentVariable(String name) => transport.environmentVariable(name);

/// Whether the process runs on Android, where an emulator on the host is reached through
/// `10.0.2.2`.
bool get isAndroid => Platform.isAndroid;

/// Always false: this file is used only where `dart:io` exists.
bool get isWeb => false;

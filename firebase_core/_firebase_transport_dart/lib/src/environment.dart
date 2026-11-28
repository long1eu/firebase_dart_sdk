/// `environmentVariable(name)`: the trimmed value of an environment variable, or null when it is
/// unset, empty or on the web. The VM library is imported only where it exists.
///
/// The package never calls it on its own. A product reads a variable only inside its
/// `emulatorHostFromEnvironment` getter, which the application passes on explicitly.
library;

export 'package:_firebase_transport_dart/src/environment_stub.dart'
    if (dart.library.io) 'package:_firebase_transport_dart/src/environment_io.dart';

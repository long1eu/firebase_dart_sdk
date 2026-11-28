/// `dartRuntimeVersion`: the first word of `Platform.version` on the VM, `web` on the web.
/// The VM library is imported only where it exists.
library;

export 'package:_firebase_transport_dart/src/runtime_version_web.dart'
    if (dart.library.io) 'package:_firebase_transport_dart/src/runtime_version_io.dart';

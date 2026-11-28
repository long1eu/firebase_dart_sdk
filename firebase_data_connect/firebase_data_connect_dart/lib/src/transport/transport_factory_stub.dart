import 'package:firebase_data_connect_dart/src/transport/transport.dart';

/// Throws an [UnsupportedError]: a platform with neither `dart:io` nor `dart:js_interop` has no
/// transport.
OperationTransport createTransport(TransportConfig config) {
  throw UnsupportedError(
    'Data Connect needs dart:io (gRPC) or dart:js_interop (REST); this platform has neither.',
  );
}

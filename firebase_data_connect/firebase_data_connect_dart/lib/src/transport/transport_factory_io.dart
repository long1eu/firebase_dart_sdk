import 'package:firebase_data_connect_dart/src/transport/transport.dart';

/// The transport of [config] on the VM: the gRPC transport.
OperationTransport createTransport(TransportConfig config) {
  throw UnsupportedError('the gRPC transport is added in phase 3');
}

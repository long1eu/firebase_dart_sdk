import 'package:firebase_data_connect_dart/src/transport/grpc/grpc_transport.dart';
import 'package:firebase_data_connect_dart/src/transport/transport.dart';

/// The transport of the VM: gRPC (5.4).
OperationTransport createTransport(TransportConfig config) =>
    GrpcTransport(config);

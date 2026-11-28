/// `createTransport(config)`: the gRPC transport on the VM, the REST transport on the web, chosen
/// at compile time, so the web build never reaches `package:grpc` or `package:protobuf`.
library;

export 'package:firebase_data_connect_dart/src/transport/transport_factory_stub.dart'
    if (dart.library.io) 'package:firebase_data_connect_dart/src/transport/transport_factory_io.dart'
    if (dart.library.js_interop) 'package:firebase_data_connect_dart/src/transport/transport_factory_web.dart';

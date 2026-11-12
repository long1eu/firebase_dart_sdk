/// The gRPC status types the whole client uses to describe RPC failures.
///
/// `package:grpc/grpc.dart` only works where `dart:io` is available, while
/// [GrpcError] and [StatusCode] are platform neutral. Import them from here so
/// the libraries that only need the status types also compile for the web.
library;

export 'package:grpc/grpc.dart'
    if (dart.library.js_interop) 'package:grpc/grpc_web.dart'
    show GrpcError, StatusCode;

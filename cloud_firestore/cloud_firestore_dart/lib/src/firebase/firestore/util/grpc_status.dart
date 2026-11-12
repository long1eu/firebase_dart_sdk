/// The gRPC types the whole client uses to describe RPCs and their failures.
///
/// `package:grpc/grpc.dart` only works where `dart:io` is available, while
/// these types are platform neutral. Import them from here so the libraries
/// that only need them also compile for the web.
library;

export 'package:grpc/grpc.dart'
    if (dart.library.js_interop) 'package:grpc/grpc_web.dart'
    show CallOptions, GrpcError, MetadataProvider, Response, StatusCode;

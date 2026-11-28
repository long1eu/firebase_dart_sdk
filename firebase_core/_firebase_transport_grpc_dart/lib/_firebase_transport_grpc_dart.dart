/// Internal gRPC channel helpers shared by the `firebase_*_dart` packages.
///
/// **Not for application code.** This library is shared by the packages of this repository. It
/// follows pub's version rules: a change that can break a dependent's compile or behaviour bumps
/// the second number, an addition bumps the third. A product does not expose a type of this
/// library in its public API.
///
/// VM only: it imports `dart:io`. A product imports it only behind `if (dart.library.io)`.
library;

export 'package:_firebase_transport_grpc_dart/src/grpc_caller.dart'
    show GrpcCaller, RpcMethod, rpcStatusOfGrpcError;
export 'package:_firebase_transport_grpc_dart/src/grpc_channel.dart'
    show createGrpcChannel, defaultFlowControlWindow;
export 'package:_firebase_transport_grpc_dart/src/grpc_target.dart'
    show GrpcTarget;
export 'package:_firebase_transport_grpc_dart/src/inbound_limit.dart'
    show InboundLimitExceeded;
export 'package:_firebase_transport_grpc_dart/src/version.dart'
    show grpcVersion;

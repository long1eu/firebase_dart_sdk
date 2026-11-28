import 'dart:io';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:_firebase_transport_grpc_dart/_firebase_transport_grpc_dart.dart';
import 'package:firebase_data_connect_dart/src/errors.dart';
import 'package:firebase_data_connect_dart/src/proto/google/protobuf/index.dart'
    as pb;
import 'package:firebase_data_connect_dart/src/proto/index.dart' as pb;
import 'package:firebase_data_connect_dart/src/transport/grpc/response_parser.dart';
import 'package:firebase_data_connect_dart/src/transport/grpc/struct_codec.dart';
import 'package:firebase_data_connect_dart/src/transport/transport.dart';
import 'package:grpc/grpc.dart';
import 'package:meta/meta.dart';
import 'package:protobuf/protobuf.dart';

const RpcMethod<pb.ExecuteQueryRequest, pb.ExecuteQueryResponse> _executeQuery =
    RpcMethod<pb.ExecuteQueryRequest, pb.ExecuteQueryResponse>(
      '/google.firebase.dataconnect.v1.ConnectorService/ExecuteQuery',
      pb.ExecuteQueryResponse.new,
      decode: parseExecuteQueryResponse,
    );

const RpcMethod<pb.ExecuteMutationRequest, pb.ExecuteMutationResponse>
_executeMutation =
    RpcMethod<pb.ExecuteMutationRequest, pb.ExecuteMutationResponse>(
      '/google.firebase.dataconnect.v1.ConnectorService/ExecuteMutation',
      pb.ExecuteMutationResponse.new,
      decode: parseExecuteMutationResponse,
    );

/// The transport of the VM: unary gRPC calls of `ConnectorService` (5.4).
final class GrpcTransport implements OperationTransport {
  /// A transport for the target of `config`, on a [GrpcCaller] it creates, or on [caller] in tests.
  ///
  /// The channel connects to `config.host` and `config.port`, over TLS when `config.secure`, and
  /// limits every response message to 16 MiB.
  GrpcTransport(this._config, {@visibleForTesting GrpcCaller? caller})
    : _caller =
          caller ??
          GrpcCaller(
            GrpcTarget(
              host: _config.host,
              port: _config.port,
              secure: _config.secure,
            ),
            maxInboundMessageBytes: maxResponseBytes,
          );

  final TransportConfig _config;
  final GrpcCaller _caller;
  bool _closed = false;

  /// The origin of the channel's target, for every kind.
  @override
  Uri tokenUrl(OperationKind kind) => _caller.target.origin;

  @override
  Future<WireResult> execute(
    OperationKind kind,
    String operationName,
    Map<String, Object?>? variables,
    RequestTokens tokens, {
    required Duration timeout,
  }) async {
    if (_closed) {
      return WireFailure(RpcStatus.cancelled);
    }
    final Map<String, String> headers = _headers();
    final pb.Struct? encoded = variables == null
        ? null
        : encodeStruct(variables);
    final ResponseStream<GeneratedMessage> call = switch (kind) {
      OperationKind.query => _caller.startCall(
        _executeQuery,
        Stream<pb.ExecuteQueryRequest>.value(
          pb.ExecuteQueryRequest(
            name: _config.connectorResourceName,
            operationName: operationName,
            variables: encoded,
          ),
        ),
        tokens: tokens,
        auth: AuthHeaderStyle.firebaseAuthToken,
        headers: headers,
        timeout: timeout,
      ),
      OperationKind.mutation => _caller.startCall(
        _executeMutation,
        Stream<pb.ExecuteMutationRequest>.value(
          pb.ExecuteMutationRequest(
            name: _config.connectorResourceName,
            operationName: operationName,
            variables: encoded,
          ),
        ),
        tokens: tokens,
        auth: AuthHeaderStyle.firebaseAuthToken,
        headers: headers,
        timeout: timeout,
      ),
    };
    return _receive(call);
  }

  /// The metadata of rule 4, in its order; the token headers are added by [GrpcCaller].
  ///
  /// Throws the [StateError] or [ArgumentError] of [TransportConfig.checkedAppId] (5.6 rule 6).
  Map<String, String> _headers() {
    return <String, String>{
      'x-goog-request-params': 'location=${_config.location}&frontend=data',
      'x-firebase-sqlconnect-affinity':
          '${_config.projectId}${_config.serviceId}',
      'x-goog-api-client': _config.apiClient(
        extra: <String>['grpc/$grpcVersion'],
      ),
      'x-client-version': _config.clientVersion,
      'x-firebase-gmpid': _config.checkedAppId(),
    };
  }

  /// Waits for the one response of [call] and turns it, or the failure, into a [WireResult].
  Future<WireResult> _receive(ResponseStream<GeneratedMessage> call) async {
    try {
      GeneratedMessage? response;
      await for (final GeneratedMessage message in call) {
        if (response != null) {
          return WireFailure(RpcStatus.internal);
        }
        response = message;
      }
      if (response == null) {
        return WireFailure(RpcStatus.internal);
      }
      return _toWire(response);
    } on InboundLimitExceeded {
      return WireFailure(RpcStatus.internal, invalidResponse: true);
    } on GrpcError catch (error) {
      return _failureOf(error);
    } on IOException {
      return WireFailure(_closed ? RpcStatus.cancelled : RpcStatus.unavailable);
    }
  }

  WireResult _toWire(GeneratedMessage response) {
    if (response is pb.ExecuteQueryResponse) {
      return _decode(
        response.hasData() ? response.data : null,
        response.errors,
      );
    }
    if (response is pb.ExecuteMutationResponse) {
      return _decode(
        response.hasData() ? response.data : null,
        response.errors,
      );
    }
    return WireFailure(RpcStatus.internal);
  }

  /// Decodes a response's [data] and [errors]; a value the rules of 5.7 refuse is
  /// `invalid-response`.
  WireResult _decode(pb.Struct? data, List<pb.GraphqlError> errors) {
    try {
      return WireResponse(
        data: data == null ? null : decodeStruct(data),
        errors: <GraphqlError>[
          for (final pb.GraphqlError error in errors) decodeGraphqlError(error),
        ],
      );
    } on FormatException {
      return WireFailure(RpcStatus.internal, invalidResponse: true);
    }
  }

  /// Rule 5: a status the server sent keeps its sanitized message; a failure `package:grpc` made
  /// itself (connection, deadline, cancel) keeps nothing of its text, which can name the host.
  WireFailure _failureOf(GrpcError error) {
    if (_closed) {
      return WireFailure(RpcStatus.cancelled);
    }
    if (isParseFailure(error)) {
      return WireFailure(RpcStatus.internal, invalidResponse: true);
    }
    final bool fromServer = error.trailers?.isNotEmpty ?? false;
    final String? message = error.message;
    return WireFailure(
      rpcStatusOfGrpcError(error),
      serverMessage: fromServer && message != null
          ? sanitizeServerText(message)
          : null,
    );
  }

  /// Shuts the channel down; calls in flight end `cancelled`.
  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _caller.shutdown();
  }
}

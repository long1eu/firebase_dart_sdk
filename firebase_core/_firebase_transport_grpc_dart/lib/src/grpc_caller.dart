import 'dart:async';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:_firebase_transport_grpc_dart/src/grpc_channel.dart';
import 'package:_firebase_transport_grpc_dart/src/grpc_target.dart';
import 'package:_firebase_transport_grpc_dart/src/inbound_limit.dart';
import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_connection_interface.dart' show ClientChannelBase;
import 'package:meta/meta.dart';
import 'package:protobuf/protobuf.dart';

/// One gRPC method: its path and how its response messages are read.
final class RpcMethod<
  Req extends GeneratedMessage,
  Res extends GeneratedMessage
> {
  /// The method at [path], whose responses are [newResponse] messages.
  const RpcMethod(this.path, this.newResponse, {this.decode});

  /// `/package.Service/Method`; also the key under which [GrpcCaller] keeps the method.
  final String path;

  /// Creates an empty response message; the default reading merges the bytes into it.
  final Res Function() newResponse;

  /// Turns the bytes of one response message into a response. Null means
  /// `newResponse()..mergeFromBuffer(bytes)`.
  final Res Function(List<int> bytes)? decode;
}

/// The names [GrpcCaller.startCall] refuses in its `headers`: these come only from the tokens.
const Set<String> _tokenHeaderNames = <String>{
  'authorization',
  'x-firebase-auth-token',
  'x-firebase-appcheck',
};

final RegExp _metadataName = RegExp(r'^[a-z0-9][a-z0-9_.-]*$');

/// Starts gRPC calls on one channel, with the tokens of each call as its metadata.
final class GrpcCaller {
  /// Creates the channel for [target] with [createGrpcChannel] and its defaults, or uses
  /// [channel] in tests.
  ///
  /// [maxInboundMessageBytes] is the largest response message a call may receive (see
  /// [InboundLimitExceeded]); it applies to a channel this caller creates.
  GrpcCaller(
    this.target, {
    required int maxInboundMessageBytes,
    @visibleForTesting ClientChannelBase? channel,
  }) : _channel =
           channel ??
           createGrpcChannel(
             target,
             maxInboundMessageBytes: maxInboundMessageBytes,
           );

  /// Where the channel connects; the token headers of every call are checked against its
  /// [GrpcTarget.origin].
  final GrpcTarget target;

  final ClientChannelBase _channel;
  late final Client _client = Client(_channel);
  final Map<String, ClientMethod<dynamic, dynamic>> _methods =
      <String, ClientMethod<dynamic, dynamic>>{};

  /// Starts a call of [method] that sends [requests].
  ///
  /// The metadata is `tokens.headersFor(target.origin, auth: auth)` plus [headers], all names in
  /// lowercase; so tokens fetched for another origin, or used before, throw a [StateError] and
  /// nothing is sent. Throws an [ArgumentError] for a name or value of [headers] that the rules
  /// refuse, before the tokens are used: a name, after lowercasing, must match
  /// `^[a-z0-9][a-z0-9_.-]*$`, must not start with `grpc-` and must not be `authorization`,
  /// `x-firebase-auth-token` or `x-firebase-appcheck`; a value must pass [isHeaderValue]. The
  /// error names the header and never the value.
  ///
  /// The returned stream is `package:grpc`'s [ResponseStream]. [timeout] is the call's deadline.
  /// When a response message is longer than the channel's limit, the stream ends with an
  /// [InboundLimitExceeded] as its error.
  ResponseStream<Res>
  startCall<Req extends GeneratedMessage, Res extends GeneratedMessage>(
    RpcMethod<Req, Res> method,
    Stream<Req> requests, {
    required RequestTokens tokens,
    required AuthHeaderStyle auth,
    Map<String, String> headers = const <String, String>{},
    required Duration timeout,
  }) {
    final Map<String, String> extra = _checkedHeaders(headers);
    final Map<String, String> metadata = <String, String>{};
    tokens.headersFor(target.origin, auth: auth).forEach((
      String name,
      String value,
    ) {
      metadata[name.toLowerCase()] = value;
    });
    metadata.addAll(extra);
    final ClientMethod<Req, Res> clientMethod = _methodFor(method);
    final ResponseStream<Res> call = _client.$createStreamingCall(
      clientMethod,
      requests,
      options: CallOptions(metadata: metadata, timeout: timeout),
    );
    return ResponseStream<Res>(_InboundLimitCall<Req, Res>(clientMethod, call));
  }

  /// Terminates the channel.
  Future<void> shutdown() => _channel.terminate();

  ClientMethod<Req, Res> _methodFor<
    Req extends GeneratedMessage,
    Res extends GeneratedMessage
  >(RpcMethod<Req, Res> method) {
    final ClientMethod<dynamic, dynamic> cached = _methods[method.path] ??=
        ClientMethod<Req, Res>(
          method.path,
          (Req request) => request.writeToBuffer(),
          method.decode ??
              (List<int> bytes) => method.newResponse()..mergeFromBuffer(bytes),
        );
    return cached as ClientMethod<Req, Res>;
  }

  static Map<String, String> _checkedHeaders(Map<String, String> headers) {
    final Map<String, String> checked = <String, String>{};
    headers.forEach((String name, String value) {
      final String lowercase = name.toLowerCase();
      if (!_metadataName.hasMatch(lowercase) ||
          lowercase.startsWith('grpc-') ||
          _tokenHeaderNames.contains(lowercase)) {
        throw ArgumentError('the header name "$lowercase" is not allowed');
      }
      if (!isHeaderValue(value)) {
        throw ArgumentError(
          'the value of header "$lowercase" is not a header value',
        );
      }
      checked[lowercase] = value;
    });
    return checked;
  }
}

/// The status of [error]: `RpcStatus.fromCode(error.code)`.
RpcStatus rpcStatusOfGrpcError(GrpcError error) =>
    RpcStatus.fromCode(error.code);

/// The call of one [GrpcCaller.startCall]: `package:grpc`'s call, whose response stream ends with
/// the [InboundLimitExceeded] itself where `package:grpc` reports the [GrpcError] that carries it
/// (see [InboundLimitStream]).
final class _InboundLimitCall<Q, R> extends ClientCall<Q, R> {
  _InboundLimitCall(ClientMethod<Q, R> method, this._inner)
    : super(method, Stream<Q>.empty(), CallOptions());

  final ResponseStream<R> _inner;

  @override
  late final Stream<R> response = _inner.transform(
    StreamTransformer<R, R>.fromHandlers(handleError: _unwrap),
  );

  void _unwrap(Object error, StackTrace stackTrace, EventSink<R> sink) {
    final Object? raw = error is GrpcError ? error.rawResponse : null;
    if (raw is InboundLimitExceeded) {
      sink.addError(raw, stackTrace);
      return;
    }
    sink.addError(error, stackTrace);
  }

  @override
  Future<Map<String, String>> get headers => _inner.headers;

  @override
  Future<Map<String, String>> get trailers => _inner.trailers;

  @override
  Future<void> cancel() => _inner.cancel();
}

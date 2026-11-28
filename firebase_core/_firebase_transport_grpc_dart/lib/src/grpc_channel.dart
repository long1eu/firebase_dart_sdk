// Derived from cloud_firestore/cloud_firestore_dart/lib/src/firebase/firestore/remote/datastore/
// grpc_channel.dart at commit b73a298d: the channel factory, with a GrpcTarget, its own window
// default, the connect timeout as an argument, and the inbound message limit. The keepalive
// defaults are Firestore's. A fix to one copy must be made in the other.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:_firebase_transport_grpc_dart/src/grpc_target.dart';
import 'package:_firebase_transport_grpc_dart/src/inbound_limit.dart';
import 'package:_firebase_transport_grpc_dart/src/keep_alive_transport.dart';
import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_connection_interface.dart' show ClientChannelBase;

/// The HTTP/2 flow-control window of a channel, for the connection and for each call: 256 KiB, the
/// `grpcFlowControlWindow` of the Android and JS SDKs.
const int defaultFlowControlWindow = 262144;

/// Creates a gRPC channel to [target], with keepalive pings, a limit on the size of each response
/// message, and an HTTP/2 flow-control window of [flowControlWindow] bytes.
///
/// - [maxInboundMessageBytes]: the largest response message a call may receive. A larger one ends
///   the call before anything of it is allocated (see [InboundLimitExceeded]). Must be positive.
/// - [connectTimeout]: how long one connection attempt may take.
/// - [keepAlivePingInterval]: how often a ping is sent while there are active calls.
/// - [keepAliveTimeout]: how long to wait for any frame after a ping before the connection is
///   terminated.
///
/// The defaults are those of Firestore's channel. No codec registry is set, so a compressed
/// response message is refused by `package:grpc`.
///
/// Throws an [ArgumentError] when [maxInboundMessageBytes] or [flowControlWindow] is not positive,
/// or when [flowControlWindow] is above 2^31 - 1.
ClientChannelBase createGrpcChannel(
  GrpcTarget target, {
  required int maxInboundMessageBytes,
  Duration connectTimeout = const Duration(seconds: 15),
  Duration keepAlivePingInterval = const Duration(seconds: 30),
  Duration keepAliveTimeout = const Duration(seconds: 20),
  int flowControlWindow = defaultFlowControlWindow,
}) {
  if (maxInboundMessageBytes < 1) {
    throw ArgumentError.value(
      maxInboundMessageBytes,
      'maxInboundMessageBytes',
      'must be positive',
    );
  }
  if (flowControlWindow < 1 || flowControlWindow > 0x7fffffff) {
    throw ArgumentError.value(
      flowControlWindow,
      'flowControlWindow',
      'must be 1 to 2^31 - 1',
    );
  }
  final ChannelOptions options = ChannelOptions(
    credentials: target.secure
        ? const ChannelCredentials.secure()
        : const ChannelCredentials.insecure(),
    connectTimeout: connectTimeout,
  );
  return ClientTransportConnectorChannel(
    KeepAliveTransportConnector(
      host: target.host,
      port: target.port,
      credentials: options.credentials,
      pingInterval: keepAlivePingInterval,
      pingTimeout: keepAliveTimeout,
      maxInboundMessageBytes: maxInboundMessageBytes,
      connectTimeout: connectTimeout,
      flowControlWindow: flowControlWindow,
    ),
    options: options,
  );
}

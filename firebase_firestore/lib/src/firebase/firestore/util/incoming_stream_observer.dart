// File created by
// Lung Razvan <long1eu>
// on 24/09/2018

import 'dart:async';

import 'package:grpc/grpc.dart';

/// Interface used for incoming/receiving gRPC streams.
abstract class IncomingStreamObserver<RespT> {
  /// Headers were received for this stream.
  void onHeaders(Map<String, String> headers);

  /// A message was received on the stream.
  Future<void> onNext(RespT response);

  /// The stream is 'ready' (What the hell does that mean?!).
  void onReady();

  /// The stream has closed. Status.isOk() is false if there an error occurred.
  void onClose(GrpcError status);
}

import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:http2/transport.dart';

/// A response message announced more bytes than the limit. The call's response stream ends with
/// this error.
///
/// Holds two numbers and no message bytes.
final class InboundLimitExceeded implements Exception {
  /// A message of [announced] bytes, refused under a limit of [limit] bytes.
  const InboundLimitExceeded({required this.limit, required this.announced});

  /// The limit: the `maxInboundMessageBytes` of the channel.
  final int limit;

  /// The length the message's 5-byte prefix announced.
  final int announced;

  /// `InboundLimitExceeded: a message of <announced> bytes exceeds the limit of <limit> bytes`.
  @override
  String toString() =>
      'InboundLimitExceeded: a message of $announced bytes exceeds the limit of $limit bytes';
}

/// The length of the prefix of a gRPC message: one flag byte and four length bytes.
const int _prefixLength = 5;

/// Decorates the HTTP/2 stream of one call so that no response message longer than
/// [maxInboundMessageBytes] reaches `package:grpc`.
///
/// `package:grpc` allocates a buffer of the length a message announces in its prefix before it
/// checks anything, so a peer could make the client allocate up to 4 GiB. This stream follows the
/// gRPC framing of the incoming data (one flag byte, four length bytes, then the message, possibly
/// across frames). When a prefix announces more than the limit, it terminates the HTTP/2 stream
/// before it hands that frame on, records [exceeded], and ends [incomingMessages] with a
/// [GrpcError] whose code is `RESOURCE_EXHAUSTED` and whose `rawResponse` is the
/// [InboundLimitExceeded]; `package:grpc` passes a [GrpcError] from the stream to the call
/// unchanged.
final class InboundLimitStream implements ClientTransportStream {
  /// Limits the response messages of the stream `inner` to [maxInboundMessageBytes] bytes each.
  InboundLimitStream(
    ClientTransportStream inner, {
    required this.maxInboundMessageBytes,
  }) : _inner = inner;

  final ClientTransportStream _inner;

  /// The largest message, in bytes, that is let through.
  final int maxInboundMessageBytes;

  /// The refused message, or null while every message was within the limit.
  InboundLimitExceeded? get exceeded => _exceeded;
  InboundLimitExceeded? _exceeded;

  /// The bytes of the current prefix read so far, 0 to 4.
  int _prefixRead = 0;

  /// The length the current prefix announces, from the bytes read so far.
  int _announced = 0;

  /// The bytes of the current message still to come.
  int _remaining = 0;

  @override
  late final Stream<StreamMessage> incomingMessages = _limited();

  Stream<StreamMessage> _limited() {
    final StreamController<StreamMessage> output =
        StreamController<StreamMessage>(sync: true);
    StreamSubscription<StreamMessage>? input;
    output
      ..onListen = () {
        input = _inner.incomingMessages.listen(
          (StreamMessage message) => _forward(message, output, input!),
          onError: output.addError,
          onDone: output.close,
        );
      }
      ..onPause = () {
        input?.pause();
      }
      ..onResume = () {
        input?.resume();
      }
      ..onCancel = () => input?.cancel();
    return output.stream;
  }

  void _forward(
    StreamMessage message,
    StreamController<StreamMessage> output,
    StreamSubscription<StreamMessage> input,
  ) {
    if (_exceeded != null) {
      return;
    }
    if (message is DataStreamMessage) {
      final InboundLimitExceeded? refused = _scan(message.bytes);
      if (refused != null) {
        _refuse(refused, output, input);
        return;
      }
    }
    output.add(message);
  }

  /// Follows the framing through [bytes]; returns the first prefix over the limit, if any.
  InboundLimitExceeded? _scan(List<int> bytes) {
    int offset = 0;
    while (offset < bytes.length) {
      if (_remaining > 0) {
        final int available = bytes.length - offset;
        final int skipped = _remaining < available ? _remaining : available;
        _remaining -= skipped;
        offset += skipped;
        continue;
      }
      final int byte = bytes[offset] & 0xff;
      offset++;
      if (_prefixRead > 0) {
        _announced = (_announced << 8) | byte;
      }
      _prefixRead++;
      if (_prefixRead == _prefixLength) {
        final int announced = _announced;
        _prefixRead = 0;
        _announced = 0;
        if (announced > maxInboundMessageBytes) {
          return InboundLimitExceeded(
            limit: maxInboundMessageBytes,
            announced: announced,
          );
        }
        _remaining = announced;
      }
    }
    return null;
  }

  void _refuse(
    InboundLimitExceeded refused,
    StreamController<StreamMessage> output,
    StreamSubscription<StreamMessage> input,
  ) {
    _exceeded = refused;
    unawaited(input.cancel());
    _inner.terminate();
    output
      ..addError(GrpcError.resourceExhausted(refused.toString(), null, refused))
      ..close();
  }

  @override
  int get id => _inner.id;

  @override
  StreamSink<StreamMessage> get outgoingMessages => _inner.outgoingMessages;

  @override
  Stream<TransportStreamPush> get peerPushes => _inner.peerPushes;

  @override
  set onTerminated(void Function(int?) value) => _inner.onTerminated = value;

  @override
  void terminate() => _inner.terminate();

  @override
  void sendHeaders(List<Header> headers, {bool endStream = false}) =>
      _inner.sendHeaders(headers, endStream: endStream);

  @override
  void sendData(List<int> bytes, {bool endStream = false}) =>
      _inner.sendData(bytes, endStream: endStream);
}

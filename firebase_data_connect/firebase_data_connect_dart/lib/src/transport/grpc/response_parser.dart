import 'package:firebase_data_connect_dart/src/proto/index.dart' as pb;
import 'package:firebase_data_connect_dart/src/transport/transport.dart'
    show maxResponseBytes;
import 'package:grpc/grpc.dart';
import 'package:protobuf/protobuf.dart';

/// The recursion limit of the protobuf reader (5.4 rule 3).
///
/// Only nested message reads count toward it, and data depth d costs about 2d + 1, so depth 100
/// needs about 201; protobuf's default of 100 would stop at about depth 49. 310 leaves a margin of
/// 109. Depth 101 is refused by the struct decoder, not here.
const int protobufRecursionLimit = 310;

/// Reads one `ExecuteQueryResponse` message: the `RpcMethod.decode` of `ExecuteQuery`.
///
/// Throws a [FormatException] for more than [maxResponseBytes] bytes, and the protobuf exception
/// for bytes that do not parse (see [isParseFailure]).
pb.ExecuteQueryResponse parseExecuteQueryResponse(List<int> bytes) =>
    _parse(bytes, pb.ExecuteQueryResponse());

/// Reads one `ExecuteMutationResponse` message: the `RpcMethod.decode` of `ExecuteMutation`.
///
/// Throws as [parseExecuteQueryResponse] does.
pb.ExecuteMutationResponse parseExecuteMutationResponse(List<int> bytes) =>
    _parse(bytes, pb.ExecuteMutationResponse());

T _parse<T extends GeneratedMessage>(List<int> bytes, T message) {
  if (bytes.length > maxResponseBytes) {
    throw const FormatException('the response message is over 16 MiB');
  }
  final CodedBufferReader reader = CodedBufferReader(
    bytes,
    recursionLimit: protobufRecursionLimit,
  );
  message.mergeFromCodedBufferReader(reader);
  reader.checkLastTagWas(0);
  return message;
}

/// Whether [error] is how `package:grpc` reports that a parser of this file threw.
///
/// `package:grpc` 5.2.0 replaces whatever the response deserializer throws with
/// `GrpcError.dataLoss('Error parsing response')` (`lib/src/client/call.dart`,
/// `ClientCall._onResponseData`), without trailers. A status the server sends always carries
/// trailers, so a server's `DATA_LOSS` is not mistaken for it.
bool isParseFailure(GrpcError error) =>
    error.code == StatusCode.dataLoss &&
    error.message == 'Error parsing response' &&
    (error.trailers?.isEmpty ?? true);

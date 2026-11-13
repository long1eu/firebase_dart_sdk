import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart';

/// A call the fake transport received.
class RecordedCall {
  RecordedCall(this.rpc, this.request);

  final String rpc;
  final GeneratedMessage request;
}

/// A [FirestoreTransport] that records the calls and answers them from the
/// functions the test sets. Without a function, a call gets the empty answer
/// of a backend with no documents.
class FakeLiteTransport implements FirestoreTransport {
  FakeLiteTransport(this.databaseInfo, this.options);

  final DatabaseInfo databaseInfo;
  final ChannelOptionsProvider options;

  final List<RecordedCall> calls = <RecordedCall>[];

  /// The answer to each RPC, by name: a list of responses, or a thrown
  /// [GrpcError].
  final Map<String, FutureOr<List<GeneratedMessage>> Function(GeneratedMessage)>
  handlers =
      <String, FutureOr<List<GeneratedMessage>> Function(GeneratedMessage)>{};

  bool isShutDown = false;

  String get database =>
      'projects/${databaseInfo.databaseId.projectId}'
      '/databases/${databaseInfo.databaseId.databaseId}';

  /// The requests of the calls to [rpc].
  List<T> requests<T extends GeneratedMessage>(String rpc) => <T>[
    for (final RecordedCall call in calls)
      if (call.rpc == rpc) call.request as T,
  ];

  /// The headers a call is sent with.
  Future<Map<String, String>> headers() async {
    final Map<String, String> headers = <String, String>{};
    for (final MetadataProvider provider
        in options.callOptions.metadataProviders) {
      await provider(headers, 'https://example.test');
    }
    return headers;
  }

  @override
  ResponseStream<Res> startCall<
    Req extends GeneratedMessage,
    Res extends GeneratedMessage
  >(FirestoreRpc<Req, Res> rpc, Stream<Req> requests, {CallOptions? options}) {
    final StreamController<Res> responses = StreamController<Res>();
    unawaited(() async {
      try {
        if (isShutDown) {
          throw const GrpcError.unavailable('The transport is shut down');
        }
        final Req request = await requests.first;
        calls.add(RecordedCall(rpc.name, request));
        final FutureOr<List<GeneratedMessage>> Function(GeneratedMessage)
        handler = handlers[rpc.name] ?? _defaultAnswer;
        for (final GeneratedMessage response in await handler(request)) {
          responses.add(response as Res);
        }
      } catch (e, s) {
        responses.addError(e, s);
      } finally {
        unawaited(responses.close());
      }
    }());
    return ResponseStream<Res>(_FakeResponse(), responses.stream);
  }

  List<GeneratedMessage> _defaultAnswer(GeneratedMessage request) {
    if (request is proto.BatchGetDocumentsRequest) {
      return <GeneratedMessage>[
        for (final String name in request.documents)
          proto.BatchGetDocumentsResponse()
            ..missing = name
            ..readTime = (proto.Timestamp()..seconds = Int64(1)),
      ];
    } else if (request is proto.CommitRequest) {
      return <GeneratedMessage>[
        proto.CommitResponse()
          ..commitTime = (proto.Timestamp()..seconds = Int64(2))
          ..writeResults.addAll(<proto.WriteResult>[
            for (final proto.Write _ in request.writes) proto.WriteResult(),
          ]),
      ];
    }
    if (request is proto.BeginTransactionRequest) {
      return <GeneratedMessage>[
        proto.BeginTransactionResponse()..transaction = <int>[1, 2, 3],
      ];
    } else if (request is proto.RollbackRequest) {
      return <GeneratedMessage>[proto.Empty()];
    }
    return <GeneratedMessage>[];
  }

  @override
  Future<void> shutdown() async {
    isShutDown = true;
  }
}

class _FakeResponse implements Response {
  @override
  Future<void> cancel() async {}

  @override
  Future<Map<String, String>> get headers async => const <String, String>{};

  @override
  Future<Map<String, String>> get trailers async => const <String, String>{};
}

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:firebase_app_dart/internal.dart';
import 'package:grpc/grpc.dart' hide ResponseStream;
import 'package:test/test.dart';

import 'unused_transport.dart';

// ignore_for_file: close_sinks

class _HeaderResponse implements Response {
  @override
  Future<Map<String, String>> get headers async => <String, String>{
    'Date': 'Fri, 13 Nov 2026 10:00:00 GMT',
    'x-google-service': 'firestore',
    'authorization': 'Bearer secret-token',
    'set-cookie': 'session=secret',
  };

  @override
  Future<Map<String, String>> get trailers async => <String, String>{};

  @override
  Future<void> cancel() async {}
}

class _Client extends FirestoreClient {
  _Client()
    : super(
        UnusedTransport(),
        ChannelOptionsProvider(
          databaseId: DatabaseId.forProject('p'),
          credentialsProvider: EmptyCredentialsProvider(),
        ),
      );

  final StreamController<proto.ListenResponse> responses =
      StreamController<proto.ListenResponse>();

  @override
  Future<ResponseStream<proto.ListenResponse>> listen(
    Stream<proto.ListenRequest> request,
  ) async {
    request.listen((_) {});
    return ResponseStream<proto.ListenResponse>(
      _HeaderResponse(),
      responses.stream,
    );
  }
}

/// Opens a watch stream with the log at [level] and returns what was printed.
Future<List<String>> _openWithLogLevel(InternalLogLevel level) async {
  final InternalLogLevel original = Log.level;
  final List<String> printed = <String>[];
  final _Client client = _Client();
  final WatchStream stream = WatchStream(
    client: client,
    scheduler: TaskScheduler('headers'),
    serializer: RemoteSerializer(DatabaseId.forProject('p')),
  );
  try {
    Log.level = level;
    await runZoned(
      () async {
        stream.listen((_) {});
        await stream.start();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await stream.stop();
      },
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
            printed.add(line),
      ),
    );
  } finally {
    Log.level = original;
    await client.responses.close();
  }
  return printed;
}

void main() {
  test('debug logging shows only the allow-listed response headers', () async {
    final List<String> printed = await _openWithLogLevel(InternalLogLevel.d);
    final String headersLine = printed.singleWhere(
      (String l) => l.contains('received headers'),
    );
    expect(headersLine, contains('Date'));
    expect(headersLine, contains('x-google-service'));
    expect(headersLine, isNot(contains('secret')));
    expect(Datastore.whiteListedHeaders, contains('date'));
  });

  test('headers are not logged without debug logging', () async {
    final List<String> printed = await _openWithLogLevel(InternalLogLevel.w);
    expect(printed.where((String l) => l.contains('headers')), isEmpty);
  });
}

// Regression tests for the problems found by web_transport_fuzz_test.dart.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_channel.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:test/test.dart';

import '../firebase/firestore/remote/web/fake_http_client.dart';

const String database = 'projects/p/databases/(default)';

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late FakeHttpClient http;
  late WebChannelStream stream;
  late List<Object> errors;

  setUp(() {
    http = FakeHttpClient();
    stream = WebChannelStream(
      http,
      'http://127.0.0.1:8080/google.firestore.v1.Firestore/Listen/channel',
      database,
      const <String, String>{},
      random: Random(1),
    );
    errors = <Object>[];
    stream.messages.listen((_) {}, onError: errors.add);
  });

  tearDown(() async {
    final Future<void> closing = stream.close();
    await pump();
    while (http.hasUnclaimed) {
      final FakeRequest request = await http.next();
      if (!request.aborted) {
        request.respond(200);
      }
    }
    await closing;
  });

  Future<void> handshake(List<Object?> open) async {
    stream.send('{"addTarget":{}}');
    final String json = jsonEncode(<Object?>[
      <Object?>[0, open],
    ]);
    (await http.next()).respond(200, body: '${json.length}\n$json');
    await pump();
  }

  test(
    'a huge back channel timeout hint does not abort the back channel',
    () async {
      // 1.5 times the hint overflowed the Duration: the timer of every back
      // channel request fired at once and aborted it.
      await handshake(<Object?>['c', 'sid', '', 8, 12, 9223372036854775807]);
      final FakeRequest back = await http.next();
      expect(back.query['RID'], 'rpc');
      expect(back.aborted, isFalse);
      expect(errors, isEmpty);
    },
  );

  test(
    'a session id that is not a string fails the handshake cleanly',
    () async {
      await handshake(<Object?>['c', 5, '', 8, 12, 30000]);
      expect(errors, hasLength(1));
      expect(
        errors.single,
        isA<GrpcError>()
            .having((GrpcError e) => e.code, 'code', StatusCode.unavailable)
            .having(
              (GrpcError e) => e.message,
              'message',
              'The handshake response has no session id',
            ),
      );
    },
  );
}

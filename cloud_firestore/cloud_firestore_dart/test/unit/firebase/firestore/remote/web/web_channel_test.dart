// Replays WebChannel exchanges that were recorded with curl against the
// Firestore emulator (cloud-firestore-emulator v1.22.0) and, for the error
// envelope, against firestore.googleapis.com.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_channel.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:test/test.dart';

import 'fake_http_client.dart';

const String database = 'projects/demo-test/databases/(default)';
const String channelUrl =
    'http://127.0.0.1:8080/google.firestore.v1.Firestore/Listen/channel';

// Recorded: the handshake response of the emulator.
const String handshakeResponse =
    '52\n[[0,["c","1PNQXW59l6IN56OhGqCYrQ==","",8,12,30000]]]';
const String sessionId = '1PNQXW59l6IN56OhGqCYrQ==';

// Recorded: the first back channel chunk for a document target.
const String listenChunk =
    '[[1,[{"targetChange":{"targetChangeType":"ADD","targetIds":[2]}}]],'
    '[2,[{"documentChange":{"document":{"name":"projects/demo-test/databases/(default)/documents/webprobe/doc1","fields":{"a":{"integerValue":"1"}},"createTime":"2026-11-12T21:14:21.909894Z","updateTime":"2026-11-12T21:14:21.909894Z"},"targetIds":[2]}}]],'
    '[3,[{"targetChange":{"targetChangeType":"CURRENT","targetIds":[2],"resumeToken":"CgkI24iE3ayDmAM=","readTime":"2026-11-12T21:14:22.007387Z"}}]],'
    '[4,[{"targetChange":{"resumeToken":"CgkI24iE3ayDmAM=","readTime":"2026-11-12T21:14:22.007387Z"}}]]]';

const String addTarget =
    '{"database":"projects/demo-test/databases/(default)","addTarget":{"documents":{"documents":["projects/demo-test/databases/(default)/documents/webprobe/doc1"]},"targetId":2}}';

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('WebChannelChunkParser', () {
    test('splits the recorded chunks, also when they arrive in pieces', () {
      final WebChannelChunkParser parser = WebChannelChunkParser();
      const String body = '${handshakeResponse}14\n[[5,["noop"]]]';

      final List<Object?> chunks = <Object?>[];
      for (int i = 0; i < body.length; i += 7) {
        chunks.addAll(parser.add(body.substring(i, min(i + 7, body.length))));
      }

      expect(chunks, <Object?>[
        <Object?>[
          <Object?>[
            0,
            <Object?>['c', sessionId, '', 8, 12, 30000]
          ]
        ],
        <Object?>[
          <Object?>[
            5,
            <Object?>['noop']
          ]
        ],
      ]);
      expect(parser.hasPartialChunk, isFalse);
    });

    test('the length counts UTF-16 code units', () {
      // As observed on the emulator: an emoji counts as two.
      const String json = '[[1,[{"s":"héllo \u{1F600} 日本"}]]]';
      expect(json.length, isNot(utf8.encode(json).length));
      expect(json.length, isNot(json.runes.length));

      final List<Object?> chunks = WebChannelChunkParser()
          .add('${chunk(json)}${chunk('[[2,["noop"]]]')}');
      expect(chunks, hasLength(2));
      expect(chunks.first, jsonDecode(json));
    });

    test('rejects a body that is not chunked', () {
      expect(() => WebChannelChunkParser().add('<html>Not Found</html>......'),
          throwsFormatException);
    });
  });

  group('WebChannelStream', () {
    late FakeHttpClient http;
    late WebChannelStream stream;
    late List<Map<String, Object?>> messages;
    late List<Object> errors;
    late bool done;

    void open({Map<String, String> headers = const <String, String>{}}) {
      http = FakeHttpClient();
      stream = WebChannelStream(http, channelUrl, database, headers,
          random: Random(1));
      messages = <Map<String, Object?>>[];
      errors = <Object>[];
      done = false;
      stream.messages
          .listen(messages.add, onError: errors.add, onDone: () => done = true);
    }

    /// Sends the first message and answers the handshake.
    Future<FakeRequest> handshake() async {
      stream.send(addTarget);
      final FakeRequest request = await http.next();
      request.respond(200, body: handshakeResponse);
      return request;
    }

    test('does not send anything before the first message', () async {
      open();
      await pump();
      expect(http.requests, isEmpty);
      await stream.close();
      // No session, so nothing to terminate.
      expect(http.requests, isEmpty);
      expect(done, isTrue);
    });

    test('the handshake carries the first message and the headers', () async {
      open(headers: <String, String>{
        'Authorization': 'Bearer owner',
        'x-goog-api-client': 'gl-dart/web fire/1',
      });
      final FakeRequest request = await handshake();

      expect(request.method, 'POST');
      expect(request.url.path, '/google.firestore.v1.Firestore/Listen/channel');
      expect(
          request.headers['Content-Type'], 'application/x-www-form-urlencoded');
      expect(request.query['database'], database);
      expect(request.query['VER'], '8');
      expect(request.query['CVER'], '22');
      expect(request.query['X-HTTP-Session-Id'], 'gsessionid');
      expect(int.parse(request.query['RID']!), greaterThanOrEqualTo(0));
      expect(request.query.containsKey('SID'), isFalse);
      expect(request.query['zx'], isNotEmpty);
      expect(request.query['t'], '1');

      expect(request.form, <String, String>{
        'headers':
            'Authorization:Bearer owner\r\nx-goog-api-client:gl-dart/web fire/1\r\n',
        'count': '1',
        'ofs': '0',
        'req0___data__': addTarget,
      });
      // The parentheses of the database name must not break the form.
      expect(request.body, isNot(contains(' ')));
      await stream.close();
    });

    test('reads the recorded Listen exchange from the back channel', () async {
      open();
      final FakeRequest first = await handshake();

      final FakeRequest back = await http.next();
      expect(back.method, 'GET');
      expect(back.query['RID'], 'rpc');
      expect(back.query['SID'], sessionId);
      expect(back.query['AID'], '0');
      expect(back.query['CI'], '0');
      expect(back.query['TYPE'], 'xmlhttp');
      expect(back.query['database'], database);
      expect(back.query['VER'], '8');
      // The emulator sends no HTTP session id.
      expect(back.query.containsKey('gsessionid'), isFalse);

      back.stream(200);
      // Split in the middle of a chunk, as the network may.
      final String body = '${chunk(listenChunk)}14\n[[5,["noop"]]]';
      back.add(body.substring(0, 100));
      await pump();
      expect(messages, isEmpty);
      back.add(body.substring(100));
      await pump();

      expect(messages, hasLength(4));
      expect(messages[0], <String, Object?>{
        'targetChange': <String, Object?>{
          'targetChangeType': 'ADD',
          'targetIds': <Object?>[2]
        }
      });
      expect(
          (messages[1]['documentChange']! as Map<String, Object?>)['targetIds'],
          <Object?>[2]);
      expect(errors, isEmpty);

      // When the request ends the back channel is requested again, after the
      // last array (the noop, 5).
      back.end();
      final FakeRequest again = await http.next();
      expect(again.query['RID'], 'rpc');
      expect(again.query['AID'], '5');

      // A later client message is a new forward request.
      stream.send('{"removeTarget":2}');
      final FakeRequest second = await http.next();
      expect(second.method, 'POST');
      expect(second.query['SID'], sessionId);
      expect(second.query['AID'], '5');
      expect(
          int.parse(second.query['RID']!), int.parse(first.query['RID']!) + 1);
      expect(second.form, <String, String>{
        'count': '1',
        'ofs': '1',
        'req0___data__': '{"removeTarget":2}',
      });
      // Recorded acknowledgement of the emulator.
      second.respond(200, body: '7\n[1,2,7]');
      await pump();
      expect(errors, isEmpty);
      await stream.close();
    });

    test('messages sent while a request is in flight are batched', () async {
      open();
      stream.send(addTarget);
      final FakeRequest first = await http.next();
      stream.send('{"a":1}');
      stream.send('{"a":2}');
      await pump();
      // Only one forward request at a time.
      expect(http.requests, hasLength(1));

      first.respond(200, body: handshakeResponse);
      final FakeRequest a = await http.next();
      final FakeRequest b = await http.next();
      final FakeRequest forward = a.method == 'POST' ? a : b;
      expect(forward.form, <String, String>{
        'count': '2',
        'ofs': '1',
        'req0___data__': '{"a":1}',
        'req1___data__': '{"a":2}',
      });
      await stream.close();
    });

    test('echoes the HTTP session id of the backend as gsessionid', () async {
      open();
      stream.send(addTarget);
      (await http.next()).respond(200,
          // Recorded from firestore.googleapis.com (the HTTP session id is
          // shortened). Its chunks end with a line feed that the length
          // includes.
          body: '51\n[[0,["c","VVb3bqrNGDP1on0x9lz7PA","",8,15,30000]]]\n',
          headers: <String, String>{
            'x-http-session-id': 'fZRGxqs0ktSPkw',
            'x-client-wire-protocol': 'h2',
          });
      final FakeRequest back = await http.next();
      expect(back.query['gsessionid'], 'fZRGxqs0ktSPkw');
      expect(back.query['SID'], 'VVb3bqrNGDP1on0x9lz7PA');
      expect(await stream.handshakeHeaders,
          containsPair('x-client-wire-protocol', 'h2'));
      await stream.close();
    });

    test('a status envelope of the backend fails the stream', () async {
      open();
      await handshake();
      final FakeRequest back = await http.next();
      back.stream(200);
      // Recorded from firestore.googleapis.com for a project without the API
      // (details and message shortened).
      back.add(chunk(
          '[[1,{"__sm__":{"status":[[{"error":{"code":403,"details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"SERVICE_DISABLED"}],"message":"Cloud Firestore API has not been used in project demo-test before or it is disabled.","status":"PERMISSION_DENIED"}}]]}}]]'));
      await pump();

      expect(messages, isEmpty);
      expect(errors, hasLength(1));
      final GrpcError error = errors.single as GrpcError;
      expect(error.code, StatusCode.permissionDenied);
      expect(error.message, startsWith('Cloud Firestore API has not been'));
      expect(done, isTrue);
      expect(back.aborted, isTrue);
    });

    test('an error message of the stream fails it with its status', () async {
      open();
      await handshake();
      final FakeRequest back = await http.next();
      back.stream(200);
      back.add(chunk(
          '[[1,[{"error":{"code":404,"message":"gone","status":"NOT_FOUND"}}]]]'));
      await pump();
      expect((errors.single as GrpcError).code, StatusCode.notFound);
      expect(done, isTrue);
    });

    test('an unknown session (HTTP 400) is reported as UNAVAILABLE', () async {
      open();
      await handshake();
      // As the emulator answers for a terminated SID.
      (await http.next()).respond(400);
      await pump();
      expect((errors.single as GrpcError).code, StatusCode.unavailable);
      expect(done, isTrue);
    });

    test('"stop" from the server closes the stream as UNAVAILABLE', () async {
      open();
      await handshake();
      final FakeRequest back = await http.next();
      back.stream(200);
      back.add(chunk('[[1,["stop"]]]'));
      await pump();
      expect((errors.single as GrpcError).code, StatusCode.unavailable);
      expect(done, isTrue);
    });

    test('a failed handshake is reported with the status of the response',
        () async {
      open();
      stream.send(addTarget);
      (await http.next()).respond(401,
          body:
              '{"error":{"code":401,"message":"bad token","status":"UNAUTHENTICATED"}}');
      await pump();
      final GrpcError error = errors.single as GrpcError;
      expect(error.code, StatusCode.unauthenticated);
      expect(error.message, 'bad token');
      expect(done, isTrue);
      expect(await stream.handshakeHeaders, isEmpty);
      // There is no session to terminate.
      expect(http.requests, hasLength(1));
    });

    test('a network error of the handshake is UNAVAILABLE', () async {
      open();
      stream.send(addTarget);
      (await http.next()).fail(StateError('offline'));
      await pump();
      expect((errors.single as GrpcError).code, StatusCode.unavailable);
      expect(done, isTrue);
    });

    test('gives up after back channel requests keep failing', () async {
      open();
      await handshake();
      for (int i = 0; i < 3; i++) {
        expect(errors, isEmpty);
        (await http.next()).fail(StateError('offline'));
        await pump();
      }
      expect((errors.single as GrpcError).code, StatusCode.unavailable);
      expect(done, isTrue);
    });

    test('an empty back channel response is retried, data resets the count',
        () async {
      open();
      await handshake();
      (await http.next()).respond(200);
      (await http.next()).respond(200);
      (await http.next()).respond(200, body: chunk('[[1,["noop"]]]'));
      (await http.next()).respond(200);
      (await http.next()).respond(200);
      final FakeRequest last = await http.next();
      await pump();
      expect(errors, isEmpty);
      expect(last.query['AID'], '1');
      await stream.close();
    });

    test('close terminates the session and aborts the back channel', () async {
      open();
      await handshake();
      final FakeRequest back = await http.next();
      back.stream(200);
      await pump();

      await stream.close();
      expect(back.aborted, isTrue);
      expect(done, isTrue);
      expect(errors, isEmpty);

      final FakeRequest terminate = await http.next();
      expect(terminate.method, 'GET');
      expect(terminate.query['TYPE'], 'terminate');
      expect(terminate.query['SID'], sessionId);
      expect(terminate.query['database'], database);
      terminate.respond(200);

      // Nothing is sent after the close.
      stream.send('{"late":true}');
      await pump();
      expect(http.hasUnclaimed, isFalse);
    });
  });
}

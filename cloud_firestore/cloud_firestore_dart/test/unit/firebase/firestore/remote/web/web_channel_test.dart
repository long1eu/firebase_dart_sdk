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

    test('parses a chunk of megabytes that arrives in small pieces without '
        'copying it for every piece', () {
      // 12 documents of 1 MiB in one chunk, delivered in pieces of 4 KiB as
      // the emulator's responses arrive. Appending every piece to the text
      // received so far took about 2.4 s here; the pieces are now joined once.
      final String json = jsonEncode(<Object?>[
        for (int i = 0; i < 12; i++)
          <Object?>[
            i,
            <Object?>[
              <String, Object?>{
                'chunk': String.fromCharCode(0x61 + i) * (1024 * 1024),
              },
            ],
          ],
      ]);
      final String body = '${chunk(json)}${chunk('[[12,["noop"]]]')}';
      final WebChannelChunkParser parser = WebChannelChunkParser();
      final List<Object?> chunks = <Object?>[];
      final Stopwatch stopwatch = Stopwatch()..start();
      for (int i = 0; i < body.length; i += 4096) {
        chunks.addAll(
          parser.add(body.substring(i, min(i + 4096, body.length))),
        );
        if (i + 4096 < json.length) {
          expect(chunks, isEmpty);
          expect(parser.hasPartialChunk, isTrue);
        }
      }
      stopwatch.stop();
      expect(chunks, hasLength(2));
      final List<Object?> arrays = chunks.first! as List<Object?>;
      expect(arrays, hasLength(12));
      for (int i = 0; i < 12; i++) {
        final Map<String, Object?> doc =
            ((arrays[i]! as List<Object?>)[1]! as List<Object?>)[0]!
                as Map<String, Object?>;
        expect(
          doc['chunk'] == String.fromCharCode(0x61 + i) * (1024 * 1024),
          isTrue,
        );
      }
      expect(parser.hasPartialChunk, isFalse);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
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

    void open({
      Map<String, String> headers = const <String, String>{},
      bool forceLongPolling = false,
      bool autoDetectLongPolling = false,
      Duration forwardRequestTimeout = const Duration(seconds: 20),
    }) {
      http = FakeHttpClient();
      stream = WebChannelStream(http, channelUrl, database, headers,
          random: Random(1),
          retryDelays: const <Duration>[
            Duration(milliseconds: 5),
            Duration(milliseconds: 10),
          ],
          forceLongPolling: forceLongPolling,
          autoDetectLongPolling: autoDetectLongPolling,
          longPollingDetectionTimeout: const Duration(milliseconds: 60),
          forwardRequestTimeout: forwardRequestTimeout);
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
      // The session is terminated on the server as well, and only then is the
      // back channel request given up.
      expect(back.aborted, isFalse);
      final FakeRequest terminate = await http.next();
      expect(terminate.query['TYPE'], 'terminate');
      terminate.respond(200);
      await stream.released;
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

    // firebase-js-sdk #9472: log a warning when the database is not found.
    test('a missing database is reported with a warning', () async {
      final List<String> logs = <String>[];
      await runZoned(
        () async {
          open();
          await handshake();
          final FakeRequest back = await http.next();
          back
            ..stream(200)
            ..add(
              chunk(
                '[[1,[{"error":{"code":404,"message":"The database (default) does not exist for project demo-test Please visit https://console.cloud.google.com/datastore/setup?project=demo-test to add a Cloud Datastore or Cloud Firestore database.","status":"NOT_FOUND"}}]]]',
              ),
            );
          await pump();
        },
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, String line) => logs.add(line),
        ),
      );
      expect((errors.single as GrpcError).code, StatusCode.notFound);
      expect(logs, hasLength(1));
      expect(
        logs.single,
        contains(
          "Database '(default)' not found. Please check your project configuration.",
        ),
      );
    });

    test('a NOT_FOUND that is not about the database logs nothing', () async {
      final List<String> logs = <String>[];
      await runZoned(
        () async {
          open();
          await handshake();
          final FakeRequest back = await http.next();
          back
            ..stream(200)
            ..add(
              chunk(
                '[[1,[{"error":{"code":404,"message":"gone","status":"NOT_FOUND"}}]]]',
              ),
            );
          await pump();
        },
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, String line) => logs.add(line),
        ),
      );
      expect((errors.single as GrpcError).code, StatusCode.notFound);
      expect(logs, isEmpty);
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
      expect(done, isTrue);
      expect(errors, isEmpty);

      final FakeRequest terminate = await http.next();
      expect(terminate.method, 'GET');
      expect(terminate.query['TYPE'], 'terminate');
      expect(terminate.query['SID'], sessionId);
      expect(terminate.query['database'], database);
      // The back channel request is not cut off before the server knows.
      expect(back.aborted, isFalse);
      terminate.respond(200);
      await stream.released;
      expect(back.aborted, isTrue);
      expect(terminate.aborted, isFalse);

      // Nothing is sent after the close.
      stream.send('{"late":true}');
      await pump();
      expect(http.hasUnclaimed, isFalse);
    });

    test(
      'forced long polling asks for responses that end with the data',
      () async {
        open(forceLongPolling: true);
        await handshake();
        final FakeRequest back = await http.next();
        expect(back.query['CI'], '1');
        expect(stream.isLongPolling, isTrue);

        // As the emulator does in this mode: the response ends after the data.
        back.respond(200, body: chunk(listenChunk));
        await pump();
        expect(messages, hasLength(4));
        final FakeRequest again = await http.next();
        expect(again.query['CI'], '1');
        expect(again.query['AID'], '4');
        expect(errors, isEmpty);
        await stream.close();
      },
    );

    test(
      'switches to long polling when the first response is held back',
      () async {
        open(autoDetectLongPolling: true);
        await handshake();
        final FakeRequest first = await http.next();
        expect(first.query['CI'], '0');
        // A buffering proxy: the headers may arrive, the data does not.
        first.stream(200);

        final FakeRequest second = await http.next();
        expect(first.aborted, isTrue);
        expect(second.query['CI'], '1');
        expect(second.query['AID'], '0');
        expect(stream.isLongPolling, isTrue);
        expect(errors, isEmpty);

        second.respond(200, body: chunk(listenChunk));
        await pump();
        expect(messages, hasLength(4));
        // Giving up the first request did not count as a failure.
        (await http.next()).respond(200);
        (await http.next()).respond(200);
        await pump();
        expect(errors, isEmpty);
        await stream.close();
      },
    );

    test(
      'stays in streaming mode when the first response arrives in time',
      () async {
        open(autoDetectLongPolling: true);
        await handshake();
        final FakeRequest back = await http.next();
        back.stream(200);
        back.add(chunk(listenChunk));
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(back.aborted, isFalse);
        expect(stream.isLongPolling, isFalse);
        expect(http.hasUnclaimed, isFalse);
        await stream.close();
      },
    );

    test(
      'closeWhenFlushed delivers the queued messages before it ends the session',
      () async {
        open();
        await handshake();
        final FakeRequest back = await http.next();
        back.stream(200);
        await pump();

        stream.send('{"removeTarget":2}');
        final FakeRequest forward = await http.next();
        stream.closeWhenFlushed();
        await pump();
        // Still waiting for the request in flight.
        expect(done, isFalse);
        expect(forward.aborted, isFalse);
        expect(back.aborted, isFalse);

        forward.respond(200, body: '7\n[1,2,7]');
        final FakeRequest terminate = await http.next();
        expect(terminate.query['TYPE'], 'terminate');
        terminate.respond(200);
        await pump();
        expect(back.aborted, isTrue);
        expect(done, isTrue);
        expect(errors, isEmpty);
      },
    );

    test(
      'closeWhenFlushed on a session that never opened just ends it',
      () async {
        open();
        stream.closeWhenFlushed();
        await pump();
        expect(http.requests, isEmpty);
        expect(done, isTrue);
      },
    );

    test('a session closed during its handshake is still terminated',
        () async {
      open();
      stream.send(addTarget);
      final FakeRequest request = await http.next();
      await stream.close();
      expect(done, isTrue);
      // The handshake is left to finish: it names the session to terminate.
      expect(request.aborted, isFalse);
      expect(http.hasUnclaimed, isFalse);

      request.respond(200, body: handshakeResponse);
      final FakeRequest terminate = await http.next();
      expect(terminate.query['TYPE'], 'terminate');
      expect(terminate.query['SID'], sessionId);
      terminate.respond(200);
      await stream.released;
      // No back channel was ever requested.
      expect(http.requests, hasLength(2));
      expect(errors, isEmpty);
    });

    test('released completes even when the server never answers', () async {
      http = FakeHttpClient();
      stream = WebChannelStream(http, channelUrl, database,
          const <String, String>{},
          random: Random(1), releaseTimeout: const Duration(milliseconds: 50));
      stream.messages.listen((_) {}, onError: (Object _) {});
      stream.send(addTarget);
      (await http.next()).respond(200, body: handshakeResponse);
      final FakeRequest back = await http.next();
      back.stream(200);
      await pump();

      await stream.close();
      final FakeRequest terminate = await http.next();
      await stream.released;
      expect(terminate.aborted, isTrue);
      expect(back.aborted, isTrue);
    });

    test('a session that never opened is released at once', () async {
      open();
      await stream.close();
      await stream.released;
      expect(http.requests, isEmpty);
    });

    test('a header with a line break is refused, nothing is sent', () async {
      open(headers: <String, String>{
        'Authorization': 'Bearer x\r\nX-Injected: 1',
      });
      stream.send(addTarget);
      await pump();
      expect(http.requests, isEmpty);
      final GrpcError error = errors.single as GrpcError;
      expect(error.code, StatusCode.invalidArgument);
      expect(error.message, contains('Authorization'));
      expect(done, isTrue);
    });

    test('a forward request that is lost is sent again with the same id',
        () async {
      open();
      final FakeRequest first = await handshake();
      final FakeRequest back = await http.next();
      back.stream(200);
      await pump();

      stream.send('{"removeTarget":2}');
      final FakeRequest lost = await http.next();
      lost.fail(StateError('connection reset'));

      // Same request id and body: the server applies a request id once, so
      // the message is not duplicated if only the answer was lost.
      final FakeRequest again = await http.next();
      expect(again.method, 'POST');
      expect(again.query['RID'], lost.query['RID']);
      expect(int.parse(again.query['RID']!), int.parse(first.query['RID']!) + 1);
      expect(again.query['SID'], sessionId);
      expect(again.body, lost.body);
      expect(lost.query['t'], '1');
      expect(again.query['t'], '2');
      again.respond(200, body: '7\n[1,2,7]');
      await pump();
      expect(errors, isEmpty);
      expect(done, isFalse);

      // The next message has the next id and offset.
      stream.send('{"x":1}');
      final FakeRequest next = await http.next();
      expect(int.parse(next.query['RID']!), int.parse(again.query['RID']!) + 1);
      expect(next.form['ofs'], '2');
      await stream.close();
    });

    test(
        'a forward request that is never answered is aborted and sent again '
        'with the same id', () async {
      // A connection that swallows the request without failing (a black hole):
      // nothing would ever be sent again, the session looks alive as long as
      // its back channel works.
      open(forwardRequestTimeout: const Duration(milliseconds: 50));
      await handshake();
      (await http.next()).stream(200);
      await pump();

      stream.send('{"removeTarget":2}');
      final FakeRequest silent = await http.next();
      final FakeRequest again = await http.next();
      expect(silent.aborted, isTrue);
      expect(again.query['RID'], silent.query['RID']);
      expect(again.body, silent.body);
      again.respond(200, body: '7\n[1,2,7]');
      await pump();
      expect(errors, isEmpty);

      stream.send('{"x":1}');
      final FakeRequest next = await http.next();
      expect(next.form['ofs'], '2');
      await stream.close();
    });

    test('a handshake that is never answered fails the stream', () async {
      open(forwardRequestTimeout: const Duration(milliseconds: 50));
      stream.send(addTarget);
      final FakeRequest silent = await http.next();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(silent.aborted, isTrue);
      expect((errors.single as GrpcError).code, StatusCode.unavailable);
      expect(done, isTrue);
    });

    test('a forward request that keeps failing ends the stream', () async {
      open();
      await handshake();
      (await http.next()).stream(200);
      stream.send('{"removeTarget":2}');
      for (int attempt = 1; attempt <= 3; attempt++) {
        expect(errors, isEmpty);
        final FakeRequest request = await http.next();
        expect(request.query['t'], '$attempt');
        request.fail(StateError('offline'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      await pump();
      expect((errors.single as GrpcError).code, StatusCode.unavailable);
      expect(done, isTrue);
    });

    test('an error answer to a forward request is not retried', () async {
      open();
      await handshake();
      (await http.next()).stream(200);
      stream.send('{"removeTarget":2}');
      (await http.next()).respond(400);
      await pump();
      expect((errors.single as GrpcError).code, StatusCode.unavailable);
      // Only the terminate request follows.
      expect((await http.next()).query['TYPE'], 'terminate');
      expect(http.hasUnclaimed, isFalse);
    });

    test('a back channel request that is cut resumes after the last array',
        () async {
      open();
      await handshake();
      final FakeRequest back = await http.next();
      back.stream(200);
      back.add(chunk(listenChunk));
      await pump();
      expect(messages, hasLength(4));

      // The connection is cut in the middle of the response.
      back.cutBody();
      final FakeRequest again = await http.next();
      expect(again.query['RID'], 'rpc');
      expect(again.query['SID'], sessionId);
      expect(again.query['AID'], '4');
      again.stream(200);
      again.add(chunk('[[5,[{"targetChange":{"targetChangeType":"NO_CHANGE"}}]]]'));
      await pump();
      expect(messages, hasLength(5));
      expect(errors, isEmpty);
      await stream.close();
    });

    // firebase-js-sdk #9242: WebChannel ignores duplicate messages received
    // from the server.
    test('arrays the server sends again are not delivered twice', () async {
      open();
      await handshake();
      final FakeRequest back = await http.next();
      back
        ..stream(200)
        ..add(chunk(listenChunk));
      await pump();
      expect(messages, hasLength(4));

      back.cutBody();
      final FakeRequest again = await http.next();
      expect(again.query['AID'], '4');
      // The server repeats arrays 3 and 4 before the new array 5.
      again
        ..stream(200)
        ..add(
          chunk(
            '[[3,[{"targetChange":{"targetChangeType":"CURRENT","targetIds":[2]}}]],'
            '[4,[{"targetChange":{"targetChangeType":"NO_CHANGE"}}]],'
            '[5,[{"targetChange":{"targetChangeType":"REMOVE","targetIds":[2]}}]]]',
          ),
        );
      await pump();
      expect(messages, hasLength(5));
      expect(messages.last, <String, Object?>{
        'targetChange': <String, Object?>{
          'targetChangeType': 'REMOVE',
          'targetIds': <Object?>[2],
        },
      });
      expect(errors, isEmpty);
      await stream.close();
    });
  });
}
